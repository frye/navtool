import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../utils/network_resilience.dart';
import '../error/network_error_classifier.dart';
import 'background_task_service.dart';
import 'noaa/progressive_chart_loader.dart';

/// Sync operation types for background processing
enum SyncOperationType {
  /// Refresh chart catalog from NOAA
  catalogRefresh,
  
  /// Download specific charts
  chartDownload,
  
  /// Update chart metadata
  metadataUpdate,
  
  /// Sync user preferences
  preferencesSync,
}

/// Priority levels for sync operations
enum SyncPriority {
  /// Low priority - can wait for optimal conditions
  low,
  
  /// Normal priority - standard background sync
  normal,
  
  /// High priority - important updates
  high,
  
  /// Critical priority - safety-related updates
  critical,
}

/// Status of sync operations
enum SyncStatus {
  /// Operation is pending execution
  pending,
  
  /// Operation is currently in progress
  inProgress,
  
  /// Operation completed successfully
  completed,
  
  /// Operation failed
  failed,
  
  /// Operation was cancelled
  cancelled,
  
  /// Operation is waiting for better network conditions
  waitingForNetwork,
}

/// Represents a queued sync operation
@immutable
class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.type,
    required this.priority,
    required this.createdAt,
    required this.data,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.status = SyncStatus.pending,
    this.lastAttempt,
    this.nextAttempt,
    this.error,
  });

  /// Unique identifier for this operation
  final String id;
  
  /// Type of sync operation
  final SyncOperationType type;
  
  /// Priority level
  final SyncPriority priority;
  
  /// When the operation was created
  final DateTime createdAt;
  
  /// Operation-specific data
  final Map<String, dynamic> data;
  
  /// Number of retry attempts made
  final int retryCount;
  
  /// Maximum number of retries allowed
  final int maxRetries;
  
  /// Current status
  final SyncStatus status;
  
  /// Last attempt timestamp
  final DateTime? lastAttempt;
  
  /// Next scheduled attempt
  final DateTime? nextAttempt;
  
  /// Last error encountered
  final Exception? error;

  /// Whether this operation can be retried
  bool get canRetry => retryCount < maxRetries && 
                       status != SyncStatus.completed &&
                       status != SyncStatus.cancelled;

  /// Whether this operation should be attempted now
  bool get shouldAttemptNow => status == SyncStatus.pending ||
                               (status == SyncStatus.waitingForNetwork && 
                                nextAttempt != null &&
                                DateTime.now().isAfter(nextAttempt!));

  /// Creates a copy with updated fields
  SyncOperation copyWith({
    SyncStatus? status,
    int? retryCount,
    DateTime? lastAttempt,
    DateTime? nextAttempt,
    Exception? error,
  }) {
    return SyncOperation(
      id: id,
      type: type,
      priority: priority,
      createdAt: createdAt,
      data: data,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries,
      status: status ?? this.status,
      lastAttempt: lastAttempt ?? this.lastAttempt,
      nextAttempt: nextAttempt ?? this.nextAttempt,
      error: error ?? this.error,
    );
  }

  /// Converts to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'priority': priority.name,
      'createdAt': createdAt.toIso8601String(),
      'data': data,
      'retryCount': retryCount,
      'maxRetries': maxRetries,
      'status': status.name,
      'lastAttempt': lastAttempt?.toIso8601String(),
      'nextAttempt': nextAttempt?.toIso8601String(),
      'error': error?.toString(),
    };
  }

  /// Creates from JSON
  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'],
      type: SyncOperationType.values.byName(json['type']),
      priority: SyncPriority.values.byName(json['priority']),
      createdAt: DateTime.parse(json['createdAt']),
      data: Map<String, dynamic>.from(json['data']),
      retryCount: json['retryCount'] ?? 0,
      maxRetries: json['maxRetries'] ?? 3,
      status: SyncStatus.values.byName(json['status']),
      lastAttempt: json['lastAttempt'] != null 
          ? DateTime.parse(json['lastAttempt']) 
          : null,
      nextAttempt: json['nextAttempt'] != null 
          ? DateTime.parse(json['nextAttempt']) 
          : null,
      error: json['error'] != null 
          ? Exception(json['error']) 
          : null,
    );
  }
}

