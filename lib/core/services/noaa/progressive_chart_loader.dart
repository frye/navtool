import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;


import '../../models/chart.dart';
import '../../models/geographic_bounds.dart';
import '../../error/network_error_classifier.dart';
import '../../utils/retryable_operation.dart';
import '../../logging/app_logger.dart';
import 'noaa_api_client.dart';

/// Progress information for chart loading operations
class ChartLoadProgress {
  const ChartLoadProgress({
    required this.stage,
    required this.currentItem,
    required this.totalItems,
    required this.completedItems,
    required this.progress,
    required this.eta,
    required this.currentItemName,
    required this.loadedCharts,
    this.error,
  });

  /// Current loading stage
  final ChartLoadStage stage;
  
  /// Current item being processed
  final int currentItem;
  
  /// Total number of items to process
  final int totalItems;
  
  /// Number of completed items
  final int completedItems;
  
  /// Overall progress as percentage (0.0 to 1.0)
  final double progress;
  
  /// Estimated time remaining
  final Duration? eta;
  
  /// Name or identifier of current item being processed
  final String currentItemName;
  
  /// Charts loaded so far (partial results)
  final List<Chart> loadedCharts;
  
  /// Error that occurred during loading (if any)
  final Exception? error;
  
  /// Whether loading has completed successfully
  bool get isCompleted => progress >= 1.0 && error == null;
  
  /// Whether an error occurred
  bool get hasError => error != null;
  
  /// Whether loading can be cancelled
  bool get canCancel => !isCompleted && !hasError;
}

/// Stages of the chart loading process
enum ChartLoadStage {
  /// Initializing the loading process
  initializing,
  
  /// Fetching chart catalog metadata
  fetchingCatalog,
  
  /// Processing individual chart entries
  processingCharts,
  
  /// Finalizing and completing the load
  finalizing,
  
  /// Loading completed successfully
  completed,
  
  /// Loading was cancelled by user
  cancelled,
  
  /// Loading failed with error
  failed,
}

/// Exception thrown when progressive loading is cancelled
class ProgressiveLoadingCancelledException implements Exception {
  const ProgressiveLoadingCancelledException(this.message);
  
  final String message;
  
  @override
  String toString() => 'ProgressiveLoadingCancelledException: $message';
}

/// Service for progressive chart loading with real-time progress updates
///
/// Provides chunked catalog downloads, progress streaming, and cancellation
/// capabilities optimized for marine environments with limited bandwidth.
class ProgressiveChartLoader {
  ProgressiveChartLoader({
    required NoaaApiClient apiClient,
    required AppLogger logger,
  }) : _apiClient = apiClient,
       _logger = logger;

  final NoaaApiClient _apiClient;
  final AppLogger _logger;
  
  // Cancellation and progress tracking
  final Map<String, StreamController<ChartLoadProgress>> _activeLoads = {};
  final Map<String, Completer<void>> _cancellationTokens = {};
  
  /// Configuration for progressive loading
  static const int _defaultChunkSize = 25; // Process charts in chunks of 25
  static const Duration _chunkDelay = Duration(milliseconds: 100); // Small delay between chunks
  static const Duration _progressUpdateInterval = Duration(milliseconds: 500); // Progress updates every 500ms

