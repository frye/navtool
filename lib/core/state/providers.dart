import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../logging/app_logger.dart';
import '../error/error_handler.dart';
import '../models/gps_position.dart';
import '../models/chart.dart';
import '../models/route.dart';
import '../models/waypoint.dart';
import '../services/http_client_service.dart';
import '../services/download_service.dart';
import '../services/download_service_impl.dart';
import '../services/download_metrics_collector.dart';
import '../services/storage_service.dart';
import '../services/database_storage_service.dart';
import '../services/file_system_service.dart';
import '../services/cache_service.dart';
import '../services/cache_service_impl.dart';
import '../services/gps_service.dart';
// Cross-platform GPS implementations
import '../services/gps_service_impl.dart'; // Geolocator-based (macOS, Linux, iOS, Android)
import '../services/gps_service_win32.dart'; // Windows-specific
import '../services/background_task_service.dart';
import '../services/compression_service.dart';
import '../services/compression_service_impl.dart';
import '../services/chart_service.dart';
import '../services/chart_service_impl.dart';
import '../services/navigation_service.dart';
import '../services/navigation_service_impl.dart';
import '../services/settings_service.dart';
import '../services/settings_service_impl.dart';
import 'app_state.dart';
import 'app_state_notifier.dart';
import 'download_state.dart';
import 'settings_state.dart';
import '../utils/network_resilience.dart';

// Dependencies
final loggerProvider = Provider<AppLogger>((ref) => const ConsoleLogger());
final errorHandlerProvider = Provider<ErrorHandler>(
  (ref) => ErrorHandler(logger: ref.read(loggerProvider)),
);

// GPS Service - Platform-specific implementation
final gpsServiceProvider = Provider<GpsService>((ref) {
  final logger = ref.read(loggerProvider);

  // Always use Windows-specific implementation on Windows to avoid geolocator CMake issues
  if (defaultTargetPlatform == TargetPlatform.windows) {
    logger.info('Using Windows-specific GPS implementation (Win32)');
    return GpsServiceWin32(logger: logger);
  } else {
    // Use geolocator for macOS, Linux, iOS, Android
    logger.info('Using geolocator-based GPS implementation');
    return GpsServiceImpl(logger: logger);
  }
});

// Background Task Service
final backgroundTaskServiceProvider = Provider<BackgroundTaskService>((ref) {
  return BackgroundTaskServiceImpl(
    workmanager: Workmanager(),
    downloadService: ref.read(downloadServiceProvider),
    gpsService: ref.read(gpsServiceProvider),
    logger: ref.read(loggerProvider),
  );
});

// HTTP and Network Services
final httpClientServiceProvider = Provider<HttpClientService>((ref) {
  final service = HttpClientService(logger: ref.read(loggerProvider));
  // Configure for NOAA endpoints
  service.configureNoaaEndpoints();
  service.configureCertificatePinning();
  return service;
});

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadServiceImpl(
    httpClient: ref.read(httpClientServiceProvider),
    storageService: ref.read(storageServiceProvider),
    logger: ref.read(loggerProvider),
    errorHandler: ref.read(errorHandlerProvider),
    queueNotifier: ref.read(downloadQueueProvider.notifier),
    metrics: ref.read(downloadMetricsCollectorProvider),
    networkResilience: ref.read(networkResilienceProvider),
  );
  return service;
});

// Download metrics collector
final downloadMetricsCollectorProvider = Provider<DownloadMetricsCollector>((
  ref,
) {
  return DownloadMetricsCollector();
});

// Reactive metrics snapshot provider (simple polling every 1s)
final downloadMetricsSnapshotProvider = StreamProvider.autoDispose((
  ref,
) async* {
  final collector = ref.watch(downloadMetricsCollectorProvider);
  while (true) {
    await Future.delayed(const Duration(seconds: 1));
    yield collector.snapshot();
  }
});

final networkResilienceProvider = Provider<NetworkResilience>((ref) {
  // Single shared instance; starts monitoring when constructed
  return NetworkResilience();
});

// Storage service (placeholder - should be implemented)
final storageServiceProvider = Provider<StorageService>((ref) {
  final service = DatabaseStorageService(logger: ref.read(loggerProvider));
  // Initialize the database asynchronously
  service.initialize().catchError((error) {
    ref.read(loggerProvider).error('Failed to initialize database: $error');
  });
  return service;
});

