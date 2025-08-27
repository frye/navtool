import 'dart:convert';
import 'dart:typed_data';
import '../../../core/logging/app_logger.dart';
import '../../../core/error/app_error.dart';
import '../../../core/models/geographic_bounds.dart';
import '../../../core/models/chart_models.dart';
import '../../../core/models/chart.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/http_client_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/spatial_operations.dart';

/// Custom exception for unsupported states
class StateNotSupportedException implements Exception {
  final String message;
  StateNotSupportedException(this.message);
  
  @override
  String toString() => 'StateNotSupportedException: $message';
}

/// Abstract interface for state-to-region mapping service
abstract class StateRegionMappingService {
  /// Gets chart cells for a given state
  Future<List<String>> getChartCellsForState(String stateName);
  
  /// Gets geographic bounds for a state
  Future<GeographicBounds?> getStateBounds(String stateName);
  
  /// Gets all supported states
  Future<List<String>> getSupportedStates();
  
  /// Updates the state-to-cell mapping for a state
  Future<void> updateStateCellMapping(String stateName, List<String> mapping);
  
  /// Clears all state mappings from cache
  Future<void> clearStateMappings();
}

/// Implementation of state region mapping service
class StateRegionMappingServiceImpl implements StateRegionMappingService {
  final AppLogger _logger;
  final CacheService _cacheService;
  final HttpClientService _httpClient;
  final StorageService _storageService;
  final Map<String, List<LatLng>> _stateBoundariesCache = {};

  StateRegionMappingServiceImpl({
    required AppLogger logger,
    required CacheService cacheService,
    required HttpClientService httpClient,
    required StorageService storageService,
  }) : _logger = logger,
       _cacheService = cacheService,
       _httpClient = httpClient,
       _storageService = storageService;

