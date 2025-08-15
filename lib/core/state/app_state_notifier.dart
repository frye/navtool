import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logging/app_logger.dart';
import '../error/error_handler.dart';
import '../models/gps_position.dart';
import '../models/chart.dart';
import '../models/route.dart';
import '../models/waypoint.dart';
import 'app_state.dart';

/// Main application state notifier
class AppStateNotifier extends StateNotifier<AppState> {
  final AppLogger _logger;
  final ErrorHandler _errorHandler;

  AppStateNotifier({
    required AppLogger logger,
    required ErrorHandler errorHandler,
  })  : _logger = logger,
        _errorHandler = errorHandler,
        super(const AppState()) {
    _initialize();
  }

  /// Initialize the application state
  Future<void> _initialize() async {
    try {
      _logger.info('Initializing application state');
      
      // TODO: Load persisted state from storage
      // TODO: Initialize services
      
      state = state.copyWith(isInitialized: true);
      _logger.info('Application state initialized successfully');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      _logger.error('Failed to initialize application state', exception: error);
    }
  }

  /// Updates the current GPS position
  void updateCurrentPosition(GpsPosition position) {
    try {
      state = state.copyWith(currentPosition: position);
      _logger.debug('Updated current position: ${position.toCoordinateString()}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Alias for updateCurrentPosition for backward compatibility
  void updateGpsPosition(GpsPosition position) => updateCurrentPosition(position);

  /// Sets GPS enabled status
  void setGpsEnabled(bool enabled) {
    try {
      state = state.copyWith(isGpsEnabled: enabled);
      _logger.info('GPS enabled status changed: $enabled');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets location permission status
  void setLocationPermissionGranted(bool granted) {
    try {
      state = state.copyWith(isLocationPermissionGranted: granted);
      _logger.info('Location permission status changed: $granted');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates available charts
  void updateAvailableCharts(List<Chart> charts) {
    try {
      state = state.copyWith(availableCharts: charts);
      _logger.info('Updated available charts: ${charts.length} charts');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates downloaded charts
  void updateDownloadedCharts(List<Chart> charts) {
    try {
      state = state.copyWith(downloadedCharts: charts);
      _logger.info('Updated downloaded charts: ${charts.length} charts');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Adds a downloaded chart
  void addDownloadedChart(Chart chart) {
    try {
      final updatedCharts = [...state.downloadedCharts, chart];
      state = state.copyWith(downloadedCharts: updatedCharts);
      _logger.info('Added downloaded chart: ${chart.id}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Removes a downloaded chart
  void removeDownloadedChart(String chartId) {
    try {
      final updatedCharts = state.downloadedCharts
          .where((chart) => chart.id != chartId)
          .toList();
      state = state.copyWith(downloadedCharts: updatedCharts);
      _logger.info('Removed downloaded chart: $chartId');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets the current chart
  void setCurrentChart(String? chartId) {
    try {
      state = state.copyWith(currentChartId: chartId);
      _logger.info('Current chart changed: $chartId');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets the active route
  void setActiveRoute(NavigationRoute? route) {
    try {
      state = state.copyWith(activeRoute: route);
      _logger.info('Active route changed: ${route?.id}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Adds a waypoint
  void addWaypoint(Waypoint waypoint) {
    try {
      final updatedWaypoints = [...state.waypoints, waypoint];
      state = state.copyWith(waypoints: updatedWaypoints);
      _logger.info('Added waypoint: ${waypoint.id}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates a waypoint
  void updateWaypoint(Waypoint waypoint) {
    try {
      final updatedWaypoints = state.waypoints
          .map((wp) => wp.id == waypoint.id ? waypoint : wp)
          .toList();
      state = state.copyWith(waypoints: updatedWaypoints);
      _logger.info('Updated waypoint: ${waypoint.id}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Removes a waypoint
  void removeWaypoint(String waypointId) {
    try {
      final updatedWaypoints = state.waypoints
          .where((wp) => wp.id != waypointId)
          .toList();
      state = state.copyWith(waypoints: updatedWaypoints);
      _logger.info('Removed waypoint: $waypointId');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets the theme mode
  void setThemeMode(AppThemeMode themeMode) {
    try {
      state = state.copyWith(themeMode: themeMode);
      _logger.info('Theme mode changed: ${themeMode.displayName}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Sets day/night mode for marine charts
  void setDayMode(bool isDayMode) {
    try {
      state = state.copyWith(isDayMode: isDayMode);
      _logger.info('Chart day mode changed: $isDayMode');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Clears all application data (for testing or reset)
  void reset() {
    try {
      state = const AppState();
      _logger.info('Application state reset');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }
}
