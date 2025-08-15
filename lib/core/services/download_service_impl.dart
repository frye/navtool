import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import '../logging/app_logger.dart';
import '../error/app_error.dart';
import '../error/error_handler.dart';
import '../state/download_state.dart';
import 'download_service.dart';
import 'http_client_service.dart';
import 'storage_service.dart';

/// Concrete implementation of DownloadService using HTTP client
class DownloadServiceImpl implements DownloadService {
  final HttpClientService _httpClient;
  final StorageService _storageService;
  final AppLogger _logger;
  final ErrorHandler _errorHandler;

  // Download state management
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<double>> _progressControllers = {};
  final Map<String, DownloadProgress> _downloadProgress = {};
  final List<String> _downloadQueue = [];

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
  Future<void> downloadChart(String chartId, String url) async {
    try {
      _logger.info('Starting download for chart: $chartId', context: 'Download');

      // Add to queue if not already present
      if (!_downloadQueue.contains(chartId)) {
        _downloadQueue.add(chartId);
      }

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

      // Start download with progress tracking
      await _httpClient.downloadFile(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final percentage = total > 0 ? (received / total) * 100 : 0.0;
          _updateProgress(chartId, received, total, percentage, DownloadStatus.downloading);
          
          // Update progress stream
          if (!progressController.isClosed) {
            progressController.add(percentage);
          }
        },
      );

      // Verify downloaded file
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        _logger.info(
          'Chart download completed: $chartId (${_formatBytes(fileSize)})',
          context: 'Download',
        );

        // Mark as completed
        _updateProgress(chartId, fileSize, fileSize, 100.0, DownloadStatus.completed);
        progressController.add(100.0);
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

      // Handle error and clean up
      _errorHandler.handleError(error, stackTrace);
      _cleanup(chartId);
      
      rethrow;
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
  Future<void> resumeDownload(String chartId) async {
    try {
      // For now, restart the download
      // TODO: Implement actual resume functionality with partial content support
      final progress = _downloadProgress[chartId];
      if (progress != null && progress.status == DownloadStatus.paused) {
        _logger.info('Resuming download: $chartId', context: 'Download');
        // This would require storing the original URL and implementing range requests
        throw AppError.network('Download resume not yet implemented. Please restart the download.');
      }
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
      _downloadQueue.remove(chartId);
      
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
    return List.from(_downloadQueue);
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
      return Stream.value(progress.progress * 100.0); // Convert back to percentage
    }
    
    // Return empty stream
    return const Stream.empty();
  }

  /// Get detailed download progress information
  DownloadProgress? getDetailedProgress(String chartId) {
    return _downloadProgress[chartId];
  }

  /// Get all current download progress
  Map<String, DownloadProgress> getAllProgress() {
    return Map.from(_downloadProgress);
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
      progress: percentage / 100.0, // Convert percentage to 0.0-1.0 range
      totalBytes: total > 0 ? total : null,
      downloadedBytes: downloaded > 0 ? downloaded : null,
      lastUpdated: DateTime.now(),
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
    _downloadQueue.remove(chartId);
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

    // Generate filename based on chart ID
    return '$chartId.zip'; // NOAA charts are typically distributed as ZIP files
  }

  /// Format bytes for human-readable display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Dispose of all resources
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

    // Clear all state
    _cancelTokens.clear();
    _progressControllers.clear();
    _downloadProgress.clear();
    _downloadQueue.clear();

    _logger.info('Download service disposed', context: 'Download');
  }
}