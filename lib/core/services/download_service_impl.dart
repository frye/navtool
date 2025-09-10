import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:collection/collection.dart';
import '../logging/app_logger.dart';
import '../error/app_error.dart';
import '../error/error_handler.dart';
import '../state/download_state.dart';
import 'download_service.dart';
import 'http_client_service.dart';
import 'storage_service.dart';
import 'download_metrics_collector.dart';
import '../utils/network_resilience.dart';
import 'package:meta/meta.dart';

/// Enhanced implementation of DownloadService with queue management,
/// batch operations, resumption, and background support
class DownloadServiceImpl implements DownloadService {
  final HttpClientService _httpClient;
  final StorageService _storageService;
  final AppLogger _logger;
  final ErrorHandler _errorHandler;
  // Optional adapter to push events into queue notifier (Phase 1 integration)
  DownloadQueueNotifier? _queueNotifier;
  DownloadMetricsCollector? _metrics; // Phase 3 metrics integration
  NetworkResilience? _networkResilience; // for auto-retry monitoring
  StreamSubscription<NetworkStatus>? _netStatusSub;

  // Enhanced download state management
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, DownloadProgress> _downloadProgress = {};

  // Enhanced queue management with priority
  final List<QueueItem> _downloadQueue = [];

  // Batch download management
  final Map<String, BatchDownloadProgress> _batchProgress = {};
  final Map<String, StreamController<BatchDownloadProgress>>
  _batchProgressControllers = {};
  final Map<String, List<String>> _batchCharts = {};

  // Resume and background support
  final Map<String, ResumeData> _resumeData = {};
  final List<DownloadNotification> _pendingNotifications = [];
  bool _backgroundNotificationsEnabled = false;
  int _maxConcurrentDownloads = 2; // Marine network friendly default
  int _activeDownloads = 0;
  // Network suitability probe (injectable for tests)
  Future<bool> Function()? _networkSuitabilityProbe;
  Timer? _networkRetryTimer;
  final Duration _networkRetryInterval = const Duration(seconds: 1);
  // Optional injected rename implementation for testing retry/fallback logic.
  final Future<void> Function(File tempFile, String finalPath)? _renameImpl;

  DownloadServiceImpl({
    required HttpClientService httpClient,
    required StorageService storageService,
    required AppLogger logger,
    required ErrorHandler errorHandler,
    DownloadQueueNotifier? queueNotifier,
    DownloadMetricsCollector? metrics,
    NetworkResilience? networkResilience,
    Future<bool> Function()? networkSuitabilityProbe,

    /// Internal/testing hook to override the low-level rename call used by
    /// [_safeRename]. This lets tests simulate transient failures to drive
    /// retry and fallback copy logic without relying on OS-level file locks.
    Future<void> Function(File tempFile, String finalPath)? renameImpl,
  }) : _httpClient = httpClient,
       _storageService = storageService,
       _logger = logger,
       _errorHandler = errorHandler,
       _renameImpl = renameImpl {
    _queueNotifier = queueNotifier;
    _metrics = metrics;
    _networkResilience = networkResilience;
    _networkSuitabilityProbe = networkSuitabilityProbe;
    _initNetworkListener();
  }

  /// Allows late binding of queue notifier (e.g. after provider init)
  void attachQueueNotifier(DownloadQueueNotifier notifier) {
    _queueNotifier = notifier;
  }

  /// Allows late binding of metrics collector
  void attachMetrics(DownloadMetricsCollector metrics) {
    _metrics = metrics;
  }

  // --- Network suitability gating (stub for Phase 1; real integration in later phases) ---
  Future<bool> _isNetworkSuitable() async {
    // Allow injection for tests or future connectivity service
    if (_networkSuitabilityProbe != null) {
      try {
        return await _networkSuitabilityProbe!.call();
      } catch (e) {
        _logger.warning(
          'Network suitability probe failed: $e',
          context: 'Download',
        );
      }
    }
    return true; // Default: assume suitable
  }

  @override
  Future<void> downloadChart(
    String chartId,
    String url, {
    String? expectedChecksum,
  }) async {
    try {
      _logger.info(
        'Starting download for chart: $chartId',
        context: 'Download',
      );
      _metrics?.start(chartId);

      // Phase 2: disk space preflight (best effort)
      if (!await _hasSufficientDiskSpace(url)) {
        throw AppError.storage(
          'Insufficient disk space for download: $chartId',
        );
      }

      // Network suitability gate (Phase 1)
      while (!await _isNetworkSuitable()) {
        _logger.debug(
          'Network unsuitable; deferring start for $chartId (retry in 1s)',
          context: 'Download',
        );
        await Future.delayed(const Duration(seconds: 1));
      }
      _logger.debug(
        'Network suitable; starting download for $chartId',
        context: 'Download',
      );

      // Check concurrent download limit
      while (_activeDownloads >= _maxConcurrentDownloads) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _activeDownloads++;

      // Create cancel token for this download
      final cancelToken = CancelToken();
      _cancelTokens[chartId] = cancelToken;

      // Reuse lazily created controller (early subscriber) or create now
      final progressController = _progressControllers[chartId] ??=
          StreamController<double>.broadcast();
      if (_downloadProgress[chartId] == null) {
        _updateProgress(chartId, 0, 0, 0.0, DownloadStatus.downloading);
        if (!progressController.isClosed) {
          progressController.add(0.0); // immediate seed
        }
      }

      // Determine final & temp file paths for chart storage (atomic write pattern)
      final chartDirectory = await _storageService.getChartsDirectory();
      final fileName = _getFileNameFromUrl(url, chartId);
      final filePath = path.join(chartDirectory.path, fileName);
      final tempFilePath = '$filePath.part';

      // Ensure directory exists
      await chartDirectory.create(recursive: true);

      // Attempt download with retry logic
      await _downloadWithRetry(
        chartId,
        url,
        tempFilePath,
        cancelToken,
        progressController,
        expectedChecksum,
      );

      // Verify downloaded temp file
      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        // Basic integrity check
        if (fileSize == 0) {
          throw AppError.storage('Downloaded file is empty: $tempFilePath');
        }

        // Verify checksum if provided BEFORE renaming so we don't leave a bad final file
        if (expectedChecksum != null) {
          final actualChecksum = await _calculateFileChecksum(tempFile);
          if (actualChecksum != expectedChecksum) {
            _logger.error(
              'Checksum verification failed for chart: $chartId. Expected: $expectedChecksum, Actual: $actualChecksum',
              context: 'Download',
            );
            await tempFile.delete();
            throw AppError.storage(
              'Downloaded file failed checksum verification: $chartId',
            );
          }
          _logger.info(
            'Checksum verification passed for chart: $chartId',
            context: 'Download',
          );
        }

        // If a previous file exists, remove it to allow atomic rename on all platforms (Windows can't overwrite on rename)
        final finalFile = File(filePath);
        // Ensure no conflicting entity (file or directory) exists at final path
        await _prepareFinalPath(File(filePath));
        // Attempt atomic rename with retry fallback (Windows may transiently lock files)
        await _safeRename(tempFile, filePath);
      }

      // Verify final file
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        // (Checksum already validated on temp file if requested)

        _logger.info(
          'Chart download completed: $chartId (${_formatBytes(fileSize)})',
          context: 'Download',
        );

        // Mark as completed
        _updateProgress(
          chartId,
          fileSize,
          fileSize,
          1.0,
          DownloadStatus.completed,
        );
        _metrics?.completeSuccess(chartId);
        progressController.add(1.0);

        // Add notification if enabled
        if (_backgroundNotificationsEnabled) {
          _addNotification(
            chartId,
            'Download Complete',
            'Chart $chartId downloaded successfully',
            DownloadStatus.completed,
          );
        }
      } else {
        throw AppError.storage('Downloaded file not found: $filePath');
      }

