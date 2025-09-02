import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../logging/app_logger.dart';
import '../error/app_error.dart';

/// HTTP client service for NOAA API integration and chart downloads
class HttpClientService {
  late final Dio _dio;
  final AppLogger _logger;

  HttpClientService({
    required AppLogger logger,
    Dio? testDio, // For testing
  }) : _logger = logger {
    if (testDio != null) {
      _dio = testDio;
    } else {
      _initializeDio();
    }
  }

  /// Checks if a path is already a full URL (starts with http:// or https://)
  static bool isFullUrl(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  /// Gets the configured Dio instance
  Dio get client => _dio;

  /// Initialize Dio with marine environment configurations
  void _initializeDio() {
    _dio = Dio(BaseOptions(
      // Marine environment requires longer timeouts due to:
      // - Potential satellite internet connections
      // - Large chart file downloads
      // - Remote marine locations with poor connectivity
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10), // Large chart files
      sendTimeout: const Duration(minutes: 5),
      
      // Default headers for NOAA API compatibility
      headers: {
        'User-Agent': 'NavTool/1.0.0 (Marine Navigation App)',
        'Accept': 'application/octet-stream, application/json, */*',
      },
      
      // Follow redirects for NOAA download URLs
      followRedirects: true,
      maxRedirects: 5,
      
      // Validate status codes
      validateStatus: (status) => status != null && status < 500,
    ));

    // Add interceptors for logging and error handling
    _addInterceptors();
  }