/// Network-aware background sync service
///
/// Provides intelligent background synchronization with network condition
/// awareness, bandwidth optimization, and marine environment adaptations.
class BackgroundSyncService extends ChangeNotifier {
  BackgroundSyncService({
    required AppLogger logger,
    required NetworkResilience networkResilience,
    required BackgroundTaskService backgroundTaskService,
    ProgressiveChartLoader? progressiveChartLoader,
  }) : _logger = logger,
       _networkResilience = networkResilience,
       _backgroundTaskService = backgroundTaskService,
       _progressiveChartLoader = progressiveChartLoader;

  final AppLogger _logger;
  final NetworkResilience _networkResilience;
  final BackgroundTaskService _backgroundTaskService;
  final ProgressiveChartLoader? _progressiveChartLoader;

  // Queue management
  final List<SyncOperation> _syncQueue = [];
  final Map<String, StreamSubscription> _activeOperations = {};
  
  // Configuration
  bool _isEnabled = true;
  bool _economyModeEnabled = false;
  Duration _syncInterval = const Duration(minutes: 15);
  Timer? _syncTimer;
  
  // Network condition thresholds
  static const ConnectionQuality _minQualityForSync = ConnectionQuality.fair;
  static const double _maxDataUsagePerHour = 50.0; // MB per hour in economy mode
  
  /// Whether background sync is enabled
  bool get isEnabled => _isEnabled;
  
  /// Whether economy mode is enabled (limited data usage)
  bool get economyModeEnabled => _economyModeEnabled;
  
  /// Current sync queue length
  int get queueLength => _syncQueue.length;
  
  /// Active operations count
  int get activeOperationsCount => _activeOperations.length;
  
  /// Current sync operations (read-only copy)
  List<SyncOperation> get syncQueue => List.unmodifiable(_syncQueue);

  /// Initialize the background sync service
  Future<void> initialize() async {
    try {
      _logger.info('Initializing background sync service', context: 'BackgroundSync');
      
      // Load persisted queue
      await _loadPersistedQueue();
      
      // Start periodic sync timer
      _startSyncTimer();
      
      // Listen to network status changes
      _networkResilience.networkStatusStream.listen((_) async {
        final conditions = await _networkResilience.assessMarineNetworkConditions();
        _onNetworkConditionsChanged(conditions);
      });
      
      _logger.info('Background sync service initialized', context: 'BackgroundSync');
    } catch (error) {
      _logger.error('Failed to initialize background sync service', 
                   context: 'BackgroundSync', exception: error);
      rethrow;
    }
  }

  /// Enable or disable background sync
  void setEnabled(bool enabled) {
    if (_isEnabled != enabled) {
      _isEnabled = enabled;
      _logger.info('Background sync ${enabled ? 'enabled' : 'disabled'}', 
                   context: 'BackgroundSync');
      
      if (enabled) {
        _startSyncTimer();
        _processPendingOperations();
      } else {
        _stopSyncTimer();
        _cancelAllActiveOperations();
      }
      
      notifyListeners();
    }
  }

  /// Enable or disable economy mode for limited data usage
  void setEconomyMode(bool enabled) {
    if (_economyModeEnabled != enabled) {
      _economyModeEnabled = enabled;
      _logger.info('Economy mode ${enabled ? 'enabled' : 'disabled'}', 
                   context: 'BackgroundSync');
      
      if (enabled) {
        // Cancel non-critical operations
        _cancelLowPriorityOperations();
      }
      
      notifyListeners();
    }
  }

  /// Set sync interval
  void setSyncInterval(Duration interval) {
    if (_syncInterval != interval) {
      _syncInterval = interval;
      _logger.info('Sync interval set to ${interval.inMinutes} minutes', 
                   context: 'BackgroundSync');
      
      if (_isEnabled) {
        _stopSyncTimer();
        _startSyncTimer();
      }
    }
  }

