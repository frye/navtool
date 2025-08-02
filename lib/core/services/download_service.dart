/// Service interface for download operations
abstract class DownloadService {
  /// Downloads a chart from the specified URL
  Future<void> downloadChart(String chartId, String url);

  /// Pauses an ongoing download
  Future<void> pauseDownload(String chartId);

  /// Resumes a paused download
  Future<void> resumeDownload(String chartId);

  /// Cancels a download
  Future<void> cancelDownload(String chartId);

  /// Gets the current download queue
  Future<List<String>> getDownloadQueue();

  /// Gets download progress for a specific chart
  Stream<double> getDownloadProgress(String chartId);
}
