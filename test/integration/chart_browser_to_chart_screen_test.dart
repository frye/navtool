import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/position_history.dart';
import 'package:navtool/core/models/gps_signal_quality.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';

// Using lightweight fakes instead of Mockito to keep integration test self-contained.

class FakeDiscoveryService implements NoaaChartDiscoveryService {
  List<Chart> stateCharts = [];
  List<Chart> locationCharts = [];
  List<Chart> searchChartsResults = [];

  @override
  Future<List<Chart>> discoverChartsByState(String state) async {
    // Debug output to help diagnose integration test issues
    // (Will appear in test logs; harmless in production builds.)
    // ignore: avoid_print
    print('[FakeDiscoveryService] discoverChartsByState("$state") returning ${stateCharts.length} charts');
    return stateCharts;
  }

  @override
  Future<List<Chart>> discoverChartsByLocation(GpsPosition position) async => locationCharts;

  @override
  Future<List<Chart>> searchCharts(String query, {Map<String, String>? filters}) async => searchChartsResults;

  @override
  Future<Chart?> getChartMetadata(String chartId) async {
    try {
      return [...stateCharts, ...locationCharts].firstWhere((c) => c.id == chartId);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<List<Chart>> watchChartsForState(String state) async* {
    yield stateCharts;
  }

  @override
  Future<bool> refreshCatalog({bool force = false}) async => true;

  @override
  Future<int> fixChartDiscoveryCache() async => 0;

  // Unused in this test (implement stubs if interface expands)
}

class FakeGpsService implements GpsService {
  GpsPosition? position;
  @override
  Future<GpsPosition?> getCurrentPositionWithFallback() async => position;

  // Unused methods stubbed
  @override
  Future<void> startLocationTracking() async {}
  @override
  Future<void> stopLocationTracking() async {}
  @override
  Future<GpsPosition?> getCurrentPosition() async => position;
  @override
  Stream<GpsPosition> getLocationStream() async* {}
  @override
  Future<bool> requestLocationPermission() async => true;
  @override
  Future<bool> checkLocationPermission() async => true;
  @override
  Future<bool> isLocationEnabled() async => true;
  @override
  Future<GpsSignalQuality> assessSignalQuality(GpsPosition? position) async =>
    GpsSignalQuality.fromAccuracy(5.0);
  @override
  Future<void> logPosition(GpsPosition position) async {}
  @override
  Future<PositionHistory> getPositionHistory(Duration timeWindow) async =>
      const PositionHistory(
        positions: [],
        totalDistance: 0,
        averageSpeed: 0,
        maxSpeed: 0,
        minSpeed: 0,
        duration: Duration.zero,
      );
  @override
  Future<List<GpsSignalQuality>> getSignalQualityTrend(Duration timeWindow) async => [];
  @override
  Future<void> clearPositionHistory() async {}
  @override
  Future<AccuracyStatistics> getAccuracyStatistics(Duration timeWindow) async =>
      const AccuracyStatistics(
        averageAccuracy: 0,
        bestAccuracy: 0,
        worstAccuracy: 0,
        marineGradePercentage: 0,
        sampleCount: 0,
        period: Duration.zero,
      );
  @override
  Future<MovementState> getMovementState(Duration analysisWindow) async => const MovementState(
        isStationary: true,
        averageSpeed: 0,
        confidence: 1.0,
        movementRadius: 0,
      );
  @override
  Future<PositionFreshness> getPositionFreshness() async =>
    PositionFreshness.fromLastUpdate(DateTime.now());
  @override
  Future<List<GpsPosition>> filterForMarineAccuracy(List<GpsPosition> positions) async => positions;
  @override
  Future<CourseOverGround?> calculateCourseOverGround(Duration timeWindow) async => null;
  @override
  Future<SpeedOverGround?> calculateSpeedOverGround(Duration timeWindow) async => null;
}

class FakeLogger implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) {}
  @override
  void info(String message, {String? context, Object? exception}) {}
  @override
  void warning(String message, {String? context, Object? exception}) {}
  @override
  void error(String message, {String? context, Object? exception}) {}
  @override
  void logError(AppError error) {}
}

