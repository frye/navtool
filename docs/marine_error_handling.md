# Marine Error Handling Best Practices

This guide covers error handling strategies specifically designed for marine navigation applications using the NOAA API client.

## Overview

Marine environments present unique challenges for network-dependent applications:
- Intermittent connectivity (satellite, cellular)
- Variable network quality
- Critical safety requirements
- Extended offline periods
- Environmental factors affecting equipment

## Error Classification

### Network-Related Errors

#### Connection Issues
```dart
try {
  final chart = await apiClient.getChartMetadata(chartId);
} on NoaaNetworkException catch (e) {
  // Handle network connectivity issues
  if (e.isTemporary) {
    // Retry with exponential backoff
    await _retryWithBackoff(() => apiClient.getChartMetadata(chartId));
  } else {
    // Switch to offline mode
    return await _getCachedChart(chartId);
  }
} on SocketException {
  // No internet connection - use cached data
  return await _getCachedChart(chartId);
} on TimeoutException {
  // Slow connection - inform user and retry with longer timeout
  _showSlowConnectionWarning();
  return await _retryWithLongerTimeout(chartId);
}
```

#### Rate Limiting
```dart
try {
  await apiClient.downloadChart(chartId, outputPath);
} on NoaaRateLimitException catch (e) {
  // Respect server rate limits
  final retryAfter = e.retryAfter ?? Duration(seconds: 30);
  
  _showRateLimitMessage(retryAfter);
  await Future.delayed(retryAfter);
  
  // Retry the operation
  return await apiClient.downloadChart(chartId, outputPath);
}
```

### Server-Related Errors

#### Service Unavailability
```dart
try {
  final catalog = await apiClient.fetchChartCatalog();
} on NoaaServerException catch (e) {
  switch (e.statusCode) {
    case 503: // Service Unavailable
      _showMaintenanceMessage();
      return await _useCachedCatalog();
      
    case 500: // Internal Server Error
      if (e.isRetryable) {
        return await _retryAfterDelay(
          () => apiClient.fetchChartCatalog(),
          Duration(minutes: 5),
        );
      }
      break;
      
    case 502: // Bad Gateway
    case 504: // Gateway Timeout
      // Infrastructure issues - retry with circuit breaker
      return await circuitBreaker.execute(
        () => apiClient.fetchChartCatalog(),
      );
  }
  
  // For non-retryable errors, show error to user
  _showServerErrorMessage(e);
  rethrow;
}
```

### Data-Related Errors

#### Chart Not Found
```dart
try {
  final chart = await apiClient.getChartMetadata(chartId);
} on NoaaChartNotFoundException catch (e) {
  // Chart doesn't exist or is no longer available
  logger.warning('Chart not found: ${e.chartId}');
  
  // Suggest alternatives if available
  final alternatives = await _findAlternativeCharts(e.region);
  if (alternatives.isNotEmpty) {
    _showAlternativeChartsDialog(alternatives);
  } else {
    _showChartUnavailableMessage(e.chartId);
  }
  
  return null;
}
```

#### Invalid Chart Data
```dart
try {
  final chart = await apiClient.getChartMetadata(chartId);
  _validateChartData(chart);
} on NoaaDataException catch (e) {
  // Corrupted or invalid chart data
  logger.error('Invalid chart data for $chartId: ${e.message}');
  
  // Try to re-download the chart
  if (e.isRecoverable) {
    return await _redownloadChart(chartId);
  }
  
  // Mark chart as corrupted and remove from cache
  await _markChartCorrupted(chartId);
  return null;
}
```

## Marine-Specific Error Handling Patterns

### 1. Graceful Degradation

```dart
class MarineChartService {
  final NoaaApiClient apiClient;
  final ChartCache cache;
  final ConnectivityService connectivity;
  
  Future<Chart?> getChart(String chartId) async {
    try {
      // Try online first
      if (await connectivity.hasConnection()) {
        final chart = await apiClient.getChartMetadata(chartId);
        await cache.store(chartId, chart);
        return chart;
      }
    } on NoaaNetworkException {
      logger.info('Network error, falling back to cache');
    } on NoaaServerException catch (e) {
      if (!e.isRetryable) {
        logger.warning('Server error, using cached data: ${e.message}');
      }
    }
    
    // Fallback to cached data
    final cachedChart = await cache.get(chartId);
    if (cachedChart != null) {
      _showUsingCachedDataWarning();
      return cachedChart;
    }
    
    // No cache available - this is a critical situation for marine navigation
    _showNoCriticalDataAvailableError(chartId);
    return null;
  }
}
```

### 2. Progressive Retry Strategy

