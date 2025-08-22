import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import '../logging/app_logger.dart';
import '../error/app_error.dart';
import '../error/error_handler.dart';
import '../state/download_state.dart';
import 'download_service.dart';
import 'http_client_service.dart';
import 'storage_service.dart';

/// Enhanced implementation of DownloadService with queue management, 
/// batch operations, resumption, and background support
class DownloadServiceImpl implements DownloadService {
  final HttpClientService _httpClient;
  final StorageService _storageService;
  final AppLogger _logger;
  final ErrorHandler _errorHandler;

  // Enhanced download state management
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, DownloadProgress> _downloadProgress = {};
  
  // Enhanced queue management with priority
  final List<QueueItem> _downloadQueue = [];
  
  // Batch download management
  final Map<String, BatchDownloadProgress> _batchProgress = {};
  final Map<String, StreamController<BatchDownloadProgress>> _batchProgressControllers = {};
  final Map<String, List<String>> _batchCharts = {};
  
  // Resume and background support
  final Map<String, ResumeData> _resumeData = {};
  final List<DownloadNotification> _pendingNotifications = [];
  bool _backgroundNotificationsEnabled = false;
  int _maxConcurrentDownloads = 2; // Marine network friendly default
  int _activeDownloads = 0;

  DownloadServiceImpl({
    required HttpClientService httpClient,
    required StorageService storageService,
    required AppLogger logger,
    required ErrorHandler errorHandler,
  })  : _httpClient = httpClient,
        _storageService = storageService,
        _logger = logger,
        _errorHandler = errorHandler;

