# NOAA API Client Usage Guide

This document provides comprehensive usage examples and best practices for the NOAA API client with Riverpod integration in marine navigation applications.

## Overview

The NOAA API client provides robust access to NOAA Electronic Navigational Chart (ENC) services with built-in resilience features optimized for marine environments including:

- **Rate Limiting**: Respects NOAA server constraints (5 requests/second)
- **Circuit Breaker Protection**: Prevents cascade failures in poor connectivity
- **Retry Logic**: Automatic retry with exponential backoff for transient failures
- **Progress Tracking**: Real-time download progress for large chart files
- **Marine Optimizations**: Extended timeouts and error handling for satellite/marine networks

## Quick Start

### Basic Setup

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';

class ChartDownloadWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.read(noaaApiClientProvider);
    
    return ElevatedButton(
      onPressed: () => _downloadChart(apiClient),
      child: Text('Download Chart'),
    );
  }
  
  Future<void> _downloadChart(NoaaApiClient apiClient) async {
    try {
      await apiClient.downloadChart(
        'US5CA52M',
        '/path/to/charts/US5CA52M.zip',
        onProgress: (progress) => print('${(progress * 100).round()}%'),
      );
    } catch (e) {
      print('Download failed: $e');
    }
  }
}
```

### Consumer Hook Pattern

```dart
class ChartCatalogWidget extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.read(noaaApiClientProvider);
    final catalogFuture = useMemoized(() => apiClient.fetchChartCatalog());
    final catalogSnapshot = useFuture(catalogFuture);
    
    return catalogSnapshot.when(
      data: (catalog) => ChartListView(catalog: catalog),
      loading: () => CircularProgressIndicator(),
      error: (error, stack) => ErrorWidget(error.toString()),
    );
  }
}
```

## Core Operations

### Fetching Chart Catalog

```dart
class ChartCatalogService {
  final NoaaApiClient _apiClient;
  
  ChartCatalogService(this._apiClient);
  
  /// Fetch complete chart catalog with optional filtering
  Future<List<Chart>> getChartCatalog({
    String? state,
    String? region,
    String? usage,
  }) async {
    try {
      final filters = <String, String>{};
      if (state != null) filters['STATE'] = state;
      if (region != null) filters['REGION'] = region;
      if (usage != null) filters['USAGE'] = usage;
      
      final catalogJson = await _apiClient.fetchChartCatalog(filters: filters);
      return _parseChartCatalog(catalogJson);
    } catch (e) {
      throw ChartCatalogException('Failed to fetch catalog: $e');
    }
  }
  
  /// Get charts for specific geographic bounds
  Future<List<Chart>> getChartsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    final filters = {
      'BBOX': '$west,$south,$east,$north',
    };
    
    final catalogJson = await _apiClient.fetchChartCatalog(filters: filters);
    return _parseChartCatalog(catalogJson);
  }
}
```

### Chart Downloads with Progress

```dart
class ChartDownloadManager extends ChangeNotifier {
  final NoaaApiClient _apiClient;
  final Map<String, double> _downloadProgress = {};
  final Map<String, StreamSubscription> _progressSubscriptions = {};
  
  ChartDownloadManager(this._apiClient);
  
  /// Download chart with real-time progress updates
  Future<void> downloadChart(String cellName, String savePath) async {
    try {
      // Initialize progress tracking
      _downloadProgress[cellName] = 0.0;
      notifyListeners();
      
      await _apiClient.downloadChart(
        cellName,
        savePath,
        onProgress: (progress) {
          _downloadProgress[cellName] = progress;
          notifyListeners();
        },
      );
      
      // Download completed
      _downloadProgress.remove(cellName);
      notifyListeners();
      
    } catch (e) {
      _downloadProgress.remove(cellName);
      notifyListeners();
      rethrow;
    }
  }
  
  /// Cancel active download
  Future<void> cancelDownload(String cellName) async {
    await _apiClient.cancelDownload(cellName);
    _progressSubscriptions[cellName]?.cancel();
    _progressSubscriptions.remove(cellName);
    _downloadProgress.remove(cellName);
    notifyListeners();
  }
  
