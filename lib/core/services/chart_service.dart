import '../models/chart.dart';

/// Service interface for chart-related operations
abstract class ChartService {
  /// Loads a chart by its ID
  Future<Chart?> loadChart(String chartId);

  /// Gets all available charts
  Future<List<Chart>> getAvailableCharts();

  /// Searches charts by query
  Future<List<Chart>> searchCharts(String query);

  /// Parses S-57 chart data
  Future<Map<String, dynamic>> parseS57Data(List<int> data);

  /// Validates chart data integrity
  Future<bool> validateChartData(List<int> data);
}
