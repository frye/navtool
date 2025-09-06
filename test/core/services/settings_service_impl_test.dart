import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navtool/core/services/settings_service.dart';
import 'package:navtool/core/services/settings_service_impl.dart';
import 'package:navtool/core/state/settings_state.dart';
import 'package:navtool/core/state/app_state.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../helpers/verify_helpers.dart';

// Generate mocks
@GenerateMocks([SharedPreferences, AppLogger])
import 'settings_service_impl_test.mocks.dart';

/// Comprehensive tests for SettingsService implementation
/// Tests preferences management, validation, backup/restore, and marine navigation settings
void main() {
  // Initialize Flutter binding for platform services
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService Implementation Tests', () {
    late SettingsService settingsService;
    late MockSharedPreferences mockPrefs;
    late MockAppLogger mockLogger;

    setUp(() {
      mockPrefs = MockSharedPreferences();
      mockLogger = MockAppLogger();
      settingsService = SettingsServiceImpl(
        prefs: mockPrefs,
        logger: mockLogger,
      );
    });

    group('Basic Operations Tests', () {
      test('should get string setting successfully', () async {
        // Arrange
        const key = 'test_string_key';
        const value = 'test_value';
        when(mockPrefs.getString(key)).thenReturn(value);

        // Act
        final result = await settingsService.getSetting(key);

        // Assert
        expect(result, equals(value));
        verify(mockPrefs.getString(key)).called(1);
      });

      test('should return null for non-existent string setting', () async {
        // Arrange
        const key = 'non_existent_key';
        when(mockPrefs.getString(key)).thenReturn(null);

        // Act
        final result = await settingsService.getSetting(key);

        // Assert
        expect(result, isNull);
        verify(mockPrefs.getString(key)).called(1);
      });

      test('should set string setting successfully', () async {
        // Arrange
        const key = 'test_string_key';
        const value = 'test_value';
        when(mockPrefs.setString(key, value)).thenAnswer((_) async => true);

        // Act
        await settingsService.setSetting(key, value);

        // Assert
        verify(mockPrefs.setString(key, value)).called(1);
        verifyDebugLogged(mockLogger, 'Setting saved:');
      });

      test('should handle set string setting failure', () async {
        // Arrange
        const key = 'test_string_key';
        const value = 'test_value';
        when(mockPrefs.setString(key, value)).thenAnswer((_) async => false);

        // Act & Assert
        expect(
          () => settingsService.setSetting(key, value),
          throwsA(isA<AppError>()),
        );
        verify(mockPrefs.setString(key, value)).called(1);
      });

      test('should delete setting successfully', () async {
        // Arrange
        const key = 'test_key';
        when(mockPrefs.containsKey(key)).thenReturn(true);
        when(mockPrefs.remove(key)).thenAnswer((_) async => true);

        // Act
        await settingsService.deleteSetting(key);

        // Assert
        verify(mockPrefs.remove(key)).called(1);
        verifyDebugLogged(mockLogger, 'Setting deleted:');
      });

      test('should handle delete non-existent setting gracefully', () async {
        // Arrange
        const key = 'non_existent_key';
        when(mockPrefs.containsKey(key)).thenReturn(false);

        // Act
        await settingsService.deleteSetting(key);

        // Assert
        verify(mockPrefs.containsKey(key)).called(1);
        verifyNever(mockPrefs.remove(key));
        verifyWarningLogged(
          mockLogger,
          'Attempted to delete non-existent setting:',
        );
      });
    });

    group('Boolean Settings Tests', () {
      test('should get boolean setting successfully', () async {
        // Arrange
        const key = 'enable_gps_logging';
        const value = true;
        when(mockPrefs.getBool(key)).thenReturn(value);

        // Act
        final result = await settingsService.getBool(key);

        // Assert
        expect(result, equals(value));
        verify(mockPrefs.getBool(key)).called(1);
      });

      test(
        'should return default false for non-existent boolean setting',
        () async {
          // Arrange
          const key = 'non_existent_bool';
          when(mockPrefs.getBool(key)).thenReturn(null);

          // Act
          final result = await settingsService.getBool(key);

          // Assert
          expect(result, isFalse);
          verify(mockPrefs.getBool(key)).called(1);
        },
      );

      test('should set boolean setting successfully', () async {
        // Arrange
        const key = 'enable_gps_logging';
        const value = true;
        when(mockPrefs.setBool(key, value)).thenAnswer((_) async => true);

        // Act
        await settingsService.setBool(key, value);

        // Assert
        verify(mockPrefs.setBool(key, value)).called(1);
        verifyDebugLogged(mockLogger, 'Boolean setting saved:');
      });
    });

    group('Integer Settings Tests', () {
      test('should get integer setting successfully', () async {
        // Arrange
        const key = 'max_concurrent_downloads';
        const value = 5;
        when(mockPrefs.getInt(key)).thenReturn(value);

        // Act
        final result = await settingsService.getInt(key);

        // Assert
        expect(result, equals(value));
        verify(mockPrefs.getInt(key)).called(1);
      });

      test(
        'should return default 0 for non-existent integer setting',
        () async {
          // Arrange
          const key = 'non_existent_int';
          when(mockPrefs.getInt(key)).thenReturn(null);

          // Act
          final result = await settingsService.getInt(key);

          // Assert
          expect(result, equals(0));
          verify(mockPrefs.getInt(key)).called(1);
        },
      );

      test('should set integer setting successfully', () async {
        // Arrange
        const key = 'max_concurrent_downloads';
        const value = 5;
        when(mockPrefs.setInt(key, value)).thenAnswer((_) async => true);

        // Act
        await settingsService.setInt(key, value);

        // Assert
        verify(mockPrefs.setInt(key, value)).called(1);
        verifyDebugLogged(mockLogger, 'Integer setting saved:');
      });

      test('should validate integer setting ranges', () async {
        // Arrange
        const key = 'max_concurrent_downloads';
        const invalidValue = -1;

        // Act & Assert
        expect(
          () => settingsService.setInt(key, invalidValue),
          throwsA(isA<AppError>()),
        );
        verifyNever(mockPrefs.setInt(key, invalidValue));
      });
    });

    group('Double Settings Tests', () {
      test('should get double setting successfully', () async {
        // Arrange
        const key = 'chart_rendering_quality';
        const value = 1.5;
        when(mockPrefs.getDouble(key)).thenReturn(value);

        // Act
        final result = await settingsService.getDouble(key);

        // Assert
        expect(result, equals(value));
        verify(mockPrefs.getDouble(key)).called(1);
      });

      test(
        'should return default 0.0 for non-existent double setting',
        () async {
          // Arrange
          const key = 'non_existent_double';
          when(mockPrefs.getDouble(key)).thenReturn(null);

          // Act
          final result = await settingsService.getDouble(key);

          // Assert
          expect(result, equals(0.0));
          verify(mockPrefs.getDouble(key)).called(1);
        },
      );

      test('should set double setting successfully', () async {
        // Arrange
        const key = 'chart_rendering_quality';
        const value = 1.5;
        when(mockPrefs.setDouble(key, value)).thenAnswer((_) async => true);

        // Act
        await settingsService.setDouble(key, value);

        // Assert
        verify(mockPrefs.setDouble(key, value)).called(1);
        verifyDebugLogged(mockLogger, 'Double setting saved:');
      });

      test('should validate double setting ranges', () async {
        // Arrange
        const key = 'chart_rendering_quality';
        const invalidValue = -0.5; // Quality can't be negative

        // Act & Assert
        expect(
          () => settingsService.setDouble(key, invalidValue),
          throwsA(isA<AppError>()),
        );
        verifyNever(mockPrefs.setDouble(key, invalidValue));
      });
    });

    group('Marine Navigation Settings Tests', () {
      test(
        'should validate GPS update interval within marine standards',
        () async {
          // Arrange
          const key = 'gps_update_interval';
          const validValue = 1.0; // 1 second is valid for marine navigation
          when(
            mockPrefs.setDouble(key, validValue),
          ).thenAnswer((_) async => true);

          // Act
          await settingsService.setDouble(key, validValue);

          // Assert
          verify(mockPrefs.setDouble(key, validValue)).called(1);
        },
      );

      test(
        'should reject GPS update interval too fast for marine use',
        () async {
          // Arrange
          const key = 'gps_update_interval';
          const invalidValue = 0.05; // 50ms is too fast for marine navigation

          // Act & Assert
          expect(
            () => settingsService.setDouble(key, invalidValue),
            throwsA(isA<AppError>()),
          );
          verifyNever(mockPrefs.setDouble(key, invalidValue));
        },
      );

      test('should validate preferred units setting', () async {
        // Arrange
        const key = 'preferred_units';
        const validValue = 'metric';
        when(
          mockPrefs.setString(key, validValue),
        ).thenAnswer((_) async => true);

        // Act
        await settingsService.setSetting(key, validValue);

        // Assert
        verify(mockPrefs.setString(key, validValue)).called(1);
      });

      test('should reject invalid units setting', () async {
        // Arrange
        const key = 'preferred_units';
        const invalidValue = 'invalid_units';

        // Act & Assert
        expect(
          () => settingsService.setSetting(key, invalidValue),
          throwsA(isA<AppError>()),
        );
        verifyNever(mockPrefs.setString(key, invalidValue));
      });

      test('should validate theme mode setting', () async {
        // Arrange
        const key = 'theme_mode';
        const validValue = 'dark';
        when(
          mockPrefs.setString(key, validValue),
        ).thenAnswer((_) async => true);

        // Act
        await settingsService.setSetting(key, validValue);

        // Assert
        verify(mockPrefs.setString(key, validValue)).called(1);
      });
    });

    group('Settings Validation Tests', () {
      test('should validate max concurrent downloads range', () async {
        // Arrange - Test upper bound
        const key = 'max_concurrent_downloads';
        const invalidValue = 15; // Too many for marine device

        // Act & Assert
        expect(
          () => settingsService.setInt(key, invalidValue),
          throwsA(isA<AppError>()),
        );
      });

      test('should validate chart rendering quality range', () async {
        // Arrange - Test upper bound
        const key = 'chart_rendering_quality';
        const invalidValue = 5.0; // Too high, should be <= 2.0

        // Act & Assert
        expect(
          () => settingsService.setDouble(key, invalidValue),
          throwsA(isA<AppError>()),
        );
      });

      test('should provide default values for known settings', () async {
        // Arrange
        when(mockPrefs.getInt('max_concurrent_downloads')).thenReturn(null);
        when(mockPrefs.getBool('enable_gps_logging')).thenReturn(null);
        when(mockPrefs.getDouble('chart_rendering_quality')).thenReturn(null);
        when(mockPrefs.getString('preferred_units')).thenReturn(null);

        // Act
        final maxDownloads = await settingsService.getInt(
          'max_concurrent_downloads',
        );
        final gpsLogging = await settingsService.getBool('enable_gps_logging');
        final renderQuality = await settingsService.getDouble(
          'chart_rendering_quality',
        );
        final units = await settingsService.getSetting('preferred_units');

        // Assert - Should return appropriate defaults
        expect(maxDownloads, equals(0)); // Base default
        expect(gpsLogging, isFalse); // Base default
        expect(renderQuality, equals(0.0)); // Base default
        expect(units, isNull); // Base default for strings
      });
    });

    group('Backup and Restore Tests', () {
      test('should export all settings to JSON', () async {
        // Arrange
        final mockSettings = {
          'theme_mode': 'dark',
          'enable_gps_logging': true,
          'max_concurrent_downloads': 3,
          'chart_rendering_quality': 1.5,
          'preferred_units': 'metric',
        };
        when(mockPrefs.getKeys()).thenReturn(mockSettings.keys.toSet());
        when(mockPrefs.get('theme_mode')).thenReturn('dark');
        when(mockPrefs.get('enable_gps_logging')).thenReturn(true);
        when(mockPrefs.get('max_concurrent_downloads')).thenReturn(3);
        when(mockPrefs.get('chart_rendering_quality')).thenReturn(1.5);
        when(mockPrefs.get('preferred_units')).thenReturn('metric');

        // Act
        final backup = await settingsService.exportSettings();

        // Assert
        expect(backup, isA<Map<String, dynamic>>());
        expect(backup['theme_mode'], equals('dark'));
        expect(backup['enable_gps_logging'], equals(true));
        expect(backup['max_concurrent_downloads'], equals(3));
        expect(backup['chart_rendering_quality'], equals(1.5));
        expect(backup['preferred_units'], equals('metric'));
        expect(backup['export_timestamp'], isA<String>());
        expect(backup['app_version'], isA<String>());
      });

      test('should import settings from JSON backup', () async {
        // Arrange
        final backupData = {
          'theme_mode': 'light',
          'enable_gps_logging': false,
          'max_concurrent_downloads': 5,
          'chart_rendering_quality': 2.0,
          'preferred_units': 'imperial',
          'export_timestamp': '2025-08-16T12:00:00Z',
          'app_version': '1.0.0',
        };

        when(mockPrefs.setString(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setBool(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setInt(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setDouble(any, any)).thenAnswer((_) async => true);

        // Act
        await settingsService.importSettings(backupData);

        // Assert
        verify(mockPrefs.setString('theme_mode', 'light')).called(1);
        verify(mockPrefs.setBool('enable_gps_logging', false)).called(1);
        verify(mockPrefs.setInt('max_concurrent_downloads', 5)).called(1);
        verify(mockPrefs.setDouble('chart_rendering_quality', 2.0)).called(1);
        verify(mockPrefs.setString('preferred_units', 'imperial')).called(1);
        verifyInfoLogged(
          mockLogger,
          'Settings imported successfully from backup',
        );
      });

      test('should validate backup data before import', () async {
        // Arrange - Invalid backup data
        final invalidBackup = {
          'theme_mode': 'invalid_theme',
          'max_concurrent_downloads': -5,
          'chart_rendering_quality': 10.0,
          'preferred_units': 'invalid_units',
        };

        // Act & Assert
        expect(
          () => settingsService.importSettings(invalidBackup),
          throwsA(isA<AppError>()),
        );
        verifyNever(mockPrefs.setString(any, any));
        verifyNever(mockPrefs.setInt(any, any));
      });

      test('should clear all settings', () async {
        // Arrange
        final settingsKeys = {'key1', 'key2', 'key3'};
        when(mockPrefs.getKeys()).thenReturn(settingsKeys);
        when(mockPrefs.remove(any)).thenAnswer((_) async => true);

        // Act
        await settingsService.clearAllSettings();

        // Assert
        for (final key in settingsKeys) {
          verify(mockPrefs.remove(key)).called(1);
        }
        verifyInfoLogged(mockLogger, 'All settings cleared');
      });

      test('should reset settings to marine navigation defaults', () async {
        // Arrange
        when(mockPrefs.setString(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setBool(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setInt(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setDouble(any, any)).thenAnswer((_) async => true);

        // Act
        await settingsService.resetToDefaults();

        // Assert
        verify(mockPrefs.setString('theme_mode', 'system')).called(1);
        verify(mockPrefs.setBool('is_day_mode', true)).called(1);
        verify(mockPrefs.setInt('max_concurrent_downloads', 3)).called(1);
        verify(mockPrefs.setBool('enable_gps_logging', false)).called(1);
        verify(mockPrefs.setDouble('chart_rendering_quality', 1.0)).called(1);
        verify(mockPrefs.setString('preferred_units', 'metric')).called(1);
        verify(mockPrefs.setDouble('gps_update_interval', 1.0)).called(1);
        verifyInfoLogged(
          mockLogger,
          'Settings reset to marine navigation defaults',
        );
      });
    });

    group('Integration with AppSettings Tests', () {
      test('should convert settings to AppSettings model', () async {
        // Arrange
        when(mockPrefs.getString('theme_mode')).thenReturn('dark');
        when(mockPrefs.getBool('is_day_mode')).thenReturn(false);
        when(mockPrefs.getInt('max_concurrent_downloads')).thenReturn(5);
        when(mockPrefs.getBool('enable_gps_logging')).thenReturn(true);
        when(mockPrefs.getBool('show_debug_info')).thenReturn(true);
        when(mockPrefs.getDouble('chart_rendering_quality')).thenReturn(1.5);
        when(mockPrefs.getBool('enable_background_downloads')).thenReturn(true);
        when(mockPrefs.getBool('auto_select_chart')).thenReturn(false);
        when(mockPrefs.getString('preferred_units')).thenReturn('imperial');
        when(mockPrefs.getDouble('gps_update_interval')).thenReturn(2.0);
        when(mockPrefs.getBool('enable_offline_mode')).thenReturn(true);
        when(mockPrefs.getBool('show_advanced_features')).thenReturn(false);

        // Act
        final appSettings = await settingsService.toAppSettings();

        // Assert
        expect(appSettings.themeMode, equals(AppThemeMode.dark));
        expect(appSettings.isDayMode, isFalse);
        expect(appSettings.maxConcurrentDownloads, equals(5));
        expect(appSettings.enableGpsLogging, isTrue);
        expect(appSettings.showDebugInfo, isTrue);
        expect(appSettings.chartRenderingQuality, equals(1.5));
        expect(appSettings.enableBackgroundDownloads, isTrue);
        expect(appSettings.autoSelectChart, isFalse);
        expect(appSettings.preferredUnits, equals('imperial'));
        expect(appSettings.gpsUpdateInterval, equals(2.0));
        expect(appSettings.enableOfflineMode, isTrue);
        expect(appSettings.showAdvancedFeatures, isFalse);
      });

      test('should save AppSettings model to preferences', () async {
        // Arrange
        const appSettings = AppSettings(
          themeMode: AppThemeMode.light,
          isDayMode: true,
          maxConcurrentDownloads: 4,
          enableGpsLogging: false,
          showDebugInfo: false,
          chartRenderingQuality: 0.8,
          enableBackgroundDownloads: false,
          autoSelectChart: true,
          preferredUnits: 'metric',
          gpsUpdateInterval: 1.5,
          enableOfflineMode: false,
          showAdvancedFeatures: true,
        );

        when(mockPrefs.setString(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setBool(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setInt(any, any)).thenAnswer((_) async => true);
        when(mockPrefs.setDouble(any, any)).thenAnswer((_) async => true);

        // Act
        await settingsService.fromAppSettings(appSettings);

        // Assert
        verify(mockPrefs.setString('theme_mode', 'light')).called(1);
        verify(mockPrefs.setBool('is_day_mode', true)).called(1);
        verify(mockPrefs.setInt('max_concurrent_downloads', 4)).called(1);
        verify(mockPrefs.setBool('enable_gps_logging', false)).called(1);
        verify(mockPrefs.setBool('show_debug_info', false)).called(1);
        verify(mockPrefs.setDouble('chart_rendering_quality', 0.8)).called(1);
        verify(
          mockPrefs.setBool('enable_background_downloads', false),
        ).called(1);
        verify(mockPrefs.setBool('auto_select_chart', true)).called(1);
        verify(mockPrefs.setString('preferred_units', 'metric')).called(1);
        verify(mockPrefs.setDouble('gps_update_interval', 1.5)).called(1);
        verify(mockPrefs.setBool('enable_offline_mode', false)).called(1);
        verify(mockPrefs.setBool('show_advanced_features', true)).called(1);
        verifyInfoLogged(mockLogger, 'AppSettings model saved to preferences');
      });
    });

    group('Error Handling Tests', () {
      test('should handle SharedPreferences errors gracefully', () async {
        // Arrange
        const key = 'test_key';
        when(
          mockPrefs.getString(key),
        ).thenThrow(Exception('SharedPreferences error'));

        // Act & Assert
        expect(() => settingsService.getSetting(key), throwsA(isA<AppError>()));
        verifyErrorLogged(mockLogger, 'Failed to get setting:');
      });

      test('should handle null SharedPreferences instance', () async {
        // Arrange
        final serviceWithNullPrefs = SettingsServiceImpl(
          prefs: null,
          logger: mockLogger,
        );

        // Act & Assert
        expect(
          () => serviceWithNullPrefs.getSetting('test_key'),
          throwsA(isA<AppError>()),
        );
      });

      test('should validate setting keys', () async {
        // Arrange
        const emptyKey = '';

        // Act & Assert
        expect(
          () => settingsService.getSetting(emptyKey),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Performance and Caching Tests', () {
      test('should cache frequently accessed settings', () async {
        // Arrange
        const key = 'theme_mode';
        const value = 'dark';
        when(mockPrefs.getString(key)).thenReturn(value);

        // Act - Call multiple times
        await settingsService.getSetting(key);
        await settingsService.getSetting(key);
        await settingsService.getSetting(key);

        // Assert - Should call SharedPreferences only once due to caching
        verify(mockPrefs.getString(key)).called(1);
      });

      test('should invalidate cache when setting is updated', () async {
        // Arrange
        const key = 'theme_mode';
        const value1 = 'dark';
        const value2 = 'light';

        when(mockPrefs.getString(key)).thenReturn(value1);
        when(mockPrefs.setString(key, value2)).thenAnswer((_) async => true);

        // Act
        await settingsService.getSetting(key); // First call - cached
        await settingsService.setSetting(
          key,
          value2,
        ); // Update - should invalidate cache

        when(mockPrefs.getString(key)).thenReturn(value2);
        final updatedValue = await settingsService.getSetting(
          key,
        ); // Should fetch fresh value

        // Assert
        expect(updatedValue, equals(value2));
        verify(
          mockPrefs.getString(key),
        ).called(2); // Initial + after cache invalidation
      });
    });
  });
}