  /// Get download progress for specific chart
  double? getProgress(String cellName) => _downloadProgress[cellName];
  
  /// Check if chart is currently downloading
  bool isDownloading(String cellName) => _downloadProgress.containsKey(cellName);
  
  @override
  void dispose() {
    for (final subscription in _progressSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}
```

### Chart Availability and Metadata

```dart
class ChartMetadataService {
  final NoaaApiClient _apiClient;
  
  ChartMetadataService(this._apiClient);
  
  /// Check if chart is available for download
  Future<bool> isChartAvailable(String cellName) async {
    try {
      return await _apiClient.isChartAvailable(cellName);
    } catch (e) {
      // If we can't check availability, assume unavailable
      return false;
    }
  }
  
  /// Get detailed chart metadata
  Future<ChartMetadata?> getChartMetadata(String cellName) async {
    try {
      final chart = await _apiClient.getChartMetadata(cellName);
      return chart != null ? ChartMetadata.fromChart(chart) : null;
    } catch (e) {
      print('Failed to get metadata for $cellName: $e');
      return null;
    }
  }
  
  /// Validate chart before download
  Future<ChartValidation> validateChart(String cellName) async {
    final isAvailable = await isChartAvailable(cellName);
    if (!isAvailable) {
      return ChartValidation.unavailable('Chart $cellName is not available');
    }
    
    final metadata = await getChartMetadata(cellName);
    if (metadata == null) {
      return ChartValidation.invalid('Unable to retrieve chart metadata');
    }
    
    if (metadata.isExpired) {
      return ChartValidation.expired('Chart has expired');
    }
    
    return ChartValidation.valid(metadata);
  }
}
```

## Error Handling

### Comprehensive Error Handling

```dart
class RobustChartService {
  final NoaaApiClient _apiClient;
  final CircuitBreaker _circuitBreaker;
  
  RobustChartService(this._apiClient, this._circuitBreaker);
  
  /// Download chart with comprehensive error handling
  Future<DownloadResult> downloadChartSafely(
    String cellName,
    String savePath,
  ) async {
    try {
      // Check circuit breaker status
      if (_circuitBreaker.isOpen) {
        return DownloadResult.circuitOpen(
          'Service temporarily unavailable due to network issues'
        );
      }
      
      // Validate chart first
      final validation = await validateChart(cellName);
      if (!validation.isValid) {
        return DownloadResult.validationFailed(validation.message);
      }
      
      // Perform download with circuit breaker protection
      await _circuitBreaker.execute(() async {
        await _apiClient.downloadChart(cellName, savePath);
      });
      
      return DownloadResult.success(savePath);
      
    } on CircuitBreakerOpenException catch (e) {
      return DownloadResult.circuitOpen(e.message);
    } on NetworkConnectivityException catch (e) {
      return DownloadResult.networkError(
        'Network connectivity issue: ${e.message}'
      );
    } on RateLimitExceededException catch (e) {
      return DownloadResult.rateLimited(
        'Rate limit exceeded. Please wait before retrying.'
      );
    } on ChartNotAvailableException catch (e) {
      return DownloadResult.chartUnavailable(e.message);
    } on ChartDownloadException catch (e) {
      return DownloadResult.downloadFailed(e.message);
    } catch (e) {
      return DownloadResult.unknownError('Unexpected error: $e');
    }
  }
}
```

### Retry Logic Usage

```dart
class RetryableChartOperations {
  final NoaaApiClient _apiClient;
  
  RetryableChartOperations(this._apiClient);
  
  /// Fetch catalog with custom retry policy
  Future<String> fetchCatalogWithRetry() async {
    return await RetryableOperation.execute(
      () => _apiClient.fetchChartCatalog(),
      policy: RetryPolicy.apiRequest,
    );
  }
  
  /// Download with persistent retry for critical charts
  Future<void> downloadCriticalChart(String cellName, String savePath) async {
    await RetryableOperation.execute(
      () => _apiClient.downloadChart(cellName, savePath),
      policy: RetryPolicy.critical, // Most persistent policy
    );
  }
  
  /// Get detailed retry metrics
  Future<RetryResult<String>> fetchCatalogWithMetrics() async {
    return await RetryableOperation.executeWithMetrics(
      () => _apiClient.fetchChartCatalog(),
      policy: RetryPolicy.apiRequest,
    );
  }
}
```

## Marine Environment Optimizations

### Satellite Internet Handling

```dart
class MarineNetworkService {
  final NoaaApiClient _apiClient;
  final RateLimiter _rateLimiter;
  
  MarineNetworkService(this._apiClient, this._rateLimiter);
  
  /// Optimized for satellite internet with lower bandwidth
  Future<void> downloadChartForSatellite(
    String cellName,
    String savePath,
  ) async {
    // Use more conservative rate limiting for satellite
    final satelliteRateLimiter = RateLimiter(
      requestsPerSecond: 2, // Reduced from default 5
      windowSize: Duration(seconds: 1),
    );
    
    await satelliteRateLimiter.acquire();
    
    await _apiClient.downloadChart(
      cellName,
      savePath,
      onProgress: (progress) {
        // Log progress less frequently to reduce bandwidth
        if (progress % 0.1 == 0) { // Every 10%
          print('Satellite download: ${(progress * 100).round()}%');
        }
      },
    );
  }
  
  /// Batch download for efficient bandwidth usage
  Future<List<String>> downloadMultipleCharts(
    List<String> cellNames,
    String basePath,
  ) async {
    final results = <String>[];
    
    for (final cellName in cellNames) {
      try {
        // Rate limiting between downloads
        await _rateLimiter.acquire();
        
        final savePath = '$basePath/$cellName.zip';
        await _apiClient.downloadChart(cellName, savePath);
        results.add(savePath);
        
        // Small delay for satellite connection stability
        await Future.delayed(Duration(milliseconds: 500));
        
      } catch (e) {
        print('Failed to download $cellName: $e');
        // Continue with next chart
      }
    }
    
    return results;
  }
}
```

### Offline Graceful Degradation

```dart
class OfflineCapableChartService {
  final NoaaApiClient _apiClient;
  final LocalChartStorage _localStorage;
  final CircuitBreaker _circuitBreaker;
  
  OfflineCapableChartService(
    this._apiClient,
    this._localStorage,
    this._circuitBreaker,
  );
  
  /// Get chart with fallback to local storage
  Future<Chart?> getChartWithFallback(String cellName) async {
    try {
      // Try online first if circuit is closed
      if (!_circuitBreaker.isOpen) {
        return await _apiClient.getChartMetadata(cellName);
      }
    } catch (e) {
      print('Online chart fetch failed, falling back to local: $e');
    }
    
    // Fallback to local storage
    return await _localStorage.getChart(cellName);
  }
  
  /// Sync when connectivity returns
  Future<void> syncWhenOnline() async {
    try {
      // Wait for circuit to close (connectivity restored)
      while (_circuitBreaker.isOpen) {
        await Future.delayed(Duration(seconds: 30));
      }
      
      // Perform sync operations
      await _syncLocalCharts();
      await _downloadPendingCharts();
      
    } catch (e) {
      print('Sync failed: $e');
    }
  }
  
  Future<void> _syncLocalCharts() async {
    final localCharts = await _localStorage.getAllCharts();
    for (final chart in localCharts) {
      try {
        final latest = await _apiClient.getChartMetadata(chart.cellName);
        if (latest != null && latest.lastUpdated.isAfter(chart.lastUpdated)) {
          // Update available - download if needed
          print('Update available for ${chart.cellName}');
        }
      } catch (e) {
        // Continue with next chart
        print('Failed to check update for ${chart.cellName}: $e');
      }
    }
  }
}
```

## Provider Integration

### Custom Provider Overrides

```dart
class TestMarineEnvironment {
  static ProviderContainer createTestContainer() {
    return ProviderContainer(
      overrides: [
        // Simulate poor marine connectivity
        rateLimiterProvider.overrideWith((ref) => RateLimiter(
          requestsPerSecond: 1, // Very conservative
          windowSize: Duration(seconds: 2),
        )),
        
        // Faster circuit breaker for testing
        circuitBreakerProvider.overrideWith((ref) => CircuitBreaker(
          failureThreshold: 2,
          timeout: Duration(seconds: 10),
        )),
        
        // More aggressive retry for testing
        apiRetryPolicyProvider.overrideWith((ref) => RetryPolicy(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 100),
          maxDelay: Duration(seconds: 5),
        )),
      ],
    );
  }
}
```

### Provider Composition

```dart
class ChartService {
  final NoaaApiClient _apiClient;
  final RateLimiter _rateLimiter;
  final CircuitBreaker _circuitBreaker;
  
