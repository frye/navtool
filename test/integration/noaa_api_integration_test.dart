import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/utils/network_resilience.dart';
import 'package:navtool/core/models/retry_policy.dart';
import 'package:navtool/core/models/chart.dart';

/// Integration tests for NOAA API client with provider dependency injection
/// 
/// These tests verify end-to-end functionality of the NOAA API client
/// when used through the Riverpod provider system, ensuring all
/// components work together correctly in marine environments.
/// 
/// **Test Categories:**
/// - Provider integration with dependency injection
/// - Rate limiting behavior in real scenarios
/// - Circuit breaker protection during failures
/// - Error handling and resilience patterns
/// - Marine environment optimizations
/// 
/// **Note:** These tests use real provider instances but mock
/// external dependencies to ensure reliable test execution.
void main() {
  group('NOAA API Integration Tests', () {
    late ProviderContainer container;
    late NoaaApiClient apiClient;
    late RateLimiter rateLimiter;
    late CircuitBreaker circuitBreaker;

    setUp(() {
      container = ProviderContainer();
      apiClient = container.read(noaaApiClientProvider);
      rateLimiter = container.read(noaaRateLimiterProvider);
      circuitBreaker = container.read(noaaCircuitBreakerProvider);
    });

    tearDown(() {
      container.dispose();
    });

    group('Provider Integration', () {
      test('should create NOAA API client with all dependencies injected', () {
        // Act & Assert
        expect(apiClient, isA<NoaaApiClient>());
        expect(apiClient, isNotNull);
        
        // Verify rate limiter is properly configured
        expect(rateLimiter.requestsPerSecond, equals(5));
        expect(rateLimiter.windowSize, equals(const Duration(seconds: 1)));
        
        // Verify circuit breaker is in closed state initially
        expect(circuitBreaker.state, equals(CircuitState.closed));
        expect(circuitBreaker.failureThreshold, equals(3));
      });

      test('should maintain singleton pattern across multiple reads', () {
        // Act
        final apiClient1 = container.read(noaaApiClientProvider);
        final apiClient2 = container.read(noaaApiClientProvider);
        final rateLimiter1 = container.read(noaaRateLimiterProvider);
        final rateLimiter2 = container.read(noaaRateLimiterProvider);
        
        // Assert
        expect(identical(apiClient1, apiClient2), isTrue);
        expect(identical(rateLimiter1, rateLimiter2), isTrue);
      });

      test('should allow provider overrides for testing scenarios', () {
        // Arrange
        final mockClient = _MockNoaaApiClient();
        final testContainer = ProviderContainer(
          overrides: [
            noaaApiClientProvider.overrideWith((ref) => mockClient),
          ],
        );

        try {
          // Act
          final overriddenClient = testContainer.read(noaaApiClientProvider);
          
          // Assert
          expect(overriddenClient, equals(mockClient));
          expect(overriddenClient, isNot(equals(apiClient)));
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Rate Limiting Integration', () {
      test('should respect rate limits with provider-configured rate limiter', () async {
        // Arrange
        final rateLimiter = container.read(noaaRateLimiterProvider);
        final start = DateTime.now();
        
        // Act - Make multiple rapid requests to test rate limiting
        final futures = List.generate(3, (_) async {
          await rateLimiter.acquire();
          return DateTime.now();
        });
        
        final timestamps = await Future.wait(futures);
        
        // Assert - Requests should be properly spaced due to rate limiting
        expect(timestamps.length, equals(3));
        final totalTime = timestamps.last.difference(start);
        
        // With 5 requests per second, 3 requests should take at least 400ms
        expect(totalTime.inMilliseconds, greaterThan(300));
      });

      test('should track rate limiter status correctly', () {
        // Act
        final status = rateLimiter.getStatus();
        
        // Assert
        expect(status.requestsPerSecond, equals(5));
        expect(status.requestsInWindow, equals(0));
        expect(status.isAtLimit, isFalse);
      });
    });

    group('Circuit Breaker Integration', () {
      test('should initialize circuit breaker in closed state', () {
        // Act
        final status = circuitBreaker.getStatus();
        
        // Assert
        expect(status.state, equals(CircuitState.closed));
        expect(status.failureCount, equals(0));
        expect(status.successCount, equals(0));
        expect(status.failureThreshold, equals(3));
      });

      test('should handle successful operations through circuit breaker', () async {
        // Act
        final result = await circuitBreaker.execute(() async => 'success');
        final status = circuitBreaker.getStatus();
        
        // Assert
        expect(result, equals('success'));
        expect(status.state, equals(CircuitState.closed));
        expect(status.successCount, equals(1));
        expect(status.failureCount, equals(0));
      });

      test('should count failures but remain closed under threshold', () async {
        // Act - Simulate one failure (under threshold)
        try {
          await circuitBreaker.execute(() async => throw Exception('test failure'));
        } catch (e) {
          // Expected to fail
        }
        
        final status = circuitBreaker.getStatus();
        
        // Assert
        expect(status.state, equals(CircuitState.closed));
        expect(status.failureCount, equals(1));
        expect(status.successCount, equals(0));
      });
    });

    group('Retry Policy Integration', () {
      test('should provide correct chart download retry policy', () {
        // Act
        final policy = container.read(chartDownloadRetryPolicyProvider);
        
        // Assert
        expect(policy.maxRetries, equals(3));
        expect(policy.initialDelay, equals(const Duration(seconds: 2)));
        expect(policy.backoffMultiplier, equals(2.0));
        expect(policy.maxDelay, equals(const Duration(minutes: 5)));
        expect(policy.useJitter, isTrue);
      });

      test('should provide correct API request retry policy', () {
        // Act
        final policy = container.read(apiRequestRetryPolicyProvider);
        
        // Assert
        expect(policy.maxRetries, equals(5));
        expect(policy.initialDelay, equals(const Duration(milliseconds: 500)));
        expect(policy.backoffMultiplier, equals(1.5));
        expect(policy.maxDelay, equals(const Duration(seconds: 30)));
        expect(policy.useJitter, isTrue);
      });

      test('should provide correct critical retry policy', () {
        // Act
        final policy = container.read(criticalRetryPolicyProvider);
        
        // Assert
        expect(policy.maxRetries, equals(7));
        expect(policy.initialDelay, equals(const Duration(seconds: 1)));
        expect(policy.backoffMultiplier, equals(2.0));
        expect(policy.maxDelay, equals(const Duration(minutes: 10)));
        expect(policy.useJitter, isTrue);
      });

      test('should calculate delays correctly for marine environments', () {
        // Arrange
        final policy = container.read(chartDownloadRetryPolicyProvider);
        
        // Act & Assert - Test delay calculations
        final delay0 = policy.calculateDelay(0);
        final delay1 = policy.calculateDelay(1);
        final delay2 = policy.calculateDelay(2);
        
        expect(delay0.inSeconds, greaterThanOrEqualTo(1)); // ~2s with jitter
        expect(delay1.inSeconds, greaterThanOrEqualTo(3)); // ~4s with jitter
        expect(delay2.inSeconds, greaterThanOrEqualTo(7)); // ~8s with jitter
      });
    });

    group('Network Resilience Integration', () {
      test('should provide network resilience utilities', () {
        // Act
        final networkResilience = container.read(networkResilienceProvider);
        
        // Assert
        expect(networkResilience, isA<NetworkResilience>());
        expect(networkResilience, isNotNull);
      });
    });

    group('Marine Environment Optimizations', () {
      test('should configure rate limiter for marine connectivity constraints', () {
        // Act
        final rateLimiter = container.read(noaaRateLimiterProvider);
        
        // Assert - Conservative rate limiting for marine environments
        expect(rateLimiter.requestsPerSecond, equals(5));
        expect(rateLimiter.windowSize, equals(const Duration(seconds: 1)));
      });

      test('should configure circuit breaker for marine reliability', () {
        // Act
        final circuitBreaker = container.read(noaaCircuitBreakerProvider);
        
        // Assert - Balanced thresholds for marine conditions
        expect(circuitBreaker.failureThreshold, equals(3));
        expect(circuitBreaker.timeout, equals(const Duration(minutes: 2)));
      });

      test('should provide marine-optimized retry policies', () {
        // Act
        final chartPolicy = container.read(chartDownloadRetryPolicyProvider);
        final apiPolicy = container.read(apiRequestRetryPolicyProvider);
        final criticalPolicy = container.read(criticalRetryPolicyProvider);
        
        // Assert - Conservative policies for challenging marine environments
        expect(chartPolicy.maxDelay, equals(const Duration(minutes: 5)));
        expect(apiPolicy.maxDelay, equals(const Duration(seconds: 30)));
        expect(criticalPolicy.maxDelay, equals(const Duration(minutes: 10)));
        
        // All policies should use jitter to prevent thundering herd
        expect(chartPolicy.useJitter, isTrue);
        expect(apiPolicy.useJitter, isTrue);
        expect(criticalPolicy.useJitter, isTrue);
      });
    });

    group('Error Handling and Resilience', () {
      test('should handle provider creation errors gracefully', () {
        // This test verifies that provider creation doesn't throw
        // even when some dependencies might not be perfectly configured
        
        expect(() => container.read(noaaMetadataParserProvider), returnsNormally);
        expect(() => container.read(chartCatalogServiceProvider), returnsNormally);
        expect(() => container.read(stateRegionMappingServiceProvider), returnsNormally);
        expect(() => container.read(noaaChartDiscoveryServiceProvider), returnsNormally);
        expect(() => container.read(noaaApiClientProvider), returnsNormally);
      });

      test('should maintain resilience component state across provider usage', () {
        // Arrange
        final rateLimiter = container.read(noaaRateLimiterProvider);
        final circuitBreaker = container.read(noaaCircuitBreakerProvider);
        
        // Act - Use providers multiple times
        container.read(noaaApiClientProvider);
        container.read(noaaApiClientProvider);
        
        // Assert - State should remain consistent
        expect(rateLimiter.getStatus().requestsInWindow, equals(0));
        expect(circuitBreaker.state, equals(CircuitState.closed));
      });
    });

    group('Performance and Memory', () {
      test('should not create excessive instances during normal usage', () {
        // Act - Read providers multiple times
        final instances = <Object>[];
        for (int i = 0; i < 10; i++) {
          instances.add(container.read(noaaApiClientProvider));
          instances.add(container.read(noaaRateLimiterProvider));
          instances.add(container.read(noaaCircuitBreakerProvider));
        }
        
        // Assert - Should reuse the same instances (singleton pattern)
        final uniqueClients = instances.where((i) => i is NoaaApiClient).toSet();
        final uniqueRateLimiters = instances.where((i) => i is RateLimiter).toSet();
        final uniqueCircuitBreakers = instances.where((i) => i is CircuitBreaker).toSet();
        
        expect(uniqueClients.length, equals(1));
        expect(uniqueRateLimiters.length, equals(1));
        expect(uniqueCircuitBreakers.length, equals(1));
      });
    });
  });
}

/// Mock NOAA API client for testing provider overrides
class _MockNoaaApiClient implements NoaaApiClient {
  @override
  Future<String> fetchChartCatalog({Map<String, String>? filters}) async => 'mock-catalog';
  
  @override
  Future<Chart?> getChartMetadata(String cellName) async => null;
  
  @override
  Future<bool> isChartAvailable(String cellName) async => true;
  
  @override
  Future<void> downloadChart(String cellName, String outputPath, {void Function(double)? onProgress}) async {
    // Simulate download progress
    if (onProgress != null) {
      onProgress(0.5);
      onProgress(1.0);
    }
  }
  
  @override
  Stream<double> getDownloadProgress(String cellName) => Stream.fromIterable([0.0, 0.5, 1.0]);
  
  @override
  Future<void> cancelDownload(String cellName) async {}
}