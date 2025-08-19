import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';

import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/utils/retryable_operation.dart';
import 'package:navtool/core/models/retry_policy.dart';

// Import mocks from the integration test file
import '../../integration/noaa_api_integration_test.mocks.dart';

/// Comprehensive tests for NOAA API exception handling and error scenarios
/// 
/// These tests verify proper error handling, recovery, and resilience
/// patterns in marine network environments.
void main() {
  group('NOAA API Error Handling Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('Network Error Handling', () {
      test('should handle connection timeout gracefully', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.connectionTimeout,
            ));

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          // Act & Assert
          final apiClient = testContainer.read(noaaApiClientProvider);
          expect(
            () => apiClient.fetchChartCatalog(),
            throwsA(isA<NetworkConnectivityException>()),
          );
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle receive timeout gracefully', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.receiveTimeout,
            ));

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          // Act & Assert
          final apiClient = testContainer.read(noaaApiClientProvider);
          expect(
            () => apiClient.fetchChartCatalog(),
            throwsA(isA<NetworkConnectivityException>()),
          );
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle server errors appropriately', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: RequestOptions(path: '/test'),
                statusCode: 500,
              ),
            ));

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          // Act & Assert
          final apiClient = testContainer.read(noaaApiClientProvider);
          expect(
            () => apiClient.fetchChartCatalog(),
            throwsA(isA<NoaaServiceUnavailableException>()),
          );
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle rate limiting errors', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: RequestOptions(path: '/test'),
                statusCode: 429,
              ),
            ));

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          // Act & Assert
          final apiClient = testContainer.read(noaaApiClientProvider);
          expect(
            () => apiClient.fetchChartCatalog(),
            throwsA(isA<RateLimitExceededException>()),
          );
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Circuit Breaker Error Handling', () {
      test('should open circuit after consecutive failures', () async {
        // Arrange
        final testContainer = ProviderContainer(
          overrides: [
            circuitBreakerProvider.overrideWith((ref) => CircuitBreaker(
              failureThreshold: 2,
              timeout: const Duration(seconds: 1),
            )),
          ],
        );

        try {
          final circuitBreaker = testContainer.read(circuitBreakerProvider);

          // Act - trigger failures
          Future<String> failingOperation() async {
            throw DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.connectionTimeout,
            );
          }

          for (int i = 0; i < 2; i++) {
            try {
              await circuitBreaker.execute(failingOperation);
            } catch (_) {
              // Expected failure
            }
          }

          // Assert
          expect(circuitBreaker.state, CircuitState.open);
          expect(circuitBreaker.isOpen, isTrue);
          expect(circuitBreaker.failureCount, 2);
        } finally {
          testContainer.dispose();
        }
      });

      test('should recover after timeout period', () async {
        // Arrange
        final testContainer = ProviderContainer(
          overrides: [
            circuitBreakerProvider.overrideWith((ref) => CircuitBreaker(
              failureThreshold: 1,
              timeout: const Duration(milliseconds: 100),
            )),
          ],
        );

        try {
          final circuitBreaker = testContainer.read(circuitBreakerProvider);

          // Open the circuit
          try {
            await circuitBreaker.execute(() async {
              throw DioException(
                requestOptions: RequestOptions(path: '/test'),
                type: DioExceptionType.connectionTimeout,
              );
            });
          } catch (_) {}

          expect(circuitBreaker.state, CircuitState.open);

          // Wait for recovery
          await Future.delayed(const Duration(milliseconds: 120));

          // Act - should transition to half-open and then closed on success
          final result = await circuitBreaker.execute(() async => 'recovered');

          // Assert
          expect(result, 'recovered');
          expect(circuitBreaker.state, CircuitState.closed);
        } finally {
          testContainer.dispose();
        }
      });

      test('should provide accurate status information', () async {
        // Arrange
        final circuitBreaker = container.read(circuitBreakerProvider);

        // Act
        final status = circuitBreaker.getStatus();

        // Assert
        expect(status.state, CircuitState.closed);
        expect(status.failureCount, 0);
        expect(status.successCount, 0);
        expect(status.failureThreshold, 3);
        expect(status.timeoutDuration, const Duration(minutes: 2));
        expect(status.lastFailureTime, isNull);
        expect(status.nextRetryTime, isNull);
      });
    });

    group('Retry Logic Error Handling', () {
      test('should retry transient failures', () async {
        // Arrange
        var attemptCount = 0;
        Future<String> flakyOperation() async {
          attemptCount++;
          if (attemptCount < 3) {
            throw NetworkConnectivityException();
          }
          return 'success';
        }

        final retryPolicy = container.read(apiRetryPolicyProvider);

        // Act
        final result = await RetryableOperation.execute(
          flakyOperation,
          policy: retryPolicy,
        );

        // Assert
        expect(result, 'success');
        expect(attemptCount, 3); // 1 initial + 2 retries
      });

      test('should not retry non-retryable errors', () async {
        // Arrange
        var attemptCount = 0;
        Future<String> nonRetryableOperation() async {
          attemptCount++;
          throw ChartNotAvailableException('US5CA52M');
        }

        final retryPolicy = container.read(apiRetryPolicyProvider);

        // Act & Assert
        expect(
          () => RetryableOperation.execute(
            nonRetryableOperation,
            policy: retryPolicy,
          ),
          throwsA(isA<ChartNotAvailableException>()),
        );

        // Should not retry
        expect(attemptCount, 1);
      });

      test('should provide retry metrics', () async {
        // Arrange
        var attemptCount = 0;
        Future<String> flakyOperation() async {
          attemptCount++;
          if (attemptCount < 2) {
            throw NetworkConnectivityException();
          }
          return 'success';
        }

        final retryPolicy = container.read(apiRetryPolicyProvider);

        // Act
        final result = await RetryableOperation.executeWithMetrics(
          flakyOperation,
          policy: retryPolicy,
        );

        // Assert
        expect(result.value, 'success');
        expect(result.totalAttempts, 2);
        expect(result.retryCount, 1);
        expect(result.errors.length, 1);
        expect(result.errors.first, isA<NetworkConnectivityException>());
        expect(result.totalDuration, greaterThan(Duration.zero));
      });

      test('should exhaust retries and throw final error', () async {
        // Arrange
        var attemptCount = 0;
        Future<String> persistentlyFailingOperation() async {
          attemptCount++;
          throw NetworkConnectivityException();
        }

        const testPolicy = RetryPolicy(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 10),
        );

        // Act & Assert
        try {
          await RetryableOperation.execute(
            persistentlyFailingOperation,
            policy: testPolicy,
          );
          fail('Should have thrown NetworkConnectivityException');
        } catch (e) {
          expect(e, isA<NetworkConnectivityException>());
        }

        expect(attemptCount, 3); // 1 initial + 2 retries
      });
    });

    group('Rate Limiter Error Scenarios', () {
      test('should handle rapid successive requests', () async {
        // Arrange
        final rateLimiter = container.read(rateLimiterProvider);

        // Act - make rapid requests
        final futures = <Future<void>>[];
        for (int i = 0; i < 10; i++) {
          futures.add(() async {
            if (rateLimiter.canMakeRequest()) {
              await rateLimiter.acquire();
            } else {
              // Would need to wait
              final waitTime = rateLimiter.getWaitTime();
              expect(waitTime, greaterThan(Duration.zero));
            }
          }());
        }

        await Future.wait(futures);

        // Assert - should respect rate limits
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, lessThanOrEqualTo(5));
      });

      test('should provide accurate wait time calculations', () async {
        // Arrange
        final rateLimiter = container.read(rateLimiterProvider);

        // Fill up the rate limiter
        for (int i = 0; i < 5; i++) {
          await rateLimiter.acquire();
        }

        // Act
        expect(rateLimiter.canMakeRequest(), isFalse);
        final waitTime = rateLimiter.getWaitTime();

        // Assert
        expect(waitTime, greaterThan(Duration.zero));
        expect(waitTime.inSeconds, lessThanOrEqualTo(1));
      });
    });

    group('Marine Environment Error Scenarios', () {
      test('should handle intermittent satellite connectivity', () async {
        // Arrange - simulate intermittent connectivity
        final mockHttpClient = MockHttpClientService();
        var callCount = 0;
        
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async {
              callCount++;
              if (callCount % 3 == 0) {
                // Every 3rd call succeeds
                return Response(
                  requestOptions: RequestOptions(path: ''),
                  data: '{"type":"FeatureCollection","features":[]}',
                  statusCode: 200,
                );
              } else {
                // Other calls fail with timeout
                throw DioException(
                  requestOptions: RequestOptions(path: '/test'),
                  type: DioExceptionType.connectionTimeout,
                );
              }
            });

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          final apiClient = testContainer.read(noaaApiClientProvider);
          final rateLimiter = testContainer.read(rateLimiterProvider);

          // Act - simulate multiple requests with failures and retries
          String? lastResult;
          for (int i = 0; i < 5; i++) {
            try {
              await rateLimiter.acquire();
              lastResult = await apiClient.fetchChartCatalog();
            } catch (e) {
              // Expected intermittent failures
              expect(e, isA<NetworkConnectivityException>());
            }
            
            // Small delay between requests
            await Future.delayed(const Duration(milliseconds: 50));
          }

          // Assert - should eventually succeed
          expect(lastResult, isNotNull);
          expect(lastResult, contains('FeatureCollection'));
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle low-bandwidth marine connections', () async {
        // Arrange - simulate slow responses
        final mockHttpClient = MockHttpClientService();
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async {
              // Simulate slow marine connection
              await Future.delayed(const Duration(milliseconds: 100));
              return Response(
                requestOptions: RequestOptions(path: ''),
                data: '{"type":"FeatureCollection","features":[]}',
                statusCode: 200,
              );
            });

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          // Act
          final apiClient = testContainer.read(noaaApiClientProvider);
          final startTime = DateTime.now();
          final result = await apiClient.fetchChartCatalog();
          final endTime = DateTime.now();

          // Assert
          expect(result, isNotEmpty);
          expect(endTime.difference(startTime).inMilliseconds, greaterThanOrEqualTo(100));
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle weather-related service disruptions', () async {
        // Arrange - simulate weather disruption pattern
        final mockHttpClient = MockHttpClientService();
        var callCount = 0;
        
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async {
              callCount++;
              if (callCount <= 3) {
                // Initial failures during weather event
                throw DioException(
                  requestOptions: RequestOptions(path: '/test'),
                  type: DioExceptionType.connectionError,
                );
              } else {
                // Recovery after weather passes
                return Response(
                  requestOptions: RequestOptions(path: ''),
                  data: '{"type":"FeatureCollection","features":[]}',
                  statusCode: 200,
                );
              }
            });

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
            circuitBreakerProvider.overrideWith((ref) => CircuitBreaker(
              failureThreshold: 5, // Higher threshold for weather events
              timeout: const Duration(milliseconds: 200), // Faster recovery test
            )),
          ],
        );

        try {
          final apiClient = testContainer.read(noaaApiClientProvider);
          final circuitBreaker = testContainer.read(circuitBreakerProvider);

          // Act - simulate requests during and after weather event
          String? result;
          for (int i = 0; i < 5; i++) {
            try {
              result = await apiClient.fetchChartCatalog();
              break; // Success - exit loop
            } catch (e) {
              // Expected failures during weather event
              expect(e, isA<NoaaApiException>());
              await Future.delayed(const Duration(milliseconds: 50));
            }
          }

          // Assert - should eventually recover
          expect(result, isNotNull);
          expect(circuitBreaker.state, CircuitState.closed); // Should remain operational
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Error Recovery and Resilience', () {
      test('should demonstrate full recovery cycle', () async {
        // Arrange
        final testContainer = ProviderContainer(
          overrides: [
            circuitBreakerProvider.overrideWith((ref) => CircuitBreaker(
              failureThreshold: 2,
              timeout: const Duration(milliseconds: 100),
            )),
          ],
        );

        try {
          final circuitBreaker = testContainer.read(circuitBreakerProvider);

          // Phase 1: Normal operation
          var result = await circuitBreaker.execute(() async => 'normal');
          expect(result, 'normal');
          expect(circuitBreaker.state, CircuitState.closed);

          // Phase 2: Failures causing circuit to open
          for (int i = 0; i < 2; i++) {
            try {
              await circuitBreaker.execute(() async {
                throw DioException(
                  requestOptions: RequestOptions(path: '/test'),
                  type: DioExceptionType.connectionTimeout,
                );
              });
            } catch (_) {}
          }
          expect(circuitBreaker.state, CircuitState.open);

          // Phase 3: Wait for recovery timeout
          await Future.delayed(const Duration(milliseconds: 120));

          // Phase 4: Recovery and return to normal
          result = await circuitBreaker.execute(() async => 'recovered');
          expect(result, 'recovered');
          expect(circuitBreaker.state, CircuitState.closed);
        } finally {
          testContainer.dispose();
        }
      });

      test('should maintain service during partial failures', () async {
        // Arrange - simulate mixed success/failure pattern
        final mockHttpClient = MockHttpClientService();
        var callCount = 0;
        
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async {
              callCount++;
              if (callCount % 2 == 0) {
                // Every other call succeeds
                return Response(
                  requestOptions: RequestOptions(path: ''),
                  data: '{"type":"FeatureCollection","features":[]}',
                  statusCode: 200,
                );
              } else {
                // Intermittent failures
                throw DioException(
                  requestOptions: RequestOptions(path: '/test'),
                  type: DioExceptionType.connectionTimeout,
                );
              }
            });

        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
          ],
        );

        try {
          final apiClient = testContainer.read(noaaApiClientProvider);
          final rateLimiter = testContainer.read(rateLimiterProvider);

          // Act - make multiple requests with mixed results
          var successCount = 0;
          var failureCount = 0;

          for (int i = 0; i < 6; i++) {
            try {
              await rateLimiter.acquire();
              await apiClient.fetchChartCatalog();
              successCount++;
            } catch (e) {
              failureCount++;
              expect(e, isA<NetworkConnectivityException>());
            }
          }

          // Assert - should have both successes and failures
          expect(successCount, greaterThan(0));
          expect(failureCount, greaterThan(0));
          expect(successCount + failureCount, 6);
        } finally {
          testContainer.dispose();
        }
      });
    });
  });
}