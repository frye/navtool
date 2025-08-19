import 'package:dio/dio.dart';
import 'dart:io';
import 'noaa_exceptions.dart';

/// Utility class for classifying and handling NOAA API errors
/// 
/// This class provides static methods for:
/// - Determining if errors are retryable
/// - Converting technical errors to user-friendly messages
/// - Providing recovery recommendations
/// - Classifying HTTP errors to appropriate exception types
class NoaaErrorClassifier {
  NoaaErrorClassifier._(); // Private constructor to prevent instantiation

  /// Determines if an error can be retried
  /// 
  /// Returns true for transient errors that may succeed on retry,
  /// false for permanent errors that will always fail.
  static bool isRetryableError(dynamic error) {
    // Handle NOAA-specific exceptions
    if (error is NoaaApiException) {
      return error.isRetryable;
    }

    // Handle Dio HTTP client exceptions
    if (error is DioException) {
      return _isDioExceptionRetryable(error);
    }

    // Handle socket exceptions (network issues)
    if (error is SocketException) {
      return true; // Network issues are generally retryable
    }

    // Handle timeout exceptions
    if (error is Exception && error.toString().contains('timeout')) {
      return true; // Timeouts are retryable
    }

    // Unknown exceptions are considered non-retryable for safety
    return false;
  }

  /// Determines if a DioException is retryable
  static bool _isDioExceptionRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true; // Network timeouts and connection issues are retryable

      case DioExceptionType.cancel:
        return false; // User cancellation is not retryable

      case DioExceptionType.badResponse:
        // Check HTTP status code for retryability
        final statusCode = error.response?.statusCode;
        if (statusCode == null) return false;
        
        // 5xx server errors are generally retryable
        if (statusCode >= 500 && statusCode < 600) {
          return true;
        }
        
        // 4xx client errors are generally not retryable
        // Exception: 429 (Too Many Requests) is retryable
        if (statusCode == 429) {
          return true;
        }
        
        return false;

      case DioExceptionType.unknown:
      case DioExceptionType.badCertificate:
        return false; // Unknown errors and certificate issues are not retryable
    }
  }

  /// Converts technical exceptions to user-friendly messages
  /// 
  /// Provides clear, actionable messages that users can understand
  /// without technical knowledge of the underlying system.
  static String getUserFriendlyMessage(dynamic error) {
    if (error is ChartNotAvailableException) {
      return 'Chart ${error.chartCellName} is not currently available from NOAA. '
             'It may have been updated or removed.';
    }

    if (error is NetworkConnectivityException) {
      return 'Unable to connect to NOAA services. '
             'Please check your internet connection and try again.';
    }

    if (error is RateLimitExceededException) {
      return 'Making too many requests to NOAA. '
             'Please wait a moment before trying again.';
    }

    if (error is NoaaServiceUnavailableException) {
      return 'NOAA services are temporarily unavailable. '
             'This is usually due to maintenance. Please try again later.';
    }

    if (error is ChartDownloadException) {
      return 'Failed to download chart ${error.chartCellName}. '
             'The download may have been interrupted or the file may be corrupted.';
    }

    if (error is NoaaApiException) {
      return 'An error occurred while communicating with NOAA services. '
             'Please try again later.';
    }

    // Fallback for unknown errors
    return 'An unexpected error occurred. Please try again later.';
  }

  /// Provides specific recovery recommendations for different error types
  /// 
  /// Returns actionable advice that users can follow to resolve or
  /// work around the error condition.
  static String getRecoveryRecommendation(dynamic error) {
    if (error is ChartNotAvailableException) {
      return 'Check NOAA\'s official website for chart availability updates. '
             'You may need to look for an alternative chart covering the same area.';
    }

    if (error is NetworkConnectivityException) {
      return 'Check your internet connection. If using satellite or marine internet, '
             'ensure you have a strong signal and try again when conditions improve.';
    }

    if (error is RateLimitExceededException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) {
        return 'Wait ${retryAfter.inSeconds} seconds before trying again. '
               'Consider reducing the number of requests or implementing delays between operations.';
      }
      return 'Wait a few moments before trying again. '
             'Consider reducing the number of requests or implementing delays between operations.';
    }

    if (error is NoaaServiceUnavailableException) {
      return 'Try again in a few minutes. NOAA services may be undergoing maintenance. '
             'Check NOAA\'s status page for any announced service interruptions.';
    }

    if (error is ChartDownloadException) {
      return 'Retry the download when you have a stable internet connection. '
             'If the problem persists, the chart file may be corrupted on NOAA\'s servers.';
    }

    if (error is NoaaApiException) {
      return 'Wait a few moments and try again. If the problem persists, '
             'check your internet connection and NOAA service status.';
    }

    // Fallback recommendation
    return 'Please try again later. If the problem persists, '
           'check your internet connection and try restarting the application.';
  }

  /// Classifies HTTP errors into appropriate NOAA exception types
  /// 
  /// Converts raw HTTP status codes and messages into specific
  /// NOAA exception instances with appropriate metadata.
  static NoaaApiException classifyHttpError(
    int statusCode,
    String message, [
    String? requestPath,
  ]) {
    switch (statusCode) {
      case 404:
        // Extract chart cell name from path if possible
        final chartCellName = _extractChartCellFromPath(requestPath) ?? 'unknown';
        return ChartNotAvailableException(chartCellName);

      case 429:
        return RateLimitExceededException();

      case 500:
      case 502:
      case 503:
      case 504:
        return NoaaServiceUnavailableException(message, statusCode);      case 401:
      case 403:
        // Authentication/authorization errors are not retryable
        return NoaaApiException(
          'Access denied: $message',
          errorCode: 'ACCESS_DENIED',
          isRetryable: false,
          metadata: {'httpStatusCode': statusCode},
        );

      default:
        // Generic HTTP error
        final isRetryable = statusCode >= 500;
        return NoaaApiException(
          'HTTP error $statusCode: $message',
          errorCode: 'HTTP_ERROR',
          isRetryable: isRetryable,
          metadata: {'httpStatusCode': statusCode},
        );
    }
  }

  /// Attempts to extract chart cell name from request path
  static String? _extractChartCellFromPath(String? path) {
    if (path == null) return null;
    
    // Look for patterns like /charts/US5CA52M or /ENCs/US5CA52M.zip
    final patterns = [
      RegExp(r'/charts/([A-Z0-9]+)'),
      RegExp(r'/ENCs/([A-Z0-9]+)\.zip'),
      RegExp(r'/([A-Z]{2}\d[A-Z0-9]+)'), // General pattern for NOAA chart cells
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(path);
      if (match != null && match.groupCount > 0) {
        return match.group(1);
      }
    }
    
    return null;
  }
}