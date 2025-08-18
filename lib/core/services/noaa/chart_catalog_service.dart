import 'dart:convert';
import 'dart:typed_data';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';

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
  Future<List<Chart>> searchChartsWithFilters(String query, Map<String, String> filters);

  /// Refreshes the catalog cache
  Future<bool> refreshCatalog({bool force = false});
}

/// Implementation of chart catalog service
class ChartCatalogServiceImpl implements ChartCatalogService {
  final CacheService _cacheService;
  final AppLogger _logger;

  ChartCatalogServiceImpl({
    required CacheService cacheService,
    required AppLogger logger,
  }) : _cacheService = cacheService,
       _logger = logger;

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
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to get cached chart', originalError: error);
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
      
      await _cacheService.store(cacheKey, encodedBytes, maxAge: Duration(hours: 24));
      
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
          _logger.warning('Failed to load chart $chartId during search', exception: e);
          // Continue with other charts
        }
      }
      
      _logger.info('Found ${charts.length} charts matching query: $query');
      return charts;
    } catch (error) {
      _logger.error('Failed to search charts with query: $query', exception: error);
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to search charts', originalError: error);
    }
  }

  @override
  Future<List<Chart>> searchChartsWithFilters(String query, Map<String, String> filters) async {
    try {
      _logger.debug('Searching charts with query: $query and filters: $filters');
      
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
                if (chart.type.name.toLowerCase() != filter.value.toLowerCase()) {
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
          _logger.warning('Failed to load chart $chartId during filtered search', exception: e);
          // Continue with other charts
        }
      }

      _logger.info('Found ${charts.length} charts matching query: $query with filters');
      return charts;
    } catch (error) {
      _logger.error('Failed to search charts with filters: $query', exception: error);
      if (error is AppError) rethrow;
      throw AppError.storage('Failed to search charts with filters', originalError: error);
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
        
        await _cacheService.store(chartListKey, encodedBytes, maxAge: Duration(days: 7));
      }
    } catch (e) {
      _logger.warning('Failed to update chart list for $chartId', exception: e);
      // Not critical, don't throw
    }
  }
}