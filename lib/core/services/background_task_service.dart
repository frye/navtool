// Export the implementation for testing
export 'background_task_service_impl.dart';

/// Service interface for managing background tasks in marine navigation
abstract class BackgroundTaskService {
  /// Initialize the background task manager
  Future<void> initialize({bool isDebugMode = false});

  /// Register periodic chart download task (runs every 6 hours when connected)
  Future<void> registerChartDownloadTask();

  /// Schedule a specific chart for background download
  Future<void> scheduleChartDownload(String chartId);

  /// Cancel a specific chart download task
  Future<void> cancelChartDownload(String chartId);

  /// Register periodic GPS tracking task (runs every 15 minutes)
  Future<void> registerGpsTrackingTask();

  /// Start recording a route in the background (every 1 minute)
  Future<void> startRouteRecording(String routeId);

  /// Stop recording a route
  Future<void> stopRouteRecording(String routeId);

  /// Register periodic weather update task (runs every 3 hours when connected)
  Future<void> registerWeatherUpdateTask();

  /// Cancel all background tasks
  Future<void> cancelAllTasks();

  /// Get the number of active background tasks
  int getActiveTaskCount();
}

/// Exception thrown when background task operations fail
class BackgroundTaskException implements Exception {
  final String message;
  final Exception? cause;

  const BackgroundTaskException(this.message, [this.cause]);

  @override
  String toString() => 'BackgroundTaskException: $message${cause != null ? ' ($cause)' : ''}';
}
