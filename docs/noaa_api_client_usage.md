# NOAA API Client Usage Guide

This guide demonstrates how to use the NOAA API client with Riverpod dependency injection for marine navigation applications.

## Overview

The NOAA API client provides enterprise-grade access to NOAA Electronic Navigational Chart services with comprehensive error handling, rate limiting, and marine environment optimizations.

## Provider Integration

### Basic Setup

The NOAA API client is available through Riverpod providers with all dependencies automatically injected:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';

class ChartService {
  final Ref ref;
  
  ChartService(this.ref);
  
  Future<void> downloadChart(String chartId) async {
    // Get the API client with all dependencies injected
    final apiClient = ref.read(noaaApiClientProvider);
    
    await apiClient.downloadChart(chartId, '/charts/$chartId.000');
  }
}
```

### Available Providers

#### Core API Client
```dart
// Main NOAA API client with full dependency injection
final noaaApiClientProvider = Provider<NoaaApiClient>((ref) { ... });
```

#### Network Resilience Components
```dart
// Rate limiter configured for NOAA server constraints (5 req/sec)
final noaaRateLimiterProvider = Provider<RateLimiter>((ref) { ... });

// Circuit breaker with marine-optimized thresholds
final noaaCircuitBreakerProvider = Provider<CircuitBreaker>((ref) { ... });

// Network quality monitoring for marine environments
final networkResilienceProvider = Provider<NetworkResilience>((ref) { ... });
```

#### Retry Policies
```dart
// Conservative policy for large chart downloads
final chartDownloadRetryPolicyProvider = Provider<RetryPolicy>((ref) { ... });

// Aggressive policy for small API requests
final apiRequestRetryPolicyProvider = Provider<RetryPolicy>((ref) { ... });

// Persistent policy for safety-critical operations
final criticalRetryPolicyProvider = Provider<RetryPolicy>((ref) { ... });
```

## Common Usage Patterns

### 1. Fetching Chart Catalog

```dart
class ChartCatalogWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: _fetchCatalog(ref),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ChartListView(catalog: snapshot.data!);
        } else if (snapshot.hasError) {
          return ErrorWidget(error: snapshot.error!);
        }
        return CircularProgressIndicator();
      },
    );
  }
  
  Future<String> _fetchCatalog(WidgetRef ref) async {
    final apiClient = ref.read(noaaApiClientProvider);
    
    try {
      return await apiClient.fetchChartCatalog(
        filters: {
          'region': 'US_East_Coast',
          'scale': 'large_scale',
        },
      );
    } on NoaaRateLimitException catch (e) {
      // Handle rate limiting gracefully
      await Future.delayed(e.retryAfter ?? Duration(seconds: 30));
      return await apiClient.fetchChartCatalog();
    } on NoaaServerException catch (e) {
      // Log server errors for marine troubleshooting
      ref.read(loggerProvider).warning(
        'NOAA server error: ${e.message}',
        context: 'ChartCatalog',
        exception: e,
      );
      rethrow;
    }
  }
}
```

### 2. Downloading Charts with Progress Tracking

```dart
class ChartDownloadService extends ConsumerNotifier<DownloadState> {
  @override
  DownloadState build() => DownloadState.initial();
  
  Future<void> downloadChart(String chartId, String outputPath) async {
    final apiClient = ref.read(noaaApiClientProvider);
    
    state = state.copyWith(status: DownloadStatus.downloading);
    
    try {
      // Start download with progress tracking
      await apiClient.downloadChart(
        chartId,
        outputPath,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );
      
      state = state.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
      );
    } on NoaaNetworkException catch (e) {
      // Handle network issues common in marine environments
      state = state.copyWith(
        status: DownloadStatus.failed,
        error: 'Network error: Poor connectivity detected. ${e.message}',
      );
    } on NoaaChartNotFoundException catch (e) {
      state = state.copyWith(
        status: DownloadStatus.failed,
        error: 'Chart not available: ${e.chartId}',
      );
    }
  }
  
  void cancelDownload(String chartId) {
    final apiClient = ref.read(noaaApiClientProvider);
    apiClient.cancelDownload(chartId);
    
    state = state.copyWith(status: DownloadStatus.cancelled);
  }
}
```

### 3. Chart Availability Checking

```dart
class ChartAvailabilityService {
  final Ref ref;
  
