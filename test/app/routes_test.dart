import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/app/routes.dart';
import 'package:navtool/features/home/home_screen.dart';
import 'package:navtool/features/about/about_screen.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/models/gps_position.dart';

// Generate mocks for dependencies
@GenerateMocks([NoaaChartDiscoveryService, AppLogger, GpsService])
import 'routes_test.mocks.dart';

void main() {
  group('App Routes Tests', () {
    late MockNoaaChartDiscoveryService mockDiscoveryService;
    late MockAppLogger mockLogger;
    late MockGpsService mockGpsService;

    setUp(() {
      mockDiscoveryService = MockNoaaChartDiscoveryService();
      mockLogger = MockAppLogger();
      mockGpsService = MockGpsService();

      // Setup default GPS service behavior
      when(mockGpsService.getCurrentPosition()).thenAnswer(
        (_) async => GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 5.0,
          timestamp: DateTime.now(),
        ),
      );
      when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
      when(
        mockGpsService.checkLocationPermission(),
      ).thenAnswer((_) async => true);
    });

    Widget createTestApp() {
      return ProviderScope(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWithValue(
            mockDiscoveryService,
          ),
          loggerProvider.overrideWithValue(mockLogger),
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
        child: MaterialApp(
          routes: AppRoutes.routes,
          initialRoute: AppRoutes.home,
        ),
      );
    }

    testWidgets('should have all required routes defined', (
      WidgetTester tester,
    ) async {
      // Test that all routes are properly defined
      expect(AppRoutes.routes.containsKey(AppRoutes.home), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.about), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.chart), isTrue);
      expect(AppRoutes.routes.containsKey(AppRoutes.chartBrowser), isTrue);
    });

    testWidgets('should navigate to chart browser from home route', (
      WidgetTester tester,
    ) async {
      // Arrange
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Verify we're on home screen
      expect(find.byType(HomeScreen), findsOneWidget);

      // Act - tap the open chart button (assuming it's visible on desktop layout)
      if (find.text('Open Chart').evaluate().isNotEmpty) {
        await tester.tap(find.text('Open Chart').first);
        await tester.pumpAndSettle();

        // Assert - should navigate to chart browser
        expect(find.byType(ChartBrowserScreen), findsOneWidget);
      }
    });

    testWidgets('should navigate directly to chart browser route', (
      WidgetTester tester,
    ) async {
      // Arrange
      final app = ProviderScope(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWithValue(
            mockDiscoveryService,
          ),
          loggerProvider.overrideWithValue(mockLogger),
        ],
        child: MaterialApp(
          routes: AppRoutes.routes,
          initialRoute: AppRoutes.chartBrowser,
        ),
      );

      // Act
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(ChartBrowserScreen), findsOneWidget);
      expect(find.text('Chart Browser'), findsOneWidget);
    });

    testWidgets('should have correct route constants', (
      WidgetTester tester,
    ) async {
      // Test that route constants are correct
      expect(AppRoutes.home, equals('/'));
      expect(AppRoutes.about, equals('/about'));
      expect(AppRoutes.chart, equals('/chart'));
      expect(AppRoutes.chartBrowser, equals('/chart-browser'));
    });
  });
}
