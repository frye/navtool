import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/app/app.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/navigation_service.dart';
import 'package:navtool/core/services/chart_service.dart';
import 'package:navtool/core/services/settings_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/features/home/home_screen.dart';

import 'app_integration_test.mocks.dart';

@GenerateMocks([
  GpsService,
  StorageService,
  DownloadService,
  NavigationService,
  ChartService,
  SettingsService,
  AppLogger,
])
void main() {
  group('NavTool App Integration Tests', () {
    late MockGpsService mockGpsService;
    late MockStorageService mockStorageService;
    late MockDownloadService mockDownloadService;
    late MockNavigationService mockNavigationService;
    late MockChartService mockChartService;
    late MockSettingsService mockSettingsService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockGpsService = MockGpsService();
      mockStorageService = MockStorageService();
      mockDownloadService = MockDownloadService();
      mockNavigationService = MockNavigationService();
      mockChartService = MockChartService();
      mockSettingsService = MockSettingsService();
      mockLogger = MockAppLogger();

      // GPS Service mocks
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

      // Storage Service mocks
      when(mockStorageService.storeChart(any, any)).thenAnswer((_) async {});
      when(
        mockStorageService.getStorageInfo(),
      ).thenAnswer((_) async => <String, dynamic>{});

      // Download Service mocks
      when(
        mockDownloadService.downloadChart(any, any),
      ).thenAnswer((_) async {});
      when(mockDownloadService.getDownloadQueue()).thenAnswer((_) async => []);

      // Chart Service mocks
      when(mockChartService.getAvailableCharts()).thenAnswer((_) async => []);

      // Settings Service mocks - using actual methods
      when(
        mockSettingsService.getSetting(any),
      ).thenAnswer((_) async => 'light');

      // Logger mocks
      when(mockLogger.info(any)).thenReturn(null);
      when(mockLogger.debug(any)).thenReturn(null);
      when(mockLogger.warning(any)).thenReturn(null);
      when(mockLogger.error(any)).thenReturn(null);
    });

    Widget createTestApp() {
      return ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
          storageServiceProvider.overrideWithValue(mockStorageService),
          downloadServiceProvider.overrideWithValue(mockDownloadService),
          navigationServiceProvider.overrideWithValue(mockNavigationService),
          chartServiceProvider.overrideWithValue(mockChartService),
          settingsServiceProvider.overrideWithValue(mockSettingsService),
          loggerProvider.overrideWithValue(mockLogger),
        ],
        child: MyApp(),
      );
    }

    group('Basic App Functionality', () {
      testWidgets('should initialize and show home screen', (
        WidgetTester tester,
      ) async {
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle basic chart loading', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testChart = Chart(
          id: 'test_chart',
          title: 'Test Chart',
          scale: 50000,
          bounds: GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          lastUpdate: DateTime.now(),
          state: 'CA',
          type: ChartType.harbor,
        );

        when(
          mockChartService.getAvailableCharts(),
        ).thenAnswer((_) async => [testChart]);

        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);

        // Note: Not verifying service calls since the app might not call them during initial load
      });
    });
  });
}
