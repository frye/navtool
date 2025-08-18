import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/error/noaa_error_classifier.dart';
import 'dart:io';

void main() {
  group('NoaaErrorClassifier Tests', () {
    group('isRetryableError', () {
      test('should identify retryable NOAA exceptions', () {
        // Arrange
        final retryableExceptions = [
          NetworkConnectivityException(),
          RateLimitExceededException(),
          NoaaServiceUnavailableException(),
          ChartDownloadException('US5CA52M', 'Temporary error'),
        ];
        
        // Act & Assert
        for (final exception in retryableExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isTrue,
            reason: 'Expected ${exception.runtimeType} to be retryable',
          );
        }
      });

      test('should identify non-retryable NOAA exceptions', () {
        // Arrange
        final nonRetryableExceptions = [
          ChartNotAvailableException('US5CA52M'),
          ChartDownloadException('US1AK90M', 'Permanent error', isRetryable: false),
          NoaaApiException('Auth failed', errorCode: 'AUTH_001', isRetryable: false),
        ];
        
        // Act & Assert
        for (final exception in nonRetryableExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isFalse,
            reason: 'Expected ${exception.runtimeType} to be non-retryable',
          );
        }
      });

      test('should identify retryable DioExceptions', () {
        // Arrange
        final retryableDioExceptions = [
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.connectionTimeout,
          ),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.receiveTimeout,
          ),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.sendTimeout,
          ),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.connectionError,
          ),
        ];
        
        // Act & Assert
        for (final exception in retryableDioExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isTrue,
            reason: 'Expected ${exception.type} to be retryable',
          );
        }
      });

      test('should identify non-retryable DioExceptions', () {
        // Arrange
        final nonRetryableDioExceptions = [
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.cancel,
          ),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 401,
            ),
          ),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 404,
            ),
          ),
        ];
        
        // Act & Assert
        for (final exception in nonRetryableDioExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isFalse,
            reason: 'Expected ${exception.type} with status ${exception.response?.statusCode} to be non-retryable',
          );
        }
      });

      test('should identify retryable HTTP server errors', () {
        // Arrange
        final serverErrors = [500, 502, 503, 504];
        
        // Act & Assert
        for (final statusCode in serverErrors) {
          final exception = DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: statusCode,
            ),
          );
          
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isTrue,
            reason: 'Expected HTTP $statusCode to be retryable',
          );
        }
      });

      test('should identify retryable socket exceptions', () {
        // Arrange
        final socketExceptions = [
          const SocketException('Connection failed'),
          const SocketException('Network unreachable'),
        ];
        
        // Act & Assert
        for (final exception in socketExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isTrue,
            reason: 'Expected SocketException to be retryable',
          );
        }
      });

      test('should handle unknown exceptions as non-retryable', () {
        // Arrange
        final unknownExceptions = [
          Exception('Unknown error'),
          StateError('Invalid state'),
          ArgumentError('Invalid argument'),
        ];
        
        // Act & Assert
        for (final exception in unknownExceptions) {
          expect(
            NoaaErrorClassifier.isRetryableError(exception),
            isFalse,
            reason: 'Expected ${exception.runtimeType} to be non-retryable',
          );
        }
      });
    });

    group('getUserFriendlyMessage', () {
      test('should return user-friendly message for network connectivity', () {
        // Arrange
        final exception = NetworkConnectivityException();
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'Unable to connect to NOAA services. Please check your internet connection and try again.');
      });

      test('should return user-friendly message for rate limiting', () {
        // Arrange
        final exception = RateLimitExceededException();
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'Making too many requests to NOAA. Please wait a moment before trying again.');
      });

      test('should return user-friendly message for chart not available', () {
        // Arrange
        final exception = ChartNotAvailableException('US5CA52M');
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'Chart US5CA52M is not currently available from NOAA. It may have been updated or removed.');
      });

      test('should return user-friendly message for service unavailable', () {
        // Arrange
        final exception = NoaaServiceUnavailableException();
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'NOAA services are temporarily unavailable. This is usually due to maintenance. Please try again later.');
      });

      test('should return user-friendly message for chart download failure', () {
        // Arrange
        final exception = ChartDownloadException('US4FL11M', 'Download interrupted');
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'Failed to download chart US4FL11M. The download may have been interrupted or the file may be corrupted.');
      });

      test('should return generic message for unknown NOAA exceptions', () {
        // Arrange
        final exception = NoaaApiException('Unknown NOAA error', errorCode: 'UNKNOWN_001');
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'An error occurred while communicating with NOAA services. Please try again later.');
      });

      test('should handle non-NOAA exceptions gracefully', () {
        // Arrange
        final exception = Exception('Generic error');
        
        // Act
        final message = NoaaErrorClassifier.getUserFriendlyMessage(exception);
        
        // Assert
        expect(message, 'An unexpected error occurred. Please try again later.');
      });
    });

    group('getRecoveryRecommendation', () {
      test('should provide recovery recommendation for network connectivity', () {
        // Arrange
        final exception = NetworkConnectivityException();
        
        // Act
        final recommendation = NoaaErrorClassifier.getRecoveryRecommendation(exception);
        
        // Assert
        expect(recommendation, contains('Check your internet connection'));
        expect(recommendation, contains('satellite or marine internet'));
      });

      test('should provide recovery recommendation for rate limiting', () {
        // Arrange
        final exception = RateLimitExceededException(retryAfter: Duration(seconds: 30));
        
        // Act
        final recommendation = NoaaErrorClassifier.getRecoveryRecommendation(exception);
        
        // Assert
        expect(recommendation, contains('Wait 30 seconds'));
        expect(recommendation, contains('reducing the number of requests'));
      });

      test('should provide recovery recommendation for chart not available', () {
        // Arrange
        final exception = ChartNotAvailableException('US5CA52M');
        
        // Act
        final recommendation = NoaaErrorClassifier.getRecoveryRecommendation(exception);
        
        // Assert
        expect(recommendation, contains('Check NOAA\'s official website'));
        expect(recommendation, contains('alternative chart'));
      });

      test('should provide recovery recommendation for service unavailable', () {
        // Arrange
        final exception = NoaaServiceUnavailableException();
        
        // Act
        final recommendation = NoaaErrorClassifier.getRecoveryRecommendation(exception);
        
        // Assert
        expect(recommendation, contains('Try again in a few minutes'));
        expect(recommendation, contains('maintenance'));
      });

      test('should provide recovery recommendation for download failure', () {
        // Arrange
        final exception = ChartDownloadException('US4FL11M', 'Download failed');
        
        // Act
        final recommendation = NoaaErrorClassifier.getRecoveryRecommendation(exception);
        
        // Assert
        expect(recommendation, contains('Retry the download'));
        expect(recommendation, contains('stable internet connection'));
      });
    });

    group('classifyHttpError', () {
      test('should classify HTTP errors to appropriate NOAA exceptions', () {
        // Arrange & Act & Assert
        
        // 404 - Chart not found
        final notFoundException = NoaaErrorClassifier.classifyHttpError(404, 'Chart not found', '/charts/US5CA52M');
        expect(notFoundException, isA<ChartNotAvailableException>());
        
        // 429 - Rate limit exceeded
        final rateLimitException = NoaaErrorClassifier.classifyHttpError(429, 'Too many requests');
        expect(rateLimitException, isA<RateLimitExceededException>());
        
        // 503 - Service unavailable
        final serviceException = NoaaErrorClassifier.classifyHttpError(503, 'Service unavailable');
        expect(serviceException, isA<NoaaServiceUnavailableException>());
        
        // 500 - Generic server error
        final serverException = NoaaErrorClassifier.classifyHttpError(500, 'Internal server error');
        expect(serverException, isA<NoaaApiException>());
        expect(serverException.isRetryable, isTrue);
        
        // 401 - Unauthorized (should not happen with NOAA, but handle gracefully)
        final authException = NoaaErrorClassifier.classifyHttpError(401, 'Unauthorized');
        expect(authException, isA<NoaaApiException>());
        expect(authException.isRetryable, isFalse);
      });
    });
  });
}
