import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logging/app_logger.dart';
import '../error/error_handler.dart';

/// Download status for individual charts
enum DownloadStatus {
  idle,
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled;

  bool get isActive => this == DownloadStatus.downloading;
  bool get canPause => this == DownloadStatus.downloading;
  bool get canResume => this == DownloadStatus.paused;
  bool get canCancel => [DownloadStatus.queued, DownloadStatus.downloading, DownloadStatus.paused].contains(this);
}

/// Download progress information
@immutable
class DownloadProgress {
  final String chartId;
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int? totalBytes;
  final int? downloadedBytes;
  final String? errorMessage;
  // Categorized error (timeout, checksum, disk, network, cancelled, unknown)
  final String? errorCategory; // Phase 3 addition
  // Precomputed instantaneous speed (bytes/sec) & ETA (secs) to avoid recomputation churn in UI build
  final double? bytesPerSecond;
  final int? etaSeconds;
  final DateTime lastUpdated;

  /// Default timestamp for downloads
  static final DateTime _defaultTime = DateTime.fromMillisecondsSinceEpoch(0);

  const DownloadProgress({
    required this.chartId,
    required this.status,
    this.progress = 0.0,
    this.totalBytes,
    this.downloadedBytes,
    this.errorMessage,
    this.errorCategory,
    this.bytesPerSecond,
    this.etaSeconds,
    required this.lastUpdated,
  });

