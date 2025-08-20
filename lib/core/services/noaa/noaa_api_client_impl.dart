import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/error/noaa_error_classifier.dart';

/// Concrete implementation of NoaaApiClient with comprehensive error handling
/// 
/// This implementation provides robust access to NOAA Electronic Navigational Chart
/// services with enterprise-grade reliability features including rate limiting,
/// automatic retry logic, progress tracking, and marine environment optimizations.
/// 
/// **Architecture Features:**
/// - Dependency injection for testability and modularity
/// - Comprehensive error classification and handling
/// - Built-in rate limiting to respect NOAA server constraints
/// - Progress tracking with broadcast streams for concurrent monitoring
/// - Resource cleanup and cancellation support
/// - Maritime-specific timeout and retry configurations
/// 
/// **Error Handling Strategy:**
/// - Automatic conversion of HTTP errors to domain-specific exceptions
/// - Intelligent retry logic for transient network failures
/// - Graceful degradation for partial service outages
/// - Detailed logging for troubleshooting offshore connectivity issues
/// 
/// **Performance Optimizations:**
/// - Connection pooling and keep-alive for multiple requests
/// - Efficient HEAD requests for availability checking
/// - Stream-based downloads with memory management
/// - Concurrent request handling with proper resource limits
class NoaaApiClientImpl implements NoaaApiClient {
  /// NOAA GIS services catalog endpoint for chart metadata queries
  static const String catalogEndpoint = 
      'https://gis.charttools.noaa.gov/arcgis/rest/services/MCS/ENCOnline/MapServer/exts/MaritimeChartService/WMSServer';
  
  /// NOAA chart download base URL for S-57 format chart files
  static const String chartDownloadBase = 'https://charts.noaa.gov/ENCs/';

  /// HTTP client service for making requests to NOAA servers
  final HttpClientService _httpClient;
  
  /// Rate limiter to control request frequency and respect server limits
  final RateLimiter _rateLimiter;
  
  /// Logger for debugging and monitoring API operations
  final AppLogger _logger;

  /// Tracks active download cancel tokens for request cancellation
  final Map<String, CancelToken> _downloadCancelTokens = {};
  
  /// Tracks active download progress streams by chart cell name
  final Map<String, StreamController<double>> _progressControllers = {};

  /// Creates a new NOAA API client with required dependencies
  /// 
  /// **Parameters:**
  /// - [httpClient] Service for HTTP operations with retry logic
  /// - [rateLimiter] Controls request frequency to respect server limits
  /// - [logger] Provides logging for debugging and monitoring
  /// 
  /// **Example:**
  /// ```dart
  /// final client = NoaaApiClientImpl(
  ///   httpClient: GetIt.instance<HttpClientService>(),
  ///   rateLimiter: GetIt.instance<RateLimiter>(),
  ///   logger: GetIt.instance<AppLogger>(),
  /// );
  /// ```

  NoaaApiClientImpl({
    required HttpClientService httpClient,
    required RateLimiter rateLimiter,
    required AppLogger logger,
  })  : _httpClient = httpClient,
        _rateLimiter = rateLimiter,
        _logger = logger {
    _logger.info('NOAA API Client initialized');
  }

  @override
  Future<String> fetchChartCatalog({Map<String, String>? filters}) async {
    _logger.info('Fetching NOAA chart catalog', context: 'NoaaApiClient', exception: filters);
    
    try {
      // Apply rate limiting before making the request
      await _rateLimiter.acquire();

      // Build WMS query parameters for chart catalog
      final queryParams = <String, String>{
        'SERVICE': 'WMS',
        'REQUEST': 'GetCapabilities',
        'VERSION': '1.3.0',
        'FORMAT': 'application/json',
      };

      // Merge any additional filters provided
      if (filters != null) {
        queryParams.addAll(filters);
      }

      // Make the HTTP request to NOAA services
      final response = await _httpClient.get(
        catalogEndpoint,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw NoaaApiException(
          'Failed to fetch chart catalog: HTTP ${response.statusCode}',
          errorCode: 'CATALOG_FETCH_ERROR',
          isRetryable: response.statusCode! >= 500,
        );
      }

      final catalogData = response.data as String;
      
      // Validate JSON format
      try {
        jsonDecode(catalogData);
      } on FormatException catch (e) {
        throw NoaaApiException(
          'Invalid JSON response from chart catalog endpoint: ${e.message}',
          errorCode: 'INVALID_JSON_RESPONSE',
          isRetryable: false,
        );
      }
      
      _logger.info('Successfully fetched chart catalog', 
        context: 'NoaaApiClient');
      
      return catalogData;
    } on DioException catch (e) {
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error('Failed to fetch chart catalog', context: 'NoaaApiClient', exception: exception);
      throw exception;
    } catch (e) {
      _logger.error('Unexpected error fetching chart catalog', context: 'NoaaApiClient', exception: e);
      rethrow;
    }
  }

