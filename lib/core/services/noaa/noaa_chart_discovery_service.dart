import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

/// Abstract interface for NOAA chart discovery operations
abstract class NoaaChartDiscoveryService {
  /// Discovers charts available for a specific US state
  Future<List<Chart>> discoverChartsByState(String state);

  /// Discovers charts based on GPS location coordinates
  /// 
  /// Finds NOAA charts that cover the specified geographic location.
  /// This method automatically determines the appropriate state/region
  /// and returns relevant charts for the area.
  /// 
  /// Parameters:
  /// - position: GPS coordinates to search around
  /// 
  /// Returns list of charts covering the specified location
  Future<List<Chart>> discoverChartsByLocation(GpsPosition position);

  /// Searches charts by title or other metadata
  Future<List<Chart>> searchCharts(String query, {Map<String, String>? filters});

  /// Gets metadata for a specific chart by ID
  Future<Chart?> getChartMetadata(String chartId);

  /// Watches chart updates for a specific state (reactive stream)
  Stream<List<Chart>> watchChartsForState(String state);

  /// Refreshes the chart catalog cache
  Future<bool> refreshCatalog({bool force = false});

  /// Fixes chart discovery issues by clearing invalid cached data and forcing refresh
  Future<int> fixChartDiscoveryCache();
}

/// Implementation of NOAA chart discovery service
class NoaaChartDiscoveryServiceImpl implements NoaaChartDiscoveryService {
  final ChartCatalogService _catalogService;
  final StateRegionMappingService _mappingService;
  final StorageService _storageService;
  final AppLogger _logger;

  NoaaChartDiscoveryServiceImpl({
    required ChartCatalogService catalogService,
    required StateRegionMappingService mappingService,
    required StorageService storageService,
    required AppLogger logger,
  }) : _catalogService = catalogService,
       _mappingService = mappingService,
       _storageService = storageService,
       _logger = logger;

  @override
  Future<List<Chart>> discoverChartsByState(String state) async {
    if (state.trim().isEmpty) {
      throw ArgumentError('State name cannot be empty');
    }

    _logger.debug('Discovering charts for state: $state');
    
    try {
      // Ensure catalog is bootstrapped before discovery
      await _catalogService.ensureCatalogBootstrapped();
      
      final cellNames = await _mappingService.getChartCellsForState(state);
      final charts = <Chart>[];
      
      for (final cellName in cellNames) {
        final chart = await _catalogService.getCachedChart(cellName);
        if (chart != null) {
          charts.add(chart);
        }
      }
      
      _logger.info('Found ${charts.length} charts for state $state');
      return charts;
    } catch (error) {
      _logger.error('Failed to discover charts for state $state', exception: error);
      rethrow;
    }
  }

  @override
  Future<List<Chart>> discoverChartsByLocation(GpsPosition position) async {
    _logger.debug('Discovering charts for location: ${position.latitude}, ${position.longitude}');
    
    try {
      // Ensure catalog is bootstrapped before discovery
      await _catalogService.ensureCatalogBootstrapped();
      
      // Determine state based on coordinates
      final state = await _mappingService.getStateFromCoordinates(
        position.latitude, 
        position.longitude
      );
      
      if (state == null) {
        _logger.warning('No state found for coordinates: ${position.latitude}, ${position.longitude}');
        return [];
      }
      
      _logger.debug('Location maps to state: $state');
      
      // Use existing state-based discovery
      final charts = await discoverChartsByState(state);
      
      // Filter charts that actually cover the specific location
      final coveringCharts = charts.where((chart) => 
        chart.coversPoint(position.latitude, position.longitude)
      ).toList();
      
      // Sort by scale (smaller scale = larger area = lower priority for specific location)
      coveringCharts.sort((a, b) => a.scale.compareTo(b.scale));
      
      _logger.info('Found ${coveringCharts.length} charts covering location ${position.latitude}, ${position.longitude}');
      return coveringCharts;
    } catch (error) {
      _logger.error('Failed to discover charts for location: ${position.latitude}, ${position.longitude}', exception: error);
      rethrow;
    }
  }

  @override
  Future<List<Chart>> searchCharts(String query, {Map<String, String>? filters}) async {
    if (query.trim().isEmpty) {
      throw ArgumentError('Query cannot be empty');
    }

    _logger.debug('Searching charts with query: $query');
    
    try {
      if (filters != null && filters.isNotEmpty) {
        return await _catalogService.searchChartsWithFilters(query, filters);
      } else {
        return await _catalogService.searchCharts(query);
      }
    } catch (error) {
      _logger.error('Failed to search charts with query: $query', exception: error);
      rethrow;
    }
  }

  @override
  Future<Chart?> getChartMetadata(String chartId) async {
    if (chartId.trim().isEmpty) {
      throw ArgumentError('Chart ID cannot be empty');
    }

    _logger.debug('Getting metadata for chart: $chartId');
    
    try {
      return await _catalogService.getChartById(chartId);
    } catch (error) {
      _logger.error('Failed to get metadata for chart $chartId', exception: error);
      rethrow;
    }
  }

  @override
  Stream<List<Chart>> watchChartsForState(String state) {
    if (state.trim().isEmpty) {
      throw ArgumentError('State name cannot be empty');
    }

    _logger.debug('Watching charts for state: $state');
    
    return Stream.fromFuture(_mappingService.getChartCellsForState(state))
        .asyncExpand((cellNames) async* {
          final charts = <Chart>[];
          for (final cellName in cellNames) {
            final chart = await _catalogService.getCachedChart(cellName);
            if (chart != null) {
              charts.add(chart);
            }
            
            // Add other charts from the same state
            for (final otherCellName in cellNames) {
              if (otherCellName != cellName) {
                final otherChart = await _catalogService.getCachedChart(otherCellName);
                if (otherChart != null) {
                  charts.add(otherChart);
                }
              }
            }
          }
          
          yield List.from(charts);
        });
  }

  @override
  Future<bool> refreshCatalog({bool force = false}) async {
    _logger.debug('Refreshing chart catalog (force: $force)');
    
    try {
      return await _catalogService.refreshCatalog(force: force);
    } catch (error) {
      _logger.error('Failed to refresh catalog', exception: error);
      rethrow;
    }
  }

  @override
  Future<int> fixChartDiscoveryCache() async {
    _logger.info('Starting chart discovery cache fix for invalid bounds issue');
    
    try {
      // Check if we have any charts with invalid bounds (from old cache)
      final invalidCount = await _storageService.countChartsWithInvalidBounds();
      
      if (invalidCount == 0) {
        _logger.info('No charts with invalid bounds found - cache is clean');
        return 0;
      }
      
      _logger.warning('Found $invalidCount charts with invalid bounds - clearing and forcing refresh');
      
      // Clear charts with invalid bounds (cache invalidation)
      final clearedCount = await _storageService.clearChartsWithInvalidBounds();
      
      // Force refresh the catalog to re-fetch with correct geometry
      await _catalogService.refreshCatalog(force: true);
      
      // Bootstrap the catalog to ensure new charts are cached with correct bounds
      await _catalogService.ensureCatalogBootstrapped();
      
      _logger.info('Chart discovery cache fix completed: cleared $clearedCount charts, forcing catalog refresh');
      return clearedCount;
      
    } catch (error) {
      _logger.error('Failed to fix chart discovery cache', exception: error);
      rethrow;
    }
  }
}