  ChartService({
    required NoaaApiClient apiClient,
    required RateLimiter rateLimiter,
    required CircuitBreaker circuitBreaker,
  }) : _apiClient = apiClient,
       _rateLimiter = rateLimiter,
       _circuitBreaker = circuitBreaker;
  
  /// Factory constructor using providers
  factory ChartService.fromProviders(ProviderContainer container) {
    return ChartService(
      apiClient: container.read(noaaApiClientProvider),
      rateLimiter: container.read(rateLimiterProvider),
      circuitBreaker: container.read(circuitBreakerProvider),
    );
  }
}

// Provider for composed service
final chartServiceProvider = Provider<ChartService>((ref) {
  return ChartService(
    apiClient: ref.read(noaaApiClientProvider),
    rateLimiter: ref.read(rateLimiterProvider),
    circuitBreaker: ref.read(circuitBreakerProvider),
  );
});
```

## Best Practices

### 1. Resource Management

```dart
class ChartDownloadSession {
  final NoaaApiClient _apiClient;
  final List<String> _activeDownloads = [];
  
  ChartDownloadSession(this._apiClient);
  
  Future<void> downloadChart(String cellName, String savePath) async {
    _activeDownloads.add(cellName);
    try {
      await _apiClient.downloadChart(cellName, savePath);
    } finally {
      _activeDownloads.remove(cellName);
    }
  }
  