  /// Predefined state to geographic bounds mapping
  static final Map<String, GeographicBounds> _stateRegions = {
    'California': GeographicBounds(north: 42.0, south: 32.5, east: -114.1, west: -124.4),
    'Florida': GeographicBounds(north: 31.0, south: 24.5, east: -80.0, west: -87.6),
    'Texas': GeographicBounds(north: 36.5, south: 25.8, east: -93.5, west: -106.6),
    'Washington': GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8),
    'Alaska': GeographicBounds(north: 71.4, south: 54.8, east: -130.0, west: -179.1),
    'Hawaii': GeographicBounds(north: 28.4, south: 18.9, east: -154.8, west: -178.3),
    'Maine': GeographicBounds(north: 47.5, south: 43.1, east: -66.9, west: -71.1),
    'Massachusetts': GeographicBounds(north: 42.9, south: 41.2, east: -69.9, west: -73.5),
    'New York': GeographicBounds(north: 45.0, south: 40.5, east: -71.9, west: -79.8),
    'North Carolina': GeographicBounds(north: 36.6, south: 33.8, east: -75.5, west: -84.3),
    'South Carolina': GeographicBounds(north: 35.2, south: 32.0, east: -78.5, west: -83.4),
    'Georgia': GeographicBounds(north: 35.0, south: 30.4, east: -80.8, west: -85.6),
    'Louisiana': GeographicBounds(north: 33.0, south: 28.9, east: -88.8, west: -94.0),
    'Oregon': GeographicBounds(north: 46.3, south: 42.0, east: -116.5, west: -124.6),
  };

  @override
  Future<List<String>> getChartCellsForState(String stateName) async {
    try {
      _logger.debug('Getting chart cells for state: $stateName');
      
      // Force refresh for testing new geometry extraction
      // TODO: Remove this force refresh after verifying spatial intersection works
      _logger.info('Force refreshing state-chart mapping to test new chart bounds for $stateName');

      // Compute mapping using spatial intersection
      final chartCells = await _computeChartCellsForState(stateName);
      
      // Cache the result in memory and database
      final cacheKey = 'state_cells_$stateName';
      final encodedData = jsonEncode(chartCells);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
      try {
        await _cacheService.store(cacheKey, encodedBytes, maxAge: Duration(hours: 24));
      } catch (e) {
        _logger.warning('Failed to store in cache, continuing: $e');
        // Continue even if cache storage fails
      }
      await _storageService.storeStateCellMapping(stateName, chartCells);
      
      return chartCells;
    } catch (e) {
      _logger.error('Failed to get chart cells for state: $stateName', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network('Failed to fetch chart cells for state', originalError: e);
    }
  }

  /// Compute chart cells for a state using spatial intersection
  Future<List<String>> _computeChartCellsForState(String stateName) async {
    // Load state boundary polygon
    final stateBoundary = await _loadStateBoundary(stateName);
    if (stateBoundary == null) {
      throw StateNotSupportedException('State $stateName not supported or not found');
    }
    
    // Get state bounds for efficient chart lookup
    final stateBounds = _stateRegions[stateName];
    if (stateBounds == null) {
      throw StateNotSupportedException('State $stateName not supported');
    }
    
    // Get all charts that might intersect with state (using bounding box)
    final candidateCharts = await _storageService.getChartsInBounds(stateBounds);
    
    final intersectingCells = <String>[];
    for (final chart in candidateCharts) {
      if (chart.source == ChartSource.noaa) {
        try {
          final chartPolygon = SpatialOperations.boundsToPolygon(chart.bounds);
          
          if (SpatialOperations.doPolygonsIntersect(stateBoundary, chartPolygon)) {
            final coverage = SpatialOperations.calculateCoveragePercentage(stateBoundary, chartPolygon);
            
            // Include charts with meaningful coverage (>1%)
            if (coverage > 0.01) {
              intersectingCells.add(chart.id);
            }
          }
        } catch (e) {
          _logger.warning('Skipping chart ${chart.id} due to invalid bounds: $e');
          // Continue with next chart instead of failing the entire operation
          continue;
        }
      }
    }
    
    _logger.info('Found ${intersectingCells.length} charts for state: $stateName using spatial intersection');
    return intersectingCells;
  }

  /// Load state boundary polygon from cache or generate from bounds
  Future<List<LatLng>?> _loadStateBoundary(String stateName) async {
    // Check memory cache first
    if (_stateBoundariesCache.containsKey(stateName)) {
      return _stateBoundariesCache[stateName];
    }
    
    // Get from predefined state bounds and convert to polygon
    final bounds = _stateRegions[stateName];
    if (bounds != null) {
      final polygon = SpatialOperations.boundsToPolygon(bounds);
      _stateBoundariesCache[stateName] = polygon;
      return polygon;
    }
    
    return null;
  }

  @override
  Future<GeographicBounds?> getStateBounds(String stateName) async {
    try {
      _logger.debug('Getting bounds for state: $stateName');
      
      // Check cache first
      final cacheKey = 'state_bounds_$stateName';
      final cached = await _cacheService.get(cacheKey);
      if (cached != null) {
        // Deserialize cached data
        final decodedData = jsonDecode(String.fromCharCodes(cached));
        if (decodedData is Map<String, dynamic>) {
          return GeographicBounds(
            north: decodedData['north'],
            south: decodedData['south'],
            east: decodedData['east'],
            west: decodedData['west'],
          );
        }
      }

      // Get from predefined mapping
      final bounds = _stateRegions[stateName];
      if (bounds != null) {
        // Cache the result
        final encodedData = jsonEncode({
          'north': bounds.north,
          'south': bounds.south,
          'east': bounds.east,
          'west': bounds.west,
        });
        final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
        await _cacheService.store(cacheKey, encodedBytes, maxAge: Duration(hours: 24));
      }

      return bounds;
    } catch (e) {
      _logger.error('Failed to get bounds for state: $stateName', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network('Failed to fetch state bounds', originalError: e);
    }
  }

  @override
  Future<List<String>> getSupportedStates() async {
    try {
      _logger.debug('Getting supported states');
      
      // Check cache first
      const cacheKey = 'supported_states';
      final cached = await _cacheService.get(cacheKey);
      if (cached != null) {
        // Deserialize cached data
        final decodedData = jsonDecode(String.fromCharCodes(cached));
        if (decodedData is List) {
          return List<String>.from(decodedData);
        }
      }

      // Return predefined states
      final states = _stateRegions.keys.toList();
      
      // Cache the result
      final encodedData = jsonEncode(states);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
      await _cacheService.store(cacheKey, encodedBytes, maxAge: Duration(hours: 24));
      
      return states;
    } catch (e) {
      _logger.error('Failed to get supported states', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network('Failed to fetch supported states', originalError: e);
    }
  }

  @override
  Future<void> updateStateCellMapping(String stateName, List<String> mapping) async {
    try {
      _logger.debug('Updating state cell mapping for: $stateName');
      
      // Store in database
      await _storageService.storeStateCellMapping(stateName, mapping);
      
      // Cache the updated mapping
      final cacheKey = 'state_cells_$stateName';
      final encodedData = jsonEncode(mapping);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
      await _cacheService.store(cacheKey, encodedBytes, maxAge: Duration(hours: 24));
      
      _logger.info('Updated state cell mapping for: $stateName');
    } catch (e) {
      _logger.error('Failed to update state cell mapping for: $stateName', exception: e);
      if (e is AppError) rethrow;
      throw AppError.storage('Failed to update state cell mapping', originalError: e);
    }
  }

  @override
  Future<void> clearStateMappings() async {
    try {
      _logger.debug('Clearing all state mappings');
      
      // Clear database mappings
      await _storageService.clearAllStateCellMappings();
      
      // Clear cache entries
      await _cacheService.clear();
      
      // Clear memory cache
      _stateBoundariesCache.clear();
      
      _logger.info('Cleared all state mappings');
    } catch (e) {
      _logger.error('Failed to clear state mappings', exception: e);
      if (e is AppError) rethrow;
      throw AppError.storage('Failed to clear state mappings', originalError: e);
    }
  }

}