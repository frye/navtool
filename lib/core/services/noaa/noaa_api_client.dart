import 'dart:async';
import 'package:navtool/core/models/chart.dart';

/// Progress callback function type for download operations
typedef NoaaProgressCallback = void Function(double progress);

/// Abstract interface for NOAA API client operations
/// 
/// Provides access to NOAA chart catalog, metadata, and download operations
/// with built-in rate limiting, retry logic, and comprehensive error handling.
abstract class NoaaApiClient {
  /// Fetches the complete NOAA chart catalog in GeoJSON format
  /// 
  /// [filters] Optional query parameters to filter the catalog results
  /// Returns the raw GeoJSON string response from NOAA servers
  /// 
  /// Throws [NoaaApiException] for API errors
  /// Throws [RateLimitExceededException] if rate limits are exceeded
  /// Throws [NetworkConnectivityException] for network issues
  Future<String> fetchChartCatalog({Map<String, String>? filters});

  /// Gets metadata for a specific chart by cell name
  /// 
  /// [cellName] The NOAA chart cell name (e.g., 'US5CA52M')
  /// Returns a [Chart] object with full metadata, or null if not found
  /// 
  /// Throws [NoaaApiException] for API errors
  /// Throws [ChartNotAvailableException] if chart doesn't exist
  Future<Chart?> getChartMetadata(String cellName);

  /// Checks if a chart is available for download
  /// 
  /// [cellName] The NOAA chart cell name to check
  /// Returns true if the chart is available, false otherwise
  /// 
  /// This is more efficient than getChartMetadata for availability checking
  Future<bool> isChartAvailable(String cellName);

  /// Downloads a chart file with progress tracking
  /// 
  /// [cellName] The NOAA chart cell name to download
  /// [savePath] Local file path where the chart should be saved
  /// [onProgress] Optional callback for download progress (0.0 to 1.0)
  /// 
  /// Throws [ChartDownloadException] for download failures
  /// Throws [ChartNotAvailableException] if chart doesn't exist
  Future<void> downloadChart(
    String cellName, 
    String savePath, {
    NoaaProgressCallback? onProgress,
  });

  /// Gets a progress stream for an ongoing download
  /// 
  /// [cellName] The chart cell name being downloaded
  /// Returns a stream of progress values from 0.0 to 1.0
  /// 
  /// The stream will emit updates during active downloads and complete
  /// when the download finishes or is cancelled.
  Stream<double> getDownloadProgress(String cellName);

  /// Cancels an ongoing download operation
  /// 
  /// [cellName] The chart cell name to cancel
  /// 
  /// If no download is in progress for the specified chart,
  /// this operation completes successfully without error.
  Future<void> cancelDownload(String cellName);
}