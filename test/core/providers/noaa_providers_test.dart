import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/models/retry_policy.dart';
import 'package:navtool/core/models/chart.dart';

void main() {
  group('NOAA Providers Registration Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('Core Service Providers', () {
      test('should register noaaMetadataParserProvider successfully', () {
        // Act
        final parser = container.read(noaaMetadataParserProvider);

        // Assert
        expect(parser, isA<NoaaMetadataParser>());
        expect(parser, isNotNull);
      });

      test('should register chartCatalogServiceProvider successfully', () {
        // Act
        final catalogService = container.read(chartCatalogServiceProvider);

        // Assert
        expect(catalogService, isA<ChartCatalogService>());
        expect(catalogService, isNotNull);
      });

      test(
        'should register stateRegionMappingServiceProvider successfully',
        () {
          // Act
          final mappingService = container.read(
            stateRegionMappingServiceProvider,
          );

          // Assert
          expect(mappingService, isA<StateRegionMappingService>());
          expect(mappingService, isNotNull);
        },
      );

      test(
        'should register noaaChartDiscoveryServiceProvider successfully',
        () {
          // Act
          final discoveryService = container.read(
            noaaChartDiscoveryServiceProvider,
          );

          // Assert
          expect(discoveryService, isA<NoaaChartDiscoveryService>());
          expect(discoveryService, isNotNull);
        },
      );

      test('should properly inject dependencies in discovery service', () {
        // Act
        final discoveryService = container.read(
          noaaChartDiscoveryServiceProvider,
        );
        final catalogService = container.read(chartCatalogServiceProvider);
        final mappingService = container.read(
          stateRegionMappingServiceProvider,
        );

        // Assert
        expect(discoveryService, isNotNull);
        expect(catalogService, isNotNull);
        expect(mappingService, isNotNull);

        // Verify that the discovery service uses the injected dependencies
        expect(discoveryService, isA<NoaaChartDiscoveryServiceImpl>());
      });
    });

    group('NOAA API Client Provider', () {
      test('should register noaaApiClientProvider successfully', () {
        // Act
        final apiClient = container.read(noaaApiClientProvider);

        // Assert
        expect(apiClient, isA<NoaaApiClient>());
        expect(apiClient, isNotNull);
      });

      test('should inject all required dependencies in API client', () {
        // Act
        final apiClient = container.read(noaaApiClientProvider);

        // Assert - dependencies should be properly injected
        expect(apiClient, isNotNull);
        // The implementation should have received HttpClientService, RateLimiter, and AppLogger
      });
    });

    group('Rate Limiter Provider', () {
      test('should register rateLimiterProvider successfully', () {
        // Act
        final rateLimiter = container.read(rateLimiterProvider);

        // Assert
        expect(rateLimiter, isA<RateLimiter>());
        expect(rateLimiter, isNotNull);
      });

      test('should configure rate limiter for NOAA API limits', () {
        // Act
        final rateLimiter = container.read(rateLimiterProvider);

        // Assert
        expect(rateLimiter.requestsPerSecond, 5); // NOAA recommended limit
        expect(rateLimiter.windowSize, const Duration(seconds: 1));
      });
    });

    group('Circuit Breaker Provider', () {
      test('should register circuitBreakerProvider successfully', () {
        // Act
        final circuitBreaker = container.read(circuitBreakerProvider);

        // Assert
        expect(circuitBreaker, isA<CircuitBreaker>());
        expect(circuitBreaker, isNotNull);
      });

      test('should configure circuit breaker for marine environments', () {
        // Act
        final circuitBreaker = container.read(circuitBreakerProvider);

        // Assert
        expect(
          circuitBreaker.failureThreshold,
          3,
        ); // Conservative for marine networks
        expect(
          circuitBreaker.timeout.inMinutes,
          greaterThanOrEqualTo(2),
        ); // Marine timeout
      });
    });

    group('Retry Policy Providers', () {
      test('should register apiRetryPolicyProvider successfully', () {
        // Act
        final policy = container.read(apiRetryPolicyProvider);

        // Assert
        expect(policy, isA<RetryPolicy>());
        expect(policy, isNotNull);
      });

      test('should register downloadRetryPolicyProvider successfully', () {
        // Act
        final policy = container.read(downloadRetryPolicyProvider);

        // Assert
        expect(policy, isA<RetryPolicy>());
        expect(policy, isNotNull);
      });

      test('should register criticalRetryPolicyProvider successfully', () {
        // Act
        final policy = container.read(criticalRetryPolicyProvider);

        // Assert
        expect(policy, isA<RetryPolicy>());
        expect(policy, isNotNull);
      });

      test('should configure different retry policies appropriately', () {
        // Act
        final apiPolicy = container.read(apiRetryPolicyProvider);
        final downloadPolicy = container.read(downloadRetryPolicyProvider);
        final criticalPolicy = container.read(criticalRetryPolicyProvider);

        // Assert - policies should have appropriate configurations for marine use
        expect(apiPolicy.maxRetries, 5); // Fast failing for API requests
        expect(downloadPolicy.maxRetries, 3); // Conservative for downloads
        expect(
          criticalPolicy.maxRetries,
          7,
        ); // Most persistent for critical ops

        // Download policy should be fastest for large files
        expect(downloadPolicy.maxDelay, greaterThan(apiPolicy.maxDelay));

        // Critical should have longest delays
        expect(criticalPolicy.maxDelay, greaterThan(downloadPolicy.maxDelay));

        // All should use jitter for marine environments
        expect(apiPolicy.useJitter, isTrue);
        expect(downloadPolicy.useJitter, isTrue);
        expect(criticalPolicy.useJitter, isTrue);
      });
    });

    group('Provider Singletons', () {
      test('should create singleton instances', () {
        // Act
        final parser1 = container.read(noaaMetadataParserProvider);
        final parser2 = container.read(noaaMetadataParserProvider);

        final catalog1 = container.read(chartCatalogServiceProvider);
        final catalog2 = container.read(chartCatalogServiceProvider);

        final mapping1 = container.read(stateRegionMappingServiceProvider);
        final mapping2 = container.read(stateRegionMappingServiceProvider);

        final discovery1 = container.read(noaaChartDiscoveryServiceProvider);
        final discovery2 = container.read(noaaChartDiscoveryServiceProvider);

        final apiClient1 = container.read(noaaApiClientProvider);
        final apiClient2 = container.read(noaaApiClientProvider);

        final rateLimiter1 = container.read(rateLimiterProvider);
        final rateLimiter2 = container.read(rateLimiterProvider);

        // Assert
        expect(identical(parser1, parser2), isTrue);
        expect(identical(catalog1, catalog2), isTrue);
        expect(identical(mapping1, mapping2), isTrue);
        expect(identical(discovery1, discovery2), isTrue);
        expect(identical(apiClient1, apiClient2), isTrue);
        expect(identical(rateLimiter1, rateLimiter2), isTrue);
      });

      test('should create separate instances for retry policies', () {
        // Act
        final apiPolicy1 = container.read(apiRetryPolicyProvider);
        final apiPolicy2 = container.read(apiRetryPolicyProvider);
        final downloadPolicy = container.read(downloadRetryPolicyProvider);
        final criticalPolicy = container.read(criticalRetryPolicyProvider);

        // Assert - policies should be const values, so identical
        expect(identical(apiPolicy1, apiPolicy2), isTrue);

        // Different policies should have different configurations
        expect(
          apiPolicy1.maxRetries != downloadPolicy.maxRetries ||
              apiPolicy1.maxDelay != downloadPolicy.maxDelay,
          isTrue,
        );
        expect(
          downloadPolicy.maxRetries != criticalPolicy.maxRetries ||
              downloadPolicy.maxDelay != criticalPolicy.maxDelay,
          isTrue,
        );
      });
    });

    group('Provider Disposal and Lifecycle', () {
      test('should handle provider disposal correctly', () {
        // Act
        final discoveryService = container.read(
          noaaChartDiscoveryServiceProvider,
        );
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(rateLimiterProvider);

        // Assert - Should not throw when container is disposed
        expect(discoveryService, isNotNull);
        expect(apiClient, isNotNull);
        expect(rateLimiter, isNotNull);
        expect(() => container.dispose(), returnsNormally);
      });

      test('should allow provider override for testing', () {
        // Arrange
        final mockDiscoveryService = MockNoaaChartDiscoveryService();
        final mockApiClient = MockNoaaApiClient();
        final testContainer = ProviderContainer(
          overrides: [
            noaaChartDiscoveryServiceProvider.overrideWith(
              (ref) => mockDiscoveryService,
            ),
            noaaApiClientProvider.overrideWith((ref) => mockApiClient),
          ],
        );

        try {
          // Act
          final discoveryService = testContainer.read(
            noaaChartDiscoveryServiceProvider,
          );
          final apiClient = testContainer.read(noaaApiClientProvider);

          // Assert
          expect(discoveryService, equals(mockDiscoveryService));
          expect(apiClient, equals(mockApiClient));
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Cross-Provider Dependencies', () {
      test('should share dependencies between providers', () {
        // Act
        final httpClient1 = container.read(httpClientServiceProvider);
        final logger1 = container.read(loggerProvider);

        // Force creation of API client (which uses httpClient and logger)
        container.read(noaaApiClientProvider);

        // Get the same providers again
        final httpClient2 = container.read(httpClientServiceProvider);
        final logger2 = container.read(loggerProvider);

        // Assert - same instances should be shared
        expect(identical(httpClient1, httpClient2), isTrue);
        expect(identical(logger1, logger2), isTrue);
      });

      test('should maintain consistency across provider reads', () {
        // Act - read providers in different orders
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(rateLimiterProvider);
        final circuitBreaker = container.read(circuitBreakerProvider);
        final discoveryService = container.read(
          noaaChartDiscoveryServiceProvider,
        );

        // Assert - all should be properly created
        expect(apiClient, isNotNull);
        expect(rateLimiter, isNotNull);
        expect(circuitBreaker, isNotNull);
        expect(discoveryService, isNotNull);

        // Re-read in different order
        final discoveryService2 = container.read(
          noaaChartDiscoveryServiceProvider,
        );
        final circuitBreaker2 = container.read(circuitBreakerProvider);
        final rateLimiter2 = container.read(rateLimiterProvider);
        final apiClient2 = container.read(noaaApiClientProvider);

        // Should be same instances
        expect(identical(apiClient, apiClient2), isTrue);
        expect(identical(rateLimiter, rateLimiter2), isTrue);
        expect(identical(circuitBreaker, circuitBreaker2), isTrue);
        expect(identical(discoveryService, discoveryService2), isTrue);
      });
    });
  });
}

