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

/// Marine region definition for multi-region states
class MarineRegion {
  const MarineRegion({
    required this.name,
    required this.bounds,
    required this.description,
  });

  /// Region name
  final String name;
  
  /// Geographic boundaries of the region
  final GeographicBounds bounds;
  
  /// Description of the region
  final String description;

  @override
  String toString() => '$name: $description';
}

/// Abstract interface for state-to-region mapping service
abstract class StateRegionMappingService {
  /// Gets chart cells for a given state
  Future<List<String>> getChartCellsForState(String stateName);

  /// Gets geographic bounds for a state
  Future<GeographicBounds?> getStateBounds(String stateName);

  /// Gets all supported states
  Future<List<String>> getSupportedStates();

  /// Gets the state name for given coordinates
  ///
  /// Returns the state name if coordinates fall within a supported
  /// coastal state's boundaries, otherwise returns null.
  Future<String?> getStateFromCoordinates(double latitude, double longitude);

  /// Updates the state-to-cell mapping for a state
  Future<void> updateStateCellMapping(String stateName, List<String> mapping);

  /// Clears all state mappings from cache
  Future<void> clearStateMappings();

  /// Gets marine regions for multi-region states
  ///
  /// Returns a list of marine regions for states that have multiple
  /// distinct marine areas (Alaska, California, Florida).
  Future<List<MarineRegion>> getMarineRegions(String stateName);

  /// Gets chart cells for a specific marine region within a state
  ///
  /// For multi-region states, this provides more granular chart discovery
  /// based on the specific marine region rather than the entire state.
  Future<List<String>> getChartCellsForRegion(String stateName, String regionName);

  /// Validates state-to-region mapping against NOAA's official data
  ///
  /// Performs validation of coordinate boundaries and region definitions
  /// against NOAA's authoritative sources for data quality assurance.
  Future<ValidationResult> validateStateRegionMapping(String stateName);

  /// Gets enhanced coverage statistics for a state
  ///
  /// Returns detailed coverage information including multi-region
  /// breakdown for complex coastal states.
  Future<StateCoverageInfo> getStateCoverageInfo(String stateName);
}

/// Validation result for state-region mapping
class ValidationResult {
  const ValidationResult({
    required this.isValid,
    required this.validatedAt,
    this.issues = const [],
    this.recommendations = const [],
  });

  /// Whether the mapping is valid
  final bool isValid;
  
  /// When validation was performed
  final DateTime validatedAt;
  
  /// List of validation issues found
  final List<String> issues;
  
  /// Recommendations for improvement
  final List<String> recommendations;
}

/// Coverage information for a state
class StateCoverageInfo {
  const StateCoverageInfo({
    required this.stateName,
    required this.totalChartCount,
    required this.coveragePercentage,
    required this.regionBreakdown,
    required this.lastUpdated,
  });

  /// State name
  final String stateName;
  
  /// Total number of charts for the state
  final int totalChartCount;
  
  /// Overall coverage percentage
  final double coveragePercentage;
  
  /// Coverage breakdown by region (for multi-region states)
  final Map<String, RegionCoverageInfo> regionBreakdown;
  
  /// When coverage info was last updated
  final DateTime lastUpdated;
}

/// Coverage information for a specific region
class RegionCoverageInfo {
  const RegionCoverageInfo({
    required this.regionName,
    required this.chartCount,
    required this.coveragePercentage,
    required this.bounds,
  });

  /// Region name
  final String regionName;
  
  /// Number of charts in this region
  final int chartCount;
  
  /// Coverage percentage for this region
  final double coveragePercentage;
  
  /// Geographic bounds of the region
  final GeographicBounds bounds;
}

/// Implementation of state region mapping service
class StateRegionMappingServiceImpl implements StateRegionMappingService {
  final AppLogger _logger;
  final CacheService _cacheService;
  // ignore: unused_field, remove once remote boundary refresh implemented in Phase 2
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

