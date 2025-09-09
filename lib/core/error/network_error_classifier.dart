import 'dart:io';
import 'package:dio/dio.dart';
import 'noaa_exceptions.dart';
import 'noaa_error_classifier.dart';

/// Network error types for marine environments
enum NetworkErrorType {
  /// No network connection available
  noConnection,
  
  /// Connection timeout (slow or unstable connection)
  timeout,
  
  /// Server error (5xx HTTP codes)
  serverError,
  
  /// Rate limiting (429 HTTP code)
  rateLimited,
  
  /// Authentication failed (401/403 HTTP codes)
  authenticationFailed,
  
  /// Unknown or unclassified error
  unknownError,
}

/// Network error classification and marine-specific handling
///
/// Provides detailed error classification and user-friendly messages
/// optimized for marine environments where connectivity can be challenging.
class NetworkErrorClassifier {
  NetworkErrorClassifier._(); // Private constructor to prevent instantiation

  /// Classifies a network error into specific types
  ///
  /// Determines the root cause of network errors to provide appropriate
  /// user feedback and retry strategies.
  static NetworkErrorType classifyError(Exception error) {
    // Handle Dio HTTP client exceptions
    if (error is DioException) {
      return _classifyDioException(error);
    }

    // Handle socket exceptions (connection issues)
    if (error is SocketException) {
      return NetworkErrorType.noConnection;
    }

    // Handle NOAA-specific exceptions
    if (error is NetworkConnectivityException) {
      return NetworkErrorType.noConnection;
    }
    
    if (error is RateLimitExceededException) {
      return NetworkErrorType.rateLimited;
    }
    
    if (error is NoaaServiceUnavailableException) {
      return NetworkErrorType.serverError;
    }

    // Handle timeout exceptions
    if (error is Exception && error.toString().toLowerCase().contains('timeout')) {
      return NetworkErrorType.timeout;
    }

    return NetworkErrorType.unknownError;
  }

  /// Returns marine-context appropriate error messages
  ///
  /// Provides clear, actionable messages that users can understand
  /// in challenging marine connectivity environments.
  static String getUserFriendlyMessage(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.noConnection:
        return '❌ No internet connection - using cached charts for navigation\n'
               'Check your marine internet connection and try again when signal improves.';
               
      case NetworkErrorType.timeout:
        return '⚠️ Slow connection detected - chart refresh may take several minutes\n'
               'Satellite connections can be slow. Consider refreshing during calmer conditions.';
               
      case NetworkErrorType.serverError:
        return '🔧 NOAA servers temporarily unavailable\n'
               'This is usually due to maintenance. Using cached charts until service resumes.';
               
      case NetworkErrorType.rateLimited:
        return '🚦 Too many requests - NOAA is limiting access\n'
               'Wait a moment before trying again to avoid overwhelming marine services.';
               
      case NetworkErrorType.authenticationFailed:
        return '🔒 Access denied to NOAA services\n'
               'Check your account credentials or contact support.';
               
      case NetworkErrorType.unknownError:
        return '❓ Unexpected network error occurred\n'
               'Check your marine internet connection and try again later.';
    }
  }

  /// Provides marine-specific recovery recommendations
  ///
  /// Returns actionable advice tailored to marine environments
  /// and connectivity constraints.
  static String getRecoveryRecommendation(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.noConnection:
        return '• Check satellite/cellular signal strength\n'
               '• Move to a clearer area if possible\n'
               '• Wait for weather conditions to improve\n'
               '• Use cached charts for navigation';
               
      case NetworkErrorType.timeout:
        return '• Estimated completion time: 3-5 minutes over satellite\n'
               '• Cancel and retry during calmer seas for faster speeds\n'
               '• Consider downloading charts in port with faster WiFi\n'
               '• Continue with partial results if available';
               
      case NetworkErrorType.serverError:
        return '• NOAA services will resume automatically\n'
               '• Check NOAA status page for maintenance schedules\n'
               '• Use cached charts which remain valid for navigation\n'
               '• Try again in 15-30 minutes';
               
      case NetworkErrorType.rateLimited:
        return '• Wait 2-5 minutes before retrying\n'
               '• Avoid rapid repeated requests\n'
               '• Consider scheduling updates during off-peak hours\n'
               '• Use background sync to retry automatically';
               
      case NetworkErrorType.authenticationFailed:
        return '• Verify NOAA account credentials\n'
               '• Check if account has proper permissions\n'
               '• Contact maritime support if issue persists\n'
               '• Use cached charts until access is restored';
               
      case NetworkErrorType.unknownError:
        return '• Check marine internet connection\n'
               '• Try refreshing in a few minutes\n'
               '• Restart the application if problem persists\n'
               '• Use cached charts for immediate navigation needs';
    }
  }

  /// Determines if an error should trigger automatic retry
  ///
  /// Uses marine-optimized retry logic that accounts for the challenging
  /// connectivity conditions common in maritime environments.
  static bool shouldRetry(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.noConnection:
      case NetworkErrorType.timeout:
      case NetworkErrorType.serverError:
      case NetworkErrorType.rateLimited:
        return true;
        
      case NetworkErrorType.authenticationFailed:
      case NetworkErrorType.unknownError:
        return false;
    }
  }

  /// Gets recommended retry delay for marine conditions
  ///
  /// Returns delays optimized for marine connectivity patterns,
  /// with longer delays for satellite connections.
  static Duration getRetryDelay(NetworkErrorType errorType, int attemptNumber) {
    final baseDelay = _getBaseRetryDelay(errorType);
    final exponentialMultiplier = _calculateExponentialBackoff(attemptNumber);
    
    return Duration(
      milliseconds: (baseDelay.inMilliseconds * exponentialMultiplier).round(),
    );
  }

  /// Classifies DioException types for marine environments
  static NetworkErrorType _classifyDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return NetworkErrorType.timeout;
        
      case DioExceptionType.connectionError:
        return NetworkErrorType.noConnection;
        
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == null) return NetworkErrorType.unknownError;
        
        if (statusCode == 429) return NetworkErrorType.rateLimited;
        if (statusCode == 401 || statusCode == 403) return NetworkErrorType.authenticationFailed;
        if (statusCode >= 500) return NetworkErrorType.serverError;
        
        return NetworkErrorType.unknownError;
        
      case DioExceptionType.cancel:
        // Cancellation is not an error to retry
        return NetworkErrorType.unknownError;
        
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return NetworkErrorType.unknownError;
    }
  }

  /// Gets base retry delay for different error types
  static Duration _getBaseRetryDelay(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.noConnection:
        return const Duration(seconds: 5); // Network issues need time to resolve
        
      case NetworkErrorType.timeout:
        return const Duration(seconds: 3); // Timeouts may resolve quickly
        
      case NetworkErrorType.serverError:
        return const Duration(seconds: 10); // Server issues take longer to resolve
        
      case NetworkErrorType.rateLimited:
        return const Duration(seconds: 15); // Rate limits need substantial delays
        
      case NetworkErrorType.authenticationFailed:
      case NetworkErrorType.unknownError:
        return const Duration(seconds: 30); // These errors are less likely to resolve quickly
    }
  }

  /// Calculates exponential backoff multiplier
  static double _calculateExponentialBackoff(int attemptNumber) {
    if (attemptNumber <= 0) return 1.0;
    
    // Use 1.5x multiplier for gentler backoff in marine environments
    double multiplier = 1.0;
    for (int i = 0; i < attemptNumber; i++) {
      multiplier *= 1.5;
    }
    
    // Cap at 8x to avoid extremely long delays
    return multiplier > 8.0 ? 8.0 : multiplier;
  }
}