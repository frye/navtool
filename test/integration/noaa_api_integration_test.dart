import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';

import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/utils/retryable_operation.dart';
import 'package:navtool/core/models/retry_policy.dart';
import 'package:navtool/core/logging/app_logger.dart';

// Mock classes for testing
@GenerateMocks([
  HttpClientService,
  AppLogger,
])
import 'noaa_api_integration_test.mocks.dart';

/// Integration tests for NOAA API client operations with real dependencies
/// 
/// These tests verify end-to-end functionality of the NOAA API client
/// integrated with rate limiting, circuit breakers, and retry logic.
void main() {
  group('NOAA API Integration Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('Provider Integration', () {
      test('should create NOAA API client with all dependencies', () {
        // Act
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(rateLimiterProvider);
        final circuitBreaker = container.read(circuitBreakerProvider);
        
        // Assert
        expect(apiClient, isA<NoaaApiClient>());
        expect(rateLimiter, isA<RateLimiter>());
        expect(circuitBreaker, isA<CircuitBreaker>());
      });

      test('should inject dependencies correctly', () {
        // Act
        final httpClient = container.read(httpClientServiceProvider);
        final apiClient = container.read(noaaApiClientProvider);
        
        // Assert
        expect(httpClient, isNotNull);
        expect(apiClient, isNotNull);
        // Dependencies should be injected through constructor
      });

      test('should create singleton instances across providers', () {
        // Act
        final client1 = container.read(noaaApiClientProvider);
        final client2 = container.read(noaaApiClientProvider);
        final rateLimiter1 = container.read(rateLimiterProvider);
        final rateLimiter2 = container.read(rateLimiterProvider);
        
        // Assert
        expect(identical(client1, client2), isTrue);
        expect(identical(rateLimiter1, rateLimiter2), isTrue);
      });
    });

    group('Rate Limiting Integration', () {
      test('should respect rate limits during API calls', () async {
        // Arrange
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(rateLimiterProvider);
        
        // Act - attempt rapid requests
        final requests = <Future>[];
        for (int i = 0; i < 10; i++) {
          requests.add(() async {
            if (rateLimiter.canMakeRequest()) {
              await rateLimiter.acquire();
              // Simulate API call (would normally call apiClient.fetchChartCatalog())
              await Future.delayed(const Duration(milliseconds: 10));
            }
          }());
        }
        
        await Future.wait(requests);
        
        // Assert - rate limiting should have been applied
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, lessThanOrEqualTo(5)); // Default 5 req/sec
      });

      test('should handle rate limit exceeded gracefully', () async {
        // Arrange
        final rateLimiter = container.read(rateLimiterProvider);
        
        // Act - exceed rate limit
        await rateLimiter.acquire(); // 1st request
        await rateLimiter.acquire(); // 2nd request
        await rateLimiter.acquire(); // 3rd request
        await rateLimiter.acquire(); // 4th request
        await rateLimiter.acquire(); // 5th request (at limit)
        
        // Assert - should not allow additional requests
        expect(rateLimiter.canMakeRequest(), isFalse);
        final waitTime = rateLimiter.getWaitTime();
        expect(waitTime.inMilliseconds, greaterThan(0));
      });
    });

    group('Circuit Breaker Integration', () {
      test('should open circuit after consecutive failures', () async {
        // Arrange
        final circuitBreaker = container.read(circuitBreakerProvider);
        
        // Act - simulate consecutive failures
        Future<String> failingOperation() async {
          throw DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.connectionTimeout,
          );
        }
        
        // Trigger failures until circuit opens
        for (int i = 0; i < 3; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {
            // Expected to fail
          }
        }
        
        // Assert
        expect(circuitBreaker.state, CircuitState.open);
        expect(circuitBreaker.isOpen, isTrue);
      });

      test('should fail fast when circuit is open', () async {
        // Arrange
        final circuitBreaker = container.read(circuitBreakerProvider);
        
        // Open the circuit first
        Future<String> failingOperation() async {
          throw DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.connectionTimeout,
          );
        }
        
        for (int i = 0; i < 3; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        // Act & Assert - should fail fast with circuit breaker exception
        expect(() => circuitBreaker.execute(() async => 'test'), 
               throwsA(isA<CircuitBreakerOpenException>()));
      });

      test('should transition to half-open after timeout', () async {
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
          
          // Open the circuit
          Future<String> failingOperation() async {
            throw DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.connectionTimeout,
            );
          }
          
          for (int i = 0; i < 2; i++) {
            try {
              await circuitBreaker.execute(failingOperation);
            } catch (_) {}
          }
          
          expect(circuitBreaker.state, CircuitState.open);
          
          // Wait for timeout
          await Future.delayed(const Duration(milliseconds: 120));
          
          // Act - next operation should transition to half-open
          Future<String> testOperation() async => 'test';
          final result = await circuitBreaker.execute(testOperation);
          
          // Assert
          expect(result, 'test');
          expect(circuitBreaker.state, CircuitState.closed);
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Retry Policy Integration', () {
      test('should apply retry policy for API requests', () async {
        // Arrange
        final retryPolicy = container.read(apiRetryPolicyProvider);
        var attemptCount = 0;
        
        Future<String> flakyOperation() async {
          attemptCount++;
          if (attemptCount < 3) {
            throw DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.connectionTimeout,
            );
          }
          return 'success';
        }
        
        // Act
        final result = await RetryableOperation.execute(
          flakyOperation,
          policy: retryPolicy,
        );
        
        // Assert
        expect(result, 'success');
        expect(attemptCount, 3); // 1 initial + 2 retries
      });

      test('should use different retry policies for different scenarios', () {
        // Act
        final apiPolicy = container.read(apiRetryPolicyProvider);
        final downloadPolicy = container.read(downloadRetryPolicyProvider);
        final criticalPolicy = container.read(criticalRetryPolicyProvider);
        
        // Assert
        expect(apiPolicy, isA<RetryPolicy>());
        expect(downloadPolicy, isA<RetryPolicy>());
        expect(criticalPolicy, isA<RetryPolicy>());
        
        // Verify expected marine-optimized configurations
        expect(apiPolicy.maxRetries, 5); // Fast-failing for API requests
        expect(downloadPolicy.maxRetries, 3); // Conservative for downloads  
        expect(criticalPolicy.maxRetries, 7); // Most persistent for critical ops
        
        // Critical should have longest delays for persistence
        expect(criticalPolicy.maxDelay, greaterThan(downloadPolicy.maxDelay));
      });
    });

    group('End-to-End NOAA Operations', () {
      test('should fetch catalog with rate limiting and circuit protection', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        final mockLogger = MockAppLogger();
        
        // Configure mock responses
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: '{"type":"FeatureCollection","features":[]}',
          statusCode: 200,
        ));
        
        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
            loggerProvider.overrideWith((ref) => mockLogger),
          ],
        );
        
        try {
          // Act
          final apiClient = testContainer.read(noaaApiClientProvider);
          final result = await apiClient.fetchChartCatalog();
          
          // Assert
          expect(result, isNotEmpty);
          verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
        } finally {
          testContainer.dispose();
        }
      });

      test('should handle download with progress tracking and resilience', () async {
        // Arrange
        final mockHttpClient = MockHttpClientService();
        final mockLogger = MockAppLogger();
        
        // Configure mock download response
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((invocation) async {
          // Simulate progress callbacks
          final onProgress = invocation.namedArguments[const Symbol('onReceiveProgress')] as Function?;
          onProgress?.call(50, 100); // 50% progress
          onProgress?.call(100, 100); // Complete
        });
        
        final testContainer = ProviderContainer(
          overrides: [
            httpClientServiceProvider.overrideWith((ref) => mockHttpClient),
            loggerProvider.overrideWith((ref) => mockLogger),
          ],
        );
        
        try {
          // Act
          final apiClient = testContainer.read(noaaApiClientProvider);
          final progressValues = <double>[];
          
          await apiClient.downloadChart(
            'US5CA52M',
            '/tmp/test_chart.zip',
            onProgress: (progress) => progressValues.add(progress),
          );
          
          // Assert
          expect(progressValues, isNotEmpty);
          expect(progressValues.last, 1.0); // Should reach 100%
          verify(mockHttpClient.downloadFile(
            any,
            any,
            onReceiveProgress: anyNamed('onReceiveProgress'),
            cancelToken: anyNamed('cancelToken'),
            queryParameters: anyNamed('queryParameters'),
          )).called(1);
        } finally {
          testContainer.dispose();
        }
      });

      test('should demonstrate offline graceful degradation', () async {
        // Arrange - create circuit breaker with lower failure threshold for testing
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
          
          // Simulate network failures directly on circuit breaker
          Future<String> failingOperation() async {
            throw DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.connectionError,
            );
          }
          
          // Trigger multiple failures to open circuit
          for (int i = 0; i < 2; i++) {
            try {
              await circuitBreaker.execute(failingOperation);
            } catch (_) {
              // Expected to fail
            }
          }
          
          // Assert - circuit should be open
          expect(circuitBreaker.state, CircuitState.open);
          
          // Further requests should fail fast
          expect(() => circuitBreaker.execute(() async => 'test'), 
                 throwsA(isA<CircuitBreakerOpenException>()));
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Performance and Marine Environment', () {
      test('should handle marine environment requirements', () {
        // Arrange
        final rateLimiter = container.read(rateLimiterProvider);
        final circuitBreaker = container.read(circuitBreakerProvider);
        final apiPolicy = container.read(apiRetryPolicyProvider);
        
        // Assert - marine-optimized configurations
        expect(rateLimiter.requestsPerSecond, 5); // NOAA recommended rate
        expect(circuitBreaker.failureThreshold, 3); // Conservative for poor connectivity
        expect(apiPolicy.maxRetries, greaterThanOrEqualTo(3)); // Multiple attempts
      });

      test('should validate timeout configurations for marine networks', () {
        // Arrange
        final downloadPolicy = container.read(downloadRetryPolicyProvider);
        final circuitBreaker = container.read(circuitBreakerProvider);
        
        // Assert - extended timeouts for marine environments
        expect(downloadPolicy.maxDelay.inMinutes, greaterThanOrEqualTo(5));
        expect(circuitBreaker.timeout.inMinutes, greaterThanOrEqualTo(2));
      });

      test('should demonstrate concurrent request handling', () async {
        // Arrange
        final rateLimiter = container.read(rateLimiterProvider);
        
        // Act - simulate multiple concurrent requests
        final futures = List.generate(20, (index) async {
          if (rateLimiter.canMakeRequest()) {
            await rateLimiter.acquire();
            return 'success-$index';
          } else {
            final waitTime = rateLimiter.getWaitTime();
            await Future.delayed(waitTime);
            await rateLimiter.acquire();
            return 'delayed-$index';
          }
        });
        
        final results = await Future.wait(futures);
        
        // Assert
        expect(results.length, 20);
        expect(results.every((r) => r.startsWith('success') || r.startsWith('delayed')), isTrue);
      });
    });
  });
}