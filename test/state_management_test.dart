import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/state/app_state.dart';
import 'package:navtool/core/models/gps_position.dart';

void main() {
  // Initialize Flutter binding for platform services
  TestWidgetsFlutterBinding.ensureInitialized();

  group('State Management Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('App state provider initializes with default state', () async {
      // Create a fresh container for this test
      final testContainer = ProviderContainer();

      try {
        // Access the provider, which will trigger the notifier creation and async initialization
        final notifier = testContainer.read(appStateProvider.notifier);

        // Wait for initialization to complete with a more robust approach
        int attempts = 0;
        while (!testContainer.read(appStateProvider).isInitialized &&
            attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 50));
          attempts++;
        }

        final state = testContainer.read(appStateProvider);

        expect(
          state.isInitialized,
          true,
          reason: 'State should be initialized after async init completes',
        );
        expect(state.currentPosition, null);
        expect(state.availableCharts, isEmpty);
        expect(state.downloadedCharts, isEmpty);
        expect(state.waypoints, isEmpty);
        expect(state.isGpsEnabled, false);
        expect(state.isLocationPermissionGranted, false);
        expect(state.themeMode, AppThemeMode.system);
        expect(state.isDayMode, true);
      } finally {
        testContainer.dispose();
      }
    });

    test('App settings provider initializes with default settings', () async {
      // Create a fresh container for this test
      final testContainer = ProviderContainer();

      try {
        // Access the provider to trigger initialization
        final notifier = testContainer.read(appSettingsProvider.notifier);

        // Wait a bit for async initialization to complete
        await Future.delayed(const Duration(milliseconds: 100));

        final settings = testContainer.read(appSettingsProvider);

        expect(settings.themeMode, AppThemeMode.system);
        expect(settings.isDayMode, true);
        expect(settings.maxConcurrentDownloads, 3);
        expect(settings.enableGpsLogging, false);
        expect(settings.showDebugInfo, false);
        expect(settings.chartRenderingQuality, 1.0);
        expect(settings.enableBackgroundDownloads, true);
        expect(settings.autoSelectChart, true);
        expect(settings.preferredUnits, 'metric');
        expect(settings.gpsUpdateInterval, 1.0);
        expect(settings.enableOfflineMode, false);
        expect(settings.showAdvancedFeatures, false);
      } finally {
        testContainer.dispose();
      }
    });

    test('Download queue provider initializes empty', () {
      final downloadState = container.read(downloadQueueProvider);

      expect(downloadState.downloads, isEmpty);
      expect(downloadState.maxConcurrentDownloads, 3);
      expect(downloadState.currentDownloadCount, 0);
    });

    test('Computed providers work correctly', () {
      // Test that computed providers return correct initial values
      final hasPosition = container.read(hasPositionProvider);
      final chartCount = container.read(chartCountProvider);
      final waypointCount = container.read(waypointCountProvider);

      expect(hasPosition, false);
      expect(chartCount, 0);
      expect(waypointCount, 0);
    });

    test('Settings derived providers work correctly', () async {
      // Create a fresh container for this test
      final testContainer = ProviderContainer();

      try {
        // Access the settings provider to trigger initialization
        final notifier = testContainer.read(appSettingsProvider.notifier);

        // Wait for initialization
        await Future.delayed(const Duration(milliseconds: 100));

        final themeMode = testContainer.read(themeProvider);
        final dayMode = testContainer.read(dayModeProvider);
        final maxDownloads = testContainer.read(maxDownloadsProvider);
        final units = testContainer.read(preferredUnitsProvider);

        expect(themeMode, AppThemeMode.system);
        expect(dayMode, true);
        expect(maxDownloads, 3);
        expect(units, 'metric');
      } finally {
        testContainer.dispose();
      }
    });

    test('App state notifier can update GPS position', () {
      final notifier = container.read(appStateProvider.notifier);

      final testPosition = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 50.0,
        speed: 0.0,
        heading: 0.0,
      );

      notifier.updateGpsPosition(testPosition);

      final state = container.read(appStateProvider);
      expect(state.currentPosition, testPosition);
    });

    test('Settings notifier can update theme mode', () async {
      // Create a fresh container for this test
      final testContainer = ProviderContainer();

      try {
        final notifier = testContainer.read(appSettingsProvider.notifier);

        // Wait for initialization
        await Future.delayed(const Duration(milliseconds: 100));

        await notifier.setThemeMode(AppThemeMode.dark);

        final settings = testContainer.read(appSettingsProvider);
        expect(settings.themeMode, AppThemeMode.dark);
      } finally {
        testContainer.dispose();
      }
    });

    test('Settings notifier can update max concurrent downloads', () async {
      // Create a fresh container for this test
      final testContainer = ProviderContainer();

      try {
        final notifier = testContainer.read(appSettingsProvider.notifier);

        // Wait for initialization
        await Future.delayed(const Duration(milliseconds: 100));

        await notifier.setMaxConcurrentDownloads(5);

        final settings = testContainer.read(appSettingsProvider);
        expect(settings.maxConcurrentDownloads, 5);
      } finally {
        testContainer.dispose();
      }
    });
  });
}
