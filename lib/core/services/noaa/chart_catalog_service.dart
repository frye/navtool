import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/services/storage/noaa_storage_extensions.dart';

/// Abstract interface for chart catalog management and caching
abstract class ChartCatalogService {
  /// Gets a cached chart by ID, returns null if not found
  Future<Chart?> getCachedChart(String chartId);

  /// Caches a chart for future retrieval
  Future<void> cacheChart(Chart chart);

  /// Gets a chart by ID from cache
  Future<Chart?> getChartById(String chartId);

  /// Searches cached charts by query string
  Future<List<Chart>> searchCharts(String query);

  /// Searches cached charts with additional filters
  Future<List<Chart>> searchChartsWithFilters(
    String query,
    Map<String, String> filters,
  );

  /// Refreshes the catalog cache
  Future<bool> refreshCatalog({bool force = false});

  /// Bootstraps the catalog by fetching all charts from NOAA if catalog is empty
  Future<void> ensureCatalogBootstrapped();

  /// Gets count of cached charts for bootstrap status checking
  Future<int> getCachedChartCount();
}

/// Implementation of chart catalog service
class ChartCatalogServiceImpl implements ChartCatalogService {
  final CacheService _cacheService;
  final AppLogger _logger;
  final NoaaApiClient _noaaApiClient;
  final DatabaseStorageService _databaseStorageService;

  ChartCatalogServiceImpl({
    required CacheService cacheService,
    required AppLogger logger,
    required NoaaApiClient noaaApiClient,
    required DatabaseStorageService databaseStorageService,
  }) : _cacheService = cacheService,
       _logger = logger,
       _noaaApiClient = noaaApiClient,
       _databaseStorageService = databaseStorageService;

  @override
  Future<Chart?> getCachedChart(String chartId) async {
    if (chartId.trim().isEmpty) {
      throw ArgumentError('Chart ID cannot be empty');
    }

    try {
      _logger.debug('Getting cached chart: $chartId');

      final cacheKey = 'chart_$chartId';
      final cached = await _cacheService.get(cacheKey);

      if (cached != null) {
        // Deserialize cached data
        final decodedData = jsonDecode(String.fromCharCodes(cached));
        return Chart.fromJson(decodedData);
      }

      return null;
    } catch (error) {
      _logger.error('Failed to get cached chart $chartId', exception: error);
      // Return null for cache errors to allow graceful fallback to network
      return null;
    }
  }

  @override
  Future<void> cacheChart(Chart chart) async {
    try {
      _logger.debug('Caching chart metadata: ${chart.id}');

      final cacheKey = 'chart_${chart.id}';
      final chartJson = chart.toJson();
      final encodedData = jsonEncode(chartJson);
      final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));

      await _cacheService.store(
        cacheKey,
        encodedBytes,
        maxAge: Duration(hours: 24),
      );

      // Update the chart list
      await _updateChartList(chart.id);

