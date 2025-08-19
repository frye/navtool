import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/utils/network_resilience.dart';
import 'package:navtool/core/models/retry_policy.dart';
import 'package:navtool/core/error/noaa_error_classifier.dart';
import 'package:navtool/core/state/providers.dart';

/// Provider for NOAA metadata parser
final noaaMetadataParserProvider = Provider<NoaaMetadataParser>((ref) {
  return NoaaMetadataParserImpl(
    logger: ref.read(loggerProvider),
  );
});

/// Provider for chart catalog service
final chartCatalogServiceProvider = Provider<ChartCatalogService>((ref) {
  return ChartCatalogServiceImpl(
    cacheService: ref.read(cacheServiceProvider),
    logger: ref.read(loggerProvider),
  );
});

/// Provider for state region mapping service
final stateRegionMappingServiceProvider = Provider<StateRegionMappingService>((ref) {
  return StateRegionMappingServiceImpl(
    cacheService: ref.read(cacheServiceProvider),
    logger: ref.read(loggerProvider),
    httpClient: ref.read(httpClientServiceProvider),
  );
});

/// Provider for NOAA chart discovery service
final noaaChartDiscoveryServiceProvider = Provider<NoaaChartDiscoveryService>((ref) {
  return NoaaChartDiscoveryServiceImpl(
    catalogService: ref.read(chartCatalogServiceProvider),
    mappingService: ref.read(stateRegionMappingServiceProvider),
    logger: ref.read(loggerProvider),
  );
});

// NOAA API Client and Network Resilience Providers

/// Provider for rate limiter configured for NOAA API constraints
/// 
/// Configured for 5 requests per second to respect NOAA server limits
/// and prevent rate limiting errors during marine operations.
final noaaRateLimiterProvider = Provider<RateLimiter>((ref) {
  return RateLimiter(
    requestsPerSecond: 5,
    windowSize: const Duration(seconds: 1),
  );
});

/// Provider for circuit breaker with NOAA-specific configuration
/// 
/// Protects against cascading failures with marine-optimized thresholds
/// for challenging network conditions common in marine environments.
final noaaCircuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  return CircuitBreaker(
    failureThreshold: 3,
    timeout: const Duration(minutes: 2),
    shouldCountAsFailure: (error) {
      // Use NOAA error classifier to determine if error should trigger circuit breaker
      final classifier = NoaaErrorClassifier();
      return classifier.shouldRetry(error).shouldRetry == false;
    },
  );
});

/// Provider for network resilience utilities
/// 
/// Provides network quality monitoring and adaptive behavior
/// for challenging marine connectivity scenarios.
final networkResilienceProvider = Provider<NetworkResilience>((ref) {
  return NetworkResilience();
});

/// Providers for predefined retry policies optimized for marine operations

/// Provider for chart download retry policy
/// 
/// Conservative policy suitable for large file downloads over
/// potentially slow marine internet connections.
final chartDownloadRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.chartDownload;
});

/// Provider for API request retry policy
/// 
/// More aggressive policy for smaller requests that should
/// fail fast in marine environments.
final apiRequestRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.apiRequest;
});

/// Provider for critical operations retry policy
/// 
/// More persistent policy for safety-critical marine operations
/// that must eventually succeed.
final criticalRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.critical;
});

/// Provider for NOAA API client with comprehensive dependency injection
/// 
/// Integrates with all network resilience components and provides
/// enterprise-grade reliability for marine navigation applications.
/// 
/// **Dependencies:**
/// - HTTP client service with NOAA endpoint configuration
/// - Rate limiter configured for NOAA server constraints
/// - Logger for debugging and monitoring
/// 
/// **Features:**
/// - Automatic rate limiting and retry logic
/// - Progress tracking for chart downloads
/// - Marine-optimized error handling
/// - Resource cleanup and cancellation support
final noaaApiClientProvider = Provider<NoaaApiClient>((ref) {
  return NoaaApiClientImpl(
    httpClient: ref.read(httpClientServiceProvider),
    rateLimiter: ref.read(noaaRateLimiterProvider),
    logger: ref.read(loggerProvider),
  );
});