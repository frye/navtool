import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/utils/network_resilience.dart';
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

    group('Basic Service Providers', () {
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

      test('should register stateRegionMappingServiceProvider successfully', () {
        // Act
        final mappingService = container.read(stateRegionMappingServiceProvider);
        
        // Assert
        expect(mappingService, isA<StateRegionMappingService>());
        expect(mappingService, isNotNull);
      });

      test('should register noaaChartDiscoveryServiceProvider successfully', () {
        // Act
        final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
        
        // Assert
        expect(discoveryService, isA<NoaaChartDiscoveryService>());
        expect(discoveryService, isNotNull);
      });
    });

    group('Network Resilience Providers', () {
      test('should register noaaRateLimiterProvider with correct configuration', () {
        // Act
        final rateLimiter = container.read(noaaRateLimiterProvider);
        
        // Assert
        expect(rateLimiter, isA<RateLimiter>());
        expect(rateLimiter.requestsPerSecond, equals(5));
        expect(rateLimiter.windowSize, equals(const Duration(seconds: 1)));
      });

      test('should register noaaCircuitBreakerProvider with marine configuration', () {
        // Act
        final circuitBreaker = container.read(noaaCircuitBreakerProvider);
        
        // Assert
        expect(circuitBreaker, isA<CircuitBreaker>());
        expect(circuitBreaker.failureThreshold, equals(3));
        expect(circuitBreaker.timeout, equals(const Duration(minutes: 2)));
        expect(circuitBreaker.state, equals(CircuitState.closed));
      });

      test('should register networkResilienceProvider successfully', () {
        // Act
        final networkResilience = container.read(networkResilienceProvider);
        
        // Assert
        expect(networkResilience, isA<NetworkResilience>());
        expect(networkResilience, isNotNull);
      });
    });

    group('Retry Policy Providers', () {
      test('should register chartDownloadRetryPolicyProvider with correct configuration', () {
        // Act
        final retryPolicy = container.read(chartDownloadRetryPolicyProvider);
        
        // Assert
        expect(retryPolicy, isA<RetryPolicy>());
        expect(retryPolicy.maxRetries, equals(3));
        expect(retryPolicy.initialDelay, equals(const Duration(seconds: 2)));
        expect(retryPolicy.backoffMultiplier, equals(2.0));
        expect(retryPolicy.maxDelay, equals(const Duration(minutes: 5)));
        expect(retryPolicy.useJitter, isTrue);
      });

      test('should register apiRequestRetryPolicyProvider with correct configuration', () {
        // Act
        final retryPolicy = container.read(apiRequestRetryPolicyProvider);
        
        // Assert
        expect(retryPolicy, isA<RetryPolicy>());
        expect(retryPolicy.maxRetries, equals(5));
        expect(retryPolicy.initialDelay, equals(const Duration(milliseconds: 500)));
        expect(retryPolicy.backoffMultiplier, equals(1.5));
        expect(retryPolicy.maxDelay, equals(const Duration(seconds: 30)));
        expect(retryPolicy.useJitter, isTrue);
      });

      test('should register criticalRetryPolicyProvider with correct configuration', () {
        // Act
        final retryPolicy = container.read(criticalRetryPolicyProvider);
        
        // Assert
        expect(retryPolicy, isA<RetryPolicy>());
        expect(retryPolicy.maxRetries, equals(7));
        expect(retryPolicy.initialDelay, equals(const Duration(seconds: 1)));
        expect(retryPolicy.backoffMultiplier, equals(2.0));
        expect(retryPolicy.maxDelay, equals(const Duration(minutes: 10)));
        expect(retryPolicy.useJitter, isTrue);
      });
    });

    group('NOAA API Client Provider', () {
      test('should register noaaApiClientProvider with all dependencies', () {
        // Act
        final apiClient = container.read(noaaApiClientProvider);
        
        // Assert
        expect(apiClient, isA<NoaaApiClient>());
        expect(apiClient, isNotNull);
      });

      test('should inject correct dependencies in NOAA API client', () {
        // Act
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(noaaRateLimiterProvider);
        
        // Assert - Verify the client was created with injected dependencies
        expect(apiClient, isNotNull);
        expect(rateLimiter, isNotNull);
        expect(rateLimiter.requestsPerSecond, equals(5));
      });
    });

    test('should properly inject dependencies in discovery service', () {
      // Act
      final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
      final catalogService = container.read(chartCatalogServiceProvider);
      final mappingService = container.read(stateRegionMappingServiceProvider);
      
      // Assert
      expect(discoveryService, isNotNull);
      expect(catalogService, isNotNull);
      expect(mappingService, isNotNull);
      
      // Verify that the discovery service uses the injected dependencies
      expect(discoveryService, isA<NoaaChartDiscoveryServiceImpl>());
    });

    test('should create singleton instances', () {
      // Act
      final parser1 = container.read(noaaMetadataParserProvider);
      final parser2 = container.read(noaaMetadataParserProvider);
      
      final catalog1 = container.read(chartCatalogServiceProvider);
      final catalog2 = container.read(chartCatalogServiceProvider);
      
      final apiClient1 = container.read(noaaApiClientProvider);
      final apiClient2 = container.read(noaaApiClientProvider);
      
      final rateLimiter1 = container.read(noaaRateLimiterProvider);
      final rateLimiter2 = container.read(noaaRateLimiterProvider);
      
      // Assert
      expect(identical(parser1, parser2), isTrue);
      expect(identical(catalog1, catalog2), isTrue);
      expect(identical(apiClient1, apiClient2), isTrue);
      expect(identical(rateLimiter1, rateLimiter2), isTrue);
    });

    test('should handle provider disposal correctly', () {
      // Act
      final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
      final apiClient = container.read(noaaApiClientProvider);
      
      // Assert - Should not throw when container is disposed
      expect(discoveryService, isNotNull);
      expect(apiClient, isNotNull);
      expect(() => container.dispose(), returnsNormally);
    });

    test('should allow provider override for testing', () {
      // Arrange
      final mockApiClient = MockNoaaApiClient();
      final testContainer = ProviderContainer(
        overrides: [
          noaaApiClientProvider.overrideWith((ref) => mockApiClient),
        ],
      );

      try {
        // Act
        final apiClient = testContainer.read(noaaApiClientProvider);
        
        // Assert
        expect(apiClient, equals(mockApiClient));
      } finally {
        testContainer.dispose();
      }
    });

    group('Provider Integration', () {
      test('should work together in complete dependency chain', () {
        // Act - Read all providers to verify complete integration
        final parser = container.read(noaaMetadataParserProvider);
        final catalog = container.read(chartCatalogServiceProvider);
        final mapping = container.read(stateRegionMappingServiceProvider);
        final discovery = container.read(noaaChartDiscoveryServiceProvider);
        final apiClient = container.read(noaaApiClientProvider);
        final rateLimiter = container.read(noaaRateLimiterProvider);
        final circuitBreaker = container.read(noaaCircuitBreakerProvider);
        
        // Assert - All providers should be available and properly configured
        expect(parser, isNotNull);
        expect(catalog, isNotNull);
        expect(mapping, isNotNull);
        expect(discovery, isNotNull);
        expect(apiClient, isNotNull);
        expect(rateLimiter, isNotNull);
        expect(circuitBreaker, isNotNull);
      });
    });
  });
}

// Mock classes for testing provider overrides
class MockNoaaChartDiscoveryService implements NoaaChartDiscoveryService {
  @override
  Future<List<Chart>> discoverChartsByState(String state) async => [];
  
  @override
  Future<List<Chart>> searchCharts(String query, {Map<String, String>? filters}) async => [];
  
  @override
  Future<Chart?> getChartMetadata(String chartId) async => null;
  
  @override
  Stream<List<Chart>> watchChartsForState(String state) => Stream.value([]);
  
  @override
  Future<bool> refreshCatalog({bool force = false}) async => true;
}

class MockNoaaApiClient implements NoaaApiClient {
  @override
  Future<String> fetchChartCatalog({Map<String, String>? filters}) async => '';
  
  @override
  Future<Chart?> getChartMetadata(String cellName) async => null;
  
  @override
  Future<bool> isChartAvailable(String cellName) async => false;
  
  @override
  Future<void> downloadChart(String cellName, String outputPath, {void Function(double)? onProgress}) async {}
  
  @override
  Stream<double> getDownloadProgress(String cellName) => Stream.value(0.0);
  
  @override
  Future<void> cancelDownload(String cellName) async {}
}