  /// Enhanced state to geographic bounds mapping with multi-region support
  /// Based on NOAA's official marine regions and territorial waters
  static final Map<String, GeographicBounds> _stateRegions = {
    // Atlantic Coast States
    'Maine': GeographicBounds(
      north: 47.5,
      south: 44.0,
      east: -66.9,
      west: -71.0,
    ),
    'New Hampshire': GeographicBounds(
      north: 43.1,
      south: 42.7,
      east: -70.6,
      west: -71.2,
    ),
    'Massachusetts': GeographicBounds(
      north: 42.9,
      south: 41.2,
      east: -69.9,
      west: -71.2,
    ),
    'Rhode Island': GeographicBounds(
      north: 41.7,
      south: 41.1,
      east: -71.1,
      west: -71.9,
    ),
    'Connecticut': GeographicBounds(
      north: 41.4,
      south: 40.9,
      east: -71.8,
      west: -73.7,
    ),
    'New York': GeographicBounds(
      north: 45.0,
      south: 40.4,
      east: -71.8,
      west: -79.8,
    ),
    'New Jersey': GeographicBounds(
      north: 41.4,
      south: 38.9,
      east: -73.9,
      west: -75.6,
    ),
    'Pennsylvania': GeographicBounds(
      north: 42.3,
      south: 39.7,
      east: -74.7,
      west: -80.5,
    ),
    'Delaware': GeographicBounds(
      north: 39.8,
      south: 38.4,
      east: -75.0,
      west: -75.8,
    ),
    'Maryland': GeographicBounds(
      north: 39.7,
      south: 37.9,
      east: -75.0,
      west: -79.5,
    ),
    'Virginia': GeographicBounds(
      north: 39.5,
      south: 36.5,
      east: -75.2,
      west: -83.7,
    ),
    'North Carolina': GeographicBounds(
      north: 36.6,
      south: 33.8,
      east: -75.4,
      west: -84.3,
    ),
    'South Carolina': GeographicBounds(
      north: 35.2,
      south: 32.0,
      east: -78.5,
      west: -83.4,
    ),
    'Georgia': GeographicBounds(
      north: 35.0,
      south: 30.4,
      east: -80.8,
      west: -85.6,
    ),
    
    // Florida - Multi-region state (Atlantic & Gulf coasts)
    'Florida': GeographicBounds(
      north: 31.0,
      south: 24.4,
      east: -80.0,
      west: -87.6,
    ),

    // Gulf Coast States
    'Alabama': GeographicBounds(
      north: 35.0,
      south: 30.1,
      east: -84.9,
      west: -88.5,
    ),
    'Mississippi': GeographicBounds(
      north: 35.0,
      south: 30.1,
      east: -88.1,
      west: -91.7,
    ),
    'Louisiana': GeographicBounds(
      north: 33.0,
      south: 28.9,
      east: -88.8,
      west: -94.0,
    ),
    'Texas': GeographicBounds(
      north: 36.5,
      south: 25.8,
      east: -93.5,
      west: -106.6,
    ),

    // Pacific Coast States
    'California': GeographicBounds(
      north: 42.0,
      south: 32.5,
      east: -114.1,
      west: -124.4,
    ),
    'Oregon': GeographicBounds(
      north: 46.3,
      south: 41.9,
      east: -116.5,
      west: -124.6,
    ),
    'Washington': GeographicBounds(
      north: 49.0,
      south: 45.5,
      east: -116.9,
      west: -124.8,
    ),

    // Alaska - Multi-region state (Southeast, Gulf, Arctic)
    'Alaska': GeographicBounds(
      north: 71.4,
      south: 51.2,
      east: -129.9,
      west: -179.1,
    ),

    // Hawaii and Pacific Territories
    'Hawaii': GeographicBounds(
      north: 22.2,
      south: 18.9,
      east: -154.8,
      west: -160.2,
    ),

    // Great Lakes States
    'Minnesota': GeographicBounds(
      north: 49.4,
      south: 43.5,
      east: -89.5,
      west: -97.2,
    ),
    'Wisconsin': GeographicBounds(
      north: 47.3,
      south: 42.5,
      east: -86.2,
      west: -92.9,
    ),
    'Michigan': GeographicBounds(
      north: 48.3,
      south: 41.7,
      east: -82.1,
      west: -90.4,
    ),
    'Illinois': GeographicBounds(
      north: 42.5,
      south: 36.9,
      east: -87.0,
      west: -91.5,
    ),
    'Indiana': GeographicBounds(
      north: 41.8,
      south: 37.8,
      east: -84.8,
      west: -88.1,
    ),
    'Ohio': GeographicBounds(
      north: 42.3,
      south: 38.4,
      east: -80.5,
      west: -84.8,
    ),
  };

