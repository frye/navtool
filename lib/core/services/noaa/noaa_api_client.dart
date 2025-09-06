import 'dart:async';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';

/// Progress callback function type for download operations
///
/// [progress] Value from 0.0 (0%) to 1.0 (100%) indicating download completion
typedef NoaaProgressCallback = void Function(double progress);

/// Abstract interface for NOAA API client operations
///
/// Provides comprehensive access to NOAA Electronic Navigational Chart (ENC) services
/// including catalog browsing, chart metadata retrieval, and S-57 chart file downloads.
///
/// **Key Features:**
/// - Built-in rate limiting to respect NOAA server constraints
/// - Automatic retry logic for transient failures
/// - Comprehensive error handling with marine-specific messages
/// - Progress tracking for large chart downloads
/// - Support for concurrent operations with proper resource management
///
/// **Marine Environment Optimizations:**
/// - Extended timeouts for satellite internet connections
/// - Intelligent error classification for network conditions
/// - Download cancellation and cleanup for bandwidth management
/// - Progress streams for monitoring multiple downloads
///
/// **Example Usage:**
/// ```dart
/// final noaaClient = NoaaApiClientImpl(
///   httpClient: httpClient,
///   rateLimiter: rateLimiter,
///   logger: logger,
/// );
///
/// // Fetch chart catalog for a specific region
/// final catalog = await noaaClient.fetchChartCatalog(
///   filters: {'STATE': 'California', 'USAGE': 'Harbor'}
/// );
///
/// // Download a chart with progress tracking
/// await noaaClient.downloadChart(
///   'US5CA52M',
///   '/path/to/charts/US5CA52M.zip',
///   onProgress: (progress) => print('${(progress * 100).round()}%'),
/// );
/// ```
abstract class NoaaApiClient {
  /// Fetches the complete NOAA chart catalog in GeoJSON format
  ///
  /// Retrieves chart metadata from NOAA's maritime chart services,
  /// optionally filtered by geographic region, chart type, or other criteria.
  ///
  /// **Parameters:**
  /// - [filters] Optional query parameters for filtering results:
  ///   - `'STATE'`: Filter by US state (e.g., 'California', 'Florida')
  ///   - `'USAGE'`: Filter by chart usage type ('Harbor', 'Approach', 'Coastal')
  ///   - `'SCALE'`: Filter by chart scale range
  ///   - Custom filters as supported by NOAA services
  ///
  /// **Returns:**
  /// Raw GeoJSON string containing chart features with complete metadata
  ///
  /// **Throws:**
  /// - [NoaaApiException] for general API errors
  /// - [RateLimitExceededException] if rate limits are exceeded
  /// - [NetworkConnectivityException] for network connectivity issues
  /// - [NoaaServiceUnavailableException] if NOAA services are down
  ///
  /// **Example:**
  /// ```dart
  /// final catalog = await client.fetchChartCatalog(
  ///   filters: {'STATE': 'California', 'USAGE': 'Harbor'}
  /// );
  /// ```
  Future<String> fetchChartCatalog({Map<String, String>? filters});

  /// Retrieves detailed metadata for a specific chart by cell name
  ///
  /// Fetches comprehensive chart information including geographic bounds,
  /// scale, last update date, and chart classification.
  ///
  /// **Parameters:**
  /// - [cellName] The NOAA chart cell identifier (e.g., 'US5CA52M' for San Francisco Bay)
  ///
  /// **Returns:**
  /// [Chart] object with complete metadata, or `null` if chart doesn't exist
  ///
  /// **Throws:**
  /// - [NoaaApiException] for API communication errors
  /// - [ChartNotAvailableException] if the chart has been discontinued
  /// - [NetworkConnectivityException] for network issues
  ///
  /// **Chart Cell Name Format:**
  /// - US[scale][region][number][usage]: e.g., US5CA52M
  ///   - Scale: 1-9 (1=largest scale/harbor, 9=smallest scale/overview)
  ///   - Region: 2-letter code (CA=California, FL=Florida, etc.)
  ///   - Number: Sequential identifier within region
  ///   - Usage: M=Harbor, A=Approach, C=Coastal, G=General, O=Overview
  Future<Chart?> getChartMetadata(String cellName);