  ChartAvailabilityService(this.ref);
  
  Future<Map<String, bool>> checkChartsAvailability(List<String> chartIds) async {
    final apiClient = ref.read(noaaApiClientProvider);
    final rateLimiter = ref.read(noaaRateLimiterProvider);
    
    final results = <String, bool>{};
    
    for (final chartId in chartIds) {
      // Respect rate limits between availability checks
      await rateLimiter.acquire();
      
      try {
        results[chartId] = await apiClient.isChartAvailable(chartId);
      } catch (e) {
        // Assume unavailable on error
        results[chartId] = false;
        ref.read(loggerProvider).warning(
          'Failed to check availability for chart $chartId: $e',
          context: 'ChartAvailability',
        );
      }
    }
    
    return results;
  }
}
```

### 4. Using Circuit Breaker for Resilience

```dart
class ResilientChartService {
  final Ref ref;
  
  ResilientChartService(this.ref);
  
  Future<Chart?> getChartWithResilience(String chartId) async {
    final apiClient = ref.read(noaaApiClientProvider);
    final circuitBreaker = ref.read(noaaCircuitBreakerProvider);
    
    try {
      // Execute through circuit breaker for automatic failure protection
      return await circuitBreaker.execute(() async {
        return await apiClient.getChartMetadata(chartId);
      });
    } on CircuitBreakerOpenException {
      // Circuit breaker is open - service is temporarily unavailable
      ref.read(loggerProvider).warning(
        'Chart service temporarily unavailable due to circuit breaker',
        context: 'ResilientChartService',
      );
      
      // Return cached data or show offline mode
      return _getCachedChart(chartId);
    }
  }
  
  Chart? _getCachedChart(String chartId) {
    // Implementation for cached chart retrieval
    return null;
  }
}
```

### 5. Batch Operations with Retry Policies

```dart
class BatchChartProcessor {
  final Ref ref;
  
  BatchChartProcessor(this.ref);
  
  Future<void> processCriticalCharts(List<String> chartIds) async {
    final apiClient = ref.read(noaaApiClientProvider);
    final retryPolicy = ref.read(criticalRetryPolicyProvider);
    
    for (final chartId in chartIds) {
      await _processWithRetry(chartId, retryPolicy);
    }
  }
  
  Future<void> _processWithRetry(String chartId, RetryPolicy policy) async {
    int attempt = 0;
    
    while (attempt < policy.maxRetries) {
      try {
        final chart = await ref.read(noaaApiClientProvider).getChartMetadata(chartId);
        if (chart != null) {
          await _processChart(chart);
          return; // Success
        }
      } catch (e) {
        attempt++;
        
        if (attempt >= policy.maxRetries) {
          ref.read(loggerProvider).error(
            'Failed to process critical chart $chartId after ${policy.maxRetries} attempts',
            context: 'BatchProcessor',
            exception: e,
          );
          rethrow;
        }
        
        // Wait before retry using policy calculation
        final delay = policy.calculateDelay(attempt - 1);
        await Future.delayed(delay);
      }
    }
  }
  
  Future<void> _processChart(Chart chart) async {
    // Chart processing implementation
  }
}
```

## Marine Environment Considerations

### Offline Handling

```dart
class OfflineAwareChartService {
  final Ref ref;
  
  OfflineAwareChartService(this.ref);
  