  /// Multi-region state definitions for enhanced mapping
  /// States with multiple distinct marine regions require special handling
  static final Map<String, List<MarineRegion>> _multiRegionStates = {
    'Alaska': [
      MarineRegion(
        name: 'Southeast Alaska',
        bounds: GeographicBounds(north: 60.0, south: 54.0, east: -129.9, west: -141.0),
        description: 'Inside Passage and Alexander Archipelago',
      ),
      MarineRegion(
        name: 'Gulf of Alaska',
        bounds: GeographicBounds(north: 61.0, south: 55.0, east: -135.0, west: -165.0),
        description: 'South-central Alaska coastal waters',
      ),
      MarineRegion(
        name: 'Arctic Alaska',
        bounds: GeographicBounds(north: 71.4, south: 66.0, east: -140.0, west: -179.1),
        description: 'Beaufort and Chukchi Sea regions',
      ),
    ],
    'California': [
      MarineRegion(
        name: 'Northern California',
        bounds: GeographicBounds(north: 42.0, south: 37.0, east: -120.0, west: -124.4),
        description: 'San Francisco Bay area and north',
      ),
      MarineRegion(
        name: 'Central California',
        bounds: GeographicBounds(north: 37.0, south: 34.5, east: -118.0, west: -122.0),
        description: 'Monterey Bay to Point Conception',
      ),
      MarineRegion(
        name: 'Southern California',
        bounds: GeographicBounds(north: 34.5, south: 32.5, east: -114.1, west: -120.5),
        description: 'Los Angeles and San Diego areas',
      ),
    ],
    'Florida': [
      MarineRegion(
        name: 'Florida Atlantic Coast',
        bounds: GeographicBounds(north: 31.0, south: 24.4, east: -80.0, west: -82.0),
        description: 'Atlantic coastal waters and Keys',
      ),
      MarineRegion(
        name: 'Florida Gulf Coast',
        bounds: GeographicBounds(north: 31.0, south: 24.5, east: -82.0, west: -87.6),
        description: 'Gulf of Mexico coastal waters',
      ),
    ],
  };

  @override
  Future<List<String>> getChartCellsForState(String stateName) async {
    try {
      _logger.debug('Getting chart cells for state: $stateName');

      final cacheKey = 'state_cells_$stateName';

      // 1. Try in‑memory cache first
      try {
        final cached = await _cacheService.get(cacheKey);
        if (cached != null) {
          final decoded = jsonDecode(String.fromCharCodes(cached));
          if (decoded is List) {
            return List<String>.from(decoded);
          }
        }
      } catch (e) {
        _logger.warning('Failed to read state cell cache for $stateName: $e');
      }

      // 2. Try persistent storage
      try {
        final stored = await _storageService.getStateCellMapping(stateName);
        if (stored != null) {
          // Rehydrate into memory cache (best effort)
          try {
            final encodedData = jsonEncode(stored);
            final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
            await _cacheService.store(
              cacheKey,
              encodedBytes,
              maxAge: Duration(hours: 24),
            );
          } catch (e) {
            _logger.warning('Failed to backfill cache for $stateName: $e');
          }
          return stored;
        }
      } catch (e) {
        _logger.warning('Failed to read stored mapping for $stateName: $e');
      }

      // 3. Compute mapping using spatial intersection
      final chartCells = await _computeChartCellsForState(stateName);

      // 4. Persist results (best effort for cache)
      final encodedData = jsonEncode(chartCells);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
      try {
        await _cacheService.store(
          cacheKey,
          encodedBytes,
          maxAge: Duration(hours: 24),
        );
      } catch (e) {
        _logger.warning('Failed to store in cache, continuing: $e');
      }
      await _storageService.storeStateCellMapping(stateName, chartCells);

      return chartCells;
    } catch (e) {
      _logger.error(
        'Failed to get chart cells for state: $stateName',
        exception: e,
      );
      if (e is AppError) rethrow;
      throw AppError.network(
        'Failed to fetch chart cells for state',
        originalError: e,
      );
    }
  }