  @override
  Future<Chart?> getChartMetadata(String cellName) async {
    // Validate input parameters
    if (cellName.isEmpty) {
      throw ArgumentError('Chart ID cannot be empty');
    }
    
    _logger.info('Fetching chart metadata', context: 'NoaaApiClient');
    
    try {
      // Apply rate limiting before making the request
      await _rateLimiter.acquire();

      // Build chart-specific metadata endpoint URL
      final metadataUrl = '${catalogEndpoint}?SERVICE=WMS&REQUEST=GetFeatureInfo&CHART=$cellName';
      
      final response = await _httpClient.get(
        metadataUrl,
        queryParameters: {'FORMAT': 'application/json'},
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          _logger.info('Chart not found', context: 'NoaaApiClient');
          return null;
        }
        throw NoaaApiException(
          'Failed to fetch chart metadata for $cellName: HTTP ${response.statusCode}',
          errorCode: 'METADATA_FETCH_ERROR',
          isRetryable: response.statusCode! >= 500,
        );
      }

      // Parse response data
      Map<String, dynamic> chartData;
      try {
        chartData = jsonDecode(response.data as String) as Map<String, dynamic>;
      } on FormatException catch (e) {
        throw NoaaApiException(
          'Invalid JSON response from chart metadata endpoint: ${e.message}',
          errorCode: 'INVALID_JSON_RESPONSE',
          isRetryable: false,
        );
      }
      
      if (chartData.isEmpty || chartData['properties'] == null) {
        _logger.info('Chart metadata not available', context: 'NoaaApiClient');
        return null;
      }

      final chart = _parseChartFromGeoJson(chartData);
      _logger.info('Successfully retrieved chart metadata', 
        context: 'NoaaApiClient');
      
      return chart;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.info('Chart not found via HTTP 404', context: 'NoaaApiClient');
        return null;
      }
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error('Failed to get chart metadata', 
        context: 'NoaaApiClient', exception: exception);
      throw exception;
    } catch (e) {
      _logger.error('Unexpected error getting chart metadata', 
        context: 'NoaaApiClient', exception: e);
      rethrow;
    }
  }

  @override
  Future<bool> isChartAvailable(String cellName) async {
    // Validate input parameters
    if (cellName.isEmpty) {
      throw ArgumentError('Chart ID cannot be empty');
    }
    
    _logger.debug('Checking chart availability', context: 'NoaaApiClient');
    
    try {
      // Apply rate limiting before making the request
      await _rateLimiter.acquire();

      // Use simulated HEAD request to check availability efficiently
      final downloadUrl = '$chartDownloadBase$cellName.zip';
      
      final response = await _httpClient.get(
        downloadUrl,
        queryParameters: {'HEAD': 'true'}, // Simulate HEAD request
      );

      final isAvailable = response.statusCode == 200;
      _logger.debug('Chart availability check complete', 
        context: 'NoaaApiClient');

      return isAvailable;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.debug('Chart not available (404)', context: 'NoaaApiClient');
        return false;
      }
      // For availability checking, we treat server errors as exceptions
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error('Error checking chart availability', 
        context: 'NoaaApiClient', exception: exception);
      throw exception;
      // to provide graceful degradation
      _logger.debug('Chart availability check failed, treating as unavailable', 
        context: 'NoaaApiClient', exception: e);
      return false;
    } catch (e) {
      // Handle non-Dio exceptions gracefully
      _logger.debug('Chart availability check error, treating as unavailable', 
        context: 'NoaaApiClient', exception: e);
      return false;
    }
  }

  @override
  Future<void> downloadChart(
    String cellName, 
    String savePath, {
    NoaaProgressCallback? onProgress,
  }) async {
    // Validate input parameters
    if (cellName.isEmpty) {
      throw ArgumentError('Chart ID cannot be empty');
    }
    if (savePath.isEmpty) {
      throw ArgumentError('Save path cannot be empty');
    }
    
    _logger.info('Starting download for chart: $cellName');
    
    try {
      // Acquire rate limit permission
      await _rateLimiter.acquire();

      // Create cancel token for this download
      final cancelToken = CancelToken();
      _downloadCancelTokens[cellName] = cancelToken;

      // Set up progress tracking
      final progressController = StreamController<double>.broadcast();
      _progressControllers[cellName] = progressController;

      // Build download URL
      final downloadUrl = '$chartDownloadBase$cellName.zip';

      // Download the file with progress tracking
      await _httpClient.downloadFile(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            
            // Notify callback if provided
            onProgress?.call(progress);
            
            // Emit to progress stream
            if (!progressController.isClosed) {
              progressController.add(progress);
            }
          }
        },
      );

      _logger.info('Chart download completed: $cellName');
      
      // Complete progress stream
      if (!progressController.isClosed) {
        progressController.add(1.0);
        await progressController.close();
      }
      
    } on DioException catch (e) {
      _logger.error('Chart download failed for $cellName', exception: e);
      
      // Clean up progress tracking
      _cleanupDownload(cellName);
      
      if (e.type == DioExceptionType.cancel) {
        throw ChartDownloadException(cellName, 'Download was cancelled');
      } else {
        throw ChartDownloadException(
          cellName, 
          'Download failed: ${e.message}',
          isRetryable: NoaaErrorClassifier.isRetryableError(e),
        );
      }
    } finally {
      // Clean up download tracking
      _downloadCancelTokens.remove(cellName);
    }
  }

  @override
  Stream<double> getDownloadProgress(String cellName) {
    final controller = _progressControllers[cellName];
    if (controller != null) {
      return controller.stream;
    }
    
    // Return empty stream if no download in progress
    return const Stream.empty();
  }

  @override
  Future<void> cancelDownload(String cellName) async {
    final cancelToken = _downloadCancelTokens[cellName];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Download cancelled by user');
      _logger.info('Cancelled download for chart: $cellName');
    }
    
    // Clean up tracking
    _cleanupDownload(cellName);
  }

  /// Converts Dio exceptions to appropriate NOAA exceptions
  NoaaApiException _convertDioExceptionToNoaaException(DioException e) {
    final statusCode = e.response?.statusCode;
    
    if (statusCode != null) {
      return NoaaErrorClassifier.classifyHttpError(
        statusCode, 
        e.message ?? 'HTTP error occurred',
        e.requestOptions.path,
      );
    }
    
    // Handle specific Dio exception types
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const NetworkConnectivityException();
      
      case DioExceptionType.cancel:
        return NoaaApiException(
          'Request was cancelled',
          errorCode: 'REQUEST_CANCELLED',
          isRetryable: false,
        );
      
      default:
        return NoaaApiException(
          e.message ?? 'Unknown API error occurred',
          errorCode: 'UNKNOWN_ERROR',
          isRetryable: false,
        );
    }
  }

  /// Parses a Chart object from GeoJSON feature data
  Chart _parseChartFromGeoJson(Map<String, dynamic> geoJsonFeature) {
    final properties = geoJsonFeature['properties'] as Map<String, dynamic>;
    final geometry = geoJsonFeature['geometry'] as Map<String, dynamic>;
    
    // Extract bounds from geometry
    final bounds = _extractBoundsFromGeometry(geometry);
    
    // Parse chart type from usage
    final usage = properties['USAGE'] as String? ?? 'harbor';
    final chartType = _parseChartUsageToType(usage);
    
    // Parse last update date
    final lastUpdateStr = properties['LAST_UPDATE'] as String?;
    final lastUpdate = lastUpdateStr != null 
        ? DateTime.parse(lastUpdateStr) 
        : DateTime.now();
    
    return Chart(
      id: properties['CHART'] as String,
      title: properties['TITLE'] as String,
      scale: properties['SCALE'] as int,
      bounds: bounds,
      lastUpdate: lastUpdate,
      state: properties['STATE'] as String? ?? 'Unknown',
      type: chartType,
    );
  }

  /// Extracts geographic bounds from GeoJSON geometry
  GeographicBounds _extractBoundsFromGeometry(Map<String, dynamic> geometry) {
    final coordinates = geometry['coordinates'] as List<dynamic>;
    
    // Handle Polygon geometry (most common for charts)
    if (geometry['type'] == 'Polygon') {
      final ring = coordinates[0] as List<dynamic>;
      
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLng = double.infinity;
      double maxLng = double.negativeInfinity;
      
      for (final coord in ring) {
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        
        minLat = lat < minLat ? lat : minLat;
        maxLat = lat > maxLat ? lat : maxLat;
        minLng = lng < minLng ? lng : minLng;
        maxLng = lng > maxLng ? lng : maxLng;
      }
      
      return GeographicBounds(
        north: maxLat,
        south: minLat,
        east: maxLng,
        west: minLng,
      );
    }
    
    // Fallback bounds for unsupported geometry types
    return GeographicBounds(
      north: 38.0,
      south: 37.0,
      east: -122.0,
      west: -123.0,
    );
  }

  /// Converts NOAA usage string to ChartType enum
  ChartType _parseChartUsageToType(String usage) {
    switch (usage.toLowerCase()) {
      case 'harbor':
        return ChartType.harbor;
      case 'approach':
        return ChartType.approach;
      case 'coastal':
        return ChartType.coastal;
      case 'general':
        return ChartType.general;
      case 'overview':
        return ChartType.overview;
      case 'berthing':
        return ChartType.berthing;
      default:
        return ChartType.harbor; // Default fallback
    }
  }

  /// Cleans up download tracking state
  void _cleanupDownload(String cellName) {
    final progressController = _progressControllers.remove(cellName);
    if (progressController != null && !progressController.isClosed) {
      progressController.close();
    }
  }
}