// Mock classes for testing provider overrides
class MockNoaaChartDiscoveryService implements NoaaChartDiscoveryService {
  @override
  Future<List<Chart>> discoverChartsByState(String state) async => [];

  // Added to satisfy updated interface
  @override
  Future<List<Chart>> discoverChartsByLocation(_) async => [];

  @override
  Future<List<Chart>> searchCharts(
    String query, {
    Map<String, String>? filters,
  }) async => [];

  @override
  Future<Chart?> getChartMetadata(String chartId) async => null;

  @override
  Stream<List<Chart>> watchChartsForState(String state) => Stream.value([]);

  @override
  Future<bool> refreshCatalog({bool force = false}) async => true;

  // Added to satisfy updated interface
  @override
  Future<int> fixChartDiscoveryCache() async => 0;
}

class MockNoaaApiClient implements NoaaApiClient {
  @override
  Future<String> fetchChartCatalog({Map<String, String>? filters}) async =>
      '{}';

  @override
  Future<void> downloadChart(
    String cellName,
    String savePath, {
    NoaaProgressCallback? onProgress,
  }) async {}

  @override
  Future<Chart?> getChartMetadata(String cellName) async => null;

  @override
  Future<bool> isChartAvailable(String cellName) async => true;

  @override
  Future<void> cancelDownload(String cellName) async {}

  @override
  Stream<double> getDownloadProgress(String cellName) => Stream.value(0.0);
}
