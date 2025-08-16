import '../state/settings_state.dart';

/// Service interface for application settings
abstract class SettingsService {
  /// Gets a setting value as string
  Future<String?> getSetting(String key);

  /// Sets a setting value
  Future<void> setSetting(String key, String value);

  /// Deletes a setting
  Future<void> deleteSetting(String key);

  /// Gets a boolean setting
  Future<bool> getBool(String key);

  /// Sets a boolean setting
  Future<void> setBool(String key, bool value);

  /// Gets an integer setting
  Future<int> getInt(String key);

  /// Sets an integer setting
  Future<void> setInt(String key, int value);

  /// Gets a double setting
  Future<double> getDouble(String key);

  /// Sets a double setting
  Future<void> setDouble(String key, double value);

  // Enhanced functionality for backup/restore and integration

  /// Exports all settings to a backup format
  Future<Map<String, dynamic>> exportSettings();

  /// Imports settings from a backup
  Future<void> importSettings(Map<String, dynamic> backup);

  /// Clears all settings
  Future<void> clearAllSettings();

  /// Resets settings to marine navigation defaults
  Future<void> resetToDefaults();

  /// Converts current settings to AppSettings model
  Future<AppSettings> toAppSettings();

  /// Saves AppSettings model to preferences
  Future<void> fromAppSettings(AppSettings settings);
}