```dart
class MarineRetryHandler {
  static const List<Duration> MARINE_RETRY_DELAYS = [
    Duration(seconds: 5),    // Quick retry for temporary glitches
    Duration(seconds: 30),   // Medium delay for connectivity issues
    Duration(minutes: 2),    // Longer delay for server issues
    Duration(minutes: 5),    // Extended delay for persistent problems
  ];
  
  Future<T> executeWithMarineRetry<T>(
    Future<T> Function() operation,
    {bool isCritical = false}
  ) async {
    Exception? lastException;
    
    final maxRetries = isCritical ? MARINE_RETRY_DELAYS.length : 2;
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
        if (attempt < maxRetries - 1) {
          final delay = MARINE_RETRY_DELAYS[attempt];
          
          logger.info(
            'Attempt ${attempt + 1} failed, retrying in ${delay.inSeconds}s: $e'
          );
          
          _showRetryMessage(attempt + 1, delay);
          await Future.delayed(delay);
        }
      }
    }
    
    // All retries exhausted
    if (isCritical) {
      _showCriticalOperationFailedError(lastException!);
    }
    
    throw lastException!;
  }
  
  void _showRetryMessage(int attempt, Duration delay) {
    // Show user-friendly retry message
    notificationService.showInfo(
      'Connection issue detected. Retrying in ${delay.inSeconds} seconds... (Attempt $attempt)'
    );
  }
  
  void _showCriticalOperationFailedError(Exception e) {
    notificationService.showError(
      'Critical marine operation failed after all retries. Please check your connection and try again.',
      details: e.toString(),
    );
  }
}
```

### 3. Context-Aware Error Messages

```dart
class MarineErrorPresenter {
  static String getMarineErrorMessage(Exception error, {required bool isOffshore}) {
    if (error is NoaaNetworkException) {
      if (isOffshore) {
        return 'Satellite connection lost. Chart updates unavailable. '
               'Using cached navigation data. Check antenna alignment.';
      } else {
        return 'Network connection lost. Trying to reconnect... '
               'Switch to cellular/WiFi if available.';
      }
    }
    
    if (error is NoaaRateLimitException) {
      return 'NOAA server busy. Waiting ${error.retryAfter?.inSeconds ?? 30} seconds '
             'before retry. Marine traffic may be high.';
    }
    
    if (error is NoaaServerException) {
      if (error.statusCode == 503) {
        return 'NOAA chart service under maintenance. Using cached charts. '
               'Service typically restored within 1-2 hours.';
      }
    }
    
    if (error is CircuitBreakerOpenException) {
      return 'Chart service temporarily disabled due to repeated failures. '
             'System will retry automatically in 2 minutes.';
    }
    
    return 'Navigation system error: ${error.toString()}';
  }
  
  static Widget buildMarineErrorWidget(Exception error, {required VoidCallback onRetry}) {
    final isOffshore = _determineIfOffshore();
    final message = getMarineErrorMessage(error, isOffshore: isOffshore);
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Navigation System Alert',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(message),
          SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                onPressed: onRetry,
                child: Text('Retry'),
              ),
              SizedBox(width: 8),
              TextButton(
                onPressed: () => _showOfflineMode(),
                child: Text('Use Offline Mode'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  static bool _determineIfOffshore() {
    // Logic to determine if vessel is offshore
    // This could use GPS coordinates, known marina locations, etc.
    return false; // Placeholder
  }
  
  static void _showOfflineMode() {
    // Switch to offline navigation mode
  }
}
```

### 4. Critical Safety Error Handling

```dart
class SafetyCriticalErrorHandler {
  final EmergencyProtocols emergencyProtocols;
  final VesselSystems vesselSystems;
  
  Future<void> handleCriticalNavigationError(Exception error, String context) async {
    // Log the critical error
    logger.error(
      'CRITICAL NAVIGATION ERROR in $context: $error',
      context: 'SafetyCritical',
      exception: error,
    );
    
    // Alert all navigation systems
    await vesselSystems.broadcastNavigationAlert(
      'Navigation data service error detected. Verify position using alternative methods.',
    );
    
    // Activate emergency protocols if needed
    if (_isSafetyOfNavigationAffected(error)) {
      await emergencyProtocols.activateBackupNavigation();
      
      // Sound navigation alarm
      await vesselSystems.soundNavigationAlarm();
      
      // Display critical warning
      await _showCriticalNavigationWarning(error);
    }
    
    // Auto-switch to backup systems
    await _activateBackupChartSystems();
  }
  
  bool _isSafetyOfNavigationAffected(Exception error) {
    // Determine if error affects vessel safety
    return error is NoaaChartNotFoundException ||
           error is NoaaDataException ||
           (error is NoaaNetworkException && !error.isTemporary);
  }
  
  Future<void> _showCriticalNavigationWarning(Exception error) async {
    // Show modal warning that cannot be dismissed easily
    await showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.white, size: 32),
            SizedBox(width: 8),
            Text(
              'NAVIGATION ALERT',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart data service error detected.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Verify vessel position using:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Text('• GPS coordinates', style: TextStyle(color: Colors.white)),
            Text('• Visual references', style: TextStyle(color: Colors.white)),
            Text('• Radar navigation', style: TextStyle(color: Colors.white)),
            Text('• Paper charts', style: TextStyle(color: Colors.white)),
            SizedBox(height: 8),
            Text(
              'Backup navigation systems activated.',
              style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text('ACKNOWLEDGED'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _activateBackupChartSystems() async {
    // Switch to backup chart providers or cached data
    await vesselSystems.switchToBackupChartProvider();
  }
}
```

