import 'package:dio/dio.dart';
import 'app_error.dart';

/// Network-specific error utilities for HTTP operations
class NetworkError {
  /// Creates network errors from HTTP status codes
  static AppError fromStatusCode(int statusCode, {String? message}) {
    final defaultMessage =
        message ?? _getDefaultMessageForStatusCode(statusCode);

    return AppError.network(defaultMessage, originalError: 'HTTP $statusCode');
  }

  /// Creates network error from Dio exception
  static AppError fromDioException(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
        return AppError.network(
          'Connection timeout. Please check your internet connection.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.sendTimeout:
        return AppError.network(
          'Request timeout. The server is taking too long to respond.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.receiveTimeout:
        return AppError.network(
          'Response timeout. Download is taking longer than expected.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.badResponse:
        final statusCode = exception.response?.statusCode ?? 0;
        return fromStatusCode(statusCode, message: exception.message);

      case DioExceptionType.cancel:
        return AppError.network(
          'Request was cancelled.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.connectionError:
        return AppError.network(
          'Unable to connect to the server. Please check your internet connection.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.badCertificate:
        return AppError.network(
          'SSL certificate verification failed. Unable to establish secure connection.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );

      case DioExceptionType.unknown:
        return AppError.network(
          exception.message ?? 'An unknown network error occurred.',
          originalError: exception,
          stackTrace: exception.stackTrace,
        );
    }
  }

  /// Check if an error is retryable based on HTTP status or error type
  static bool isRetryable(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode ?? 0;
          // Retry on server errors (5xx) but not client errors (4xx)
          return statusCode >= 500 && statusCode < 600;

        default:
          return false;
      }
    }

    if (error is AppError && error.type == AppErrorType.network) {
      return true;
    }

    return false;
  }

  /// Check if error indicates no internet connection
  static bool isNoConnection(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
    }

    return false;
  }

  /// Check if error is due to server issues
  static bool isServerError(Object error) {
    if (error is DioException && error.response != null) {
      final statusCode = error.response!.statusCode ?? 0;
      return statusCode >= 500 && statusCode < 600;
    }

    return false;
  }

  /// Check if error is due to client issues (bad request, unauthorized, etc.)
  static bool isClientError(Object error) {
    if (error is DioException && error.response != null) {
      final statusCode = error.response!.statusCode ?? 0;
      return statusCode >= 400 && statusCode < 500;
    }

    return false;
  }

  /// Get user-friendly message for common network scenarios
  static String getUserFriendlyMessage(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.connectionError:
          return 'No internet connection. Please check your network and try again.';

        case DioExceptionType.receiveTimeout:
          return 'Download is taking longer than expected. This may be due to a slow connection or large file size.';

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode ?? 0;
          if (statusCode == 404) {
            return 'The requested chart is not available or has been moved.';
          } else if (statusCode >= 500) {
            return 'Chart service is temporarily unavailable. Please try again later.';
          } else if (statusCode == 401 || statusCode == 403) {
            return 'Access denied. You may not have permission to download this chart.';
          }
          return 'Unable to download chart. Please try again later.';

        case DioExceptionType.badCertificate:
          return 'Security certificate error. Unable to establish secure connection.';

        default:
          return 'A network error occurred. Please check your connection and try again.';
      }
    }

    if (error is AppError && error.type == AppErrorType.network) {
      return error.message;
    }

    return 'An unexpected error occurred. Please try again.';
  }

  /// Get recommended action for the user based on error type
  static String getRecommendedAction(Object error) {
    if (isNoConnection(error)) {
      return 'Check your internet connection and try again.';
    }

    if (isServerError(error)) {
      return 'The chart service is temporarily unavailable. Please try again in a few minutes.';
    }

    if (isClientError(error)) {
      if (error is DioException && error.response?.statusCode == 404) {
        return 'The chart may have been updated or moved. Try searching for an updated version.';
      }
      return 'Please verify the chart information and try again.';
    }

    if (isRetryable(error)) {
      return 'This error may be temporary. Try again in a moment.';
    }

    return 'If the problem persists, please contact support.';
  }

  /// Get default error message for HTTP status codes
  static String _getDefaultMessageForStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request. The chart request is invalid.';
      case 401:
        return 'Unauthorized. Authentication required.';
      case 403:
        return 'Forbidden. Access to this chart is not allowed.';
      case 404:
        return 'Chart not found. The requested chart is not available.';
      case 408:
        return 'Request timeout. The server took too long to respond.';
      case 429:
        return 'Too many requests. Please wait before trying again.';
      case 500:
        return 'Internal server error. The chart service is experiencing issues.';
      case 502:
        return 'Bad gateway. The chart service is temporarily unavailable.';
      case 503:
        return 'Service unavailable. The chart service is temporarily down for maintenance.';
      case 504:
        return 'Gateway timeout. The chart service is not responding.';
    }
    if (statusCode >= 400 && statusCode < 500) {
      return 'Client error (HTTP $statusCode). There is an issue with the request.';
    } else if (statusCode >= 500) {
      return 'Server error (HTTP $statusCode). The chart service is experiencing problems.';
    }
    return 'HTTP error $statusCode occurred.';
  }
}

/// Network connectivity status
enum NetworkStatus {
  connected,
  disconnected,
  limited, // Connected but with limited functionality
  unknown,
}

/// Network quality indicators for marine environments
enum NetworkQuality {
  excellent, // Fast, reliable connection
  good, // Adequate for chart downloads
  poor, // Slow, may affect large downloads
  veryPoor, // Barely usable, suitable only for small requests
  offline, // No connection
}

/// Network configuration specific to marine environments
class MarineNetworkConfig {
  /// Timeout for initial connection (shorter for satellite connections)
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Timeout for receiving data (longer for large chart files)
  static const Duration receiveTimeout = Duration(minutes: 10);

  /// Timeout for sending data
  static const Duration sendTimeout = Duration(minutes: 5);

  /// Maximum number of retry attempts
  static const int maxRetries = 3;

  /// Base delay between retries (will be multiplied for exponential backoff)
  static const Duration retryDelay = Duration(seconds: 2);

  /// Maximum concurrent downloads (conservative for satellite connections)
  static const int maxConcurrentDownloads = 2;

  /// Chunk size for resumable downloads (smaller for unreliable connections)
  static const int downloadChunkSize = 1024 * 1024; // 1MB chunks
}
