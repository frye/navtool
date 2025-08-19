import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'package:navtool/core/models/retry_policy.dart';
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

/// Provider for rate limiter configured for NOAA API constraints
/// 
/// Configured to respect NOAA's recommended rate limit of 5 requests per second
/// to prevent server overload and ensure reliable marine operations.
final rateLimiterProvider = Provider<RateLimiter>((ref) {
  return RateLimiter(
    requestsPerSecond: 5, // NOAA recommended rate limit
    windowSize: const Duration(seconds: 1),
  );
});

/// Provider for circuit breaker configured for marine environments
/// 
/// Conservative failure threshold and extended timeout optimized for
/// challenging marine network conditions including satellite connections.
final circuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  return CircuitBreaker(
    failureThreshold: 3, // Conservative for marine networks
    timeout: const Duration(minutes: 2), // Extended for marine recovery
  );
});

/// Provider for API retry policy
/// 
/// Optimized for fast API requests with moderate retry attempts
/// suitable for chart catalog and metadata operations.
final apiRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.apiRequest;
});

/// Provider for download retry policy
/// 
/// More persistent policy for large chart file downloads
/// with extended timeouts suitable for marine environments.
final downloadRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.chartDownload;
});

/// Provider for critical operations retry policy
/// 
/// Most persistent policy for safety-critical marine operations
/// that must eventually succeed for navigation safety.
final criticalRetryPolicyProvider = Provider<RetryPolicy>((ref) {
  return RetryPolicy.critical;
});

/// Provider for NOAA API client with comprehensive marine optimizations
/// 
/// Integrates rate limiting, circuit breaker protection, and retry logic
/// with the HTTP client service and logging for robust marine operations.
final noaaApiClientProvider = Provider<NoaaApiClient>((ref) {
  return NoaaApiClientImpl(
    httpClient: ref.read(httpClientServiceProvider),
    rateLimiter: ref.read(rateLimiterProvider),
    logger: ref.read(loggerProvider),
  );
});