      // Clean up (queue will be processed in finally after concurrency slot released)
      _cleanup(chartId);
    } catch (error, stackTrace) {
      _logger.error(
        'Chart download failed: $chartId',
        exception: error,
        context: 'Download',
      );

      // Mark as failed
      final category = _deriveErrorCategory(error);
      _updateProgress(
        chartId,
        0,
        0,
        0.0,
        DownloadStatus.failed,
        errorMessage: error.toString(),
        errorCategory: category,
      );
      _metrics?.completeFailure(chartId, category);

      // Save resume data for potential recovery using actual partial bytes if present
      int partialBytes = 0;
      try {
        final chartDirectory = await _storageService.getChartsDirectory();
        final fileName = _getFileNameFromUrl(url, chartId);
        final tempFilePath = path.join(chartDirectory.path, '$fileName.part');
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          partialBytes = await tempFile.length();
        }
      } catch (_) {
        // ignore - fallback to 0
      }
      final code = _classifyErrorCode(error);
      _saveResumeDataWithError(
        chartId,
        url,
        partialBytes,
        code,
        checksum: expectedChecksum,
      );

      // Add failure notification if enabled
      if (_backgroundNotificationsEnabled) {
        _addNotification(
          chartId,
          'Download Failed',
          'Chart $chartId download failed: ${error.toString()}',
          DownloadStatus.failed,
        );
      }

      // Handle error and clean up
      _errorHandler.handleError(error, stackTrace);
      _cleanup(chartId);

      // Convert to AppError for consistent error handling (preserve existing AppError)
      if (error is AppError) {
        rethrow;
      } else if (error is DioException) {
        throw AppError.network(
          'Chart download failed: $chartId - ${error.message}',
        );
      } else if (error is FileSystemException) {
        throw AppError.storage(
          'Storage error during download: $chartId - ${error.message}',
        );
      } else {
        throw AppError.unknown(
          'Unexpected error during download: $chartId - ${error.toString()}',
        );
      }
    } finally {
      // Release concurrency slot THEN process queue once
      _activeDownloads--;
      _processQueue();
    }
  }

  @override
  Future<void> pauseDownload(String chartId) async {
    try {
      final cancelToken = _cancelTokens[chartId];
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('Download paused by user');
        // Preserve partial bytes & progress
        final existing = _downloadProgress[chartId];
        final downloadedBytes = await _getPartialBytes(chartId, existing);
        _updateProgress(
          chartId,
          downloadedBytes,
          existing?.totalBytes ?? 0,
          existing?.progress ?? 0.0,
          DownloadStatus.paused,
        );
        // Persist resume data explicitly on user pause to guarantee recovery metadata
        final resume = _resumeData[chartId];
        if (resume != null) {
          _saveResumeData(
            chartId,
            resume.originalUrl,
            downloadedBytes,
            checksum: resume.checksum,
          );
        }
        _logger.info('Download paused: $chartId', context: 'Download');
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);

      // Convert to AppError for consistent error handling
      if (error is DioException) {
        throw AppError.network(
          'Failed to pause download: $chartId - ${error.message}',
        );
      } else if (error is AppError) {
        rethrow;
      } else {
        throw AppError.unknown(
          'Unexpected error pausing download: $chartId - ${error.toString()}',
        );
      }
    }
  }

  @override
  Future<void> resumeDownload(String chartId, {String? url}) async {
    try {
      // Get resume data
      final resumeData = _resumeData[chartId];
      final downloadUrl = url ?? resumeData?.originalUrl;

      if (downloadUrl == null) {
        throw AppError.network(
          'Cannot resume download: missing URL for $chartId',
        );
      }

      _logger.info('Resuming download: $chartId', context: 'Download');

      // Check if partial file exists
      final chartDirectory = await _storageService.getChartsDirectory();
      final fileName = _getFileNameFromUrl(downloadUrl, chartId);
      final filePath = path.join(chartDirectory.path, fileName);
      final file = File(filePath);

      // Use .part temp file pattern for partial downloads
      final tempFilePath = '$filePath.part';
      final tempFile = File(tempFilePath);

      int resumeFrom = 0;
      if (await tempFile.exists()) {
        resumeFrom = await tempFile.length();
        // Validate against stored resume data size if present
        if (resumeData != null && resumeData.downloadedBytes != resumeFrom) {
          _logger.warning(
            'Partial size mismatch (${resumeData.downloadedBytes} vs $resumeFrom); resetting download: $chartId',
            context: 'Download',
          );
          await tempFile.delete();
          resumeFrom = 0;
        } else {
          _logger.info(
            'Resuming from byte: $resumeFrom for chart: $chartId',
            context: 'Download',
          );
        }
      }

      // Create new cancel token
      final cancelToken = CancelToken();
      _cancelTokens[chartId] = cancelToken;

      // Reuse existing (lazy) controller or create new
      final progressController = _progressControllers[chartId] ??=
          StreamController<double>.broadcast();
      if (_downloadProgress[chartId] == null) {
        _updateProgress(
          chartId,
          resumeFrom,
          0,
          0.0,
          DownloadStatus.downloading,
        );
        if (!progressController.isClosed) {
          progressController.add(0.0);
        }
      }

      try {
        // Phase 2: If server supports range (probe), attempt manual streaming append when resuming
        final supportsRange = await _probeRangeSupport(downloadUrl);
        if (resumeFrom > 0 && supportsRange) {
          await _appendResumeStream(
            chartId,
            downloadUrl,
            tempFilePath,
            resumeFrom,
            cancelToken,
            progressController,
          );
        } else {
          await _httpClient.downloadFile(
            downloadUrl,
            tempFilePath,
            cancelToken: cancelToken,
            resumeFrom: resumeFrom > 0 ? resumeFrom : null,
            onReceiveProgress: (received, total) {
              final progressNorm = total > 0 ? (received / total) : 0.0;
              _updateProgress(
                chartId,
                received,
                total,
                progressNorm,
                DownloadStatus.downloading,
              );
              if (!progressController.isClosed) {
                progressController.add(progressNorm);
              }
            },
          );
        }

        // Update progress to completed (rename temp file atomically)
        final finalFile = File(filePath);
        if (await tempFile.exists()) {
          if (await finalFile.exists()) {
            await finalFile.delete();
          }
          await tempFile.rename(finalFile.path);
        }
        if (await finalFile.exists()) {
          final fileSize = await finalFile.length();
          _updateProgress(
            chartId,
            fileSize,
            fileSize,
            1.0,
            DownloadStatus.completed,
          );
          if (!progressController.isClosed) {
            progressController.add(1.0);
          }
        }
      } on DioException catch (e) {
        // Handle range not satisfiable (HTTP 416) by restarting download
        if (e.response?.statusCode == 416) {
          _logger.warning(
            'Range not satisfiable, restarting download: $chartId',
            context: 'Download',
          );

          // Delete corrupted partial file
          if (await file.exists()) {
            await file.delete();
          }

          // Restart download from beginning
          await _httpClient.downloadFile(
            downloadUrl,
            tempFilePath,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              final progressNorm = total > 0 ? (received / total) : 0.0;
              _updateProgress(
                chartId,
                received,
                total,
                progressNorm,
                DownloadStatus.downloading,
              );
              if (!progressController.isClosed) {
                progressController.add(progressNorm);
              }
            },
          );
        } else {
          rethrow;
        }
      }

      _cleanup(chartId);
      if (_downloadProgress[chartId]?.status == DownloadStatus.completed) {
        _metrics?.completeSuccess(chartId);
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);

      // Attempt classification & persistence of error resume data if URL known
      try {
        final resume = _resumeData[chartId];
        final effectiveUrl = url ?? resume?.originalUrl;
        if (effectiveUrl != null) {
          final partial = await _getPartialBytes(
            chartId,
            _downloadProgress[chartId],
          );
          final code = _classifyErrorCode(error);
          _saveResumeDataWithError(
            chartId,
            effectiveUrl,
            partial,
            code,
            checksum: resume?.checksum,
          );
        }
      } catch (_) {}
      // Convert to AppError for consistent error handling (preserve existing AppError)
      if (error is AppError) {
        rethrow;
      } else if (error is DioException) {
        throw AppError.network(
          'Failed to resume download: $chartId - ${error.message}',
        );
      } else if (error is FileSystemException) {
        throw AppError.storage(
          'Storage error during resume: $chartId - ${error.message}',
        );
      } else {
        throw AppError.unknown(
          'Unexpected error resuming download: $chartId - ${error.toString()}',
        );
      }
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
            _logger.debug(
              'Deleted partial download: ${file.path}',
              context: 'Download',
            );
          }
        }
      } catch (e) {
        _logger.warning(
          'Failed to clean up partial download for: $chartId',
          context: 'Download',
        );
      }

      _cleanup(chartId);
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);

      // Convert to AppError for consistent error handling
      if (error is DioException) {
        throw AppError.network(
          'Failed to cancel download: $chartId - ${error.message}',
        );
      } else if (error is FileSystemException) {
        throw AppError.storage(
          'Storage error during cancellation: $chartId - ${error.message}',
        );
      } else if (error is AppError) {
        rethrow;
      } else {
        throw AppError.unknown(
          'Unexpected error cancelling download: $chartId - ${error.toString()}',
        );
      }
    }
  }

  @override
  Future<List<String>> getDownloadQueue() async {
    return _downloadQueue.map((item) => item.chartId).toList();
  }

  @override
  Stream<double> getDownloadProgress(String chartId) {
    // Lazily create a broadcast controller so early subscribers always receive
    // an initial emission (0.0 or cached) even if they attach before a download starts.
    var controller = _progressControllers[chartId];
    if (controller == null) {
      controller = StreamController<double>.broadcast();
      _progressControllers[chartId] = controller;
      final initial = _downloadProgress[chartId]?.progress ?? 0.0;
      scheduleMicrotask(() {
        if (!controller!.isClosed) controller.add(initial);
      });
    }
    return controller.stream;
  }

  @override
  Stream<double> progressStream(String chartId) => getDownloadProgress(chartId);

  // Enhanced queue management methods

  @override
  Future<void> addToQueue(
    String chartId,
    String url, {
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

    _logger.info(
      'Added chart to queue: $chartId (priority: $priority)',
      context: 'Download',
    );
    // Notify external queue notifier (UI state) if attached and not already present
    try {
      if (_queueNotifier != null) {
        final existing = _queueNotifier!.state.downloads[chartId];
        if (existing == null) {
          _queueNotifier!.queueDownload(chartId);
        } else if (existing.status == DownloadStatus.failed) {
          // Requeue previously failed download
          _queueNotifier!.resumeDownload(chartId);
        }
      }
    } catch (e) {
      _logger.warning(
        'Failed to notify queue notifier for $chartId: $e',
        context: 'Download',
      );
    }

    // Process queue to start downloads if slots are available
    _processQueue();
  }

  @override
  Future<void> pauseAllDownloads() async {
    for (final id in _downloadProgress.keys.toList()) {
      final prog = _downloadProgress[id];
      if (prog != null && prog.status == DownloadStatus.downloading) {
        // ignore: discarded_futures
        pauseDownload(id);
      }
    }
    _queueNotifier?.pauseAll();
  }

  @override
  Future<void> resumeAllDownloads() async {
    for (final id in _downloadProgress.keys.toList()) {
      final prog = _downloadProgress[id];
      if (prog != null && prog.status == DownloadStatus.paused) {
        // ignore: discarded_futures
        resumeDownload(id);
      }
    }
    _queueNotifier?.resumeAll();
    _processQueue();
  }

  @override
  Future<String> exportDiagnostics() async {
    try {
      final metrics = _metrics?.snapshot();
      final state = {
        'timestamp': DateTime.now().toIso8601String(),
        'activeDownloads': _downloadProgress.values
            .map(
              (d) => {
                'chartId': d.chartId,
                'status': d.status.name,
                'progress': d.progress,
                'errorCategory': d.errorCategory,
                'errorMessage': d.errorMessage,
              },
            )
            .toList(),
        'queue': _downloadQueue.map((q) => q.chartId).toList(),
        'metrics': metrics == null
            ? null
            : {
                'successCount': metrics.successCount,
                'failureCount': metrics.failureCount,
                'failureByCategory': metrics.failureByCategory,
                'averageDurationSeconds': metrics.averageDurationSeconds,
                'medianDurationSeconds': metrics.medianDurationSeconds,
                'retryCount': metrics.retryCount,
              },
      };
      return jsonEncode(state);
    } catch (e) {
      _logger.warning('Diagnostics export failed: $e', context: 'Download');
      return '{}';
    }
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
  Future<String> startBatchDownload(
    List<String> chartIds,
    List<String> urls, {
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
    final progressController =
        StreamController<BatchDownloadProgress>.broadcast();
    _batchProgressControllers[batchId] = progressController;

    // Add charts to queue
    for (int i = 0; i < chartIds.length; i++) {
      await addToQueue(chartIds[i], urls[i], priority: priority);
    }

    _logger.info(
      'Started batch download: $batchId (${chartIds.length} charts)',
      context: 'Download',
    );
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
        _logger.warning(
          'Failed to pause chart in batch: $chartId',
          context: 'Download',
        );
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
        _logger.warning(
          'Failed to cancel chart in batch: $chartId',
          context: 'Download',
        );
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
    try {
      // Save current state to disk for persistence
      await _savePersistentState();
      return _downloadProgress.values.toList();
    } catch (e) {
      _logger.warning(
        'Failed to persist download state: $e',
        context: 'Download',
      );
      return _downloadProgress.values.toList();
    }
  }

  @override
  Future<void> recoverDownloads(
    List<DownloadProgress> persistedDownloads,
  ) async {
    try {
      // Load persistent state from disk
      await _loadPersistentState();

      // Merge with provided downloads
      for (final download in persistedDownloads) {
        if (download.status == DownloadStatus.downloading) {
          // Attempt to resume automatically
          try {
            await resumeDownload(download.chartId);
          } catch (e) {
            _logger.warning(
              'Failed to auto-resume download: ${download.chartId}',
              context: 'Download',
            );
          }
        } else if (download.status == DownloadStatus.paused) {
          // Add back to queue as paused
          _downloadProgress[download.chartId] = download;
        }
      }

      _logger.info(
        'Recovered ${persistedDownloads.length} download states',
        context: 'Download',
      );
    } catch (e) {
      _logger.error('Failed to recover downloads: $e', context: 'Download');
      rethrow;
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
    _logger.info(
      'Max concurrent downloads set to: $maxConcurrent',
      context: 'Download',
    );
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
            final progressNorm = total > 0 ? (received / total) : 0.0;
            _updateProgress(
              chartId,
              received,
              total,
              progressNorm,
              DownloadStatus.downloading,
            );
            if (total > 0) {
              _saveResumeData(
                chartId,
                url,
                received,
                checksum: expectedChecksum,
              );
            }
            if (!progressController.isClosed) {
              progressController.add(progressNorm);
            }
          },
        );

        // If we get here, download succeeded
        break;
      } catch (e) {
        attempt++;
        if (attempt > 1) {
          // Count as a retry (attempt 2+)
          _metrics?.incrementRetry(chartId);
        }
        if (attempt >= maxRetries) {
          rethrow;
        }

        // Exponential backoff
        final base = Duration(seconds: pow(2, attempt).toInt());
        final jitterMs = Random().nextInt(500);
        final delay = base + Duration(milliseconds: jitterMs);
        _logger.warning(
          'Download attempt $attempt failed for $chartId, retrying in ${delay.inSeconds}.${(delay.inMilliseconds % 1000).toString().padLeft(3, '0')}s (jitter ${jitterMs}ms)',
          context: 'Download',
        );
        await Future.delayed(delay);
      }
    }
  }

  /// Update download progress
  void _updateProgress(
    String chartId,
    int downloaded,
    int total,
    double progressNormalized,
    DownloadStatus status, {
    String? errorMessage,
    String? errorCategory,
  }) {
    // Section C: Progress Normalization Enforcement
    // All progress values in the service are expected to be normalized (0.0 - 1.0).
    // If an out-of-range value is provided (e.g., legacy percentage 0-100), we
    // log a warning (once per chart lifecycle) and clamp. This protects against
    // future regressions while keeping production resilient.
    if (progressNormalized < -1e-6 || progressNormalized > 1.0 + 1e-6) {
      _logger.warning(
        'Out-of-range progress value received for $chartId: ${progressNormalized.toStringAsFixed(4)} (expected 0.0-1.0). Clamping applied.',
        context: 'Download',
      );
    }
    assert(
      progressNormalized >= -1e-6 && progressNormalized <= 1.0 + 1e-6,
      'Download progress must be normalized 0..1 (got $progressNormalized for $chartId)',
    );
    // Compute speed / ETA (simple instantaneous estimation)
    double? bps;
    int? eta;
    if (status == DownloadStatus.downloading && downloaded > 0 && total > 0) {
      final existing = _downloadProgress[chartId];
      if (existing != null && existing.downloadedBytes != null) {
        final deltaBytes = downloaded - (existing.downloadedBytes ?? 0);
        final deltaMs = DateTime.now()
            .difference(existing.lastUpdated)
            .inMilliseconds;
        if (deltaBytes > 0 && deltaMs > 0) {
          bps = (deltaBytes * 1000) / deltaMs;
          final remaining = total - downloaded;
          if (bps > 0) eta = (remaining / bps).round();
        }
      }
    }
    _downloadProgress[chartId] = DownloadProgress(
      chartId: chartId,
      status: status,
      progress: progressNormalized.clamp(0.0, 1.0),
      totalBytes: total > 0 ? total : null,
      downloadedBytes: downloaded > 0 ? downloaded : null,
      errorMessage: errorMessage,
      errorCategory: errorCategory,
      bytesPerSecond: bps,
      etaSeconds: eta,
      lastUpdated: DateTime.now(),
    );

    // Push to notifier adapter if attached
    _queueNotifier?.updateProgress(
      chartId,
      status: status,
      progress: progressNormalized,
      totalBytes: total > 0 ? total : null,
      downloadedBytes: downloaded > 0 ? downloaded : null,
      errorMessage: errorMessage,
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

  /// Process the download queue automatically
  void _processQueue() {
    final availableSlots = _maxConcurrentDownloads - _activeDownloads;

    if (availableSlots <= 0 || _downloadQueue.isEmpty) {
      return;
    }

    // Get items to start (up to available slots)
    final toStart = _downloadQueue.take(availableSlots).toList();

    for (final item in toStart) {
      // ignore: discarded_futures
      _isNetworkSuitable().then((suitable) {
        if (!suitable) {
          _logger.debug(
            'Network unsuitable; deferring queued download: ${item.chartId}',
            context: 'Download',
          );
          _scheduleNetworkRetry();
          return; // keep item queued
        }
        _logger.debug(
          'Network suitable; initiating queued download: ${item.chartId}',
          context: 'Download',
        );
        if (_downloadProgress.containsKey(item.chartId) &&
            _downloadProgress[item.chartId]!.status ==
                DownloadStatus.downloading) {
          return;
        }
        _startQueuedDownload(item).catchError((e) {
          _logger.error(
            'Failed to start queued download: ${item.chartId}',
            exception: e,
            context: 'Download',
          );
        });
      });
    }
  }

  void _scheduleNetworkRetry() {
    if (_networkRetryTimer?.isActive == true) return;
    _networkRetryTimer = Timer(_networkRetryInterval, () {
      _logger.debug(
        'Retrying deferred downloads after network unsuitability window',
        context: 'Download',
      );
      _processQueue();
    });
  }

  /// Start a queued download item
  Future<void> _startQueuedDownload(QueueItem item) async {
    try {
      // Remove from queue
      _downloadQueue.removeWhere(
        (queueItem) => queueItem.chartId == item.chartId,
      );

      // Start the download
      await downloadChart(
        item.chartId,
        item.url,
        expectedChecksum: item.expectedChecksum,
      );
    } catch (e) {
      _logger.error(
        'Failed to start queued download: ${item.chartId}',
        exception: e,
        context: 'Download',
      );
      rethrow;
    }
  }

  /// Save resume data
  void _saveResumeData(
    String chartId,
    String url,
    int downloadedBytes, {
    String? checksum,
  }) {
    final existing = _resumeData[chartId];
    _resumeData[chartId] = ResumeData(
      chartId: chartId,
      originalUrl: url,
      downloadedBytes: downloadedBytes,
      lastAttempt: DateTime.now(),
      checksum: checksum ?? existing?.checksum,
      supportsRange: existing?.supportsRange,
      attempts: (existing?.attempts ?? 0) + 1,
      lastErrorCode: existing?.lastErrorCode,
    );

    // Persist to disk for background recovery
    _savePersistentState().catchError((e) {
      _logger.warning('Failed to persist resume data: $e', context: 'Download');
    });
  }

  /// Save resume data and explicitly set an error code (used on failures)
  void _saveResumeDataWithError(
    String chartId,
    String url,
    int downloadedBytes,
    int errorCode, {
    String? checksum,
  }) {
    final existing = _resumeData[chartId];
    _resumeData[chartId] = ResumeData(
      chartId: chartId,
      originalUrl: url,
      downloadedBytes: downloadedBytes,
      lastAttempt: DateTime.now(),
      checksum: checksum ?? existing?.checksum,
      supportsRange: existing?.supportsRange,
      attempts: (existing?.attempts ?? 0) + 1,
      lastErrorCode: errorCode,
    );
    _savePersistentState().catchError((e) {
      _logger.warning(
        'Failed to persist resume data (error variant): $e',
        context: 'Download',
      );
    });
  }

  int _classifyErrorCode(Object error) {
    if (error is AppError) {
      final msg = error.message.toLowerCase();
      if (msg.contains('checksum')) return DownloadErrorCode.checksumMismatch;
      if (msg.contains('insufficient disk space')) {
        return DownloadErrorCode.insufficientDiskSpace;
      }
      if (msg.contains('timeout')) return DownloadErrorCode.networkTimeout;
      switch (error.type) {
        case AppErrorType.network:
          return DownloadErrorCode.network;
        case AppErrorType.storage:
          return DownloadErrorCode.storage;
        default:
          return DownloadErrorCode.unknown;
      }
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return DownloadErrorCode.networkTimeout;
        default:
          return DownloadErrorCode.network;
      }
    }
    if (error is FileSystemException) {
      return DownloadErrorCode.storage;
    }
    return DownloadErrorCode.unknown;
  }

  /// Add notification
  void _addNotification(
    String chartId,
    String title,
    String message,
    DownloadStatus status,
  ) {
    _pendingNotifications.add(
      DownloadNotification(
        chartId: chartId,
        title: title,
        message: message,
        status: status,
        timestamp: DateTime.now(),
      ),
    );
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

  String _deriveErrorCategory(Object error) {
    if (error is AppError) {
      switch (error.type) {
        case AppErrorType.network:
          final msg = error.message.toLowerCase();
          if (msg.contains('timeout')) return 'timeout';
          return 'network';
        case AppErrorType.storage:
          final msg = error.message.toLowerCase();
          if (msg.contains('disk') || msg.contains('space')) return 'disk';
          return 'storage';
        default:
          return 'unknown';
      }
    } else if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'timeout';
      }
      return 'network';
    } else if (error is FileSystemException) {
      return 'disk';
    }
    return 'unknown';
  }

  Future<int> _getPartialBytes(
    String chartId,
    DownloadProgress? existing,
  ) async {
    try {
      final chartDirectory = await _storageService.getChartsDirectory();
      // Attempt to reconstruct filename from existing progress or resumeData
      final resume = _resumeData[chartId];
      final url = resume?.originalUrl;
      if (url == null) return existing?.downloadedBytes ?? 0;
      final fileName = _getFileNameFromUrl(url, chartId);
      final filePath = path.join(chartDirectory.path, '$fileName.part');
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return existing?.downloadedBytes ?? 0;
    } catch (_) {
      return existing?.downloadedBytes ?? 0;
    }
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
      _logger.warning(
        'Failed to extract filename from URL: $url',
        context: 'Download',
      );
    }

    return '$chartId.zip';
  }

  /// Format bytes for human-readable display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Calculate SHA-256 checksum of a file
  Future<String> _calculateFileChecksum(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      _logger.error(
        'Failed to calculate checksum for file: ${file.path}',
        exception: e,
        context: 'Download',
      );
      rethrow;
    }
  }

  /// Best-effort disk space preflight check.
  /// Currently returns true if unable to determine free space. We attempt
  /// a HEAD request to get content-length and compare with a conservative
  /// threshold (existing partial bytes + required remaining + 5MB buffer).
  Future<bool> _hasSufficientDiskSpace(String url) async {
    try {
      final headResponse = await _httpClient.head(url);
      final contentLengthHeader =
          headResponse.headers['content-length']?.firstOrNull;
      if (contentLengthHeader == null) return true; // can't determine size
      final totalBytes = int.tryParse(contentLengthHeader) ?? 0;
      if (totalBytes <= 0) return true;

      // Obtain charts directory path and approximate used partial bytes (sum of .part files)
      final dir = await _storageService.getChartsDirectory();
      int partialBytes = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          try {
            partialBytes += await entity.length();
          } catch (_) {}
        }
      }

      // We lack a cross-platform free disk space API in pure Dart (without FFI); accept download
      // if size is < 2GB and partial + new total < arbitrary 5GB safety threshold.
      final projected =
          partialBytes + totalBytes + 5 * 1024 * 1024; // add 5MB buffer
      if (projected < 5 * 1024 * 1024 * 1024) {
        return true;
      }
      return false; // Extremely large aggregate; reject
    } catch (e) {
      _logger.warning(
        'Disk space preflight fallback (allow) due to error: $e',
        context: 'Download',
      );
      return true; // fail open to avoid false negatives
    }
  }

  /// Probe server for HTTP Range support using a small Range request.
  Future<bool> _probeRangeSupport(String url) async {
    try {
      // Use a simple GET with Range: bytes=0-0
      final response = await _httpClient.get(
        url,
        options: Options(
          headers: {'Range': 'bytes=0-0'},
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (code) => code != null && code >= 200 && code < 400,
        ),
      );
      final accepts =
          response.statusCode == 206 ||
          response.headers['content-range'] != null;
      // Persist support flag on any associated resume entry
      final entry = _resumeData.values.firstWhereOrNull(
        (r) => r.originalUrl == url,
      );
      if (entry != null && entry.supportsRange != accepts) {
        _resumeData[entry.chartId] = ResumeData(
          chartId: entry.chartId,
          originalUrl: entry.originalUrl,
          downloadedBytes: entry.downloadedBytes,
          lastAttempt: entry.lastAttempt,
          checksum: entry.checksum,
          supportsRange: accepts,
          attempts: entry.attempts,
          lastErrorCode: entry.lastErrorCode,
        );
        // Persist asynchronously
        _savePersistentState();
      }
      return accepts;
    } catch (e) {
      _logger.warning(
        'Range probe failed (treat as not supported): $e',
        context: 'Download',
      );
      return false;
    }
  }

  /// Manual resume append streaming using an HTTP Range request starting at resumeFrom.
  Future<void> _appendResumeStream(
    String chartId,
    String url,
    String tempFilePath,
    int resumeFrom,
    CancelToken cancelToken,
    StreamController<double> progressController,
  ) async {
    final file = File(tempFilePath);
    final sink = file.openWrite(mode: FileMode.append);
    try {
      final response = await _httpClient.get(
        url,
        options: Options(
          headers: {'Range': 'bytes=$resumeFrom-'},
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200) {
        // Server ignored Range; restart full download by truncating file
        await sink.close();
        await file.writeAsBytes([]); // truncate
        resumeFrom = 0;
        _logger.warning(
          'Server returned 200 for ranged request; restarting full download for $chartId',
          context: 'Download',
        );
      } else if (response.statusCode == 206) {
        // Parse total size from Content-Range: bytes start-end/total
        int? totalBytes;
        final contentRange = response.headers['content-range']?.firstOrNull;
        if (contentRange != null) {
          final parts = contentRange.split('/');
          if (parts.length == 2) {
            totalBytes = int.tryParse(parts[1]);
          }
        }
        // Stream and append
        int receivedSinceResume = 0;
        final stream = (response.data as ResponseBody).stream;
        await for (final chunk in stream) {
          sink.add(chunk);
          receivedSinceResume += chunk.length;
          final downloaded = resumeFrom + receivedSinceResume;
          final progressNorm = (totalBytes != null && totalBytes > 0)
              ? downloaded / totalBytes
              : 0.0;
          _updateProgress(
            chartId,
            downloaded,
            totalBytes ?? 0,
            progressNorm,
            DownloadStatus.downloading,
          );
          if (!progressController.isClosed) {
            progressController.add(progressNorm);
          }
          _saveResumeData(chartId, url, downloaded);
        }
        await sink.flush();
        await sink.close();
        return;
      }

      // Fallback: perform normal download (overwrite existing temp file)
      await _httpClient.downloadFile(
        url,
        tempFilePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final progressNorm = total > 0 ? (received / total) : 0.0;
          _updateProgress(
            chartId,
            received,
            total,
            progressNorm,
            DownloadStatus.downloading,
          );
          if (total > 0) {
            _saveResumeData(chartId, url, received);
          }
          if (!progressController.isClosed) {
            progressController.add(progressNorm);
          }
        },
      );
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  /// Save persistent download state to disk
  Future<void> _savePersistentState() async {
    try {
      final storageDir = await _storageService.getChartsDirectory();
      final stateFile = File(
        path.join(storageDir.path, '.download_state.json'),
      );

      final state = {
        'downloads': _downloadProgress.map(
          (key, value) => MapEntry(key, {
            'chartId': value.chartId,
            'status': value.status.name,
            'progress': value.progress,
            'totalBytes': value.totalBytes,
            'downloadedBytes': value.downloadedBytes,
            'lastUpdated': value.lastUpdated.toIso8601String(),
          }),
        ),
        'resumeData': _resumeData.map(
          (key, value) => MapEntry(key, {
            'chartId': value.chartId,
            'originalUrl': value.originalUrl,
            'downloadedBytes': value.downloadedBytes,
            'lastAttempt': value.lastAttempt.toIso8601String(),
            'checksum': value.checksum,
            'supportsRange': value.supportsRange,
            'attempts': value.attempts,
            'lastErrorCode': value.lastErrorCode,
          }),
        ),
        'queue': _downloadQueue
            .map(
              (item) => {
                'chartId': item.chartId,
                'url': item.url,
                'priority': item.priority.name,
                'addedAt': item.addedAt.toIso8601String(),
                'expectedChecksum': item.expectedChecksum,
              },
            )
            .toList(),
      };

      await stateFile.writeAsString(jsonEncode(state));
      _logger.debug('Download state saved to disk', context: 'Download');
    } catch (e) {
      _logger.warning('Failed to save download state: $e', context: 'Download');
    }
  }

  /// Load persistent download state from disk
  Future<void> _loadPersistentState() async {
    try {
      final storageDir = await _storageService.getChartsDirectory();
      final stateFile = File(
        path.join(storageDir.path, '.download_state.json'),
      );

      if (!await stateFile.exists()) {
        _logger.debug(
          'No persistent download state found',
          context: 'Download',
        );
        return;
      }

      final stateJson = await stateFile.readAsString();
      final state = jsonDecode(stateJson) as Map<String, dynamic>;

      // Restore download progress
      if (state.containsKey('downloads')) {
        final downloads = state['downloads'] as Map<String, dynamic>;
        for (final entry in downloads.entries) {
          final data = entry.value as Map<String, dynamic>;
          _downloadProgress[entry.key] = DownloadProgress(
            chartId: data['chartId'],
            status: DownloadStatus.values.firstWhere(
              (s) => s.name == data['status'],
            ),
            progress: data['progress'],
            totalBytes: data['totalBytes'],
            downloadedBytes: data['downloadedBytes'],
            lastUpdated: DateTime.parse(data['lastUpdated']),
          );
        }
      }

      // Restore resume data
      if (state.containsKey('resumeData')) {
        final resumeData = state['resumeData'] as Map<String, dynamic>;
        for (final entry in resumeData.entries) {
          final data = entry.value as Map<String, dynamic>;
          _resumeData[entry.key] = ResumeData(
            chartId: data['chartId'],
            originalUrl: data['originalUrl'],
            downloadedBytes: data['downloadedBytes'],
            lastAttempt: DateTime.parse(data['lastAttempt']),
            checksum: data['checksum'],
            supportsRange: data['supportsRange'],
            attempts: data['attempts'] ?? 0,
            lastErrorCode: data['lastErrorCode'],
          );
        }
      }

      // Restore queue
      if (state.containsKey('queue')) {
        final queue = state['queue'] as List<dynamic>;
        _downloadQueue.clear();
        for (final item in queue) {
          final data = item as Map<String, dynamic>;
          _downloadQueue.add(
            QueueItem(
              chartId: data['chartId'],
              url: data['url'],
              priority: DownloadPriority.values.firstWhere(
                (p) => p.name == data['priority'],
              ),
              addedAt: DateTime.parse(data['addedAt']),
              expectedChecksum: data['expectedChecksum'],
            ),
          );
        }
      }

      _logger.info(
        'Download state loaded from disk: ${_downloadProgress.length} downloads, ${_resumeData.length} resume entries, ${_downloadQueue.length} queued',
        context: 'Download',
      );

      // Phase 2 follow-up: stale resume sweep (remove entries with no corresponding .part or with completed final file)
      await _sweepStaleResumeEntries(storageDir);
    } catch (e) {
      _logger.warning('Failed to load download state: $e', context: 'Download');
    }
  }

  /// Remove stale or invalid resume entries:
  /// - Missing .part file and no active download
  /// - Final file already exists and appears complete (>= downloadedBytes)
  /// - Recorded downloadedBytes mismatch actual .part length (correct it or purge if zero)
  Future<void> _sweepStaleResumeEntries(Directory storageDir) async {
    if (_resumeData.isEmpty) return;
    final toRemove = <String>[];
    bool mutated = false;
    for (final entry in _resumeData.values) {
      try {
        final fileName = _getFileNameFromUrl(entry.originalUrl, entry.chartId);
        final finalFile = File(path.join(storageDir.path, fileName));
        final partFile = File(path.join(storageDir.path, '$fileName.part'));
        final partExists = await partFile.exists();
        final finalExists = await finalFile.exists();
        if (!partExists && !finalExists) {
          // Nothing on disk -> stale
          toRemove.add(entry.chartId);
          continue;
        }
        if (finalExists) {
          final finalLen = await finalFile.length();
          if (finalLen >= entry.downloadedBytes) {
            // Completed; resume data no longer needed
            toRemove.add(entry.chartId);
            continue;
          }
        }
        if (partExists) {
          final partLen = await partFile.length();
          if (partLen == 0 && entry.downloadedBytes > 0) {
            // Corrupt partial; remove metadata and delete empty file
            toRemove.add(entry.chartId);
            try {
              await partFile.delete();
            } catch (_) {}
            continue;
          }
          if (partLen != entry.downloadedBytes) {
            // Adjust to actual size to avoid mismatch resume failure
            _resumeData[entry.chartId] = ResumeData(
              chartId: entry.chartId,
              originalUrl: entry.originalUrl,
              downloadedBytes: partLen,
              lastAttempt: entry.lastAttempt,
              checksum: entry.checksum,
              supportsRange: entry.supportsRange,
              attempts: entry.attempts,
              lastErrorCode: entry.lastErrorCode,
            );
            mutated = true;
          }
        }
      } catch (e) {
        _logger.warning(
          'Resume sweep error for ${entry.chartId}: $e',
          context: 'Download',
        );
      }
    }
    if (toRemove.isNotEmpty) {
      for (final id in toRemove) {
        _resumeData.remove(id);
      }
      mutated = true;
    }
    if (mutated) {
      _logger.info(
        'Stale resume sweep removed ${toRemove.length} entries; ${_resumeData.length} remain',
        context: 'Download',
      );
      // Persist updated state (fire and forget)
      _savePersistentState();
    }
  }

  @override
  void dispose() {
    _netStatusSub?.cancel();
    _networkRetryTimer?.cancel();
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

  void _initNetworkListener() {
    if (_networkResilience == null) return;
    _netStatusSub = _networkResilience!.networkStatusStream.listen(
      _handleNetworkStatusChange,
    );
  }

  bool _isTransientCategory(String? category) {
    if (category == null) return false;
    return ['network', 'timeout'].contains(category);
  }

  void _handleNetworkStatusChange(NetworkStatus status) {
    if (status == NetworkStatus.connected || status == NetworkStatus.limited) {
      for (final entry in _downloadProgress.entries) {
        final prog = entry.value;
        if (prog.status == DownloadStatus.failed &&
            _isTransientCategory(prog.errorCategory)) {
          final resume = _resumeData[prog.chartId];
          final url = resume?.originalUrl;
          if (url != null) {
            // ignore: discarded_futures
            addToQueue(prog.chartId, url);
          }
        }
      }
    }
  }

  // ---------------- Testing Hooks ----------------
  @visibleForTesting
  Map<String, DownloadProgress> get debugProgressMap =>
      Map.unmodifiable(_downloadProgress);

  @visibleForTesting
  List<String> get debugQueueIds =>
      _downloadQueue.map((e) => e.chartId).toList(growable: false);

  /// Inject a failed download state for auto-retry tests
  @visibleForTesting
  void injectFailedDownload(
    String chartId,
    String url, {
    String category = 'network',
  }) {
    _downloadProgress[chartId] = DownloadProgress(
      chartId: chartId,
      status: DownloadStatus.failed,
      progress: 0.0,
      errorMessage: 'Simulated failure',
      errorCategory: category,
      lastUpdated: DateTime.now(),
    );
    _resumeData[chartId] = ResumeData(
      chartId: chartId,
      originalUrl: url,
      downloadedBytes: 0,
      lastAttempt: DateTime.now(),
    );
  }

  /// Manually simulate network status (test helper)
  @visibleForTesting
  void simulateNetworkStatus(NetworkStatus status) {
    _handleNetworkStatusChange(status);
  }

  // ---- Filesystem mitigation helpers (Phase E) ----

  /// Removes any existing entity at the target path (file or directory) with retries.
  Future<void> _prepareFinalPath(File finalFile) async {
    final pathStr = finalFile.path;
    final entityType = await FileSystemEntity.type(pathStr);
    if (entityType == FileSystemEntityType.notFound) return;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (entityType == FileSystemEntityType.directory) {
          // Unexpected: a directory where a file should be.
          _logger.warning(
            'Directory exists at target file path; removing: $pathStr',
            context: 'Download',
          );
          final dir = Directory(pathStr);
          if (await dir.exists()) await dir.delete(recursive: true);
        } else if (entityType == FileSystemEntityType.file) {
          final existing = File(pathStr);
          if (await existing.exists()) await existing.delete();
        } else {
          // Symlink or other: attempt generic delete.
          final fse = FileSystemEntity.typeSync(pathStr);
          if (fse != FileSystemEntityType.notFound) {
            try {
              await File(pathStr).delete();
            } catch (_) {}
            try {
              await Directory(pathStr).delete(recursive: true);
            } catch (_) {}
          }
        }
        return; // success or path gone
      } catch (e) {
        if (attempt == 2) {
          _logger.warning(
            'Failed to clear existing target path after retries: $pathStr',
            context: 'Download',
          );
          rethrow;
        }
        final backoff = Duration(milliseconds: 30 * (attempt + 1));
        await Future.delayed(backoff);
      }
    }
  }

  /// Performs a safe rename with small retry/backoff; falls back to copy+delete if rename keeps failing.
  Future<void> _safeRename(File tempFile, String finalPath) async {
    const int maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (_renameImpl != null) {
          await _renameImpl!(tempFile, finalPath);
        } else {
          await tempFile.rename(finalPath);
        }
        return;
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          _logger.warning(
            'Rename failed after retries; attempting copy fallback for $finalPath',
            context: 'Download',
          );
          try {
            final target = File(finalPath);
            await target.writeAsBytes(
              await tempFile.readAsBytes(),
              flush: true,
            );
            await tempFile.delete();
            return;
          } catch (copyError) {
            _logger.error(
              'Copy fallback failed for $finalPath',
              exception: copyError,
              context: 'Download',
            );
            rethrow;
          }
        } else {
          final delay = Duration(milliseconds: 40 * (attempt + 1));
          await Future.delayed(delay);
        }
      }
    }
  }
}
