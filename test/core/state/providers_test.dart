import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/state/app_state.dart';
import 'package:navtool/core/state/settings_state.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

/// Comprehensive tests for Riverpod providers
/// Tests provider creation, computed providers, and state selectors
void main() {
  group('Providers Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('Core State Providers', () {
      test('should create appStateProvider successfully', () async {
        // Act
        final state = container.read(appStateProvider);
        
        // Wait for initialization
        await Future.delayed(const Duration(milliseconds: 50));
        final initializedState = container.read(appStateProvider);
        
        // Assert
        expect(state, isA<AppState>());
        expect(initializedState.isInitialized, isTrue);
      });

      test('should create appSettingsProvider successfully', () {
        // Act
        final settings = container.read(appSettingsProvider);
        
        // Assert
        expect(settings, isA<AppSettings>());
        expect(settings.themeMode, equals(AppThemeMode.system));
        expect(settings.isDayMode, isTrue);
        expect(settings.maxConcurrentDownloads, equals(3));
      });

      test('should create downloadQueueProvider successfully', () {
        // Act
        final downloadState = container.read(downloadQueueProvider);
        
        // Assert
        expect(downloadState, isA<DownloadQueueState>());
        expect(downloadState.downloads, isEmpty);
        expect(downloadState.queue, isEmpty);
        expect(downloadState.maxConcurrentDownloads, equals(3));
        expect(downloadState.isPaused, isFalse);
      });

      test('should provide notifiers for state management', () {
        // Act
        final appNotifier = container.read(appStateProvider.notifier);
        final settingsNotifier = container.read(appSettingsProvider.notifier);
        final downloadNotifier = container.read(downloadQueueProvider.notifier);
        
        // Assert
        expect(appNotifier, isNotNull);
        expect(settingsNotifier, isNotNull);
        expect(downloadNotifier, isNotNull);
      });
    });

    group('Computed State Providers', () {
      test('should provide isAppInitializedProvider correctly', () async {
        // Arrange
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Act
        final isInitialized = container.read(isAppInitializedProvider);
        
        // Assert
        expect(isInitialized, isTrue);
      });

      test('should provide currentPositionProvider correctly', () {
        // Arrange
        final testPosition = _createTestPosition();
        container.read(appStateProvider.notifier).updateCurrentPosition(testPosition);
        
        // Act
        final position = container.read(currentPositionProvider);
        
        // Assert
        expect(position, equals(testPosition));
      });

      test('should provide currentChartProvider correctly', () {
        // Arrange
        final testChart = _createTestChart('US5CA52M');
        final notifier = container.read(appStateProvider.notifier);
        notifier.updateAvailableCharts([testChart]);
        notifier.setCurrentChart(testChart.id);
        
        // Act
        final chart = container.read(currentChartProvider);
        
        // Assert
        expect(chart, equals(testChart));
      });

      test('should handle null currentChartProvider', () {
        // Act
        final chart = container.read(currentChartProvider);
        
        // Assert
        expect(chart, isNull);
      });

      test('should provide availableChartsProvider correctly', () {
        // Arrange
        final testCharts = [
          _createTestChart('US5CA52M'),
          _createTestChart('US4CA11M'),
        ];
        container.read(appStateProvider.notifier).updateAvailableCharts(testCharts);
        
        // Act
        final charts = container.read(availableChartsProvider);
        
        // Assert
        expect(charts, hasLength(2));
        expect(charts, containsAll(testCharts));
      });

      test('should provide downloadedChartsProvider correctly', () {
        // Arrange
        final testChart = _createTestChart('US5CA52M');
        container.read(appStateProvider.notifier).addDownloadedChart(testChart);
        
        // Act
        final charts = container.read(downloadedChartsProvider);
        
        // Assert
        expect(charts, hasLength(1));
        expect(charts.first, equals(testChart));
      });

      test('should provide activeRouteProvider correctly', () {
        // Arrange
        final testRoute = _createTestRoute();
        container.read(appStateProvider.notifier).setActiveRoute(testRoute);
        
        // Act
        final route = container.read(activeRouteProvider);
        
        // Assert
        expect(route, equals(testRoute));
      });

      test('should provide waypointsProvider correctly', () {
        // Arrange
        final testWaypoint = _createTestWaypoint();
        container.read(appStateProvider.notifier).addWaypoint(testWaypoint);
        
        // Act
        final waypoints = container.read(waypointsProvider);
        
        // Assert
        expect(waypoints, hasLength(1));
        expect(waypoints.first, equals(testWaypoint));
      });
    });

    group('Settings Derived Providers', () {
      test('should provide themeProvider correctly', () {
        // Arrange
        container.read(appSettingsProvider.notifier).setThemeMode(AppThemeMode.dark);
        
        // Act
        final themeMode = container.read(themeProvider);
        
        // Assert
        expect(themeMode, equals(AppThemeMode.dark));
      });

      test('should provide dayModeProvider correctly', () {
        // Arrange
        container.read(appSettingsProvider.notifier).setDayMode(false);
        
        // Act
        final dayMode = container.read(dayModeProvider);
        
        // Assert
        expect(dayMode, isFalse);
      });

      test('should provide maxDownloadsProvider correctly', () {
        // Arrange
        container.read(appSettingsProvider.notifier).setMaxConcurrentDownloads(5);
        
        // Act
        final maxDownloads = container.read(maxDownloadsProvider);
        
        // Assert
        expect(maxDownloads, equals(5));
      });

      test('should provide preferredUnitsProvider correctly', () {
        // Arrange
        container.read(appSettingsProvider.notifier).setPreferredUnits('imperial');
        
        // Act
        final units = container.read(preferredUnitsProvider);
        
        // Assert
        expect(units, equals('imperial'));
      });
    });

    group('Utility Providers', () {
      test('should provide hasPositionProvider correctly', () {
        // Arrange - Initially no position
        bool hasPosition = container.read(hasPositionProvider);
        expect(hasPosition, isFalse);
        
        // Act - Add position
        final testPosition = _createTestPosition();
        container.read(appStateProvider.notifier).updateCurrentPosition(testPosition);
        hasPosition = container.read(hasPositionProvider);
        
        // Assert
        expect(hasPosition, isTrue);
      });

      test('should provide chartCountProvider correctly', () {
        // Arrange - Initially no charts
        int chartCount = container.read(chartCountProvider);
        expect(chartCount, equals(0));
        
        // Act - Add charts
        final testCharts = [
          _createTestChart('US5CA52M'),
          _createTestChart('US4CA11M'),
        ];
        container.read(appStateProvider.notifier).updateAvailableCharts(testCharts);
        chartCount = container.read(chartCountProvider);
        
        // Assert
        expect(chartCount, equals(2));
      });

      test('should provide waypointCountProvider correctly', () {
        // Arrange - Initially no waypoints
        int waypointCount = container.read(waypointCountProvider);
        expect(waypointCount, equals(0));
        
        // Act - Add waypoints
        final testWaypoint = _createTestWaypoint();
        container.read(appStateProvider.notifier).addWaypoint(testWaypoint);
        waypointCount = container.read(waypointCountProvider);
        
        // Assert
        expect(waypointCount, equals(1));
      });

      test('should provide isOfflineCapableProvider correctly', () {
        // Arrange - Initially no downloaded charts
        bool isOfflineCapable = container.read(isOfflineCapableProvider);
        expect(isOfflineCapable, isFalse);
        
        // Act - Add downloaded chart
        final testChart = _createTestChart('US5CA52M');
        container.read(appStateProvider.notifier).addDownloadedChart(testChart);
        isOfflineCapable = container.read(isOfflineCapableProvider);
        
        // Assert
        expect(isOfflineCapable, isTrue);
      });

      test('should provide currentChartScaleProvider correctly', () {
        // Arrange - Initially no current chart
        int? chartScale = container.read(currentChartScaleProvider);
        expect(chartScale, isNull);
        
        // Act - Set current chart
        final testChart = _createTestChart('US5CA52M');
        final notifier = container.read(appStateProvider.notifier);
        notifier.updateAvailableCharts([testChart]);
        notifier.setCurrentChart(testChart.id);
        chartScale = container.read(currentChartScaleProvider);
        
        // Assert
        expect(chartScale, equals(25000));
      });

      test('should provide isNavigatingProvider correctly', () {
        // Arrange - Initially not navigating
        bool isNavigating = container.read(isNavigatingProvider);
        expect(isNavigating, isFalse);
        
        // Act - Set active route with isActive = true
        final testRoute = _createTestRoute().copyWith(isActive: true);
        container.read(appStateProvider.notifier).setActiveRoute(testRoute);
        isNavigating = container.read(isNavigatingProvider);
        
        // Assert
        expect(isNavigating, isTrue);
      });
    });

    group('Provider Reactivity', () {
      test('should update dependent providers when state changes', () {
        // Arrange
        final initialHasPosition = container.read(hasPositionProvider);
        expect(initialHasPosition, isFalse);
        
        // Act
        final testPosition = _createTestPosition();
        container.read(appStateProvider.notifier).updateCurrentPosition(testPosition);
        
        // Assert
        final updatedHasPosition = container.read(hasPositionProvider);
        expect(updatedHasPosition, isTrue);
      });

      test('should maintain provider consistency across updates', () {
        // Arrange
        final testChart = _createTestChart('US5CA52M');
        final notifier = container.read(appStateProvider.notifier);
        
        // Act
        notifier.updateAvailableCharts([testChart]);
        notifier.setCurrentChart(testChart.id);
        
        // Assert
        final availableCharts = container.read(availableChartsProvider);
        final currentChart = container.read(currentChartProvider);
        final chartCount = container.read(chartCountProvider);
        
        expect(availableCharts, contains(testChart));
        expect(currentChart, equals(testChart));
        expect(chartCount, equals(1));
      });

      test('should handle rapid state changes correctly', () {
        // Arrange
        final notifier = container.read(appStateProvider.notifier);
        final charts = List.generate(5, (i) => _createTestChart('CHART_$i'));
        
        // Act - Rapid updates
        for (final chart in charts) {
          notifier.updateAvailableCharts([chart]);
        }
        
        // Assert
        final finalCharts = container.read(availableChartsProvider);
        expect(finalCharts, hasLength(1));
        expect(finalCharts.first.id, equals('CHART_4'));
      });
    });

    group('Marine Navigation Provider Integration', () {
      test('should support complete marine navigation workflow', () {
        // Arrange
        final testPosition = _createTestPosition();
        final testChart = _createTestChart('US5CA52M');
        final testWaypoint = _createTestWaypoint();
        final testRoute = _createTestRoute();
        final notifier = container.read(appStateProvider.notifier);
        
        // Act - Setup complete navigation scenario
        notifier.updateCurrentPosition(testPosition);
        notifier.updateAvailableCharts([testChart]);
        notifier.setCurrentChart(testChart.id);
        notifier.addWaypoint(testWaypoint);
        notifier.setActiveRoute(testRoute.copyWith(isActive: true));
        
        // Assert - All providers reflect navigation state
        expect(container.read(hasPositionProvider), isTrue);
        expect(container.read(currentChartProvider), equals(testChart));
        expect(container.read(waypointCountProvider), equals(1));
        expect(container.read(isNavigatingProvider), isTrue);
        expect(container.read(currentPositionProvider), equals(testPosition));
      });

      test('should provide GPS status correctly', () async {
        // Arrange
        final notifier = container.read(appStateProvider.notifier);
        
        // Act
        notifier.setGpsEnabled(true);
        notifier.setLocationPermissionGranted(true);
        final testPosition = _createTestPosition();
        notifier.updateCurrentPosition(testPosition);
        
        // Wait for potential async GPS provider
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Assert
        final appState = container.read(appStateProvider);
        expect(appState.isGpsEnabled, isTrue);
        expect(appState.isLocationPermissionGranted, isTrue);
        expect(appState.currentPosition, equals(testPosition));
      });

      test('should handle chart selection and navigation', () {
        // Arrange
        final charts = [
          _createTestChart('US5CA52M'),
          _createTestChart('US4CA11M'),
        ];
        final notifier = container.read(appStateProvider.notifier);
        
        // Act
        notifier.updateAvailableCharts(charts);
        notifier.setCurrentChart(charts.first.id);
        
        // Assert
        expect(container.read(availableChartsProvider), hasLength(2));
        expect(container.read(currentChartProvider), equals(charts.first));
        expect(container.read(currentChartScaleProvider), equals(25000));
      });
    });
  });
}

