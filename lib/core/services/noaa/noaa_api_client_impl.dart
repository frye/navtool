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
  /// NOAA Chart catalog endpoint (ArcGIS REST service for chart coverage data)
  static const String catalogEndpoint =
      'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query';

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
  }) : _httpClient = httpClient,
       _rateLimiter = rateLimiter,
       _logger = logger {
    _logger.info('NOAA API Client initialized');
  }

  @override
  Future<String> fetchChartCatalog({Map<String, String>? filters}) async {
    _logger.info(
      'Fetching NOAA chart catalog (paginated)',
      context: 'NoaaApiClient',
      exception: filters,
    );

    try {
      final List<dynamic> allFeatures = [];
      int offset = 0;
      const int pageSize = 1000; // ArcGIS transfer limit per request
      bool more = true;
      Map<String, dynamic>? templateResponse; // Keep last response structure

      while (more) {
        await _rateLimiter.acquire();
        final queryParams = <String, String>{
          'where': '1=1',
          'outFields': '*',
          'f': 'json',
          'returnGeometry': 'true',
          'resultRecordCount': '$pageSize',
          'resultOffset': '$offset',
        };
        if (filters != null) queryParams.addAll(filters);

        final response = await _httpClient.get(
          catalogEndpoint,
          queryParameters: queryParams,
        );

        if (response.statusCode != 200) {
          final statusCode = response.statusCode ?? 0;
          throw NoaaApiException(
            'Failed to fetch chart catalog page @offset=$offset: HTTP $statusCode',
            errorCode: 'CATALOG_FETCH_ERROR',
            isRetryable: statusCode >= 500,
          );
        }

        Map<String, dynamic> responseData;
        if (response.data is String) {
          try {
            responseData =
                jsonDecode(response.data as String) as Map<String, dynamic>;
          } on FormatException catch (e) {
            throw NoaaApiException(
              'Invalid JSON response (offset $offset): ${e.message}',
              errorCode: 'INVALID_JSON_RESPONSE',
              isRetryable: false,
            );
          }
        } else if (response.data is Map<String, dynamic>) {
          responseData = response.data as Map<String, dynamic>;
        } else {
          throw NoaaApiException(
            'Unexpected response type (offset $offset): ${response.data.runtimeType}',
            errorCode: 'INVALID_RESPONSE_TYPE',
            isRetryable: false,
          );
        }

        final features =
            (responseData['features'] as List<dynamic>?) ?? const [];
        if (templateResponse == null) {
          templateResponse = Map<String, dynamic>.from(responseData)
            ..remove('features');
        }
        allFeatures.addAll(features);

        final exceeded = responseData['exceededTransferLimit'] == true;
        _logger.info(
          'Fetched page: offset=$offset features=${features.length} exceeded=$exceeded',
          context: 'NoaaApiClient',
        );

        if (!exceeded || features.isEmpty) {
          more = false;
        } else {
          offset += features.length;
        }
        // Safety break to avoid infinite loop
        if (offset > 20000) {
          _logger.warning(
            'Stopping pagination early after 20000 features to avoid runaway loop',
          );
          more = false;
        }
      }

      final merged = <String, dynamic>{
        ...?templateResponse,
        'features': allFeatures,
        'totalFeatures': allFeatures.length,
      };

      _logger.info(
        'Successfully fetched full catalog: ${allFeatures.length} features',
        context: 'NoaaApiClient',
      );
      return jsonEncode(merged);
    } on DioException catch (e) {
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error(
        'Failed to fetch chart catalog (paginated)',
        context: 'NoaaApiClient',
        exception: exception,
      );
      throw exception;
    } catch (e) {
      _logger.error(
        'Unexpected error during paginated catalog fetch',
        context: 'NoaaApiClient',
        exception: e,
      );
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

      // Build chart-specific metadata query for ArcGIS REST
      final queryParams = <String, String>{
        'where': "DSNM='$cellName'", // Filter by dataset name (chart cell name)
        'outFields': '*', // Return all fields
        'f': 'json', // Return JSON format
        'returnGeometry': 'false', // Don't need geometry for metadata
      };

      final response = await _httpClient.get(
        catalogEndpoint,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          _logger.info('Chart not found', context: 'NoaaApiClient');
          return null;
        }
        final statusCode = response.statusCode ?? 0;
        throw NoaaApiException(
          'Failed to fetch chart metadata for $cellName: HTTP $statusCode',
          errorCode: 'METADATA_FETCH_ERROR',
          isRetryable: statusCode >= 500,
        );
      }

      // Parse response data (GeoJSON FeatureCollection)
      Map<String, dynamic> responseData;
      if (response.data is String) {
        // If it's a string, parse it as JSON
        try {
          responseData =
              jsonDecode(response.data as String) as Map<String, dynamic>;
        } on FormatException catch (e) {
          throw NoaaApiException(
            'Invalid JSON response from chart metadata endpoint: ${e.message}',
            errorCode: 'INVALID_JSON_RESPONSE',
            isRetryable: false,
          );
        }
      } else if (response.data is Map<String, dynamic>) {
        // If it's already a Map, use it directly
        responseData = response.data as Map<String, dynamic>;
      } else {
        throw NoaaApiException(
          'Unexpected response data type: ${response.data.runtimeType}',
          errorCode: 'INVALID_RESPONSE_TYPE',
          isRetryable: false,
        );
      }

      // Check if any features were returned
      final features = responseData['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) {
        _logger.info('Chart metadata not available', context: 'NoaaApiClient');
        return null;
      }

      // Use the first feature found
      final chartData = features.first as Map<String, dynamic>;
      final chart = _parseChartFromGeoJson(chartData);
      _logger.info(
        'Successfully retrieved chart metadata',
        context: 'NoaaApiClient',
      );

      return chart;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.info('Chart not found via HTTP 404', context: 'NoaaApiClient');
        return null;
      }
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error(
        'Failed to get chart metadata',
        context: 'NoaaApiClient',
        exception: exception,
      );
      throw exception;
    } catch (e) {
      _logger.error(
        'Unexpected error getting chart metadata',
        context: 'NoaaApiClient',
        exception: e,
      );
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
      _logger.debug(
        'Chart availability check complete',
        context: 'NoaaApiClient',
      );

      return isAvailable;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.debug('Chart not available (404)', context: 'NoaaApiClient');
        return false;
      }
      // For availability checking, we treat server errors as exceptions
      final exception = _convertDioExceptionToNoaaException(e);
      _logger.error(
        'Error checking chart availability',
        context: 'NoaaApiClient',
        exception: exception,
      );
      throw exception;
    } catch (e) {
      // Handle non-Dio exceptions gracefully
      _logger.debug(
        'Chart availability check error, treating as unavailable',
        context: 'NoaaApiClient',
        exception: e,
      );
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

  /// Parses a Chart object from NOAA ENC coverage data
  Chart _parseChartFromGeoJson(Map<String, dynamic> featureData) {
    final attributes = featureData['attributes'] as Map<String, dynamic>;

    // Extract chart information from NOAA ENC coverage attributes
    final dsnm = attributes['DSNM'] as String? ?? 'Unknown';
    final title =
        attributes['TITLE'] as String? ??
        attributes['INFORM'] as String? ??
        dsnm;
    final catcov = attributes['CATCOV'] as String? ?? 'unknown';

    // Determine chart type from dataset name pattern
    final chartType = _parseChartTypeFromDSNM(dsnm);

    // Use current time as last update since NOAA doesn't provide this in coverage data
    final lastUpdate = DateTime.now();

    // Extract basic scale information from dataset name if possible
    final scale = _parseScaleFromDSNM(dsnm);

    // Extract bounds from geometry if available, otherwise use reasonable defaults
    GeographicBounds bounds;
    final geometry = featureData['geometry'] as Map<String, dynamic>?;
    if (geometry != null && geometry['rings'] != null) {
      // ArcGIS JSON format uses 'rings' for polygon geometry
      bounds = _extractBoundsFromArcGISGeometry(geometry);
    } else {
      // Use region-specific default bounds based on dataset name
      bounds = _getDefaultBoundsForDataset(dsnm);
    }

    return Chart(
      id: dsnm,
      title: title,
      scale: scale,
      bounds: bounds,
      lastUpdate: lastUpdate,
      state: 'Unknown', // Will be determined later by geographic analysis
      type: chartType,
      metadata: {
        'cell_name': dsnm,
        'coverage_category': catcov,
        'inform': attributes['INFORM'] as String? ?? '',
        'source_date': attributes['SORDAT'] as String? ?? '',
        'source_indicator': attributes['SORIND'] as String? ?? '',
        'object_id': attributes['OBJECTID']?.toString() ?? '',
      },
    );
  }

  /// Determines chart type from NOAA dataset name patterns
  ChartType _parseChartTypeFromDSNM(String dsnm) {
    // NOAA ENC dataset names follow patterns like US5AK51M, US4AK7M, etc.
    // The number after US indicates the usage band:
    // 1 = Overview, 2 = General, 3 = Coastal, 4 = Approach, 5 = Harbour, 6 = Berthing

    if (dsnm.length >= 4) {
      final usageBand = dsnm.substring(2, 3);
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
          return ChartType.harbor; // Default fallback
      }
    }

    return ChartType.harbor; // Default fallback
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

  /// Extracts geographic bounds from ArcGIS JSON geometry
  GeographicBounds _extractBoundsFromArcGISGeometry(
    Map<String, dynamic> geometry,
  ) {
    final rings = geometry['rings'] as List<dynamic>?;
    if (rings == null || rings.isEmpty) {
      return _getDefaultBoundsForDataset('US1WC01M.000'); // Fallback
    }

    final firstRing = rings[0] as List<dynamic>;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;

    for (final coord in firstRing) {
      if (coord is List && coord.length >= 2) {
        final lng = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();

        minLat = lat < minLat ? lat : minLat;
        maxLat = lat > maxLat ? lat : maxLat;
        minLng = lng < minLng ? lng : minLng;
        maxLng = lng > maxLng ? lng : maxLng;
      }
    }

    return GeographicBounds(
      north: maxLat,
      south: minLat,
      east: maxLng,
      west: minLng,
    );
  }

  /// Returns reasonable default bounds for a dataset based on its name pattern
  GeographicBounds _getDefaultBoundsForDataset(String dsnm) {
    // Parse region from dataset name (e.g., US1AK90M -> Alaska, US1WC01M -> West Coast)
    if (dsnm.length >= 5) {
      final region = dsnm.substring(3, 5);
      switch (region.toUpperCase()) {
        case 'AK': // Alaska
          return GeographicBounds(
            north: 71.0,
            south: 54.0,
            east: -130.0,
            west: -180.0,
          );
        case 'WC': // West Coast
          return GeographicBounds(
            north: 49.0,
            south: 32.0,
            east: -117.0,
            west: -125.0,
          );
        case 'EC': // East Coast
          return GeographicBounds(
            north: 45.0,
            south: 25.0,
            east: -67.0,
            west: -82.0,
          );
        case 'GC': // Gulf Coast
          return GeographicBounds(
            north: 31.0,
            south: 24.0,
            east: -81.0,
            west: -97.0,
          );
        case 'HA': // Hawaii
          return GeographicBounds(
            north: 22.5,
            south: 18.5,
            east: -154.0,
            west: -161.0,
          );
        case 'BS': // Bering Sea
          return GeographicBounds(
            north: 66.0,
            south: 54.0,
            east: -157.0,
            west: -180.0,
          );
        case 'PO': // Pacific Ocean
          return GeographicBounds(
            north: 49.0,
            south: 32.0,
            east: -117.0,
            west: -180.0,
          );
        case 'EE': // Exclusive Economic Zone
          return GeographicBounds(
            north: 49.0,
            south: 24.0,
            east: -67.0,
            west: -180.0,
          );
        default:
          // Default to US waters
          return GeographicBounds(
            north: 49.0,
            south: 24.0,
            east: -67.0,
            west: -125.0,
          );
      }
    }

    // Fallback for unrecognized patterns
    return GeographicBounds(
      north: 49.0,
      south: 24.0,
      east: -67.0,
      west: -125.0,
    );
  }

  /// Cleans up download tracking state
  void _cleanupDownload(String cellName) {
    final progressController = _progressControllers.remove(cellName);
    if (progressController != null && !progressController.isClosed) {
      progressController.close();
    }
  }
}
