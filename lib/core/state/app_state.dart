import 'package:flutter/foundation.dart';
import '../models/gps_position.dart';
import '../models/chart.dart';
import '../models/route.dart';
import '../models/waypoint.dart';

/// Application-wide state
@immutable
class AppState {
  final bool isInitialized;
  final String? currentChartId;
  final GpsPosition? currentPosition;
  final List<Chart> availableCharts;
  final List<Chart> downloadedCharts;
  final NavigationRoute? activeRoute;
  final List<Waypoint> waypoints;
  final bool isGpsEnabled;
  final bool isLocationPermissionGranted;
  final AppThemeMode themeMode;
  final bool isDayMode;

  const AppState({
    this.isInitialized = false,
    this.currentChartId,
    this.currentPosition,
    this.availableCharts = const [],
    this.downloadedCharts = const [],
    this.activeRoute,
    this.waypoints = const [],
    this.isGpsEnabled = false,
    this.isLocationPermissionGranted = false,
    this.themeMode = AppThemeMode.system,
    this.isDayMode = true,
  });

  AppState copyWith({
    bool? isInitialized,
    String? currentChartId,
    GpsPosition? currentPosition,
    List<Chart>? availableCharts,
    List<Chart>? downloadedCharts,
    NavigationRoute? activeRoute,
    List<Waypoint>? waypoints,
    bool? isGpsEnabled,
    bool? isLocationPermissionGranted,
    AppThemeMode? themeMode,
    bool? isDayMode,
  }) {
    return AppState(
      isInitialized: isInitialized ?? this.isInitialized,
      currentChartId: currentChartId ?? this.currentChartId,
      currentPosition: currentPosition ?? this.currentPosition,
      availableCharts: availableCharts ?? this.availableCharts,
      downloadedCharts: downloadedCharts ?? this.downloadedCharts,
      activeRoute: activeRoute ?? this.activeRoute,
      waypoints: waypoints ?? this.waypoints,
      isGpsEnabled: isGpsEnabled ?? this.isGpsEnabled,
      isLocationPermissionGranted:
          isLocationPermissionGranted ?? this.isLocationPermissionGranted,
      themeMode: themeMode ?? this.themeMode,
      isDayMode: isDayMode ?? this.isDayMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppState &&
          runtimeType == other.runtimeType &&
          isInitialized == other.isInitialized &&
          currentChartId == other.currentChartId &&
          currentPosition == other.currentPosition &&
          listEquals(availableCharts, other.availableCharts) &&
          listEquals(downloadedCharts, other.downloadedCharts) &&
          activeRoute == other.activeRoute &&
          listEquals(waypoints, other.waypoints) &&
          isGpsEnabled == other.isGpsEnabled &&
          isLocationPermissionGranted == other.isLocationPermissionGranted &&
          themeMode == other.themeMode &&
          isDayMode == other.isDayMode;

  @override
  int get hashCode =>
      isInitialized.hashCode ^
      currentChartId.hashCode ^
      currentPosition.hashCode ^
      availableCharts.hashCode ^
      downloadedCharts.hashCode ^
      activeRoute.hashCode ^
      waypoints.hashCode ^
      isGpsEnabled.hashCode ^
      isLocationPermissionGranted.hashCode ^
      themeMode.hashCode ^
      isDayMode.hashCode;

  @override
  String toString() {
    return 'AppState('
        'isInitialized: $isInitialized, '
        'currentChartId: $currentChartId, '
        'currentPosition: $currentPosition, '
        'availableCharts: ${availableCharts.length}, '
        'downloadedCharts: ${downloadedCharts.length}, '
        'activeRoute: $activeRoute, '
        'waypoints: ${waypoints.length}, '
        'isGpsEnabled: $isGpsEnabled, '
        'isLocationPermissionGranted: $isLocationPermissionGranted, '
        'themeMode: $themeMode, '
        'isDayMode: $isDayMode'
        ')';
  }
}

/// Theme mode options
enum AppThemeMode {
  system,
  light,
  dark;

  String get displayName {
    switch (this) {
      case AppThemeMode.system:
        return 'System';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }
}