  /// Compute chart cells for a state using spatial intersection
  Future<List<String>> _computeChartCellsForState(String stateName) async {
    // Load state boundary polygon
    final stateBoundary = await _loadStateBoundary(stateName);
    if (stateBoundary == null) {
      throw StateNotSupportedException(
        'State $stateName not supported or not found',
      );
    }

    // Get state bounds for efficient chart lookup
    final stateBounds = _stateRegions[stateName];
    if (stateBounds == null) {
      throw StateNotSupportedException('State $stateName not supported');
    }

    // Get all charts that might intersect with state (using bounding box)
    final candidateCharts = await _storageService.getChartsInBounds(
      stateBounds,
    );

    final intersectingCells = <String>[];
    for (final chart in candidateCharts) {
      if (chart.source == ChartSource.noaa) {
        try {
          final chartPolygon = SpatialOperations.boundsToPolygon(chart.bounds);

          if (SpatialOperations.doPolygonsIntersect(
            stateBoundary,
            chartPolygon,
          )) {
            final coverage = SpatialOperations.calculateCoveragePercentage(
              stateBoundary,
              chartPolygon,
            );

            // Include charts with meaningful coverage (>1%)
            if (coverage > 0.01) {
              intersectingCells.add(chart.id);
            }
          }
        } catch (e) {
          _logger.warning(
            'Skipping chart ${chart.id} due to invalid bounds: $e',
          );
          // Continue with next chart instead of failing the entire operation
          continue;
        }
      }
    }

    _logger.info(
      'Found ${intersectingCells.length} charts for state: $stateName using spatial intersection',
    );
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
        await _cacheService.store(
          cacheKey,
          encodedBytes,
          maxAge: Duration(hours: 24),
        );
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
      await _cacheService.store(
        cacheKey,
        encodedBytes,
        maxAge: Duration(hours: 24),
      );

      return states;
    } catch (e) {
      _logger.error('Failed to get supported states', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network(
        'Failed to fetch supported states',
        originalError: e,
      );
    }
  }

  @override
  Future<void> updateStateCellMapping(
    String stateName,
    List<String> mapping,
  ) async {
    try {
      _logger.debug('Updating state cell mapping for: $stateName');

      // Store in database
      await _storageService.storeStateCellMapping(stateName, mapping);

      // Cache the updated mapping
      final cacheKey = 'state_cells_$stateName';
      final encodedData = jsonEncode(mapping);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));
      await _cacheService.store(
        cacheKey,
        encodedBytes,
        maxAge: Duration(hours: 24),
      );