  /// Cancel all active downloads on disposal
  Future<void> dispose() async {
    for (final cellName in _activeDownloads.toList()) {
      await _apiClient.cancelDownload(cellName);
    }
    _activeDownloads.clear();
  }
}
```

### 2. Monitoring and Logging

```dart
class ChartServiceWithMonitoring {
  final NoaaApiClient _apiClient;
  final AppLogger _logger;
  
  ChartServiceWithMonitoring(this._apiClient, this._logger);
  
  Future<void> downloadChartWithLogging(String cellName, String savePath) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _logger.info('Starting download of $cellName');
      
      await _apiClient.downloadChart(
        cellName,
        savePath,
        onProgress: (progress) {
          if (progress % 0.25 == 0) { // Log every 25%
            _logger.info('Download $cellName: ${(progress * 100).round()}%');
          }
        },
      );
      
      stopwatch.stop();
      _logger.info(
        'Successfully downloaded $cellName in ${stopwatch.elapsedMilliseconds}ms'
      );
      
    } catch (e) {
      stopwatch.stop();
      _logger.error(
        'Failed to download $cellName after ${stopwatch.elapsedMilliseconds}ms',
        exception: e,
      );
      rethrow;
    }
  }
}
```

### 3. Performance Optimization

```dart
class OptimizedChartService {
  final NoaaApiClient _apiClient;
  final Map<String, Chart> _metadataCache = {};
  final Duration _cacheExpiry = Duration(hours: 6);
  
  OptimizedChartService(this._apiClient);
  
  /// Get chart metadata with caching
  Future<Chart?> getCachedChartMetadata(String cellName) async {
    // Check cache first
    final cached = _metadataCache[cellName];
    if (cached != null && !_isCacheExpired(cached)) {
      return cached;
    }
    
    // Fetch fresh data
    try {
      final chart = await _apiClient.getChartMetadata(cellName);
      if (chart != null) {
        _metadataCache[cellName] = chart;
      }
      return chart;
    } catch (e) {
      // Return cached data if available, even if expired
      return cached;
    }
  }
  