// File system service
final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  return FileSystemService(logger: ref.read(loggerProvider));
});

// Cache service
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheServiceImpl(
    logger: ref.read(loggerProvider),
    fileSystemService: ref.read(fileSystemServiceProvider),
    compressionService: ref.read(compressionServiceProvider),
  );
});

// Compression service
final compressionServiceProvider = Provider<CompressionService>((ref) {
  return CompressionServiceImpl(logger: ref.read(loggerProvider));
});

// Chart service
final chartServiceProvider = Provider<ChartService>((ref) {
  return ChartServiceImpl(
    logger: ref.read(loggerProvider),
    storageService: ref.read(storageServiceProvider),
  );
});

// Navigation service
final navigationServiceProvider = Provider<NavigationService>((ref) {
  return NavigationServiceImpl(logger: ref.read(loggerProvider));
});

// Settings service
final settingsServiceProvider = Provider<SettingsService>((ref) {
  // Create with placeholder prefs - will be initialized properly in main.dart
  return SettingsServiceImpl(
    prefs: null, // Will be set during app initialization
    logger: ref.read(loggerProvider),
  );
});

// Main application state
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((
  ref,
) {
  return AppStateNotifier(
    logger: ref.read(loggerProvider),
    errorHandler: ref.read(errorHandlerProvider),
  );
});

// Settings provider
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
      return AppSettingsNotifier(
        logger: ref.read(loggerProvider),
        errorHandler: ref.read(errorHandlerProvider),
      );
    });

// Download queue state
final downloadQueueProvider =
    StateNotifierProvider<DownloadQueueNotifier, DownloadQueueState>((ref) {
      return DownloadQueueNotifier(
        logger: ref.read(loggerProvider),
        errorHandler: ref.read(errorHandlerProvider),
      );
    });

// Computed state selectors
final isAppInitializedProvider = Provider<bool>((ref) {
  return ref.watch(appStateProvider).isInitialized;
});

final currentPositionProvider = Provider<GpsPosition?>((ref) {
  return ref.watch(appStateProvider).currentPosition;
});

final gpsPositionProvider = FutureProvider<GpsPosition?>((ref) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getCurrentPosition();
});

final currentChartProvider = Provider<Chart?>((ref) {
  final state = ref.watch(appStateProvider);
  if (state.currentChartId == null) return null;

  // Try to find the chart in downloaded charts first
  for (final chart in state.downloadedCharts) {
    if (chart.id == state.currentChartId) return chart;
  }

  // Fall back to available charts
  for (final chart in state.availableCharts) {
    if (chart.id == state.currentChartId) return chart;
  }

  return null;
});

final availableChartsProvider = Provider<List<Chart>>((ref) {
  return ref.watch(appStateProvider).availableCharts;
});

final downloadedChartsProvider = Provider<List<Chart>>((ref) {
  return ref.watch(appStateProvider).downloadedCharts;
});

final activeRouteProvider = Provider<NavigationRoute?>((ref) {
  return ref.watch(appStateProvider).activeRoute;
});

final waypointsProvider = Provider<List<Waypoint>>((ref) {
  return ref.watch(appStateProvider).waypoints;
});

final isGpsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(appStateProvider).isGpsEnabled;
});

final isLocationPermissionGrantedProvider = Provider<bool>((ref) {
  return ref.watch(appStateProvider).isLocationPermissionGranted;
});

final themeModelProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(appStateProvider).themeMode;
});

final isDayModeProvider = Provider<bool>((ref) {
  return ref.watch(appStateProvider).isDayMode;
});

// Download-specific selectors
final activeDownloadsProvider = Provider<List<DownloadProgress>>((ref) {
  return ref.watch(downloadQueueProvider).activeDownloads;
});

final queuedDownloadsProvider = Provider<List<DownloadProgress>>((ref) {
  return ref.watch(downloadQueueProvider).queuedDownloads;
});

final completedDownloadsProvider = Provider<List<DownloadProgress>>((ref) {
  return ref.watch(downloadQueueProvider).completedDownloads;
});

