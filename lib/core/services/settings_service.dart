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
}