/// Helper function to create test GPS position
GpsPosition _createTestPosition() {
  return GpsPosition(
    latitude: 37.7749,
    longitude: -122.4194,
    timestamp: DateTime.now(),
    accuracy: 5.0,
    altitude: 50.0,
    speed: 0.0,
    heading: 0.0,
  );
}

/// Helper function to create test chart
Chart _createTestChart(String id) {
  return Chart(
    id: id,
    title: 'Test Chart $id',
    scale: 25000,
    bounds: GeographicBounds(
      north: 38.0,
      south: 37.0,
      east: -122.0,
      west: -123.0,
    ),
    lastUpdate: DateTime.now(),
    state: 'California',
    type: ChartType.harbor,
  );
}

/// Helper function to create test waypoint
Waypoint _createTestWaypoint() {
  return Waypoint(
    id: 'wp001',
    name: 'Test Waypoint',
    latitude: 37.7749,
    longitude: -122.4194,
    type: WaypointType.destination,
  );
}

/// Helper function to create test route
NavigationRoute _createTestRoute() {
  return NavigationRoute(
    id: 'route001',
    name: 'Test Route',
    waypoints: [
      _createTestWaypoint(),
      Waypoint(
        id: 'wp002',
        name: 'End Point',
        latitude: 37.8000,
        longitude: -122.4000,
        type: WaypointType.destination,
      ),
    ],
  );
}