  /// Loads charts with real-time progress updates
  ///
  /// Returns a stream that emits progress updates as charts are loaded.
  /// Supports cancellation and provides partial results during loading.
  ///
  /// [region] Optional region filter (e.g., 'Washington', 'California')
  /// [chunkSize] Number of charts to process in each chunk (default: 25)
  /// [loadId] Unique identifier for this loading operation
  Stream<ChartLoadProgress> loadChartsWithProgress({
    String? region,
    int chunkSize = _defaultChunkSize,
    String? loadId,
  }) {
    final effectiveLoadId = loadId ?? _generateLoadId();
    
    // Clean up any existing load with the same ID
    if (_activeLoads.containsKey(effectiveLoadId)) {
      _cleanupLoad(effectiveLoadId);
    }
    
    final controller = StreamController<ChartLoadProgress>();
    _activeLoads[effectiveLoadId] = controller;
    _cancellationTokens[effectiveLoadId] = Completer<void>();
    
    // Start the loading process asynchronously
    _executeProgressiveLoad(
      effectiveLoadId,
      controller,
      region: region,
      chunkSize: chunkSize,
    ).catchError((error) {
      _logger.error(
        'Progressive chart loading failed: $error',
        context: 'ProgressiveChartLoader',
        exception: error,
      );
      
      if (!controller.isClosed) {
        controller.add(ChartLoadProgress(
          stage: ChartLoadStage.failed,
          currentItem: 0,
          totalItems: 0,
          completedItems: 0,
          progress: 0.0,
          eta: null,
          currentItemName: '',
          loadedCharts: [],
          error: error is Exception ? error : Exception(error.toString()),
        ));
        controller.close();
      }
      _cleanupLoad(effectiveLoadId);
    });
    
    return controller.stream;
  }

  /// Cancels an active loading operation
  ///
  /// [loadId] The identifier of the loading operation to cancel
  Future<void> cancelLoading(String loadId) async {
    if (!_activeLoads.containsKey(loadId)) {
      _logger.warning(
        'Attempted to cancel non-existent load: $loadId',
        context: 'ProgressiveChartLoader',
      );
      return;
    }
    
    _logger.info(
      'Cancelling progressive chart loading: $loadId',
      context: 'ProgressiveChartLoader',
    );
    
    // Signal cancellation
    final cancellationToken = _cancellationTokens[loadId];
    if (cancellationToken != null && !cancellationToken.isCompleted) {
      cancellationToken.complete();
    }
    
    // Update progress stream with cancellation
    final controller = _activeLoads[loadId];
    if (controller != null && !controller.isClosed) {
      controller.add(ChartLoadProgress(
        stage: ChartLoadStage.cancelled,
        currentItem: 0,
        totalItems: 0,
        completedItems: 0,
        progress: 0.0,
        eta: null,
        currentItemName: 'Cancelled by user',
        loadedCharts: [],
        error: const ProgressiveLoadingCancelledException('Loading cancelled by user'),
      ));
      controller.close();
    }
    
    _cleanupLoad(loadId);
  }

  /// Checks if a loading operation is currently active
  bool isLoadingActive(String loadId) {
    return _activeLoads.containsKey(loadId) && 
           _cancellationTokens.containsKey(loadId) &&
           !_cancellationTokens[loadId]!.isCompleted;
  }

  /// Gets list of currently active loading operation IDs
  List<String> getActiveLoadIds() {
    return _activeLoads.keys.toList();
  }

