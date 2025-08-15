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
      final state = container.read(appStateProvider);
      
      // Wait a bit for async initialization to complete
      await Future.delayed(const Duration(milliseconds: 100));
      
      final updatedState = container.read(appStateProvider);
      
      expect(updatedState.isInitialized, true); // State should be initialized by the notifier
      expect(updatedState.currentPosition, null);
      expect(updatedState.availableCharts, isEmpty);
      expect(updatedState.downloadedCharts, isEmpty);
      expect(updatedState.waypoints, isEmpty);
      expect(updatedState.isGpsEnabled, false);
      expect(updatedState.isLocationPermissionGranted, false);
      expect(updatedState.themeMode, AppThemeMode.system);
      expect(updatedState.isDayMode, true);
    });

    test('App settings provider initializes with default settings', () {
      final settings = container.read(appSettingsProvider);
      
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

    test('Settings derived providers work correctly', () {
      final themeMode = container.read(themeProvider);
      final dayMode = container.read(dayModeProvider);
      final maxDownloads = container.read(maxDownloadsProvider);
      final units = container.read(preferredUnitsProvider);
      
      expect(themeMode, AppThemeMode.system);
      expect(dayMode, true);
      expect(maxDownloads, 3);
      expect(units, 'metric');
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
      final notifier = container.read(appSettingsProvider.notifier);
      
      await notifier.setThemeMode(AppThemeMode.dark);
      
      final settings = container.read(appSettingsProvider);
      expect(settings.themeMode, AppThemeMode.dark);
    });

    test('Settings notifier can update max concurrent downloads', () async {
      final notifier = container.read(appSettingsProvider.notifier);
      
      await notifier.setMaxConcurrentDownloads(5);
      
      final settings = container.read(appSettingsProvider);
      expect(settings.maxConcurrentDownloads, 5);
    });
  });
}
