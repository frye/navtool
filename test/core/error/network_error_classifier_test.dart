import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'dart:io';

import 'package:navtool/core/error/network_error_classifier.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';

void main() {
  group('NetworkErrorClassifier', () {
    group('Error Classification', () {
      test('should classify DioException connection timeout as timeout', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.timeout));
      });

      test('should classify DioException connection error as no connection', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionError,
        );

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.noConnection));
      });

      test('should classify 429 status code as rate limited', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 429,
          ),
        );

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.rateLimited));
      });

      test('should classify 500 status code as server error', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.serverError));
      });

      test('should classify 401 status code as authentication failed', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 401,
          ),
        );

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.authenticationFailed));
      });

      test('should classify SocketException as no connection', () {
        final error = const SocketException('Network unreachable');

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.noConnection));
      });

      test('should classify NetworkConnectivityException as no connection', () {
        final error = NetworkConnectivityException();

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.noConnection));
      });

      test('should classify RateLimitExceededException as rate limited', () {
        final error = RateLimitExceededException();

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.rateLimited));
      });

      test('should classify NoaaServiceUnavailableException as server error', () {
        final error = NoaaServiceUnavailableException('Service down', 503);

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.serverError));
      });

      test('should classify unknown exception as unknown error', () {
        final error = Exception('Random error');

        final result = NetworkErrorClassifier.classifyError(error);
        
        expect(result, equals(NetworkErrorType.unknownError));
      });
    });

    group('User-Friendly Messages', () {
      test('should provide marine-specific message for no connection', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.noConnection,
        );
        
        expect(message, contains('❌ No internet connection'));
        expect(message, contains('cached charts for navigation'));
        expect(message, contains('marine internet connection'));
      });

      test('should provide marine-specific message for timeout', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.timeout,
        );
        
        expect(message, contains('⚠️ Slow connection detected'));
        expect(message, contains('several minutes'));
        expect(message, contains('Satellite connections'));
      });

      test('should provide marine-specific message for server error', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.serverError,
        );
        
        expect(message, contains('🔧 NOAA servers'));
        expect(message, contains('temporarily unavailable'));
        expect(message, contains('cached charts'));
      });

      test('should provide marine-specific message for rate limited', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.rateLimited,
        );
        
        expect(message, contains('🚦 Too many requests'));
        expect(message, contains('limiting access'));
        expect(message, contains('marine services'));
      });

      test('should provide marine-specific message for authentication failed', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.authenticationFailed,
        );
        
        expect(message, contains('🔒 Access denied'));
        expect(message, contains('credentials'));
      });

      test('should provide marine-specific message for unknown error', () {
        final message = NetworkErrorClassifier.getUserFriendlyMessage(
          NetworkErrorType.unknownError,
        );
        
        expect(message, contains('❓ Unexpected network error'));
        expect(message, contains('marine internet connection'));
      });
    });

    group('Recovery Recommendations', () {
      test('should provide marine-specific recommendations for no connection', () {
        final recommendation = NetworkErrorClassifier.getRecoveryRecommendation(
          NetworkErrorType.noConnection,
        );
        
        expect(recommendation, contains('satellite/cellular signal'));
        expect(recommendation, contains('weather conditions'));
        expect(recommendation, contains('cached charts'));
      });

      test('should provide marine-specific recommendations for timeout', () {
        final recommendation = NetworkErrorClassifier.getRecoveryRecommendation(
          NetworkErrorType.timeout,
        );
        
        expect(recommendation, contains('3-5 minutes over satellite'));
        expect(recommendation, contains('calmer seas'));
        expect(recommendation, contains('port with faster WiFi'));
      });

      test('should provide marine-specific recommendations for server error', () {
        final recommendation = NetworkErrorClassifier.getRecoveryRecommendation(
          NetworkErrorType.serverError,
        );
        
        expect(recommendation, contains('NOAA services will resume'));
        expect(recommendation, contains('maintenance schedules'));
        expect(recommendation, contains('15-30 minutes'));
      });

      test('should provide marine-specific recommendations for rate limited', () {
        final recommendation = NetworkErrorClassifier.getRecoveryRecommendation(
          NetworkErrorType.rateLimited,
        );
        
        expect(recommendation, contains('2-5 minutes'));
        expect(recommendation, contains('off-peak hours'));
        expect(recommendation, contains('background sync'));
      });
    });

    group('Retry Logic', () {
      test('should recommend retry for retryable errors', () {
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.noConnection),
          isTrue,
        );
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.timeout),
          isTrue,
        );
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.serverError),
          isTrue,
        );
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.rateLimited),
          isTrue,
        );
      });

      test('should not recommend retry for non-retryable errors', () {
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.authenticationFailed),
          isFalse,
        );
        expect(
          NetworkErrorClassifier.shouldRetry(NetworkErrorType.unknownError),
          isFalse,
        );
      });

      test('should provide appropriate retry delays for marine conditions', () {
        // Test base delays
        final noConnectionDelay = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.noConnection, 0,
        );
        expect(noConnectionDelay.inSeconds, equals(5));

        final timeoutDelay = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.timeout, 0,
        );
        expect(timeoutDelay.inSeconds, equals(3));

        final serverErrorDelay = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.serverError, 0,
        );
        expect(serverErrorDelay.inSeconds, equals(10));

        final rateLimitedDelay = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.rateLimited, 0,
        );
        expect(rateLimitedDelay.inSeconds, equals(15));
      });

      test('should apply exponential backoff with marine-optimized multiplier', () {
        final delay1 = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.timeout, 1,
        );
        final delay2 = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.timeout, 2,
        );
        
        // Should increase with exponential backoff (1.5x multiplier)
        expect(delay2.inMilliseconds, greaterThan(delay1.inMilliseconds));
        
        // Verify 1.5x multiplier
        final expectedDelay2 = Duration(
          milliseconds: (3000 * 1.5 * 1.5).round(),
        );
        expect(delay2.inMilliseconds, equals(expectedDelay2.inMilliseconds));
      });

      test('should cap exponential backoff at maximum multiplier', () {
        final delay = NetworkErrorClassifier.getRetryDelay(
          NetworkErrorType.timeout, 10, // High attempt number
        );
        
        // Should be capped at 8x multiplier
        final expectedMaxDelay = Duration(
          milliseconds: (3000 * 8.0).round(),
        );
        expect(delay.inMilliseconds, equals(expectedMaxDelay.inMilliseconds));
      });
    });
  });
}