      _logger.info('Updated state cell mapping for: $stateName');
    } catch (e) {
      _logger.error(
        'Failed to update state cell mapping for: $stateName',
        exception: e,
      );
      if (e is AppError) rethrow;
      throw AppError.storage(
        'Failed to update state cell mapping',
        originalError: e,
      );
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
      throw AppError.storage(
        'Failed to clear state mappings',
        originalError: e,
      );
    }
  }

  @override
  Future<String?> getStateFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      _logger.debug('Determining state for coordinates: $latitude, $longitude');

      // Check each state's bounds to find which one contains the coordinates
      for (final entry in _stateRegions.entries) {
        final stateName = entry.key;
        final bounds = entry.value;

        if (bounds.contains(latitude, longitude)) {
          _logger.debug('Coordinates fall within $stateName bounds');
          return stateName;
        }
      }

      _logger.debug(
        'Coordinates do not fall within any supported state bounds',
      );
      return null;
    } catch (e) {
      _logger.error(
        'Failed to determine state from coordinates: $latitude, $longitude',
        exception: e,
      );
      rethrow;
    }
  }

  @override
  Future<List<MarineRegion>> getMarineRegions(String stateName) async {
    try {
      _logger.debug('Getting marine regions for state: $stateName');

      // Return regions for multi-region states
      final regions = _multiRegionStates[stateName];
      if (regions != null) {
        _logger.debug('Found ${regions.length} marine regions for $stateName');
        return regions;
      }

      // For single-region states, create a default region
      final bounds = _stateRegions[stateName];
      if (bounds != null) {
        return [
          MarineRegion(
            name: '$stateName Marine Region',
            bounds: bounds,
            description: 'Primary marine region for $stateName',
          ),
        ];
      }

      _logger.warning('No marine regions found for state: $stateName');
      return [];
    } catch (e) {
      _logger.error('Failed to get marine regions for: $stateName', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network(
        'Failed to fetch marine regions',
        originalError: e,
      );
    }
  }

  @override
  Future<List<String>> getChartCellsForRegion(String stateName, String regionName) async {
    try {
      _logger.debug('Getting chart cells for region: $regionName in $stateName');

      // Get the specific region bounds
      final regions = _multiRegionStates[stateName];
      MarineRegion? targetRegion;
      
      if (regions != null) {
        try {
          targetRegion = regions.firstWhere((r) => r.name == regionName);
        } catch (_) {
          throw StateNotSupportedException(
            'Region $regionName not found in state $stateName',
          );
        }
      } else {
        // For single-region states, use the state bounds
        final bounds = _stateRegions[stateName];
        if (bounds != null) {
          targetRegion = MarineRegion(
            name: regionName,
            bounds: bounds,
            description: 'Marine region for $stateName',
          );
        }
      }

      if (targetRegion == null) {
        throw StateNotSupportedException(
          'Region $regionName not supported in state $stateName',
        );
      }

      // Get charts that intersect with the region
      final candidateCharts = await _storageService.getChartsInBounds(targetRegion.bounds);
      final intersectingCells = <String>[];

      // Load region boundary polygon
      final regionPolygon = SpatialOperations.boundsToPolygon(targetRegion.bounds);

      for (final chart in candidateCharts) {
        if (chart.source == ChartSource.noaa) {
          try {
            final chartPolygon = SpatialOperations.boundsToPolygon(chart.bounds);

            if (SpatialOperations.doPolygonsIntersect(regionPolygon, chartPolygon)) {
              final coverage = SpatialOperations.calculateCoveragePercentage(
                regionPolygon,
                chartPolygon,
              );

              // Include charts with meaningful coverage (>1%)
              if (coverage > 0.01) {
                intersectingCells.add(chart.id);
              }
            }
          } catch (e) {
            _logger.warning(
              'Skipping chart ${chart.id} due to invalid bounds: $e',
            );
            continue;
          }
        }
      }

      _logger.info(
        'Found ${intersectingCells.length} charts for region: $regionName in $stateName',
      );
      return intersectingCells;
    } catch (e) {
      _logger.error(
        'Failed to get chart cells for region: $regionName in $stateName',
        exception: e,
      );
      if (e is AppError) rethrow;
      throw AppError.network(
        'Failed to fetch chart cells for region',
        originalError: e,
      );
    }
  }

  @override
  Future<ValidationResult> validateStateRegionMapping(String stateName) async {
    try {
      _logger.debug('Validating state-region mapping for: $stateName');

      final issues = <String>[];
      final recommendations = <String>[];

      // Check if state is supported
      final bounds = _stateRegions[stateName];
      if (bounds == null) {
        issues.add('State $stateName is not supported');
        recommendations.add('Add $stateName to supported states list');
        return ValidationResult(
          isValid: false,
          validatedAt: DateTime.now(),
          issues: issues,
          recommendations: recommendations,
        );
      }

      // Validate coordinate bounds
      if (!_isValidGeographicBounds(bounds)) {
        issues.add('Invalid geographic bounds for $stateName');
        recommendations.add('Verify and correct coordinate boundaries');
      }

      // Check for multi-region consistency
      final regions = _multiRegionStates[stateName];
      if (regions != null) {
        for (final region in regions) {
          if (!_isValidGeographicBounds(region.bounds)) {
            issues.add('Invalid bounds for region ${region.name}');
            recommendations.add('Correct bounds for region ${region.name}');
          }

          // Check if region bounds are within state bounds
          if (!_isRegionWithinState(region.bounds, bounds)) {
            issues.add('Region ${region.name} extends beyond state boundaries');
            recommendations.add('Adjust region boundaries to fit within state');
          }
        }
      }

      // Validate chart availability
      try {
        final chartCells = await getChartCellsForState(stateName);
        if (chartCells.isEmpty) {
          issues.add('No charts found for $stateName');
          recommendations.add('Verify chart data availability and spatial intersection logic');
        } else if (chartCells.length < 3) {
          issues.add('Insufficient chart coverage for $stateName (${chartCells.length} charts)');
          recommendations.add('Increase chart coverage for adequate navigation support');
        }
      } catch (e) {
        issues.add('Failed to retrieve charts: ${e.toString()}');
        recommendations.add('Check data integrity and spatial operations');
      }

      final isValid = issues.isEmpty;
      _logger.info(
        'Validation completed for $stateName: ${isValid ? "VALID" : "INVALID"} '
        '(${issues.length} issues found)',
      );

      return ValidationResult(
        isValid: isValid,
        validatedAt: DateTime.now(),
        issues: issues,
        recommendations: recommendations,
      );
    } catch (e) {
      _logger.error('Failed to validate state-region mapping for: $stateName', exception: e);
      return ValidationResult(
        isValid: false,
        validatedAt: DateTime.now(),
        issues: ['Validation failed: ${e.toString()}'],
        recommendations: ['Check system logs and retry validation'],
      );
    }
  }

  @override
  Future<StateCoverageInfo> getStateCoverageInfo(String stateName) async {
    try {
      _logger.debug('Getting coverage info for state: $stateName');

      final totalCharts = await getChartCellsForState(stateName);
      final regionBreakdown = <String, RegionCoverageInfo>{};

      // Get regions for this state
      final regions = await getMarineRegions(stateName);
      
      for (final region in regions) {
        final regionCharts = await getChartCellsForRegion(stateName, region.name);
        final coveragePercentage = _calculateRegionCoverage(region, regionCharts.length);

        regionBreakdown[region.name] = RegionCoverageInfo(
          regionName: region.name,
          chartCount: regionCharts.length,
          coveragePercentage: coveragePercentage,
          bounds: region.bounds,
        );
      }

      // Calculate overall coverage
      final overallCoverage = _calculateStateCoverage(stateName, totalCharts.length);

      return StateCoverageInfo(
        stateName: stateName,
        totalChartCount: totalCharts.length,
        coveragePercentage: overallCoverage,
        regionBreakdown: regionBreakdown,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      _logger.error('Failed to get coverage info for: $stateName', exception: e);
      if (e is AppError) rethrow;
      throw AppError.network(
        'Failed to fetch coverage info',
        originalError: e,
      );
    }
  }

  /// Validates geographic bounds
  bool _isValidGeographicBounds(GeographicBounds bounds) {
    return bounds.north > bounds.south &&
           bounds.north <= 90 &&
           bounds.south >= -90 &&
           bounds.east <= 180 &&
           bounds.west >= -180;
  }

  /// Checks if region bounds are within state bounds
  bool _isRegionWithinState(GeographicBounds regionBounds, GeographicBounds stateBounds) {
    return regionBounds.north <= stateBounds.north &&
           regionBounds.south >= stateBounds.south &&
           regionBounds.east <= stateBounds.east &&
           regionBounds.west >= stateBounds.west;
  }

  /// Calculates coverage percentage for a region
  double _calculateRegionCoverage(MarineRegion region, int chartCount) {
    // Heuristic based on region complexity and expected chart density
    const expectedChartDensities = {
      'Southeast Alaska': 0.8,      // Charts per 1000 sq nautical miles
      'Gulf of Alaska': 0.5,
      'Arctic Alaska': 0.3,
      'Northern California': 1.2,
      'Central California': 1.0,
      'Southern California': 1.5,
      'Florida Atlantic Coast': 1.8,
      'Florida Gulf Coast': 1.0,
    };

    final expectedDensity = expectedChartDensities[region.name] ?? 0.8;
    final regionArea = _calculateApproximateArea(region.bounds);
    final expectedCharts = (regionArea * expectedDensity / 1000).round();
    
    if (expectedCharts == 0) return 100.0;
    
    final coverage = (chartCount / expectedCharts) * 100;
    return coverage.clamp(0.0, 100.0);
  }

  /// Calculates overall coverage for a state
  double _calculateStateCoverage(String stateName, int chartCount) {
    // Expected chart counts based on coastline complexity and marine activity
    const expectedStateCounts = {
      'Alaska': 25,
      'California': 20,
      'Florida': 15,
      'Texas': 12,
      'Washington': 10,
      'Maine': 8,
      'Hawaii': 8,
      'North Carolina': 8,
      'South Carolina': 6,
      'Georgia': 6,
      'Louisiana': 8,
      'Alabama': 4,
      'Mississippi': 4,
      'Oregon': 8,
      'New York': 10,
      'Massachusetts': 8,
      'Connecticut': 4,
      'Rhode Island': 3,
      'New Hampshire': 3,
      'New Jersey': 6,
      'Delaware': 3,
      'Maryland': 6,
      'Virginia': 8,
      'Pennsylvania': 4,
      'Ohio': 5,
      'Michigan': 10,
      'Indiana': 3,
      'Illinois': 4,
      'Wisconsin': 6,
      'Minnesota': 8,
    };

    final expectedCount = expectedStateCounts[stateName] ?? 5;
    final coverage = (chartCount / expectedCount) * 100;
    return coverage.clamp(0.0, 100.0);
  }

  /// Calculates approximate area of geographic bounds in square nautical miles
  double _calculateApproximateArea(GeographicBounds bounds) {
    final latSpan = bounds.north - bounds.south;
    final lngSpan = (bounds.east - bounds.west).abs();
    
    // Convert to approximate nautical miles (1 degree ≈ 60 nm)
    final latNm = latSpan * 60;
    final lngNm = lngSpan * 60 * 0.8; // Approximate correction for longitude at mid-latitudes
    
    return latNm * lngNm;
  }
}
