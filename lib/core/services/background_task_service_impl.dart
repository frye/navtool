import 'package:workmanager/workmanager.dart';
import '../logging/app_logger.dart';
import '../services/download_service.dart';
import '../services/gps_service.dart';
import 'background_task_service.dart';

/// Implementation of BackgroundTaskService using workmanager
class BackgroundTaskServiceImpl implements BackgroundTaskService {
  final Workmanager _workmanager;
  final DownloadService _downloadService; // ignore: unused_field
  final GpsService _gpsService; // ignore: unused_field
  final AppLogger _logger;

  // Track active tasks (workmanager doesn't provide this natively)
  int _activeTaskCount = 0;

  BackgroundTaskServiceImpl({
    Workmanager? workmanager,
    required DownloadService downloadService,
    required GpsService gpsService,
    required AppLogger logger,
  })  : _workmanager = workmanager ?? Workmanager(),
        _downloadService = downloadService,
        _gpsService = gpsService,
        _logger = logger;

  @override
  Future<void> initialize({bool isDebugMode = false}) async {
    try {
      await _workmanager.initialize(
        callbackDispatcher,
        isInDebugMode: isDebugMode,
      );
      _logger.info('Background task service initialized');
    } catch (e) {
      _logger.error('Failed to initialize background task service: $e');
      throw BackgroundTaskException('Failed to initialize workmanager', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> registerChartDownloadTask() async {
    try {
      await _workmanager.registerPeriodicTask(
        'chartDownloadTask',
        'chartDownload',
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
      _activeTaskCount++;
      _logger.info('Chart download task registered');
    } catch (e) {
      _logger.error('Failed to register chart download task: $e');
      throw BackgroundTaskException('Failed to register chart download task', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> scheduleChartDownload(String chartId) async {
    try {
      await _workmanager.registerOneOffTask(
        'downloadChart_$chartId',
        'downloadSingleChart',
        inputData: {'chartId': chartId},
      );
      _activeTaskCount++;
      _logger.info('Chart download scheduled for chart: $chartId');
    } catch (e) {
      _logger.error('Failed to schedule chart download for $chartId: $e');
      throw BackgroundTaskException('Failed to schedule chart download', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> cancelChartDownload(String chartId) async {
    try {
      await _workmanager.cancelByUniqueName('downloadChart_$chartId');
      _activeTaskCount = (_activeTaskCount - 1).clamp(0, double.infinity).toInt();
      _logger.info('Chart download cancelled for chart: $chartId');
    } catch (e) {
      _logger.error('Failed to cancel chart download for $chartId: $e');
      throw BackgroundTaskException('Failed to cancel chart download', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> registerGpsTrackingTask() async {
    try {
      await _workmanager.registerPeriodicTask(
        'gpsTrackingTask',
        'gpsTracking',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false, // GPS tracking is critical for marine safety
        ),
      );
      _activeTaskCount++;
      _logger.info('GPS tracking task registered');
    } catch (e) {
      _logger.error('Failed to register GPS tracking task: $e');
      throw BackgroundTaskException('Failed to register GPS tracking task', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> startRouteRecording(String routeId) async {
    try {
      await _workmanager.registerPeriodicTask(
        'routeRecording_$routeId',
        'recordRoute',
        frequency: const Duration(minutes: 1),
        inputData: {'routeId': routeId},
      );
      _activeTaskCount++;
      _logger.info('Route recording started for route: $routeId');
    } catch (e) {
      _logger.error('Failed to start route recording for $routeId: $e');
      throw BackgroundTaskException('Failed to start route recording', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> stopRouteRecording(String routeId) async {
    try {
      await _workmanager.cancelByUniqueName('routeRecording_$routeId');
      _activeTaskCount = (_activeTaskCount - 1).clamp(0, double.infinity).toInt();
      _logger.info('Route recording stopped for route: $routeId');
    } catch (e) {
      _logger.error('Failed to stop route recording for $routeId: $e');
      throw BackgroundTaskException('Failed to stop route recording', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> registerWeatherUpdateTask() async {
    try {
      await _workmanager.registerPeriodicTask(
        'weatherUpdateTask',
        'weatherUpdate',
        frequency: const Duration(hours: 3),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
      _activeTaskCount++;
      _logger.info('Weather update task registered');
    } catch (e) {
      _logger.error('Failed to register weather update task: $e');
      throw BackgroundTaskException('Failed to register weather update task', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  Future<void> cancelAllTasks() async {
    try {
      await _workmanager.cancelAll();
      _activeTaskCount = 0;
      _logger.info('All background tasks cancelled');
    } catch (e) {
      _logger.error('Failed to cancel all background tasks: $e');
      throw BackgroundTaskException('Failed to cancel all tasks', e is Exception ? e : Exception(e.toString()));
    }
  }

  @override
  int getActiveTaskCount() => _activeTaskCount;
}

/// Background task callback dispatcher
/// This function runs in a separate isolate and handles background task execution
@pragma('vm:entry-point')
void callbackDispatcher() {
  // Create a lightweight logger suitable for the background isolate.
  // We can't reuse dependency injection here; construct a ConsoleLogger directly.
  // Using a top-level static so helper functions can reuse the same instance.
  _backgroundLogger ??= ConsoleLogger(minimumLevel: LogLevel.info);
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'chartDownload':
        return await _handleChartDownloadTask(inputData);
      case 'downloadSingleChart':
        return await _handleSingleChartDownload(inputData);
      case 'gpsTracking':
        return await _handleGpsTrackingTask(inputData);
      case 'recordRoute':
        return await _handleRouteRecordingTask(inputData);
      case 'weatherUpdate':
        return await _handleWeatherUpdateTask(inputData);
      default:
        _backgroundLogger?.warning('Unknown background task: $task', context: 'BackgroundTask');
        return false;
    }
  });
}

// Lazily initialized background isolate logger
AppLogger? _backgroundLogger;

/// Handle periodic chart download task
Future<bool> _handleChartDownloadTask(Map<String, dynamic>? inputData) async {
  try {
    _backgroundLogger?.info('Executing background chart download task', context: 'BackgroundTask');
    // TODO: Implement chart download queue processing
    // This would check for pending downloads and process them
    return true;
  } catch (e) {
    _backgroundLogger?.error('Chart download task failed', context: 'BackgroundTask', exception: e);
    return false;
  }
}

/// Handle single chart download task
Future<bool> _handleSingleChartDownload(Map<String, dynamic>? inputData) async {
  try {
    final chartId = inputData?['chartId'] as String?;
    if (chartId == null) {
      _backgroundLogger?.warning('No chartId provided for single chart download', context: 'BackgroundTask');
      return false;
    }
    _backgroundLogger?.info('Executing background download for chart: $chartId', context: 'BackgroundTask');
    // TODO: Implement single chart download
    return true;
  } catch (e) {
    _backgroundLogger?.error('Single chart download task failed', context: 'BackgroundTask', exception: e);
    return false;
  }
}

/// Handle GPS tracking task
Future<bool> _handleGpsTrackingTask(Map<String, dynamic>? inputData) async {
  try {
    _backgroundLogger?.info('Executing background GPS tracking task', context: 'BackgroundTask');
    // TODO: Implement GPS position logging
    // This would get current position and store it for tracking
    return true;
  } catch (e) {
    _backgroundLogger?.error('GPS tracking task failed', context: 'BackgroundTask', exception: e);
    return false;
  }
}

/// Handle route recording task
Future<bool> _handleRouteRecordingTask(Map<String, dynamic>? inputData) async {
  try {
    final routeId = inputData?['routeId'] as String?;
    if (routeId == null) {
      _backgroundLogger?.warning('No routeId provided for route recording', context: 'BackgroundTask');
      return false;
    }
    _backgroundLogger?.info('Executing background route recording for route: $routeId', context: 'BackgroundTask');
    // TODO: Implement route recording
    // This would get current position and add it to the route track
    return true;
  } catch (e) {
    _backgroundLogger?.error('Route recording task failed', context: 'BackgroundTask', exception: e);
    return false;
  }
}

/// Handle weather update task
Future<bool> _handleWeatherUpdateTask(Map<String, dynamic>? inputData) async {
  try {
    _backgroundLogger?.info('Executing background weather update task', context: 'BackgroundTask');
    // TODO: Implement weather data updates
    // This would fetch latest weather data for the user's location
    return true;
  } catch (e) {
    _backgroundLogger?.error('Weather update task failed', context: 'BackgroundTask', exception: e);
    return false;
  }
}
