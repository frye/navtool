import '../models/chart.dart';

/// Service interface for storage operations
abstract class StorageService {
  /// Stores chart data locally
  Future<void> storeChart(Chart chart, List<int> data);

  /// Loads chart data from local storage
  Future<List<int>?> loadChart(String chartId);

  /// Deletes a chart from local storage
  Future<void> deleteChart(String chartId);

  /// Gets storage information (used space, available space, etc.)
  Future<Map<String, dynamic>> getStorageInfo();

  /// Cleans up old or unused data
  Future<void> cleanupOldData();

  /// Gets total storage usage in bytes
  Future<int> getStorageUsage();
}