final failedDownloadsProvider = Provider<List<DownloadProgress>>((ref) {
  return ref.watch(downloadQueueProvider).failedDownloads;
});

final overallDownloadProgressProvider = Provider<double>((ref) {
  return ref.watch(downloadQueueProvider).overallProgress;
});

final isDownloadingProvider = Provider<bool>((ref) {
  return ref.watch(downloadQueueProvider).activeDownloads.isNotEmpty;
});

final downloadQueueLengthProvider = Provider<int>((ref) {
  return ref.watch(downloadQueueProvider).queue.length;
});

// Chart-specific providers
final chartsByStateProvider = Provider.family<List<Chart>, String>((
  ref,
  state,
) {
  final charts = ref.watch(availableChartsProvider);
  return charts
      .where((chart) => chart.state.toLowerCase() == state.toLowerCase())
      .toList();
});

final chartsByTypeProvider = Provider.family<List<Chart>, ChartType>((
  ref,
  type,
) {
  final charts = ref.watch(availableChartsProvider);
  return charts.where((chart) => chart.type == type).toList();
});

final chartsInBoundsProvider =
    Provider.family<
      List<Chart>,
      ({double north, double south, double east, double west})
    >((ref, bounds) {
      final charts = ref.watch(availableChartsProvider);
      return charts.where((chart) {
        return chart.bounds.north <= bounds.north &&
            chart.bounds.south >= bounds.south &&
            chart.bounds.east <= bounds.east &&
            chart.bounds.west >= bounds.west;
      }).toList();
    });

// Navigation-specific providers
final routeWaypointsProvider = Provider<List<Waypoint>>((ref) {
  final route = ref.watch(activeRouteProvider);
  return route?.waypoints ?? [];
});

final nextWaypointProvider = Provider<Waypoint?>((ref) {
  final route = ref.watch(activeRouteProvider);
  final position = ref.watch(currentPositionProvider);

  if (route == null || position == null) return null;

  return route.getNextWaypoint(position);
});

final remainingDistanceProvider = Provider<double?>((ref) {
  final route = ref.watch(activeRouteProvider);
  final position = ref.watch(currentPositionProvider);

  if (route == null || position == null) return null;

  return route.remainingDistance(position);
});

final bearingToNextWaypointProvider = Provider<double?>((ref) {
  final route = ref.watch(activeRouteProvider);
  final position = ref.watch(currentPositionProvider);

  if (route == null || position == null) return null;

  return route.getBearing(position);
});

// Utility providers
final isOfflineCapableProvider = Provider<bool>((ref) {
  final downloadedCharts = ref.watch(downloadedChartsProvider);
  return downloadedCharts.isNotEmpty;
});

final currentChartScaleProvider = Provider<int?>((ref) {
  final chart = ref.watch(currentChartProvider);
  return chart?.scale;
});

final isNavigatingProvider = Provider<bool>((ref) {
  final route = ref.watch(activeRouteProvider);
  return route?.isActive ?? false;
});

// Count providers
final hasPositionProvider = Provider<bool>((ref) {
  final state = ref.watch(appStateProvider);
  return state.currentPosition != null;
});

final chartCountProvider = Provider<int>((ref) {
  final charts = ref.watch(availableChartsProvider);
  return charts.length;
});

final waypointCountProvider = Provider<int>((ref) {
  final waypoints = ref.watch(waypointsProvider);
  return waypoints.length;
});

// GPS status provider
final gpsStatusProvider =
    Provider<({bool enabled, bool permissionGranted, bool hasPosition})>((ref) {
      final state = ref.watch(appStateProvider);
      return (
        enabled: state.isGpsEnabled,
        permissionGranted: state.isLocationPermissionGranted,
        hasPosition: state.currentPosition != null,
      );
    });

// Settings-derived providers
final themeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.themeMode),
  );
});

final dayModeProvider = Provider<bool>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.isDayMode),
  );
});

final maxDownloadsProvider = Provider<int>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.maxConcurrentDownloads),
  );
});

final preferredUnitsProvider = Provider<String>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.preferredUnits),
  );
});

final debugInfoEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.showDebugInfo),
  );
});

final advancedFeaturesEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
    appSettingsProvider.select((settings) => settings.showAdvancedFeatures),
  );
});