  Future<Chart?> getChart(String chartId) async {
    final networkResilience = ref.read(networkResilienceProvider);
    
    // Check network quality before attempting download
    await networkResilience.startMonitoring();
    
    await for (final status in networkResilience.statusStream.take(1)) {
      if (status.quality == ConnectionQuality.offline) {
        // Use cached data in offline mode
        return _getCachedChart(chartId);
      } else if (status.quality == ConnectionQuality.poor) {
        // Use aggressive rate limiting for poor connections
        final apiClient = ref.read(noaaApiClientProvider);
        return await _getChartWithSlowConnection(apiClient, chartId);
      }
    }
    
    // Normal operation for good connections
    return await ref.read(noaaApiClientProvider).getChartMetadata(chartId);
  }
  
  Future<Chart?> _getChartWithSlowConnection(NoaaApiClient client, String chartId) async {
    // Implement slower, more conservative requests for poor connections
    await Future.delayed(Duration(seconds: 2)); // Extra delay
    return await client.getChartMetadata(chartId);
  }
  
  Chart? _getCachedChart(String chartId) {
    // Return cached chart data for offline use
    return null;
  }
}
```

### Progress Monitoring for Marine UI

```dart
class MarineChartDownloader extends ConsumerStatefulWidget {
  final String chartId;
  
  const MarineChartDownloader({required this.chartId, Key? key}) : super(key: key);
  
  @override
  ConsumerState<MarineChartDownloader> createState() => _MarineChartDownloaderState();
}

class _MarineChartDownloaderState extends ConsumerState<MarineChartDownloader> {
  StreamSubscription<double>? _progressSubscription;
  double _progress = 0.0;
  bool _isDownloading = false;
  
  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }
  
  Future<void> _startDownload() async {
    if (_isDownloading) return;
    
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });
    
    final apiClient = ref.read(noaaApiClientProvider);
    
    // Subscribe to progress updates
    _progressSubscription = apiClient
        .getDownloadProgress(widget.chartId)
        .listen((progress) {
      setState(() {
        _progress = progress;
      });
    });
    
    try {
      await apiClient.downloadChart(
        widget.chartId,
        '/charts/${widget.chartId}.000',
      );
      
      // Download completed successfully
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chart ${widget.chartId} downloaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
      _progressSubscription?.cancel();
    }
  }
  
  void _cancelDownload() {
    ref.read(noaaApiClientProvider).cancelDownload(widget.chartId);
    _progressSubscription?.cancel();
    setState(() {
      _isDownloading = false;
      _progress = 0.0;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart ${widget.chartId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _progress),
              SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(1)}%'),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: _cancelDownload,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text('Cancel'),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: _startDownload,
                child: Text('Download Chart'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

## Provider Testing

### Testing with Overrides

```dart
void main() {
  group('Chart Service Tests', () {
    testWidgets('should handle chart download with mocked providers', (tester) async {
      // Arrange
      final mockApiClient = MockNoaaApiClient();
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noaaApiClientProvider.overrideWith((ref) => mockApiClient),
          ],
          child: MyApp(),
        ),
      );
      
      // Act & Assert
      // Test your UI with the mocked provider
    });
  });
}
```

## Best Practices

1. **Always use providers** rather than creating instances directly
2. **Handle marine-specific errors** like poor connectivity gracefully
3. **Respect rate limits** to avoid server blocking
4. **Monitor network quality** and adapt behavior accordingly
5. **Implement offline fallbacks** for critical marine operations
6. **Use circuit breakers** for non-critical operations to prevent cascading failures
7. **Log errors appropriately** for marine troubleshooting scenarios

## Configuration

### Marine Environment Tuning

The providers are pre-configured for marine environments but can be customized:

```dart
// Example: Custom rate limiter for specific marine conditions
final customRateLimiterProvider = Provider<RateLimiter>((ref) {
  return RateLimiter(
    requestsPerSecond: 3, // More conservative for satellite connections
    windowSize: const Duration(seconds: 2),
  );
});
```

This configuration provides robust, enterprise-grade access to NOAA chart services optimized for the challenging conditions encountered in marine navigation applications.