  bool _isCacheExpired(Chart chart) {
    return DateTime.now().difference(chart.lastUpdated) > _cacheExpiry;
  }
  
  /// Preload metadata for multiple charts
  Future<void> preloadMetadata(List<String> cellNames) async {
    final futures = cellNames.map((cellName) async {
      try {
        await getCachedChartMetadata(cellName);
      } catch (e) {
        // Continue with other charts
        print('Failed to preload $cellName: $e');
      }
    });
    
    await Future.wait(futures);
  }
}
```

## Troubleshooting

### Common Issues and Solutions

#### Rate Limiting
**Problem**: `RateLimitExceededException` thrown frequently
**Solution**: 
```dart
// Check rate limiter status before requests
final rateLimiter = ref.read(rateLimiterProvider);
if (!rateLimiter.canMakeRequest()) {
  final waitTime = rateLimiter.getWaitTime();
  await Future.delayed(waitTime);
}
await rateLimiter.acquire();
```

#### Circuit Breaker Open
**Problem**: `CircuitBreakerOpenException` preventing requests
**Solution**:
```dart
final circuitBreaker = ref.read(circuitBreakerProvider);
if (circuitBreaker.isOpen) {
  // Wait for circuit to close or implement fallback
  await Future.delayed(Duration(minutes: 2));
  // Or use cached/offline data
}
```

#### Network Connectivity
**Problem**: Frequent `NetworkConnectivityException` in marine environments
**Solution**:
```dart
// Use more conservative retry policy
final marineRetryPolicy = RetryPolicy(
  maxRetries: 7,
  initialDelay: Duration(seconds: 2),
  maxDelay: Duration(minutes: 10),
  backoffMultiplier: 2.0,
);

await RetryableOperation.execute(
  () => apiClient.fetchChartCatalog(),
  policy: marineRetryPolicy,
);
```

#### Memory Management
**Problem**: High memory usage during multiple downloads
**Solution**:
```dart
// Limit concurrent downloads
final semaphore = Semaphore(2); // Max 2 concurrent downloads

Future<void> downloadWithLimit(String cellName, String savePath) async {
  await semaphore.acquire();
  try {
    await apiClient.downloadChart(cellName, savePath);
  } finally {
    semaphore.release();
  }
}
```

## Performance Tuning

### Marine Environment Recommendations

1. **Rate Limiting**: Use 2-3 requests/second for satellite connections
2. **Timeouts**: Extend to 60+ seconds for large chart downloads
3. **Retry Policy**: Use exponential backoff with jitter
4. **Circuit Breaker**: Set 5+ failure threshold for marine conditions
5. **Caching**: Cache metadata for 6+ hours to reduce requests
6. **Batch Operations**: Group multiple chart requests when possible

### Monitoring Metrics

```dart
class PerformanceMonitor {
  final RateLimiter _rateLimiter;
  final CircuitBreaker _circuitBreaker;
  
  PerformanceMonitor(this._rateLimiter, this._circuitBreaker);
  
  Map<String, dynamic> getMetrics() {
    final rateLimiterStatus = _rateLimiter.getStatus();
    final circuitBreakerStatus = _circuitBreaker.getStatus();
    
    return {
      'rateLimiter': {
        'requestsInWindow': rateLimiterStatus.requestsInWindow,
        'isAtLimit': rateLimiterStatus.isAtLimit,
      },
      'circuitBreaker': {
        'state': circuitBreakerStatus.state.toString(),
        'failureCount': circuitBreakerStatus.failureCount,
        'successCount': circuitBreakerStatus.successCount,
        'failureRate': circuitBreakerStatus.successCount > 0 
            ? circuitBreakerStatus.failureCount / 
              (circuitBreakerStatus.failureCount + circuitBreakerStatus.successCount)
            : 0.0,
      },
    };
  }
}
```

This completes the comprehensive usage guide for the NOAA API client with Riverpod integration. The examples demonstrate proper usage patterns, error handling, and marine environment optimizations essential for reliable maritime navigation applications.