      _logger.info('Cached chart metadata: ${chart.id}');
    } catch (error) {
      _logger.error('Failed to cache chart ${chart.id}', exception: error);
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to cache chart', originalError: error);
    }
  }

  @override
  Future<Chart?> getChartById(String chartId) async {
    return await getCachedChart(chartId);
  }

  @override
  Future<List<Chart>> searchCharts(String query) async {
    try {
      _logger.debug('Searching charts with query: $query');

      // Since CacheService doesn't have getAll, we maintain a list of cached chart IDs
      final chartListKey = 'chart_list';
      final cached = await _cacheService.get(chartListKey);

      if (cached == null) {
        _logger.debug('No chart list found in cache');
        return [];
      }

      // Deserialize chart ID list
      final decodedData = jsonDecode(String.fromCharCodes(cached));
      final chartIds = List<String>.from(decodedData);

      final charts = <Chart>[];

      for (final chartId in chartIds) {
        try {
          final chart = await getCachedChart(chartId);
          if (chart != null &&
              chart.title.toLowerCase().contains(query.toLowerCase())) {
            charts.add(chart);
          }
        } catch (e) {
          _logger.warning(
            'Failed to load chart $chartId during search',
            exception: e,
          );
          // Continue with other charts
        }
      }

      _logger.info('Found ${charts.length} charts matching query: $query');
      return charts;
    } catch (error) {
      _logger.error(
        'Failed to search charts with query: $query',
        exception: error,
      );
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to search charts', originalError: error);
    }
  }

  @override
  Future<List<Chart>> searchChartsWithFilters(
    String query,
    Map<String, String> filters,
  ) async {
    try {
      _logger.debug(
        'Searching charts with query: $query and filters: $filters',
      );

      // Get all cached charts first
      final chartListKey = 'chart_list';
      final cached = await _cacheService.get(chartListKey);

      if (cached == null) {
        _logger.debug('No chart list found in cache');
        return [];
      }

      // Deserialize chart ID list
      final decodedData = jsonDecode(String.fromCharCodes(cached));
      final chartIds = List<String>.from(decodedData);

      final charts = <Chart>[];

      for (final chartId in chartIds) {
        try {
          final chart = await getCachedChart(chartId);
          if (chart == null) continue;

          // Check query match
          if (!chart.title.toLowerCase().contains(query.toLowerCase())) {
            continue;
          }

          // Check filters
          bool matchesFilters = true;
          for (final filter in filters.entries) {
            switch (filter.key.toLowerCase()) {
              case 'state':
                if (chart.state.toLowerCase() != filter.value.toLowerCase()) {
                  matchesFilters = false;
                }
                break;
              case 'type':
                if (chart.type.name.toLowerCase() !=
                    filter.value.toLowerCase()) {
                  matchesFilters = false;
                }
                break;
            }
            if (!matchesFilters) break;
          }

          if (matchesFilters) {
            charts.add(chart);
          }
        } catch (e) {
          _logger.warning(
            'Failed to load chart $chartId during filtered search',
            exception: e,
          );
          // Continue with other charts
        }
      }

      _logger.info(
        'Found ${charts.length} charts matching query: $query with filters',
      );
      return charts;
    } catch (error) {
      _logger.error(
        'Failed to search charts with filters: $query',
        exception: error,
      );
      if (error is AppError) rethrow;
      throw AppError.storage(
        'Failed to search charts with filters',
        originalError: error,
      );
    }
  }

  @override
  Future<bool> refreshCatalog({bool force = false}) async {
    try {
      _logger.info('Refreshing chart catalog cache${force ? ' (forced)' : ''}');

      // Clear chart-related cache entries
      await _cacheService.clear();

      _logger.info('Chart catalog cache refreshed');
      return true;
    } catch (error) {
      _logger.error('Failed to refresh catalog', exception: error);
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to refresh catalog', originalError: error);
    }
  }

  /// Helper method to update the cached chart list when a chart is cached
  Future<void> _updateChartList(String chartId) async {
    try {
      final chartListKey = 'chart_list';
      final cached = await _cacheService.get(chartListKey);

      List<String> chartIds = [];
      if (cached != null) {
        final decodedData = jsonDecode(String.fromCharCodes(cached));
        chartIds = List<String>.from(decodedData);
      }

      if (!chartIds.contains(chartId)) {
        chartIds.add(chartId);

        final encodedData = jsonEncode(chartIds);
        final encodedBytes = Uint8List.fromList(utf8.encode(encodedData));

        await _cacheService.store(
          chartListKey,
          encodedBytes,
          maxAge: Duration(days: 7),
        );
      }
    } catch (e) {
      _logger.warning('Failed to update chart list for $chartId', exception: e);
      // Not critical, don't throw
    }
  }

  @override
  Future<void> ensureCatalogBootstrapped() async {
    try {
      _logger.debug('Checking if chart catalog needs bootstrapping');

      // Check if catalog is already populated
      final chartCount = await getCachedChartCount();

      // Force re-bootstrap to test new geometry extraction
      // TODO: Remove this force refresh after verifying geometry extraction works
      if (chartCount > 0) {
        _logger.info(
          'Force refreshing chart catalog to test geometry extraction (chartCount: $chartCount)',
        );
      }

      _logger.info('Chart catalog is empty, bootstrapping from NOAA API...');

      // Fetch the complete chart catalog from NOAA API
      final catalogGeoJson = await _noaaApiClient.fetchChartCatalog();

      // Parse the GeoJSON catalog
      final catalogData = jsonDecode(catalogGeoJson);

      if (catalogData['features'] == null) {
        _logger.warning('NOAA catalog response missing features array');
        return;
      }

      final features = catalogData['features'] as List;
      _logger.info('Processing ${features.length} charts from NOAA catalog');

      int successCount = 0;
      int errorCount = 0;
      final List<Chart> chartsToStore =
          []; // Collect charts for database storage

      // Process each chart feature
      for (final feature in features) {
        try {
          // Handle both GeoJSON format (properties) and regular JSON format (attributes)
          final properties = feature['properties'] ?? feature['attributes'];

          if (properties == null) {
            _logger.debug(
              'Skipping feature with missing properties or attributes',
            );
            continue;
          }

          // Extract & normalize cell name
          String? cellName =
              (properties['DSNM'] ??
                      properties['CELL_NAME'] ??
                      properties['CELLNAME'] ??
                      properties['name'])
                  as String?;
          if (cellName == null || cellName.trim().isEmpty) {
            _logger.debug('Skipping feature with missing cell name');
            continue;
          }
          cellName = cellName.trim();
          final editionSuffixIndex = cellName.indexOf('.');
          if (editionSuffixIndex > 0 &&
              editionSuffixIndex == cellName.length - 4) {
            final suffix = cellName.substring(editionSuffixIndex + 1);
            if (RegExp(r'^[0-9]{3}').hasMatch(suffix)) {
              cellName = cellName.substring(0, editionSuffixIndex);
            }
          }

          final title =
              properties['TITLE'] as String? ??
              properties['INFORM'] as String? ??
              'Unknown Chart';
          final lastUpdateStr =
              properties['DATE_UPD'] as String? ??
              properties['SORDAT'] as String?;
          final usageStr = _parseUsageFromDSNM(cellName);
          final scaleStr = properties['SCALE'] as String?;

          // Parse scale from string (e.g., "1:80000" -> 80000) or estimate from dataset name
          int scale = _parseScaleFromDSNM(cellName);
          if (scaleStr != null && scaleStr.contains(':')) {
            final scaleParts = scaleStr.split(':');
            if (scaleParts.length > 1) {
              scale = int.tryParse(scaleParts[1]) ?? scale;
            }
          }

          // Determine chart type from usage
          ChartType chartType = ChartType.general;
          final usageLower = usageStr.toLowerCase();
          if (usageLower.contains('harbor')) {
            chartType = ChartType.harbor;
          } else if (usageLower.contains('approach')) {
            chartType = ChartType.approach;
          } else if (usageLower.contains('coastal')) {
            chartType = ChartType.coastal;
          } else if (usageLower.contains('overview')) {
            chartType = ChartType.overview;
          } else if (usageLower.contains('berthing')) {
            chartType = ChartType.berthing;
          }

          // Extract geographic bounds from geometry data
          GeographicBounds bounds;
          final geometry = feature['geometry'];

          if (geometry != null) {
            double minLat = double.infinity;
            double maxLat = double.negativeInfinity;
            double minLon = double.infinity;
            double maxLon = double.negativeInfinity;

            bool validBounds = false;

            // Handle ArcGIS rings format (NOAA API format)
            if (geometry['rings'] != null) {
              final rings = geometry['rings'] as List;
              for (final ring in rings) {
                if (ring is List) {
                  for (final coord in ring) {
                    if (coord is List && coord.length >= 2) {
                      final lon = (coord[0] as num).toDouble();
                      final lat = (coord[1] as num).toDouble();

                      minLat = math.min(minLat, lat);
                      maxLat = math.max(maxLat, lat);
                      minLon = math.min(minLon, lon);
                      maxLon = math.max(maxLon, lon);
                      validBounds = true;
                    }
                  }
                }
              }
            }
            // Handle GeoJSON coordinates format (backup)
            else if (geometry['type'] == 'Polygon' &&
                geometry['coordinates'] != null) {
              final coordinates = geometry['coordinates'][0] as List;
              for (final coord in coordinates) {
                if (coord is List && coord.length >= 2) {
                  final lon = (coord[0] as num).toDouble();
                  final lat = (coord[1] as num).toDouble();

                  minLat = math.min(minLat, lat);
                  maxLat = math.max(maxLat, lat);
                  minLon = math.min(minLon, lon);
                  maxLon = math.max(maxLon, lon);
                  validBounds = true;
                }
              }
            }

            if (validBounds) {
              bounds = GeographicBounds(
                north: maxLat,
                south: minLat,
                east: maxLon,
                west: minLon,
              );
              _logger.debug(
                'Extracted bounds for $cellName: ($minLon, $minLat) to ($maxLon, $maxLat)',
              );
            } else {
              // Skip charts with invalid geometry
              _logger.warning(
                'Skipping chart $cellName: no valid geometry bounds found',
              );
              continue;
            }
          } else {
            // Skip charts without geometry
            _logger.warning('Skipping chart $cellName: no geometry data');
            continue;
          }

          // Determine state from chart bounds (since NOAA API doesn't provide state)
          String state = 'Unknown';
          final centerLat = (bounds.north + bounds.south) / 2;
          final centerLon = (bounds.east + bounds.west) / 2;

          // Use predefined state boundaries to determine state
          final stateBounds = {
            'California': GeographicBounds(
              north: 42.0,
              south: 32.5,
              east: -114.1,
              west: -124.4,
            ),
            'Florida': GeographicBounds(
              north: 31.0,
              south: 24.5,
              east: -80.0,
              west: -87.6,
            ),
            'Texas': GeographicBounds(
              north: 36.5,
              south: 25.8,
              east: -93.5,
              west: -106.6,
            ),
            'Washington': GeographicBounds(
              north: 49.0,
              south: 45.5,
              east: -116.9,
              west: -124.8,
            ),
            'Alaska': GeographicBounds(
              north: 71.4,
              south: 54.8,
              east: -130.0,
              west: -179.1,
            ),
            'Hawaii': GeographicBounds(
              north: 28.4,
              south: 18.9,
              east: -154.8,
              west: -178.3,
            ),
            'Oregon': GeographicBounds(
              north: 46.3,
              south: 42.0,
              east: -116.5,
              west: -124.6,
            ),
            'Maine': GeographicBounds(
              north: 47.5,
              south: 43.1,
              east: -66.9,
              west: -71.1,
            ),
            'Massachusetts': GeographicBounds(
              north: 42.9,
              south: 41.2,
              east: -69.9,
              west: -73.5,
            ),
            'New York': GeographicBounds(
              north: 45.0,
              south: 40.5,
              east: -71.9,
              west: -79.8,
            ),
            'North Carolina': GeographicBounds(
              north: 36.6,
              south: 33.8,
              east: -75.5,
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
            'Alabama': GeographicBounds(
              north: 35.0,
              south: 30.2,
              east: -84.9,
              west: -88.5,
            ),
            'Mississippi': GeographicBounds(
              north: 35.0,
              south: 30.2,
              east: -88.1,
              west: -91.7,
            ),
            'Louisiana': GeographicBounds(
              north: 33.0,
              south: 28.9,
              east: -88.8,
              west: -94.0,
            ),
          };

          for (final entry in stateBounds.entries) {
            final stateName = entry.key;
            final stateRegion = entry.value;
            if (centerLat >= stateRegion.south &&
                centerLat <= stateRegion.north &&
                centerLon >= stateRegion.west &&
                centerLon <= stateRegion.east) {
              state = stateName;
              break;
            }
          }

          // Parse last update date
          DateTime lastUpdate = DateTime.now();
          if (lastUpdateStr != null) {
            try {
              lastUpdate = DateTime.parse(lastUpdateStr);
            } catch (e) {
              // Use current date if parsing fails
              lastUpdate = DateTime.now();
            }
          }

          // Create Chart object from GeoJSON feature
          final chart = Chart(
            id: cellName!,
            title: title,
            scale: scale,
            bounds: bounds,
            lastUpdate: lastUpdate,
            state: state,
            type: chartType,
            source: ChartSource.noaa,
            status: ChartStatus.current,
            metadata: Map<String, dynamic>.from(properties),
          );

          // Cache the chart
          await cacheChart(chart);

          // Add to list for database storage
          chartsToStore.add(chart);

          successCount++;

          // Log progress every 100 charts
          if (successCount % 100 == 0) {
            _logger.info('Bootstrapped $successCount charts so far...');
          }
        } catch (e) {
          errorCount++;
          _logger.warning(
            'Failed to process chart feature during bootstrap',
            exception: e,
          );
          // Continue processing other charts
        }
      }

      // Store all charts in database
      if (chartsToStore.isNotEmpty) {
        _logger.info('Storing ${chartsToStore.length} charts in database...');
        try {
          await _databaseStorageService.insertNoaaCharts(chartsToStore);
          _logger.info(
            'Successfully stored ${chartsToStore.length} charts in database',
          );
        } catch (e) {
          _logger.error(
            'Failed to store charts in database during bootstrap',
            exception: e,
          );
          // Don't fail the entire bootstrap if database storage fails
        }
      }

      _logger.info(
        'Chart catalog bootstrap completed: $successCount charts cached, $errorCount errors',
      );

      if (successCount == 0) {
        throw AppError.storage(
          'Failed to bootstrap chart catalog: no charts were successfully cached',
        );
      }
    } catch (error) {
      _logger.error('Failed to bootstrap chart catalog', exception: error);
      if (error is AppError) rethrow;
      throw AppError.storage(
        'Failed to bootstrap chart catalog',
        originalError: error,
      );
    }
  }

  @override
  Future<int> getCachedChartCount() async {
    try {
      final chartListKey = 'chart_list';
      final cached = await _cacheService.get(chartListKey);

      if (cached == null) {
        return 0;
      }

      final decodedData = jsonDecode(String.fromCharCodes(cached));
      final chartIds = List<String>.from(decodedData);
      return chartIds.length;
    } catch (error) {
      _logger.warning('Failed to get cached chart count', exception: error);
      return 0; // Return 0 on error to trigger bootstrap
    }
  }

  /// Parses chart usage type from NOAA dataset name
  String _parseUsageFromDSNM(String dsnm) {
    // NOAA ENC dataset names follow patterns like US5AK51M, US4AK7M, etc.
    // The number after US indicates the usage band:
    // 1 = Overview, 2 = General, 3 = Coastal, 4 = Approach, 5 = Harbour, 6 = Berthing

    if (dsnm.length >= 4) {
      final usageBand = dsnm.substring(2, 3);
      switch (usageBand) {
        case '1':
          return 'overview';
        case '2':
          return 'general';
        case '3':
          return 'coastal';
        case '4':
          return 'approach';
        case '5':
          return 'harbor';
        case '6':
          return 'berthing';
        default:
          return 'general';
      }
    }

    return 'general';
  }

  /// Estimates scale from NOAA dataset name
  int _parseScaleFromDSNM(String dsnm) {
    // Estimate scale based on usage band (rough approximations)
    if (dsnm.length >= 4) {
      final usageBand = dsnm.substring(2, 3);
      switch (usageBand) {
        case '1': // Overview
          return 3000000;
        case '2': // General
          return 1000000;
        case '3': // Coastal
          return 200000;
        case '4': // Approach
          return 50000;
        case '5': // Harbour
          return 20000;
        case '6': // Berthing
          return 5000;
        default:
          return 50000; // Default scale
      }
    }

    return 50000; // Default scale
  }
}