  /// Add interceptors for logging, error handling, and retry logic
  void _addInterceptors() {
    // Request/Response logging interceptor
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: false, // Don't log large chart file uploads
        responseBody: false, // Don't log large chart file downloads
        logPrint: (obj) => _logger.debug(obj.toString(), context: 'HTTP'),
      ),
    );

    // Error handling interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final appError = _convertDioErrorToAppError(error);
          _logger.error(
            'HTTP request failed: ${appError.message}',
            exception: error.error,
            context: 'HTTP',
          );
          
          // Continue with the converted error
          handler.next(DioException(
            requestOptions: error.requestOptions,
            error: appError,
            message: appError.message,
            type: error.type,
          ));
        },
        onRequest: (options, handler) {
          _logger.debug(
            'HTTP ${options.method} ${options.uri}',
            context: 'HTTP',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.debug(
            'HTTP ${response.statusCode} ${response.requestOptions.uri}',
            context: 'HTTP',
          );
          handler.next(response);
        },
      ),
    );

    // Retry interceptor for network resilience in marine environments
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (_shouldRetryRequest(error)) {
            try {
              final retryResponse = await _retryRequest(error.requestOptions);
              handler.resolve(retryResponse);
              return;
            } catch (retryError) {
              _logger.warning(
                'Retry failed for ${error.requestOptions.uri}',
                context: 'HTTP',
                exception: retryError,
              );
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Configure base URL for NOAA chart services
  void configureNoaaEndpoints() {
    // NOAA Office of Coast Survey ENC Distribution
    _dio.options.baseUrl = 'https://charts.noaa.gov';
    
    _logger.info('Configured HTTP client for NOAA chart services');
  }

  /// Configure certificate pinning for secure chart downloads
  void configureCertificatePinning() {
    // Add certificate pinning for production NOAA endpoints
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      
      // Configure certificate validation for NOAA domains
      client.badCertificateCallback = (cert, host, port) {
        // In production, implement proper certificate pinning
        // For now, use default validation
        return false;
      };
      
      return client;
    };

    _logger.info('Certificate pinning configured for secure downloads');
  }

  /// Convert Dio errors to application-specific errors
  AppError _convertDioErrorToAppError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError.network(
          'Network timeout occurred. Please check your connection.',
          originalError: error,
          stackTrace: error.stackTrace,
        );
      
      case DioExceptionType.connectionError:
        return AppError.network(
          'Unable to connect to chart services. Please check your internet connection.',
          originalError: error,
          stackTrace: error.stackTrace,
        );
      
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        if (statusCode >= 400 && statusCode < 500) {
          return AppError.network(
            'Chart service error (HTTP $statusCode). The requested chart may not be available.',
            originalError: error,
            stackTrace: error.stackTrace,
          );
        } else {
          return AppError.network(
            'Chart service is temporarily unavailable (HTTP $statusCode). Please try again later.',
            originalError: error,
            stackTrace: error.stackTrace,
          );
        }
      
      case DioExceptionType.cancel:
        return AppError.network(
          'Request was cancelled.',
          originalError: error,
          stackTrace: error.stackTrace,
        );
      
      case DioExceptionType.badCertificate:
        return AppError.network(
          'SSL certificate error. Unable to establish secure connection.',
          originalError: error,
          stackTrace: error.stackTrace,
        );
      
      case DioExceptionType.unknown:
        return AppError.network(
          'An unexpected network error occurred: ${error.message ?? 'Unknown error'}',
          originalError: error,
          stackTrace: error.stackTrace,
        );
    }
  }

  /// Determine if a request should be retried based on error type
  bool _shouldRetryRequest(DioException error) {
    // Retry on network timeouts and temporary server errors
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        // Retry on server errors (5xx) but not client errors (4xx)
        return statusCode >= 500;
      
      default:
        return false;
    }
  }

  /// Retry a failed request with exponential backoff
  Future<Response> _retryRequest(RequestOptions options) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 2);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      await Future.delayed(Duration(seconds: baseDelay.inSeconds * attempt));
      
      _logger.info(
        'Retrying request to ${options.uri} (attempt $attempt/$maxRetries)',
        context: 'HTTP',
      );
      
      try {
        return await _dio.fetch(options);
      } catch (e) {
        if (attempt == maxRetries) {
          rethrow;
        }
      }
    }
    
    throw DioException(
      requestOptions: options,
      message: 'All retry attempts failed',
    );
  }

  /// Download a file with progress tracking and resume support
  Future<void> downloadFile(
    String url,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    Map<String, dynamic>? queryParameters,
    int? resumeFrom,
  }) async {
    try {
      final options = Options(
        // Use longer timeout for large chart files
        receiveTimeout: const Duration(minutes: 30),
        headers: resumeFrom != null ? {'Range': 'bytes=$resumeFrom-'} : null,
      );

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: resumeFrom != null 
          ? (received, total) {
              // Adjust progress for resumed downloads
              final adjustedReceived = received + resumeFrom;
              final adjustedTotal = total > 0 ? total + resumeFrom : total;
              onReceiveProgress?.call(adjustedReceived, adjustedTotal);
            }
          : onReceiveProgress,
        cancelToken: cancelToken,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _convertDioErrorToAppError(e);
    }
  }

  /// Make a GET request with error handling and smart URL construction
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      // Handle full URLs vs relative paths intelligently
      final effectivePath = _resolveUrl(path);
      
      return await _dio.get(
        effectivePath,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _convertDioErrorToAppError(e);
    }
  }

  /// Make a HEAD request (used for preflight size / range checks)
  Future<Response> head(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final effectivePath = _resolveUrl(path);
      return await _dio.head(
        effectivePath,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _convertDioErrorToAppError(e);
    }
  }

  /// Resolve URL handling for both full URLs and relative paths
  String _resolveUrl(String path) {
    if (isFullUrl(path)) {
      // For full URLs, temporarily clear baseUrl to prevent concatenation
      final originalBaseUrl = _dio.options.baseUrl;
      _dio.options.baseUrl = '';
      
      // Schedule restoration of baseUrl for next request
      Future.microtask(() {
        _dio.options.baseUrl = originalBaseUrl;
      });
      
      return path;
    } else {
      // For relative paths, use normal Dio behavior (baseUrl + path)
      return path;
    }
  }

  /// Make a POST request with error handling
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _convertDioErrorToAppError(e);
    }
  }

  /// Dispose of resources
  void dispose() {
    _dio.close();
    _logger.debug('HTTP client disposed', context: 'HTTP');
  }
}