  /// Constructor with optional lastUpdated that defaults to epoch
  DownloadProgress.withDefaults({
    required this.chartId,
    required this.status,
    this.progress = 0.0,
    this.totalBytes,
    this.downloadedBytes,
    this.errorMessage,
    this.errorCategory,
    this.bytesPerSecond,
    this.etaSeconds,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? _defaultTime;

  /// Creates a new progress with updated values
  DownloadProgress copyWith({
    DownloadStatus? status,
    double? progress,
    int? totalBytes,
    int? downloadedBytes,
    String? errorMessage,
    String? errorCategory,
    double? bytesPerSecond,
    int? etaSeconds,
    DateTime? lastUpdated,
  }) {
    return DownloadProgress(
      chartId: chartId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCategory: errorCategory ?? this.errorCategory,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  /// Gets the download speed in bytes per second (if available)
  double? get downloadSpeed {
    if (downloadedBytes == null || lastUpdated.millisecondsSinceEpoch == 0) return null;
    final duration = DateTime.now().difference(lastUpdated);
    if (duration.inMilliseconds <= 0) return null;
    return downloadedBytes! / duration.inSeconds;
  }

  /// Gets estimated time remaining in seconds (if available)
  int? get estimatedTimeRemaining {
    if (totalBytes == null || downloadedBytes == null || downloadSpeed == null || downloadSpeed! <= 0) {
      return null;
    }
    final remainingBytes = totalBytes! - downloadedBytes!;
    return (remainingBytes / downloadSpeed!).round();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadProgress &&
          runtimeType == other.runtimeType &&
          chartId == other.chartId &&
          status == other.status &&
          progress == other.progress &&
          totalBytes == other.totalBytes &&
          downloadedBytes == other.downloadedBytes &&
      errorMessage == other.errorMessage &&
      errorCategory == other.errorCategory &&
      bytesPerSecond == other.bytesPerSecond &&
      etaSeconds == other.etaSeconds;

  @override
  int get hashCode =>
      chartId.hashCode ^
      status.hashCode ^
      progress.hashCode ^
      totalBytes.hashCode ^
      downloadedBytes.hashCode ^
  errorMessage.hashCode ^
  (errorCategory?.hashCode ?? 0) ^
  (bytesPerSecond?.hashCode ?? 0) ^
  (etaSeconds?.hashCode ?? 0);

  @override
  String toString() {
    return 'DownloadProgress('
        'chartId: $chartId, '
        'status: $status, '
        'progress: ${(progress * 100).toStringAsFixed(1)}%, '
        'bytes: $downloadedBytes/$totalBytes'
        ')';
  }
}

/// Download queue state
@immutable
class DownloadQueueState {
  final Map<String, DownloadProgress> downloads;
  final List<String> queue;
  final int maxConcurrentDownloads;
  final bool isPaused;

  const DownloadQueueState({
    this.downloads = const {},
    this.queue = const [],
    this.maxConcurrentDownloads = 3,
    this.isPaused = false,
  });

  /// Gets currently active downloads
  List<DownloadProgress> get activeDownloads =>
      downloads.values.where((d) => d.status.isActive).toList();

  /// Gets current number of active downloads
  int get currentDownloadCount => activeDownloads.length;

  /// Gets queued downloads
  List<DownloadProgress> get queuedDownloads =>
      queue.map((id) => downloads[id]).whereType<DownloadProgress>().toList();

  /// Gets completed downloads
  List<DownloadProgress> get completedDownloads =>
      downloads.values.where((d) => d.status == DownloadStatus.completed).toList();

  /// Gets failed downloads
  List<DownloadProgress> get failedDownloads =>
      downloads.values.where((d) => d.status == DownloadStatus.failed).toList();

  /// Gets overall download progress (0.0 to 1.0)
  double get overallProgress {
    if (downloads.isEmpty) return 0.0;
    final totalProgress = downloads.values.fold<double>(0.0, (sum, d) => sum + d.progress);
    return totalProgress / downloads.length;
  }

  DownloadQueueState copyWith({
    Map<String, DownloadProgress>? downloads,
    List<String>? queue,
    int? maxConcurrentDownloads,
    bool? isPaused,
  }) {
    return DownloadQueueState(
      downloads: downloads ?? this.downloads,
      queue: queue ?? this.queue,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadQueueState &&
          runtimeType == other.runtimeType &&
          mapEquals(downloads, other.downloads) &&
          listEquals(queue, other.queue) &&
          maxConcurrentDownloads == other.maxConcurrentDownloads &&
          isPaused == other.isPaused;

  @override
  int get hashCode =>
      downloads.hashCode ^
      queue.hashCode ^
      maxConcurrentDownloads.hashCode ^
      isPaused.hashCode;

  @override
  String toString() {
    return 'DownloadQueueState('
        'downloads: ${downloads.length}, '
        'queue: ${queue.length}, '
        'active: ${activeDownloads.length}, '
        'maxConcurrent: $maxConcurrentDownloads, '
        'isPaused: $isPaused'
        ')';
  }
}

/// Download queue state notifier
class DownloadQueueNotifier extends StateNotifier<DownloadQueueState> {
  final AppLogger _logger;
  final ErrorHandler _errorHandler;

  DownloadQueueNotifier({
    required AppLogger logger,
    required ErrorHandler errorHandler,
  })  : _logger = logger,
        _errorHandler = errorHandler,
        super(const DownloadQueueState());

  /// Adds a chart to the download queue
  void queueDownload(String chartId) {
    try {
      if (state.downloads.containsKey(chartId)) {
        _logger.warning('Chart $chartId is already in download queue');
        return;
      }

      final progress = DownloadProgress.withDefaults(
        chartId: chartId,
        status: DownloadStatus.queued,
      );

      final updatedDownloads = Map<String, DownloadProgress>.from(state.downloads);
      updatedDownloads[chartId] = progress;

      final updatedQueue = [...state.queue, chartId];

      state = state.copyWith(
        downloads: updatedDownloads,
        queue: updatedQueue,
      );

      _logger.info('Queued chart for download: $chartId');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates download progress
  void updateProgress(String chartId, {
    DownloadStatus? status,
    double? progress,
    int? totalBytes,
    int? downloadedBytes,
    String? errorMessage,
  }) {
    try {
      final currentProgress = state.downloads[chartId];
      // If progress entry doesn't exist (e.g., service initiated download directly), create one
      final baseProgress = currentProgress ?? DownloadProgress.withDefaults(
        chartId: chartId,
        status: status ?? DownloadStatus.downloading,
        progress: progress ?? 0.0,
      );

      final updatedProgress = baseProgress.copyWith(
        status: status,
        progress: progress,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        errorMessage: errorMessage,
        lastUpdated: DateTime.now(),
      );

      final updatedDownloads = Map<String, DownloadProgress>.from(state.downloads);
      updatedDownloads[chartId] = updatedProgress;

      state = state.copyWith(downloads: updatedDownloads);

      if (status == DownloadStatus.completed) {
        _removeFromQueue(chartId);
        _logger.info('Download completed: $chartId');
        _processQueue();
      } else if (status == DownloadStatus.failed) {
        _removeFromQueue(chartId);
        _logger.error('Download failed: $chartId - $errorMessage');
        _processQueue();
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Pauses a download
  void pauseDownload(String chartId) {
    try {
      updateProgress(chartId, status: DownloadStatus.paused);
      _removeFromQueue(chartId);
      _logger.info('Paused download: $chartId');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Resumes a paused download
  void resumeDownload(String chartId) {
    try {
      final progress = state.downloads[chartId];
      if (progress?.status != DownloadStatus.paused) {
        _logger.warning('Cannot resume download that is not paused: $chartId');
        return;
      }

      updateProgress(chartId, status: DownloadStatus.queued);
      final updatedQueue = [...state.queue, chartId];
      state = state.copyWith(queue: updatedQueue);
      
      _logger.info('Resumed download: $chartId');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Cancels a download
  void cancelDownload(String chartId) {
    try {
      updateProgress(chartId, status: DownloadStatus.cancelled);
      _removeFromQueue(chartId);
      _logger.info('Cancelled download: $chartId');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Pauses all downloads
  void pauseAll() {
    try {
      state = state.copyWith(isPaused: true);
      _logger.info('Paused all downloads');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Resumes all downloads
  void resumeAll() {
    try {
      state = state.copyWith(isPaused: false);
      _logger.info('Resumed all downloads');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Clears completed and failed downloads
  void clearCompleted() {
    try {
      final updatedDownloads = Map<String, DownloadProgress>.from(state.downloads);
      updatedDownloads.removeWhere((_, progress) => 
          progress.status == DownloadStatus.completed || 
          progress.status == DownloadStatus.failed ||
          progress.status == DownloadStatus.cancelled);

      state = state.copyWith(downloads: updatedDownloads);
      _logger.info('Cleared completed downloads');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets maximum concurrent downloads
  void setMaxConcurrentDownloads(int max) {
    try {
      if (max <= 0) {
        _logger.warning('Invalid max concurrent downloads: $max');
        return;
      }

      state = state.copyWith(maxConcurrentDownloads: max);
      _logger.info('Set max concurrent downloads: $max');
      _processQueue();
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Removes a chart from the queue
  void _removeFromQueue(String chartId) {
    final updatedQueue = state.queue.where((id) => id != chartId).toList();
    state = state.copyWith(queue: updatedQueue);
  }

  /// Processes the download queue
  void _processQueue() {
    if (state.isPaused) return;

    final activeCount = state.activeDownloads.length;
    final availableSlots = state.maxConcurrentDownloads - activeCount;

    if (availableSlots > 0 && state.queue.isNotEmpty) {
      final toStart = state.queue.take(availableSlots);
      for (final chartId in toStart) {
        updateProgress(chartId, status: DownloadStatus.downloading);
        // Queue processing is now handled by DownloadServiceImpl._processQueue()
      }
    }
  }
}
