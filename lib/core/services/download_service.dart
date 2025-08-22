import 'dart:async';
import '../state/download_state.dart';

/// Download priority levels for queue management
enum DownloadPriority { low, normal, high }

/// Status of batch download operations
enum BatchDownloadStatus {
  pending,
  inProgress,
  paused,
  completed,
  cancelled,
  failed
}

/// Queue item with priority and metadata
class QueueItem {
  final String chartId;
  final String url;
  final DownloadPriority priority;
  final DateTime addedAt;
  final String? expectedChecksum;

  QueueItem({
    required this.chartId,
    required this.url,
    required this.priority,
    required this.addedAt,
    this.expectedChecksum,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          chartId == other.chartId;

  @override
  int get hashCode => chartId.hashCode;
}

/// Progress tracking for batch downloads
class BatchDownloadProgress {
  final String batchId;
  final BatchDownloadStatus status;
  final int totalCharts;
  final int completedCharts;
  final int failedCharts;
  final double overallProgress;
  final DateTime lastUpdated;
  final List<String> failedChartIds;

  BatchDownloadProgress({
    required this.batchId,
    required this.status,
    required this.totalCharts,
    required this.completedCharts,
    required this.failedCharts,
    required this.overallProgress,
    required this.lastUpdated,
    required this.failedChartIds,
  });
}

/// Resume data for interrupted downloads
class ResumeData {
  final String chartId;
  final String originalUrl;
  final int downloadedBytes;
  final DateTime lastAttempt;
  final String? checksum;

  ResumeData({
    required this.chartId,
    required this.originalUrl,
    required this.downloadedBytes,
    required this.lastAttempt,
    this.checksum,
  });
}

/// Download notification for background operations
class DownloadNotification {
  final String chartId;
  final String title;
  final String message;
  final DownloadStatus status;
  final DateTime timestamp;

  DownloadNotification({
    required this.chartId,
    required this.title,
    required this.message,
    required this.status,
    required this.timestamp,
  });
}

/// Service interface for enhanced download operations
abstract class DownloadService {
  /// Downloads a chart from the specified URL
  Future<void> downloadChart(String chartId, String url, {String? expectedChecksum});

  /// Pauses an ongoing download
  Future<void> pauseDownload(String chartId);

  /// Resumes a paused download with URL for resumable downloads
  Future<void> resumeDownload(String chartId, {String? url});

  /// Cancels a download
  Future<void> cancelDownload(String chartId);

  /// Gets the current download queue (legacy method for backward compatibility)
  Future<List<String>> getDownloadQueue();

  /// Gets download progress for a specific chart
  Stream<double> getDownloadProgress(String chartId);

  // New enhanced methods for queue management
  
  /// Adds a chart to the download queue with priority
  Future<void> addToQueue(String chartId, String url, {
    DownloadPriority priority = DownloadPriority.normal,
    String? expectedChecksum,
  });

  /// Removes a chart from the download queue
  Future<void> removeFromQueue(String chartId);

  /// Clears the entire download queue
  Future<void> clearQueue();

  /// Gets the detailed download queue with priorities
  Future<List<QueueItem>> getDetailedQueue();

  // Batch download operations
  
  /// Starts a batch download for multiple charts
  Future<String> startBatchDownload(List<String> chartIds, List<String> urls, {
    DownloadPriority priority = DownloadPriority.normal,
  });

  /// Gets batch download progress
  Future<BatchDownloadProgress> getBatchProgress(String batchId);

  /// Gets batch download progress stream
  Stream<BatchDownloadProgress> getBatchProgressStream(String batchId);

  /// Pauses a batch download
  Future<void> pauseBatchDownload(String batchId);

  /// Resumes a batch download
  Future<void> resumeBatchDownload(String batchId);

  /// Cancels a batch download
  Future<void> cancelBatchDownload(String batchId);

  // Background download support
  
  /// Gets persisted download state for recovery
  Future<List<DownloadProgress>> getPersistedDownloadState();

  /// Recovers downloads from persisted state
  Future<void> recoverDownloads(List<DownloadProgress> persistedDownloads);

  /// Enables background download notifications
  Future<void> enableBackgroundNotifications();

  /// Gets pending download notifications
  Future<List<DownloadNotification>> getPendingNotifications();

  /// Gets maximum concurrent downloads
  Future<int> getMaxConcurrentDownloads();

  /// Sets maximum concurrent downloads
  Future<void> setMaxConcurrentDownloads(int maxConcurrent);

  // Resume support
  
  /// Gets resume data for a chart
  Future<ResumeData?> getResumeData(String chartId);

  /// Cleans up resources on disposal
  void dispose();
}