  /// Executes the progressive loading process
  Future<void> _executeProgressiveLoad(
    String loadId,
    StreamController<ChartLoadProgress> controller,
    {
    String? region,
    required int chunkSize,
  }) async {
    final startTime = DateTime.now();
    List<Chart> loadedCharts = [];
    
    try {
      // Stage 1: Initializing
      _emitProgress(controller, ChartLoadProgress(
        stage: ChartLoadStage.initializing,
        currentItem: 0,
        totalItems: 0,
        completedItems: 0,
        progress: 0.0,
        eta: null,
        currentItemName: 'Initializing chart discovery...',
        loadedCharts: [],
      ));
      
      await _checkCancellation(loadId);
      
      // Stage 2: Fetch catalog
      _emitProgress(controller, ChartLoadProgress(
        stage: ChartLoadStage.fetchingCatalog,
        currentItem: 0,
        totalItems: 0,
        completedItems: 0,
        progress: 0.1,
        eta: null,
        currentItemName: 'Fetching NOAA chart catalog...',
        loadedCharts: [],
      ));
      
      // Fetch catalog with retry logic
      late final String catalogGeoJson;
      late final List<Chart> allCharts;
      
      try {
        catalogGeoJson = await RetryableOperation.execute(
          () => _apiClient.fetchChartCatalog(
            filters: region != null ? {'STATE': region} : null,
          ),
          shouldRetry: (error) => NetworkErrorClassifier.shouldRetry(
            NetworkErrorClassifier.classifyError(error),
          ),
        );

        // Parse the GeoJSON catalog to get chart list
        allCharts = _parseChartsFromGeoJson(catalogGeoJson);
      } catch (error) {
        // Emit error progress before rethrowing
        _emitProgress(controller, ChartLoadProgress(
          stage: ChartLoadStage.failed,
          currentItem: 0,
          totalItems: 0,
          completedItems: 0,
          progress: 0.0,
          eta: null,
          currentItemName: 'Failed to fetch catalog',
          loadedCharts: [],
          error: error is Exception ? error : Exception(error.toString()),
        ));
        rethrow;
      }
      
      await _checkCancellation(loadId);
      
      final totalCharts = allCharts.length;
      
      _logger.info(
        'Starting progressive loading of $totalCharts charts in chunks of $chunkSize',
        context: 'ProgressiveChartLoader',
      );
      
      // Stage 3: Process charts in chunks
      _emitProgress(controller, ChartLoadProgress(
        stage: ChartLoadStage.processingCharts,
        currentItem: 0,
        totalItems: totalCharts,
        completedItems: 0,
        progress: 0.15,
        eta: _estimateETA(startTime, 0, totalCharts),
        currentItemName: 'Processing charts...',
        loadedCharts: [],
      ));
      
      for (int i = 0; i < totalCharts; i += chunkSize) {
        await _checkCancellation(loadId);
        
        final end = math.min(i + chunkSize, totalCharts);
        final chunk = allCharts.sublist(i, end);
        
        // Process chunk with progress updates
        for (int j = 0; j < chunk.length; j++) {
          await _checkCancellation(loadId);
          
          final chart = chunk[j];
          final currentIndex = i + j;
          
          try {
            // Validate and enrich chart data
            final enrichedChart = await _enrichChartData(chart);
            loadedCharts.add(enrichedChart);
            
            // Emit progress update
            final progress = 0.15 + (0.75 * (currentIndex + 1) / totalCharts);
            _emitProgress(controller, ChartLoadProgress(
              stage: ChartLoadStage.processingCharts,
              currentItem: currentIndex + 1,
              totalItems: totalCharts,
              completedItems: currentIndex + 1,
              progress: progress,
              eta: _estimateETA(startTime, currentIndex + 1, totalCharts),
              currentItemName: chart.id,
              loadedCharts: List.from(loadedCharts), // Provide partial results
            ));
            
          } catch (error) {
            _logger.warning(
              'Failed to process chart ${chart.id}: $error',
              context: 'ProgressiveChartLoader',
              exception: error,
            );
            // Continue with other charts
          }
        }
        
        // Small delay between chunks to prevent overwhelming the system
        if (i + chunkSize < totalCharts) {
          await Future.delayed(_chunkDelay);
        }
      }
      
      await _checkCancellation(loadId);
      
      // Stage 4: Finalizing
      _emitProgress(controller, ChartLoadProgress(
        stage: ChartLoadStage.finalizing,
        currentItem: totalCharts,
        totalItems: totalCharts,
        completedItems: totalCharts,
        progress: 0.95,
        eta: _estimateETA(startTime, totalCharts, totalCharts),
        currentItemName: 'Finalizing chart data...',
        loadedCharts: loadedCharts,
      ));
      
      // Small delay to show finalization stage
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Stage 5: Completed
      _emitProgress(controller, ChartLoadProgress(
        stage: ChartLoadStage.completed,
        currentItem: totalCharts,
        totalItems: totalCharts,
        completedItems: totalCharts,
        progress: 1.0,
        eta: Duration.zero,
        currentItemName: 'Loading completed successfully',
        loadedCharts: loadedCharts,
      ));
      
      _logger.info(
        'Progressive chart loading completed: $loadId (${loadedCharts.length} charts loaded)',
        context: 'ProgressiveChartLoader',
      );
      
    } catch (error) {
      if (error is ProgressiveLoadingCancelledException) {
        // Cancellation already handled
        return;
      }
      
      _logger.error(
        'Progressive chart loading failed: $loadId - $error',
        context: 'ProgressiveChartLoader',
        exception: error,
      );
      
      rethrow;
    } finally {
      if (!controller.isClosed) {
        controller.close();
      }
      _cleanupLoad(loadId);
    }
  }