  @override
  Future<void> downloadChart(String chartId, String url, {String? expectedChecksum}) async {
    try {
      _logger.info('Starting download for chart: $chartId', context: 'Download');

      // Check concurrent download limit
      while (_activeDownloads >= _maxConcurrentDownloads) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _activeDownloads++;

      // Create cancel token for this download
      final cancelToken = CancelToken();
      _cancelTokens[chartId] = cancelToken;

      // Create progress controller
      final progressController = StreamController<double>.broadcast();
      _progressControllers[chartId] = progressController;

      // Initialize progress
      _updateProgress(chartId, 0, 0, 0.0, DownloadStatus.downloading);

      // Determine file path for chart storage
      final chartDirectory = await _storageService.getChartsDirectory();
      final fileName = _getFileNameFromUrl(url, chartId);
      final filePath = path.join(chartDirectory.path, fileName);

      // Ensure directory exists
      await chartDirectory.create(recursive: true);

      // Attempt download with retry logic
      await _downloadWithRetry(chartId, url, filePath, cancelToken, progressController, expectedChecksum);

      // Verify downloaded file
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        
        // Basic integrity check
        if (fileSize == 0) {
          throw AppError.storage('Downloaded file is empty: $filePath');
        }

        _logger.info(
          'Chart download completed: $chartId (${_formatBytes(fileSize)})',
          context: 'Download',
        );

        // Mark as completed
        _updateProgress(chartId, fileSize, fileSize, 100.0, DownloadStatus.completed);
        progressController.add(100.0);

        // Add notification if enabled
        if (_backgroundNotificationsEnabled) {
          _addNotification(chartId, 'Download Complete', 'Chart $chartId downloaded successfully', DownloadStatus.completed);
        }
      } else {
        throw AppError.storage('Downloaded file not found: $filePath');
      }

      // Clean up
      _cleanup(chartId);

    } catch (error, stackTrace) {
      _logger.error(
        'Chart download failed: $chartId',
        exception: error,
        context: 'Download',
      );

      // Mark as failed
      _updateProgress(chartId, 0, 0, 0.0, DownloadStatus.failed);

      // Save resume data for potential recovery
      _saveResumeData(chartId, url, 0);

      // Add failure notification if enabled
      if (_backgroundNotificationsEnabled) {
        _addNotification(chartId, 'Download Failed', 'Chart $chartId download failed: ${error.toString()}', DownloadStatus.failed);
      }

      // Handle error and clean up
      _errorHandler.handleError(error, stackTrace);
      _cleanup(chartId);
      
      rethrow;
    } finally {
      _activeDownloads--;
    }
  }

  @override
  Future<void> pauseDownload(String chartId) async {
    try {
      final cancelToken = _cancelTokens[chartId];
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('Download paused by user');
        _updateProgress(chartId, 0, 0, 0.0, DownloadStatus.paused);
        _logger.info('Download paused: $chartId', context: 'Download');
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> resumeDownload(String chartId, {String? url}) async {
    try {
      // Get resume data
      final resumeData = _resumeData[chartId];
      final downloadUrl = url ?? resumeData?.originalUrl;
      
      if (downloadUrl == null) {
        throw AppError.network('Cannot resume download: missing URL for $chartId');
      }

      _logger.info('Resuming download: $chartId', context: 'Download');

      // Check if partial file exists
      final chartDirectory = await _storageService.getChartsDirectory();
      final fileName = _getFileNameFromUrl(downloadUrl, chartId);
      final filePath = path.join(chartDirectory.path, fileName);
      final file = File(filePath);

      int resumeFrom = 0;
      if (await file.exists()) {
        resumeFrom = await file.length();
        _logger.info('Resuming from byte: $resumeFrom for chart: $chartId', context: 'Download');
      }

      // Create new cancel token
      final cancelToken = CancelToken();
      _cancelTokens[chartId] = cancelToken;

      // Create progress controller
      final progressController = StreamController<double>.broadcast();
      _progressControllers[chartId] = progressController;

      try {
        // Attempt resumable download
        await _httpClient.downloadFile(
          downloadUrl,
          filePath,
          cancelToken: cancelToken,
          resumeFrom: resumeFrom > 0 ? resumeFrom : null,
          onReceiveProgress: (received, total) {
            final percentage = total > 0 ? (received / total) * 100 : 0.0;
            _updateProgress(chartId, received, total, percentage, DownloadStatus.downloading);
            
            if (!progressController.isClosed) {
              progressController.add(percentage);
            }
          },
        );

        // Update progress to completed
        final finalFile = File(filePath);
        if (await finalFile.exists()) {
          final fileSize = await finalFile.length();
          _updateProgress(chartId, fileSize, fileSize, 100.0, DownloadStatus.completed);
          progressController.add(100.0);
        }

      } on DioException catch (e) {
        // Handle range not satisfiable (HTTP 416) by restarting download
        if (e.response?.statusCode == 416) {
          _logger.warning('Range not satisfiable, restarting download: $chartId', context: 'Download');
          
          // Delete corrupted partial file
          if (await file.exists()) {
            await file.delete();
          }
          
          // Restart download from beginning
          await _httpClient.downloadFile(
            downloadUrl,
            filePath,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              final percentage = total > 0 ? (received / total) * 100 : 0.0;
              _updateProgress(chartId, received, total, percentage, DownloadStatus.downloading);
              
              if (!progressController.isClosed) {
                progressController.add(percentage);
              }
            },
          );
        } else {
          rethrow;
        }
      }

      _cleanup(chartId);

    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> cancelDownload(String chartId) async {
    try {
      final cancelToken = _cancelTokens[chartId];
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('Download cancelled by user');
        _updateProgress(chartId, 0, 0, 0.0, DownloadStatus.cancelled);
        _logger.info('Download cancelled: $chartId', context: 'Download');
      }

      // Remove from queue
      _downloadQueue.removeWhere((item) => item.chartId == chartId);
      
      // Clean up partial file if it exists
      try {
        final chartDirectory = await _storageService.getChartsDirectory();
        final files = await chartDirectory.list().toList();
        for (final file in files) {
          if (file is File && file.path.contains(chartId)) {
            await file.delete();
            _logger.debug('Deleted partial download: ${file.path}', context: 'Download');
          }
        }
      } catch (e) {
        _logger.warning('Failed to clean up partial download for: $chartId', context: 'Download');
      }

      _cleanup(chartId);
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<String>> getDownloadQueue() async {
    return _downloadQueue.map((item) => item.chartId).toList();
  }

  @override
  Stream<double> getDownloadProgress(String chartId) {
    final controller = _progressControllers[chartId];
    if (controller != null) {
      return controller.stream;
    }
    
    // Return a stream with current progress if available
    final progress = _downloadProgress[chartId];
    if (progress != null) {
      return Stream.value(progress.progress * 100.0);
    }
    
    return const Stream.empty();
  }

  // Enhanced queue management methods

  @override
  Future<void> addToQueue(String chartId, String url, {
    DownloadPriority priority = DownloadPriority.normal,
    String? expectedChecksum,
  }) async {
    // Check if already in queue
    if (_downloadQueue.any((item) => item.chartId == chartId)) {
      _logger.debug('Chart already in queue: $chartId', context: 'Download');
      return;
    }

    final queueItem = QueueItem(
      chartId: chartId,
      url: url,
      priority: priority,
      addedAt: DateTime.now(),
      expectedChecksum: expectedChecksum,
    );

    _downloadQueue.add(queueItem);
    _sortQueueByPriority();

    _logger.info('Added chart to queue: $chartId (priority: $priority)', context: 'Download');
  }

  @override
  Future<void> removeFromQueue(String chartId) async {
    _downloadQueue.removeWhere((item) => item.chartId == chartId);
    _logger.info('Removed chart from queue: $chartId', context: 'Download');
  }

  @override
  Future<void> clearQueue() async {
    _downloadQueue.clear();
    _logger.info('Cleared download queue', context: 'Download');
  }

  @override
  Future<List<QueueItem>> getDetailedQueue() async {
    return List.from(_downloadQueue);
  }

  // Batch download methods

  @override
  Future<String> startBatchDownload(List<String> chartIds, List<String> urls, {
    DownloadPriority priority = DownloadPriority.normal,
  }) async {
    if (chartIds.length != urls.length) {
      throw ArgumentError('Chart IDs and URLs lists must have the same length');
    }

    final batchId = _generateBatchId();
    _batchCharts[batchId] = List.from(chartIds);

    // Initialize batch progress
    final batchProgress = BatchDownloadProgress(
      batchId: batchId,
      status: BatchDownloadStatus.inProgress,
      totalCharts: chartIds.length,
      completedCharts: 0,
      failedCharts: 0,
      overallProgress: 0.0,
      lastUpdated: DateTime.now(),
      failedChartIds: [],
    );
    _batchProgress[batchId] = batchProgress;

    // Create progress controller
    final progressController = StreamController<BatchDownloadProgress>.broadcast();
    _batchProgressControllers[batchId] = progressController;

    // Add charts to queue
    for (int i = 0; i < chartIds.length; i++) {
      await addToQueue(chartIds[i], urls[i], priority: priority);
    }

    _logger.info('Started batch download: $batchId (${chartIds.length} charts)', context: 'Download');
    return batchId;
  }

  @override
  Future<BatchDownloadProgress> getBatchProgress(String batchId) async {
    final progress = _batchProgress[batchId];
    if (progress == null) {
      throw ArgumentError('Batch not found: $batchId');
    }
    return progress;
  }

  @override
  Stream<BatchDownloadProgress> getBatchProgressStream(String batchId) {
    final controller = _batchProgressControllers[batchId];
    if (controller != null) {
      return controller.stream;
    }
    return const Stream.empty();
  }

  @override
  Future<void> pauseBatchDownload(String batchId) async {
    final progress = _batchProgress[batchId];
    if (progress == null) return;

    // Pause all charts in this batch
    final chartIds = _batchCharts[batchId] ?? [];
    for (final chartId in chartIds) {
      try {
        await pauseDownload(chartId);
      } catch (e) {
        _logger.warning('Failed to pause chart in batch: $chartId', context: 'Download');
      }
    }

    // Update batch status
    _batchProgress[batchId] = BatchDownloadProgress(
      batchId: progress.batchId,
      status: BatchDownloadStatus.paused,
      totalCharts: progress.totalCharts,
      completedCharts: progress.completedCharts,
      failedCharts: progress.failedCharts,
      overallProgress: progress.overallProgress,
      lastUpdated: DateTime.now(),
      failedChartIds: progress.failedChartIds,
    );
    _updateBatchProgress(batchId);
  }

  @override
  Future<void> resumeBatchDownload(String batchId) async {
    final progress = _batchProgress[batchId];
    if (progress == null) return;

    // Update batch status
    _batchProgress[batchId] = BatchDownloadProgress(
      batchId: progress.batchId,
      status: BatchDownloadStatus.inProgress,
      totalCharts: progress.totalCharts,
      completedCharts: progress.completedCharts,
      failedCharts: progress.failedCharts,
      overallProgress: progress.overallProgress,
      lastUpdated: DateTime.now(),
      failedChartIds: progress.failedChartIds,
    );
    _updateBatchProgress(batchId);

    _logger.info('Resumed batch download: $batchId', context: 'Download');
  }

  @override
  Future<void> cancelBatchDownload(String batchId) async {
    final progress = _batchProgress[batchId];
    if (progress == null) return;

    // Cancel all charts in this batch
    final chartIds = _batchCharts[batchId] ?? [];
    for (final chartId in chartIds) {
      try {
        await cancelDownload(chartId);
      } catch (e) {
        _logger.warning('Failed to cancel chart in batch: $chartId', context: 'Download');
      }
    }

    // Update batch status
    _batchProgress[batchId] = BatchDownloadProgress(
      batchId: progress.batchId,
      status: BatchDownloadStatus.cancelled,
      totalCharts: progress.totalCharts,
      completedCharts: progress.completedCharts,
      failedCharts: progress.failedCharts,
      overallProgress: progress.overallProgress,
      lastUpdated: DateTime.now(),
      failedChartIds: progress.failedChartIds,
    );
    _updateBatchProgress(batchId);

    // Clean up
    _batchCharts.remove(batchId);
    _batchProgressControllers[batchId]?.close();
    _batchProgressControllers.remove(batchId);
  }

  // Background download support methods

  @override
  Future<List<DownloadProgress>> getPersistedDownloadState() async {
    return _downloadProgress.values.toList();
  }

  @override
  Future<void> recoverDownloads(List<DownloadProgress> persistedDownloads) async {
    for (final download in persistedDownloads) {
      if (download.status == DownloadStatus.downloading) {
        // Attempt to resume automatically
        try {
          await resumeDownload(download.chartId);
        } catch (e) {
          _logger.warning('Failed to auto-resume download: ${download.chartId}', context: 'Download');
        }
      } else if (download.status == DownloadStatus.paused) {
        // Add back to queue as paused
        _downloadProgress[download.chartId] = download;
      }
    }
  }

  @override
  Future<void> enableBackgroundNotifications() async {
    _backgroundNotificationsEnabled = true;
    _logger.info('Background notifications enabled', context: 'Download');
  }

  @override
  Future<List<DownloadNotification>> getPendingNotifications() async {
    return List.from(_pendingNotifications);
  }

  @override
  Future<int> getMaxConcurrentDownloads() async {
    return _maxConcurrentDownloads;
  }

  @override
  Future<void> setMaxConcurrentDownloads(int maxConcurrent) async {
    _maxConcurrentDownloads = maxConcurrent;
    _logger.info('Max concurrent downloads set to: $maxConcurrent', context: 'Download');
  }

  @override
  Future<ResumeData?> getResumeData(String chartId) async {
    return _resumeData[chartId];
  }

  // Helper methods

  /// Download with retry logic
  Future<void> _downloadWithRetry(
    String chartId,
    String url,
    String filePath,
    CancelToken cancelToken,
    StreamController<double> progressController,
    String? expectedChecksum,
  ) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        await _httpClient.downloadFile(
          url,
          filePath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            final percentage = total > 0 ? (received / total) * 100 : 0.0;
            _updateProgress(chartId, received, total, percentage, DownloadStatus.downloading);
            
            if (!progressController.isClosed) {
              progressController.add(percentage);
            }
          },
        );

        // If we get here, download succeeded
        break;

      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          rethrow;
        }

        // Exponential backoff
        final delay = Duration(seconds: pow(2, attempt).toInt());
        _logger.warning('Download attempt $attempt failed for $chartId, retrying in ${delay.inSeconds}s', context: 'Download');
        await Future.delayed(delay);
      }
    }
  }

  /// Update download progress
  void _updateProgress(
    String chartId,
    int downloaded,
    int total,
    double percentage,
    DownloadStatus status,
  ) {
    _downloadProgress[chartId] = DownloadProgress(
      chartId: chartId,
      status: status,
      progress: percentage / 100.0,
      totalBytes: total > 0 ? total : null,
      downloadedBytes: downloaded > 0 ? downloaded : null,
      lastUpdated: DateTime.now(),
    );
  }

  /// Sort queue by priority
  void _sortQueueByPriority() {
    _downloadQueue.sort((a, b) {
      // Higher priority first
      final priorityComparison = b.priority.index.compareTo(a.priority.index);
      if (priorityComparison != 0) return priorityComparison;
      
      // Then by add time (FIFO for same priority)
      return a.addedAt.compareTo(b.addedAt);
    });
  }

  /// Generate unique batch ID
  String _generateBatchId() {
    return 'batch_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Update batch progress
  void _updateBatchProgress(String batchId) {
    final controller = _batchProgressControllers[batchId];
    final progress = _batchProgress[batchId];
    
    if (controller != null && progress != null && !controller.isClosed) {
      controller.add(progress);
    }
  }

  /// Save resume data
  void _saveResumeData(String chartId, String url, int downloadedBytes) {
    _resumeData[chartId] = ResumeData(
      chartId: chartId,
      originalUrl: url,
      downloadedBytes: downloadedBytes,
      lastAttempt: DateTime.now(),
    );
  }

  /// Add notification
  void _addNotification(String chartId, String title, String message, DownloadStatus status) {
    _pendingNotifications.add(DownloadNotification(
      chartId: chartId,
      title: title,
      message: message,
      status: status,
      timestamp: DateTime.now(),
    ));
  }

  /// Clean up resources for a specific download
  void _cleanup(String chartId) {
    // Cancel and remove cancel token
    final cancelToken = _cancelTokens.remove(chartId);
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
    }

    // Close and remove progress controller
    final progressController = _progressControllers.remove(chartId);
    if (progressController != null && !progressController.isClosed) {
      progressController.close();
    }

    // Remove from queue
    _downloadQueue.removeWhere((item) => item.chartId == chartId);
  }

  /// Extract filename from URL or generate one based on chart ID
  String _getFileNameFromUrl(String url, String chartId) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      if (pathSegments.isNotEmpty) {
        final fileName = pathSegments.last;
        if (fileName.isNotEmpty && fileName.contains('.')) {
          return fileName;
        }
      }
    } catch (e) {
      _logger.warning('Failed to extract filename from URL: $url', context: 'Download');
    }

    return '$chartId.zip';
  }

  /// Format bytes for human-readable display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    // Cancel all active downloads
    for (final cancelToken in _cancelTokens.values) {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('Service disposal');
      }
    }

    // Close all progress controllers
    for (final controller in _progressControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }

    // Close all batch progress controllers
    for (final controller in _batchProgressControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }

    // Clear all state
    _cancelTokens.clear();
    _progressControllers.clear();
    _downloadProgress.clear();
    _downloadQueue.clear();
    _batchProgress.clear();
    _batchProgressControllers.clear();
    _batchCharts.clear();
    _resumeData.clear();
    _pendingNotifications.clear();

    _logger.info('Enhanced download service disposed', context: 'Download');
  }
}
