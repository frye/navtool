import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/chart_service.dart';
import 'package:navtool/core/services/navigation_service.dart';
import 'package:navtool/core/services/settings_service.dart';

/// Test to verify the newly added provider registrations work correctly
void main() {
  group('Provider Registration Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('should register chartServiceProvider successfully', () {
      // Act
      final chartService = container.read(chartServiceProvider);

      // Assert
      expect(chartService, isA<ChartService>());
      expect(chartService, isNotNull);
    });

    test('should register navigationServiceProvider successfully', () {
      // Act
      final navigationService = container.read(navigationServiceProvider);

      // Assert
      expect(navigationService, isA<NavigationService>());
      expect(navigationService, isNotNull);
    });

    test('should register settingsServiceProvider successfully', () {
      // Act
      final settingsService = container.read(settingsServiceProvider);

      // Assert
      expect(settingsService, isA<SettingsService>());
      expect(settingsService, isNotNull);
    });

    test('should register all core service providers', () {
      // Act & Assert - Verify all core services can be instantiated
      expect(() => container.read(downloadServiceProvider), returnsNormally);
      expect(() => container.read(storageServiceProvider), returnsNormally);
      expect(() => container.read(gpsServiceProvider), returnsNormally);
      expect(() => container.read(chartServiceProvider), returnsNormally);
      expect(() => container.read(navigationServiceProvider), returnsNormally);
      expect(() => container.read(settingsServiceProvider), returnsNormally);
    });
  });
}