  /// Checks if loading should be cancelled
  Future<void> _checkCancellation(String loadId) async {
    final cancellationToken = _cancellationTokens[loadId];
    if (cancellationToken != null && cancellationToken.isCompleted) {
      throw const ProgressiveLoadingCancelledException('Loading was cancelled');
    }
  }

  /// Emits progress update to the stream
  void _emitProgress(StreamController<ChartLoadProgress> controller, ChartLoadProgress progress) {
    if (!controller.isClosed) {
      controller.add(progress);
    }
  }

  /// Enriches chart data with additional validation
  Future<Chart> _enrichChartData(Chart chart) async {
    // For now, just return the chart as-is
    // In the future, this could validate metadata, check availability, etc.
    return chart;
  }

  /// Estimates time remaining based on current progress
  Duration? _estimateETA(DateTime startTime, int completed, int total) {
    if (completed == 0 || total == 0) return null;
    
    final elapsed = DateTime.now().difference(startTime);
    final rate = completed / elapsed.inMilliseconds;
    final remaining = total - completed;
    
    if (rate <= 0) return null;
    
    final etaMilliseconds = remaining / rate;
    return Duration(milliseconds: etaMilliseconds.round());
  }

  /// Generates a unique load ID
  String _generateLoadId() {
    return 'load_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Cleans up resources for a completed/cancelled load
  void _cleanupLoad(String loadId) {
    final controller = _activeLoads.remove(loadId);
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
    
    final cancellationToken = _cancellationTokens.remove(loadId);
    if (cancellationToken != null && !cancellationToken.isCompleted) {
      cancellationToken.complete();
    }
  }

  /// Dispose method to clean up all resources
  void dispose() {
    for (final loadId in _activeLoads.keys.toList()) {
      cancelLoading(loadId);
    }
  }

  /// Parses charts from GeoJSON catalog response
  List<Chart> _parseChartsFromGeoJson(String geoJsonString) {
    final catalogData = jsonDecode(geoJsonString);
    
    if (catalogData['features'] == null) {
      _logger.warning('NOAA catalog response missing features array');
      return [];
    }

    final features = catalogData['features'] as List;
    final charts = <Chart>[];

    for (final feature in features) {
      try {
        final chart = _parseChartFromFeature(feature);
        if (chart != null) {
          charts.add(chart);
        }
      } catch (e) {
        _logger.warning('Failed to parse chart feature', exception: e);
        // Continue with other charts
      }
    }

    return charts;
  }

  /// Parses a single chart from a GeoJSON feature
  Chart? _parseChartFromFeature(Map<String, dynamic> feature) {
    // Handle both GeoJSON format (properties) and regular JSON format (attributes)
    final properties = feature['properties'] ?? feature['attributes'];
    if (properties == null) return null;

    // Extract & normalize cell name
    String? cellName = (properties['DSNM'] ??
            properties['CELL_NAME'] ??
            properties['CELLNAME'] ??
            properties['name'])
        as String?;
    
    if (cellName == null || cellName.trim().isEmpty) return null;
    
    cellName = cellName.trim();
    
    // Remove edition suffix if present (e.g., "US5WA50M.000" -> "US5WA50M")
    final editionSuffixIndex = cellName.indexOf('.');
    if (editionSuffixIndex > 0 && editionSuffixIndex == cellName.length - 4) {
      final suffix = cellName.substring(editionSuffixIndex + 1);
      if (RegExp(r'^[0-9]{3}').hasMatch(suffix)) {
        cellName = cellName.substring(0, editionSuffixIndex);
      }
    }

    final title = properties['TITLE'] as String? ??
        properties['INFORM'] as String? ??
        'Unknown Chart';
    
    final lastUpdateStr = properties['DATE_UPD'] as String? ?? 
        properties['SORDAT'] as String?;
    
    // Parse scale from chart cell name
    final scale = _parseScaleFromCellName(cellName);
    
    // Determine chart type from cell name
    final chartType = _parseChartTypeFromCellName(cellName);
    
    // Extract geographic bounds from geometry
    final bounds = _parseGeographicBounds(feature['geometry']);
    if (bounds == null) return null;
    
    // Parse last update date
    DateTime lastUpdate = DateTime.now();
    if (lastUpdateStr != null) {
      try {
        lastUpdate = DateTime.parse(lastUpdateStr);
      } catch (e) {
        lastUpdate = DateTime.now();
      }
    }

    return Chart(
      id: cellName,
      title: title,
      scale: scale,
      bounds: bounds,
      lastUpdate: lastUpdate,
      state: _determineStateFromBounds(bounds),
      type: chartType,
    );
  }

  /// Parses scale from NOAA chart cell name
  int _parseScaleFromCellName(String cellName) {
    if (cellName.length >= 3) {
      final usageBand = cellName.substring(2, 3);
      switch (usageBand) {
        case '1':
          return 3000000; // Overview
        case '2':
          return 1000000; // General
        case '3':
          return 200000; // Coastal
        case '4':
          return 50000; // Approach
        case '5':
          return 20000; // Harbor
        case '6':
          return 5000; // Berthing
        default:
          return 50000; // Default
      }
    }
    return 50000;
  }

  /// Parses chart type from NOAA chart cell name
  ChartType _parseChartTypeFromCellName(String cellName) {
    if (cellName.length >= 3) {
      final usageBand = cellName.substring(2, 3);
      switch (usageBand) {
        case '1':
          return ChartType.overview;
        case '2':
          return ChartType.general;
        case '3':
          return ChartType.coastal;
        case '4':
          return ChartType.approach;
        case '5':
          return ChartType.harbor;
        case '6':
          return ChartType.berthing;
        default:
          return ChartType.general;
      }
    }
    return ChartType.general;
  }

  /// Parses geographic bounds from GeoJSON geometry
  GeographicBounds? _parseGeographicBounds(Map<String, dynamic>? geometry) {
    if (geometry == null) return null;

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
    // Handle GeoJSON coordinates format
    else if (geometry['type'] == 'Polygon' && geometry['coordinates'] != null) {
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

    if (!validBounds) return null;

    return GeographicBounds(
      north: maxLat,
      south: minLat,
      east: maxLon,
      west: minLon,
    );
  }

  /// Determines state from geographic bounds
  String _determineStateFromBounds(GeographicBounds bounds) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLon = (bounds.east + bounds.west) / 2;

    // Simple state boundaries for common coastal states
    final stateBounds = {
      'Washington': GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8),
      'California': GeographicBounds(north: 42.0, south: 32.5, east: -114.1, west: -124.4),
      'Florida': GeographicBounds(north: 31.0, south: 24.5, east: -80.0, west: -87.6),
      'Texas': GeographicBounds(north: 36.5, south: 25.8, east: -93.5, west: -106.6),
      'Alaska': GeographicBounds(north: 71.4, south: 54.8, east: -130.0, west: -179.1),
    };

    for (final entry in stateBounds.entries) {
      final stateName = entry.key;
      final stateRegion = entry.value;
      if (centerLat >= stateRegion.south &&
          centerLat <= stateRegion.north &&
          centerLon >= stateRegion.west &&
          centerLon <= stateRegion.east) {
        return stateName;
      }
    }

    return 'Unknown';
  }
}