### 5. Offline Mode Management

```dart
class OfflineModeManager {
  final ChartCache cache;
  final ConnectivityService connectivity;
  final UserPreferences preferences;
  
  Future<bool> enterOfflineMode({required String reason}) async {
    logger.info('Entering offline mode: $reason');
    
    // Check cached chart availability
    final availableCharts = await cache.getAvailableCharts();
    final currentPosition = await _getCurrentPosition();
    
    // Verify sufficient charts are cached for current area
    final neededCharts = await _getChartsForArea(currentPosition, radiusNm: 50);
    final missingCharts = neededCharts.where(
      (chart) => !availableCharts.contains(chart.id)
    ).toList();
    
    if (missingCharts.isNotEmpty) {
      await _warnAboutMissingCharts(missingCharts);
    }
    
    // Configure system for offline operation
    await preferences.setOfflineMode(true);
    await _configureOfflineSettings();
    
    // Show offline mode status
    await _showOfflineModeActive();
    
    return true;
  }
  
  Future<void> exitOfflineMode() async {
    logger.info('Exiting offline mode');
    
    // Check if connection is restored
    if (!await connectivity.hasConnection()) {
      _showNoConnectionWarning();
      return;
    }
    
    await preferences.setOfflineMode(false);
    
    // Sync with remote servers
    await _syncWithRemoteServers();
    
    // Show online mode restored
    await _showOnlineModeRestored();
  }
  
  Future<void> _warnAboutMissingCharts(List<Chart> missingCharts) async {
    final message = 'Warning: ${missingCharts.length} charts not cached for current area. '
                   'Navigation may be limited in these regions:\n'
                   '${missingCharts.map((c) => '• ${c.name}').join('\n')}';
    
    await showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text('Offline Mode Warning'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Continue Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _tryToDownloadMissingCharts(missingCharts);
            },
            child: Text('Try to Download'),
          ),
        ],
      ),
    );
  }
}
```

## Error Recovery Strategies

### Automatic Recovery
```dart
class AutomaticErrorRecovery {
  final Timer _recoveryTimer;
  final List<Exception> _recentErrors = [];
  
  void startMonitoring() {
    _recoveryTimer = Timer.periodic(Duration(minutes: 1), (_) {
      _attemptAutomaticRecovery();
    });
  }
  
  Future<void> _attemptAutomaticRecovery() async {
    // Clear old errors
    _recentErrors.removeWhere(
      (error) => DateTime.now().difference(error.timestamp) > Duration(minutes: 10)
    );
    
    // Check if system should attempt recovery
    if (_shouldAttemptRecovery()) {
      await _performRecoveryActions();
    }
  }
  
  bool _shouldAttemptRecovery() {
    // Only attempt if there have been recent errors but not too many
    return _recentErrors.length > 0 && _recentErrors.length < 5;
  }
  
  Future<void> _performRecoveryActions() async {
    try {
      // Test connection
      final hasConnection = await connectivity.hasConnection();
      if (!hasConnection) return;
      
      // Test NOAA API
      final apiClient = ref.read(noaaApiClientProvider);
      await apiClient.fetchChartCatalog();
      
      // If successful, clear errors and notify user
      _recentErrors.clear();
      notificationService.showSuccess('Navigation system connection restored');
    } catch (e) {
      // Recovery failed, will try again next cycle
      logger.debug('Automatic recovery attempt failed: $e');
    }
  }
}
```

## Best Practices Summary

1. **Always provide fallback options** - cached data, alternative charts, manual navigation
2. **Use appropriate error types** - network vs. server vs. data errors require different handling
3. **Implement progressive retry** - start with quick retries, increase delays for persistent issues
4. **Consider marine context** - offshore vs. coastal, critical vs. non-critical operations
5. **Provide clear user feedback** - explain what went wrong and what the system is doing about it
6. **Log appropriately** - detailed logs for debugging but don't overwhelm the user
7. **Plan for extended offline periods** - ensure sufficient cached data for voyage duration
8. **Test in realistic conditions** - simulate poor connectivity, server outages, etc.

These error handling patterns ensure robust operation of navigation systems even in challenging marine environments where reliable connectivity cannot be guaranteed.