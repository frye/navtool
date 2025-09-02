import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../logging/app_logger.dart';
import '../error/app_error.dart';
import '../state/settings_state.dart';
import '../state/app_state.dart';
import 'settings_service.dart';

/// Implementation of SettingsService using SharedPreferences
/// Provides persistent storage for app configuration with marine navigation defaults
class SettingsServiceImpl implements SettingsService {
  final SharedPreferences? _prefs;
  final AppLogger _logger;
  
  // Cache for frequently accessed settings
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiration = Duration(minutes: 5);

  SettingsServiceImpl({
    required SharedPreferences? prefs,
    required AppLogger logger,
  }) : _prefs = prefs,
       _logger = logger;

  /// Validates that SharedPreferences is available
  void _validatePrefs() {
    if (_prefs == null) {
      throw AppError(
        message: 'SharedPreferences not initialized',
        type: AppErrorType.storage,
      );
    }
  }

  /// Validates setting key
  void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError('Setting key cannot be empty');
    }
  }

  /// Gets cached value if still valid
  T? _getCached<T>(String key) {
    if (_cache.containsKey(key)) {
      final timestamp = _cacheTimestamps[key];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) < _cacheExpiration) {
        return _cache[key] as T?;
      } else {
        // Remove expired cache entry
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }
    return null;
  }

  /// Caches a value with timestamp
  void _setCached(String key, dynamic value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// Invalidates cache for a key
  void _invalidateCache(String key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
  }

  @override
  Future<String?> getSetting(String key) async {
    try {
      _validateKey(key);
      _validatePrefs();

      // Check cache first
      final cached = _getCached<String>(key);
      if (cached != null) {
        return cached;
      }

  final prefs = _prefs; // safe after _validatePrefs
  final value = prefs!.getString(key);
      if (value != null) {
        _setCached(key, value);
      }
      
      return value;
    } catch (error) {
      _logger.error('Failed to get setting: $key', exception: error);
      throw AppError(
        message: 'Failed to get setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> setSetting(String key, String value) async {
    try {
      _validateKey(key);
      _validatePrefs();
      
      // Validate specific settings
      _validateSettingValue(key, value);

      final success = await _prefs!.setString(key, value);
      if (!success) {
        throw AppError(
          message: 'Failed to save setting to storage',
          type: AppErrorType.storage,
        );
      }

      _invalidateCache(key);
      _logger.debug('Setting saved: $key = $value');
    } catch (error) {
      if (error is AppError) rethrow;
      _logger.error('Failed to set setting: $key', exception: error);
      throw AppError(
        message: 'Failed to set setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> deleteSetting(String key) async {
    try {
      _validateKey(key);
      _validatePrefs();

      if (!_prefs!.containsKey(key)) {
        _logger.warning('Attempted to delete non-existent setting: $key');
        return;
      }

      await _prefs!.remove(key);
      _invalidateCache(key);
      _logger.debug('Setting deleted: $key');
    } catch (error) {
      _logger.error('Failed to delete setting: $key', exception: error);
      throw AppError(
        message: 'Failed to delete setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<bool> getBool(String key) async {
    try {
      _validateKey(key);
      _validatePrefs();

      // Check cache first
      final cached = _getCached<bool>(key);
      if (cached != null) {
        return cached;
      }

  final prefs = _prefs; // safe after _validatePrefs
  final value = prefs!.getBool(key) ?? false;
      _setCached(key, value);
      
      return value;
    } catch (error) {
      _logger.error('Failed to get bool setting: $key', exception: error);
      throw AppError(
        message: 'Failed to get bool setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> setBool(String key, bool value) async {
    try {
      _validateKey(key);
      _validatePrefs();

  final success = await _prefs!.setBool(key, value);
      if (!success) {
        throw AppError(
          message: 'Failed to save bool setting to storage',
          type: AppErrorType.storage,
        );
      }

      _invalidateCache(key);
      _logger.debug('Boolean setting saved: $key = $value');
    } catch (error) {
      if (error is AppError) rethrow;
      _logger.error('Failed to set bool setting: $key', exception: error);
      throw AppError(
        message: 'Failed to set bool setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<int> getInt(String key) async {
    try {
      _validateKey(key);
      _validatePrefs();

      // Check cache first
      final cached = _getCached<int>(key);
      if (cached != null) {
        return cached;
      }

  final prefs = _prefs; // safe after _validatePrefs
  final value = prefs!.getInt(key) ?? 0;
      _setCached(key, value);
      
      return value;
    } catch (error) {
      _logger.error('Failed to get int setting: $key', exception: error);
      throw AppError(
        message: 'Failed to get int setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> setInt(String key, int value) async {
    try {
      _validateKey(key);
      _validatePrefs();
      
      // Validate marine navigation ranges
      _validateIntegerValue(key, value);

  final success = await _prefs!.setInt(key, value);
      if (!success) {
        throw AppError(
          message: 'Failed to save int setting to storage',
          type: AppErrorType.storage,
        );
      }

      _invalidateCache(key);
      _logger.debug('Integer setting saved: $key = $value');
    } catch (error) {
      if (error is AppError) rethrow;
      _logger.error('Failed to set int setting: $key', exception: error);
      throw AppError(
        message: 'Failed to set int setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<double> getDouble(String key) async {
    try {
      _validateKey(key);
      _validatePrefs();

      // Check cache first
      final cached = _getCached<double>(key);
      if (cached != null) {
        return cached;
      }

  final prefs = _prefs; // safe after _validatePrefs
  final value = prefs!.getDouble(key) ?? 0.0;
      _setCached(key, value);
      
      return value;
    } catch (error) {
      _logger.error('Failed to get double setting: $key', exception: error);
      throw AppError(
        message: 'Failed to get double setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> setDouble(String key, double value) async {
    try {
      _validateKey(key);
      _validatePrefs();
      
      // Validate marine navigation ranges
      _validateDoubleValue(key, value);

  final success = await _prefs!.setDouble(key, value);
      if (!success) {
        throw AppError(
          message: 'Failed to save double setting to storage',
          type: AppErrorType.storage,
        );
      }

      _invalidateCache(key);
      _logger.debug('Double setting saved: $key = $value');
    } catch (error) {
      if (error is AppError) rethrow;
      _logger.error('Failed to set double setting: $key', exception: error);
      throw AppError(
        message: 'Failed to set double setting: $key',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> exportSettings() async {
    try {
      _validatePrefs();

      final keys = _prefs!.getKeys();
      final settings = <String, dynamic>{};
      
      for (final key in keys) {
        settings[key] = _prefs!.get(key);
      }

      // Add metadata
      final packageInfo = await PackageInfo.fromPlatform();
      settings['export_timestamp'] = DateTime.now().toIso8601String();
      settings['app_version'] = packageInfo.version;

      _logger.info('Settings exported successfully');
      return settings;
    } catch (error) {
      _logger.error('Failed to export settings', exception: error);
      throw AppError(
        message: 'Failed to export settings',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> importSettings(Map<String, dynamic> backup) async {
    try {
      _validatePrefs();

      // Validate backup data first
      _validateBackupData(backup);

      // Import settings (skip metadata)
      for (final entry in backup.entries) {
        final key = entry.key;
        final value = entry.value;

        // Skip metadata
        if (['export_timestamp', 'app_version'].contains(key)) {
          continue;
        }

        // Set based on type
        if (value is String) {
          await setSetting(key, value);
        } else if (value is bool) {
          await setBool(key, value);
        } else if (value is int) {
          await setInt(key, value);
        } else if (value is double) {
          await setDouble(key, value);
        }
      }

      _logger.info('Settings imported successfully from backup');
    } catch (error) {
      if (error is AppError) rethrow;
      _logger.error('Failed to import settings', exception: error);
      throw AppError(
        message: 'Failed to import settings',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> clearAllSettings() async {
    try {
      _validatePrefs();

      final keys = _prefs!.getKeys();
      for (final key in keys) {
        await _prefs!.remove(key);
      }

      // Clear cache
      _cache.clear();
      _cacheTimestamps.clear();

      _logger.info('All settings cleared');
    } catch (error) {
      _logger.error('Failed to clear all settings', exception: error);
      throw AppError(
        message: 'Failed to clear all settings',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<void> resetToDefaults() async {
    try {
      _validatePrefs();

      // Set marine navigation defaults
      await setString('theme_mode', 'system');
      await setBool('is_day_mode', true);
      await setInt('max_concurrent_downloads', 3);
      await setBool('enable_gps_logging', false);
      await setBool('show_debug_info', false);
      await setDouble('chart_rendering_quality', 1.0);
      await setBool('enable_background_downloads', true);
      await setBool('auto_select_chart', true);
      await setString('preferred_units', 'metric');
      await setDouble('gps_update_interval', 1.0);
      await setBool('enable_offline_mode', false);
      await setBool('show_advanced_features', false);

      _logger.info('Settings reset to marine navigation defaults');
    } catch (error) {
      _logger.error('Failed to reset settings to defaults', exception: error);
      throw AppError(
        message: 'Failed to reset settings to defaults',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  @override
  Future<AppSettings> toAppSettings() async {
    try {
      final themeModeName = await getString('theme_mode');
      final themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == themeModeName,
        orElse: () => AppThemeMode.system,
      );

      return AppSettings(
        themeMode: themeMode,
        isDayMode: await getBool('is_day_mode'),
        maxConcurrentDownloads: await getInt('max_concurrent_downloads'),
        enableGpsLogging: await getBool('enable_gps_logging'),
        showDebugInfo: await getBool('show_debug_info'),
        chartRenderingQuality: await getDouble('chart_rendering_quality'),
        enableBackgroundDownloads: await getBool('enable_background_downloads'),
        autoSelectChart: await getBool('auto_select_chart'),
        preferredUnits: await getString('preferred_units') ?? 'metric',
        gpsUpdateInterval: await getDouble('gps_update_interval'),
        enableOfflineMode: await getBool('enable_offline_mode'),
        showAdvancedFeatures: await getBool('show_advanced_features'),
      );
    } catch (error) {
      _logger.error('Failed to convert to AppSettings', exception: error);
      throw AppError(
        message: 'Failed to convert to AppSettings',
        type: AppErrorType.parsing,
        originalError: error,
      );
    }
  }

  @override
  Future<void> fromAppSettings(AppSettings settings) async {
    try {
      await setString('theme_mode', settings.themeMode.name);
      await setBool('is_day_mode', settings.isDayMode);
      await setInt('max_concurrent_downloads', settings.maxConcurrentDownloads);
      await setBool('enable_gps_logging', settings.enableGpsLogging);
      await setBool('show_debug_info', settings.showDebugInfo);
      await setDouble('chart_rendering_quality', settings.chartRenderingQuality);
      await setBool('enable_background_downloads', settings.enableBackgroundDownloads);
      await setBool('auto_select_chart', settings.autoSelectChart);
      await setString('preferred_units', settings.preferredUnits);
      await setDouble('gps_update_interval', settings.gpsUpdateInterval);
      await setBool('enable_offline_mode', settings.enableOfflineMode);
      await setBool('show_advanced_features', settings.showAdvancedFeatures);

      _logger.info('AppSettings model saved to preferences');
    } catch (error) {
      _logger.error('Failed to save AppSettings to preferences', exception: error);
      throw AppError(
        message: 'Failed to save AppSettings to preferences',
        type: AppErrorType.storage,
        originalError: error,
      );
    }
  }

  /// Helper method for setting string values (used internally)
  Future<void> setString(String key, String value) async {
    await setSetting(key, value);
  }

  /// Helper method for getting string values (used internally)
  Future<String?> getString(String key) async {
    return await getSetting(key);
  }

  /// Validates setting values for marine navigation standards
  void _validateSettingValue(String key, String value) {
    switch (key) {
      case 'preferred_units':
        if (!['metric', 'imperial'].contains(value)) {
          throw AppError(
            message: 'Invalid units: $value. Must be "metric" or "imperial"',
            type: AppErrorType.validation,
          );
        }
        break;
      case 'theme_mode':
        if (!['system', 'light', 'dark'].contains(value)) {
          throw AppError(
            message: 'Invalid theme mode: $value',
            type: AppErrorType.validation,
          );
        }
        break;
    }
  }

  /// Validates integer values for marine navigation ranges
  void _validateIntegerValue(String key, int value) {
    switch (key) {
      case 'max_concurrent_downloads':
        if (value < 1 || value > 10) {
          throw AppError(
            message: 'Invalid max concurrent downloads: $value. Must be between 1 and 10',
            type: AppErrorType.validation,
          );
        }
        break;
    }
  }

  /// Validates double values for marine navigation ranges
  void _validateDoubleValue(String key, double value) {
    switch (key) {
      case 'chart_rendering_quality':
        if (value < 0.1 || value > 2.0) {
          throw AppError(
            message: 'Invalid chart rendering quality: $value. Must be between 0.1 and 2.0',
            type: AppErrorType.validation,
          );
        }
        break;
      case 'gps_update_interval':
        if (value < 0.1 || value > 60.0) {
          throw AppError(
            message: 'Invalid GPS update interval: $value. Must be between 0.1 and 60.0 seconds',
            type: AppErrorType.validation,
          );
        }
        break;
    }
  }

  /// Validates backup data before import
  void _validateBackupData(Map<String, dynamic> backup) {
    // Validate critical settings if present
    if (backup.containsKey('preferred_units')) {
      final units = backup['preferred_units'];
      if (units is String && !['metric', 'imperial'].contains(units)) {
        throw AppError(
          message: 'Invalid backup data: invalid units',
          type: AppErrorType.validation,
        );
      }
    }

    if (backup.containsKey('max_concurrent_downloads')) {
      final downloads = backup['max_concurrent_downloads'];
      if (downloads is int && (downloads < 1 || downloads > 10)) {
        throw AppError(
          message: 'Invalid backup data: invalid max concurrent downloads',
          type: AppErrorType.validation,
        );
      }
    }

    if (backup.containsKey('chart_rendering_quality')) {
      final quality = backup['chart_rendering_quality'];
      if (quality is double && (quality < 0.1 || quality > 2.0)) {
        throw AppError(
          message: 'Invalid backup data: invalid chart rendering quality',
          type: AppErrorType.validation,
        );
      }
    }

    if (backup.containsKey('theme_mode')) {
      final theme = backup['theme_mode'];
      if (theme is String && !['system', 'light', 'dark'].contains(theme)) {
        throw AppError(
          message: 'Invalid backup data: invalid theme mode',
          type: AppErrorType.validation,
        );
      }
    }
  }
}