void main() {
  group('Integration: ChartBrowser -> ChartScreen', () {
  late FakeDiscoveryService fakeDiscovery;
  late FakeGpsService fakeGps;
  late FakeLogger fakeLogger;

    setUp(() {
      fakeDiscovery = FakeDiscoveryService();
      fakeGps = FakeGpsService();
      fakeLogger = FakeLogger();
    });

    Chart testChart() => Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 37.9,
            south: 37.7,
            east: -122.3,
            west: -122.5,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
          description: 'Detailed harbor chart of San Francisco Bay',
          fileSize: 15728640,
        );

    Widget buildApp() {
      return ProviderScope(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWithValue(fakeDiscovery),
          gpsServiceProvider.overrideWithValue(fakeGps),
          loggerProvider.overrideWithValue(fakeLogger),
        ],
        child: MaterialApp(
          initialRoute: '/',
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute(builder: (_) => const ChartBrowserScreen());
            }
            if (settings.name == '/chart') {
              final args = settings.arguments as Map<String, dynamic>?;
              final chart = args != null ? args['chart'] as Chart? : null;
              final chartTitle = args != null ? args['chartTitle'] as String? : null;
              return MaterialPageRoute(builder: (_) => ChartScreen(chart: chart, chartTitle: chartTitle));
            }
            return null;
          },
        ),
      );
    }

    testWidgets('tapping a chart card navigates and shows real chart metadata', (tester) async {
      // Arrange
      final chart = testChart();
      fakeDiscovery.stateCharts = [chart];
      fakeDiscovery.locationCharts = [chart];
      fakeDiscovery.searchChartsResults = [chart];
      fakeGps.position = GpsPosition(
        latitude: 37.78,
        longitude: -122.42,
        timestamp: DateTime.now(),
        accuracy: 1000.0,
      );

      // Act
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Select state (ensure dropdown opens even if wrapped)
      final stateDropdown = find.byType(DropdownButtonFormField<String>);
      expect(stateDropdown, findsOneWidget);
      await tester.tap(stateDropdown);
      await tester.pumpAndSettle();
      // Some test environments need scroll to reveal item
      if (find.text('California').evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('California'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // If still not rendered, force a frame and verify fallback
      if (find.text('San Francisco Bay').evaluate().isEmpty) {
        // Force additional pumps to allow async state update
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Wait for chart to appear with retries (as async setState + filter happens after await)
      final chartCardKey = find.byKey(const ValueKey('chart-card-US5CA52M'));
      var attempts = 0;
      while (chartCardKey.evaluate().isEmpty && attempts < 12) {
        await tester.pump(const Duration(milliseconds: 120));
        attempts++;
      }
      if (chartCardKey.evaluate().isEmpty) {
        debugPrint('Chart card not found by key; dumping widget tree.');
        debugPrint(tester.element(find.byType(ChartBrowserScreen)).toStringDeep());
      }
  expect(chartCardKey, findsOneWidget, reason: 'Chart card for mocked chart should be present');
  // Ensure the chart card is visible (it may be below the fold due to controls section height)
  await tester.ensureVisible(chartCardKey);
  await tester.pump();
  await tester.tap(chartCardKey, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Open info dialog from ChartScreen AppBar
      // There may be multiple info icons (one per route underneath), so select the last (topmost route)
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsWidgets);
      final appBarInfoButton = find.descendant(
        of: appBarFinder.last,
        matching: find.byIcon(Icons.info_outline),
      );
      expect(appBarInfoButton, findsOneWidget);
      await tester.tap(appBarInfoButton);
      await tester.pumpAndSettle();

      // Assert chart metadata visible
      expect(find.text('Chart Information'), findsOneWidget);
      expect(find.text('Chart Title:'), findsOneWidget);
  // Title may appear in multiple widgets (AppBar title + status bar). Ensure at least one.
  expect(find.text('San Francisco Bay'), findsWidgets);
      expect(find.text('Chart ID:'), findsOneWidget);
      expect(find.textContaining('US5CA52M'), findsOneWidget);
      expect(find.text('Scale:'), findsWidgets);
      expect(find.textContaining('1:25000'), findsOneWidget);

      // Close dialog to clean up
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });
}