  /// Checks chart availability without downloading full metadata
  ///
  /// Performs an efficient availability check using HTTP HEAD requests
  /// to verify that a chart exists and is downloadable.
  ///
  /// **Parameters:**
  /// - [cellName] The chart cell identifier to check
  ///
  /// **Returns:**
  /// `true` if chart is available for download, `false` otherwise
  ///
  /// **Performance Note:**
  /// This method is more efficient than [getChartMetadata] when you only
  /// need to verify chart existence before initiating downloads.
  Future<bool> isChartAvailable(String cellName);

  /// Downloads an S-57 format chart file with progress tracking
  ///
  /// Downloads the complete Electronic Navigational Chart (ENC) file
  /// in S-57 format, suitable for use with marine navigation software.
  ///
  /// **Parameters:**
  /// - [cellName] The chart cell identifier to download
  /// - [savePath] Local file system path where chart should be saved
  /// - [onProgress] Optional callback for real-time progress updates (0.0 to 1.0)
  ///
  /// **File Format:**
  /// Downloaded files are ZIP archives containing:
  /// - S-57 chart data (.000 files)
  /// - Metadata and cataloging information
  /// - Digital signatures for integrity verification
  ///
  /// **Download Management:**
  /// - Automatic resume for interrupted downloads
  /// - Integrity verification using checksums
  /// - Cleanup of partial downloads on cancellation
  /// - Rate limiting to prevent server overload
  ///
  /// **Throws:**
  /// - [ChartDownloadException] for download failures
  /// - [ChartNotAvailableException] if chart doesn't exist
  /// - [NetworkConnectivityException] for network issues
  /// - [RateLimitExceededException] if download rate limits are exceeded
  ///
  /// **Example:**
  /// ```dart
  /// await client.downloadChart(
  ///   'US5CA52M',
  ///   '/charts/US5CA52M.zip',
  ///   onProgress: (progress) {
  ///     print('Download: ${(progress * 100).toStringAsFixed(1)}%');
  ///   },
  /// );
  /// ```
  Future<void> downloadChart(
    String cellName,
    String savePath, {
    NoaaProgressCallback? onProgress,
  });

  /// Provides a progress stream for monitoring ongoing downloads
  ///
  /// Returns a broadcast stream that emits progress values (0.0 to 1.0)
  /// during active downloads for the specified chart.
  ///
  /// **Parameters:**
  /// - [cellName] The chart cell identifier being downloaded
  ///
  /// **Returns:**
  /// Stream of progress values from 0.0 (starting) to 1.0 (complete)
  ///
  /// **Stream Behavior:**
  /// - Emits progress updates during active downloads
  /// - Completes when download finishes successfully
  /// - Emits error if download fails
  /// - Returns empty stream if no download is in progress
  ///
  /// **Multiple Listeners:**
  /// The stream is broadcast-enabled, allowing multiple widgets or
  /// services to monitor the same download progress simultaneously.
  ///
  /// **Example:**
  /// ```dart
  /// client.getDownloadProgress('US5CA52M').listen(
  ///   (progress) => updateProgressBar(progress),
  ///   onDone: () => showDownloadComplete(),
  ///   onError: (error) => showDownloadError(error),
  /// );
  /// ```
  Stream<double> getDownloadProgress(String cellName);

  /// Cancels an ongoing download operation
  ///
  /// Immediately stops the download, cleans up temporary files,
  /// and releases network resources.
  ///
  /// **Parameters:**
  /// - [cellName] The chart cell identifier to cancel
  ///
  /// **Behavior:**
  /// - Immediately cancels active HTTP requests
  /// - Cleans up partial download files
  /// - Closes progress streams
  /// - Completes successfully even if no download is in progress
  ///
  /// **Resource Cleanup:**
  /// All associated resources are properly cleaned up:
  /// - Network connections are closed
  /// - Temporary files are removed
  /// - Progress streams are completed
  /// - Cancel tokens are invalidated
  ///
  /// **Example:**
  /// ```dart
  /// // Start download
  /// final downloadFuture = client.downloadChart('US5CA52M', '/path/chart.zip');
  ///
  /// // Cancel if needed
  /// await client.cancelDownload('US5CA52M');
  /// ```
  Future<void> cancelDownload(String cellName);
}