  /// Queue a chart catalog refresh operation
  Future<String> queueCatalogRefresh({
    SyncPriority priority = SyncPriority.normal,
    String? region,
  }) async {
    final operation = SyncOperation(
      id: 'catalog_refresh_${DateTime.now().millisecondsSinceEpoch}',
      type: SyncOperationType.catalogRefresh,
      priority: priority,
      createdAt: DateTime.now(),
      data: {
        if (region != null) 'region': region,
      },
    );

    return _queueOperation(operation);
  }

  /// Queue chart downloads
  Future<String> queueChartDownloads(
    List<String> chartIds, {
    SyncPriority priority = SyncPriority.normal,
  }) async {
    final operation = SyncOperation(
      id: 'charts_download_${DateTime.now().millisecondsSinceEpoch}',
      type: SyncOperationType.chartDownload,
      priority: priority,
      createdAt: DateTime.now(),
      data: {
        'chartIds': chartIds,
      },
    );

    return _queueOperation(operation);
  }

  /// Queue metadata update
  Future<String> queueMetadataUpdate({
    SyncPriority priority = SyncPriority.low,
  }) async {
    final operation = SyncOperation(
      id: 'metadata_update_${DateTime.now().millisecondsSinceEpoch}',
      type: SyncOperationType.metadataUpdate,
      priority: priority,
      createdAt: DateTime.now(),
      data: {},
    );

    return _queueOperation(operation);
  }

  /// Cancel a queued operation
  Future<void> cancelOperation(String operationId) async {
    final index = _syncQueue.indexWhere((op) => op.id == operationId);
    if (index != -1) {
      final operation = _syncQueue[index];
      
      // Cancel if in progress
      final subscription = _activeOperations.remove(operationId);
      if (subscription != null) {
        await subscription.cancel();
      }
      
      // Update status and keep in queue for history
      _syncQueue[index] = operation.copyWith(status: SyncStatus.cancelled);
      
      _logger.info('Cancelled sync operation: $operationId', context: 'BackgroundSync');
      
      await _persistQueue();
      notifyListeners();
    }
  }

  /// Clear completed operations from queue
  Future<void> clearCompletedOperations() async {
    final sizeBefore = _syncQueue.length;
    _syncQueue.removeWhere((op) => 
        op.status == SyncStatus.completed || 
        op.status == SyncStatus.cancelled);
    
    final removed = sizeBefore - _syncQueue.length;
    if (removed > 0) {
      _logger.info('Cleared $removed completed operations', context: 'BackgroundSync');
      await _persistQueue();
      notifyListeners();
    }
  }

  /// Force sync now (ignoring network conditions)
  Future<void> forceSyncNow() async {
    _logger.info('Force sync requested', context: 'BackgroundSync');
    await _processPendingOperations(forceSync: true);
  }

  /// Get sync statistics
  Map<String, dynamic> getSyncStatistics() {
    final stats = <SyncStatus, int>{};
    for (final status in SyncStatus.values) {
      stats[status] = _syncQueue.where((op) => op.status == status).length;
    }

    return {
      'totalOperations': _syncQueue.length,
      'statusBreakdown': stats.map((k, v) => MapEntry(k.name, v)),
      'activeOperations': _activeOperations.length,
      'economyMode': _economyModeEnabled,
      'enabled': _isEnabled,
      'syncInterval': _syncInterval.inMinutes,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _stopSyncTimer();
    _cancelAllActiveOperations();
    super.dispose();
  }

  /// Queue an operation
  Future<String> _queueOperation(SyncOperation operation) async {
    _syncQueue.add(operation);
    _logger.info('Queued ${operation.type.name} operation: ${operation.id}', 
                context: 'BackgroundSync');
    
    await _persistQueue();
    notifyListeners();
    
    // Try to process immediately if conditions are good
    if (_isEnabled) {
      _processPendingOperations();
    }
    
    return operation.id;
  }

  /// Start the periodic sync timer
  void _startSyncTimer() {
    _stopSyncTimer();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (_isEnabled) {
        _processPendingOperations();
      }
    });
  }

  /// Stop the sync timer
  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Process pending operations
  Future<void> _processPendingOperations({bool forceSync = false}) async {
    if (!_isEnabled && !forceSync) return;
    
    final networkConditions = await _networkResilience.assessMarineNetworkConditions();
    
    // Check if network conditions are suitable for sync
    if (!forceSync && !_isNetworkSuitableForSync(networkConditions)) {
      _logger.debug('Network conditions not suitable for sync', context: 'BackgroundSync');
      return;
    }
    
    // Get operations ready for processing
    final readyOperations = _syncQueue
        .where((op) => op.shouldAttemptNow && 
                       _activeOperations[op.id] == null)
        .toList();
    
    // Sort by priority
    readyOperations.sort((a, b) => _comparePriority(a.priority, b.priority));
    
    // Process operations based on network capacity
    final maxConcurrent = _getMaxConcurrentOperations(networkConditions);
    final toProcess = readyOperations.take(maxConcurrent - _activeOperations.length);
    
    for (final operation in toProcess) {
      _executeOperation(operation);
    }
  }

  /// Execute a sync operation
  Future<void> _executeOperation(SyncOperation operation) async {
    final index = _syncQueue.indexWhere((op) => op.id == operation.id);
    if (index == -1) return;
    
    // Update status to in progress
    _syncQueue[index] = operation.copyWith(
      status: SyncStatus.inProgress,
      lastAttempt: DateTime.now(),
    );
    
    _logger.info('Executing ${operation.type.name} operation: ${operation.id}', 
                context: 'BackgroundSync');
    
    try {
      switch (operation.type) {
        case SyncOperationType.catalogRefresh:
          await _executeCatalogRefresh(operation);
          break;
        case SyncOperationType.chartDownload:
          await _executeChartDownload(operation);
          break;
        case SyncOperationType.metadataUpdate:
          await _executeMetadataUpdate(operation);
          break;
        case SyncOperationType.preferencesSync:
          await _executePreferencesSync(operation);
          break;
      }
      
      // Mark as completed
      _syncQueue[index] = _syncQueue[index].copyWith(status: SyncStatus.completed);
      _logger.info('Completed ${operation.type.name} operation: ${operation.id}', 
                  context: 'BackgroundSync');
      
    } catch (error) {
      _logger.warning('Failed ${operation.type.name} operation: ${operation.id}', 
                     context: 'BackgroundSync', exception: error);
      
      final updatedOperation = _syncQueue[index];
      final errorType = NetworkErrorClassifier.classifyError(error as Exception);
      
      if (updatedOperation.canRetry && NetworkErrorClassifier.shouldRetry(errorType)) {
        // Schedule retry
        final delay = NetworkErrorClassifier.getRetryDelay(errorType, updatedOperation.retryCount);
        _syncQueue[index] = updatedOperation.copyWith(
          status: SyncStatus.waitingForNetwork,
          retryCount: updatedOperation.retryCount + 1,
          nextAttempt: DateTime.now().add(delay),
          error: error,
        );
      } else {
        // Mark as failed
        _syncQueue[index] = updatedOperation.copyWith(
          status: SyncStatus.failed,
          error: error,
        );
      }
    } finally {
      _activeOperations.remove(operation.id);
      await _persistQueue();
      notifyListeners();
    }
  }

  /// Execute catalog refresh operation
  Future<void> _executeCatalogRefresh(SyncOperation operation) async {
    if (_progressiveChartLoader == null) {
      throw Exception('Progressive chart loader not available');
    }
    
    final region = operation.data['region'] as String?;
    
    final progressStream = _progressiveChartLoader!.loadChartsWithProgress(
      region: region,
      loadId: operation.id,
    );
    
    final subscription = progressStream.listen(
      (progress) {
        // Progress updates could be emitted as events if needed
        _logger.debug('Catalog refresh progress: ${(progress.progress * 100).round()}%', 
                     context: 'BackgroundSync');
      },
      onError: (error) {
        _logger.error('Catalog refresh error', context: 'BackgroundSync', exception: error);
        throw error;
      },
    );
    
    _activeOperations[operation.id] = subscription;
    
    // Wait for completion
    await subscription.asFuture();
  }

  /// Execute chart download operation
  Future<void> _executeChartDownload(SyncOperation operation) async {
    final chartIds = List<String>.from(operation.data['chartIds']);
    
    for (final chartId in chartIds) {
      // Individual chart download logic would go here
      // This is a placeholder - would integrate with actual download service
      await Future.delayed(const Duration(seconds: 1));
      _logger.debug('Downloaded chart: $chartId', context: 'BackgroundSync');
    }
  }

  /// Execute metadata update operation
  Future<void> _executeMetadataUpdate(SyncOperation operation) async {
    // Metadata update logic would go here
    await Future.delayed(const Duration(milliseconds: 500));
    _logger.debug('Updated metadata', context: 'BackgroundSync');
  }

  /// Execute preferences sync operation
  Future<void> _executePreferencesSync(SyncOperation operation) async {
    // Preferences sync logic would go here
    await Future.delayed(const Duration(milliseconds: 200));
    _logger.debug('Synced preferences', context: 'BackgroundSync');
  }

  /// Handle network condition changes
  void _onNetworkConditionsChanged(MarineNetworkConditions conditions) {
    _logger.debug('Network conditions changed: ${conditions.connectionQuality}', 
                 context: 'BackgroundSync');
    
    if (_isNetworkSuitableForSync(conditions)) {
      // Good conditions - try to process pending operations
      _processPendingOperations();
    } else {
      // Poor conditions - cancel non-critical operations
      _cancelLowPriorityOperations();
    }
  }

  /// Check if network is suitable for sync operations
  bool _isNetworkSuitableForSync(MarineNetworkConditions conditions) {
    if (_economyModeEnabled) {
      // In economy mode, require better conditions
      return conditions.connectionQuality.index >= ConnectionQuality.good.index &&
             conditions.isSuitableForApiRequests;
    }
    
    return conditions.connectionQuality.index >= _minQualityForSync.index &&
           conditions.isSuitableForApiRequests;
  }

  /// Get maximum concurrent operations based on network conditions
  int _getMaxConcurrentOperations(MarineNetworkConditions conditions) {
    switch (conditions.connectionQuality) {
      case ConnectionQuality.excellent:
        return 3;
      case ConnectionQuality.good:
        return 2;
      case ConnectionQuality.fair:
        return 1;
      case ConnectionQuality.poor:
      case ConnectionQuality.veryPoor:
      case ConnectionQuality.offline:
        return 0;
    }
  }

  /// Compare operation priorities
  int _comparePriority(SyncPriority a, SyncPriority b) {
    return b.index.compareTo(a.index); // Higher priority first
  }

  /// Cancel low priority operations
  void _cancelLowPriorityOperations() {
    final toCancelIds = <String>[];
    
    for (int i = 0; i < _syncQueue.length; i++) {
      final operation = _syncQueue[i];
      if (operation.priority == SyncPriority.low && 
          operation.status == SyncStatus.inProgress) {
        toCancelIds.add(operation.id);
        _syncQueue[i] = operation.copyWith(status: SyncStatus.cancelled);
      }
    }
    
    for (final id in toCancelIds) {
      final subscription = _activeOperations.remove(id);
      subscription?.cancel();
    }
    
    if (toCancelIds.isNotEmpty) {
      _logger.info('Cancelled ${toCancelIds.length} low priority operations', 
                  context: 'BackgroundSync');
      _persistQueue();
      notifyListeners();
    }
  }

  /// Cancel all active operations
  void _cancelAllActiveOperations() {
    for (final subscription in _activeOperations.values) {
      subscription.cancel();
    }
    _activeOperations.clear();
  }

  /// Load persisted queue from storage
  Future<void> _loadPersistedQueue() async {
    try {
      // This would load from actual storage
      // For now, just log
      _logger.debug('Loading persisted sync queue', context: 'BackgroundSync');
    } catch (error) {
      _logger.warning('Failed to load persisted sync queue', 
                     context: 'BackgroundSync', exception: error);
    }
  }

  /// Persist queue to storage
  Future<void> _persistQueue() async {
    try {
      // This would persist to actual storage
      final queueJson = _syncQueue.map((op) => op.toJson()).toList();
      _logger.debug('Persisting sync queue (${queueJson.length} operations)', 
                   context: 'BackgroundSync');
    } catch (error) {
      _logger.warning('Failed to persist sync queue', 
                     context: 'BackgroundSync', exception: error);
    }
  }
}