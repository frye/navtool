import '../models/chart.dart';
import '../models/geographic_bounds.dart';

/// Washington State chart test data using existing Elliott Bay test charts
/// Based on actual NOAA test fixtures in test/fixtures/charts/noaa_enc/
class WashingtonTestCharts {
  /// Elliott Bay test charts with real file data available
  static final List<Chart> _elliottBayCharts = [
    // US5WA50M - Elliott Bay Harbor Chart (actual test chart)
    Chart(
      id: 'US5WA50M',
      title: 'APPROACHES TO EVERETT - Elliott Bay Harbor',
      scale: 20000,
      bounds: GeographicBounds(
        north: 47.7,
        south: 47.5,
        east: -122.2,
        west: -122.4,
      ),
      state: 'Washington',
      type: ChartType.harbor,
      description: 'Harbor-scale chart covering Elliott Bay and Seattle Harbor',
      isDownloaded: true,
      fileSize: 147361, // 143.9 KB from test fixtures
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
    
    // US3WA01M - Puget Sound Coastal Chart (actual test chart)  
    Chart(
      id: 'US3WA01M',
      title: 'PUGET SOUND - NORTHERN PART - Coastal Overview',
      scale: 90000,
      bounds: GeographicBounds(
        north: 48.5,
        south: 47.0,
        east: -122.0,
        west: -123.0,
      ),
      state: 'Washington',
      type: ChartType.coastal,
      description: 'Coastal-scale chart covering broader Puget Sound region',
      isDownloaded: true,
      fileSize: 640268, // 625.3 KB from test fixtures
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
  ];
  
  /// Additional synthetic Washington charts for comprehensive coverage
  static final List<Chart> _syntheticWashingtonCharts = [
    // US1WC01M - Columbia River to Destruction Island
    Chart(
      id: 'US1WC01M',
      title: 'Columbia River to Destruction Island',
      scale: 80000,
      bounds: GeographicBounds(
        north: 48.5,
        south: 46.0,
        east: -123.5,
        west: -124.8,
      ),
      state: 'Washington',
      type: ChartType.general,
      description: 'General chart covering Washington coastal waters',
      isDownloaded: false,
      fileSize: 0,
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
    
    // US5WA10M - Strait of Juan de Fuca
    Chart(
      id: 'US5WA10M',
      title: 'Strait of Juan de Fuca',
      scale: 50000,
      bounds: GeographicBounds(
        north: 48.5,
        south: 47.5,
        east: -122.5,
        west: -124.8,
      ),
      state: 'Washington',
      type: ChartType.approach,
      description: 'Approach chart for northern Washington waters',
      isDownloaded: false,
      fileSize: 0,
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
    
    // US4WA02M - San Juan Islands
    Chart(
      id: 'US4WA02M',
      title: 'San Juan Islands',
      scale: 40000,
      bounds: GeographicBounds(
        north: 48.8,
        south: 48.4,
        east: -122.6,
        west: -123.2,
      ),
      state: 'Washington',
      type: ChartType.coastal,
      description: 'Coastal chart covering San Juan Islands archipelago',
      isDownloaded: false,
      fileSize: 0,
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
    
    // US2WA03M - Admiralty Inlet  
    Chart(
      id: 'US2WA03M',
      title: 'Admiralty Inlet',
      scale: 30000,
      bounds: GeographicBounds(
        north: 48.2,
        south: 47.9,
        east: -122.5,
        west: -122.8,
      ),
      state: 'Washington',
      type: ChartType.approach,
      description: 'Approach chart for Admiralty Inlet and Port Townsend',
      isDownloaded: false,
      fileSize: 0,
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      lastUpdate: DateTime.now(),
    ),
  ];

  /// Get all Washington test charts (Elliott Bay + synthetic)
  static List<Chart> getAllCharts() {
    return [..._elliottBayCharts, ..._syntheticWashingtonCharts];
  }

  /// Get only Elliott Bay charts with real test data
  static List<Chart> getElliottBayCharts() {
    return List.from(_elliottBayCharts);
  }
  
  /// Get charts for a specific state (case insensitive)
  static List<Chart> getChartsForState(String state) {
    if (state.toLowerCase() == 'washington') {
      return getAllCharts();
    }
    return [];
  }
  
  /// Check if a chart ID is an Elliott Bay test chart with real data
  static bool hasRealChartData(String chartId) {
    return _elliottBayCharts.any((chart) => chart.id == chartId);
  }
  
  /// Get the file path for a real Elliott Bay test chart
  /// Get test chart path, preferring S57 format over ZIP
  static String? getTestChartPath(String chartId) {
    // Check S57 format first (preferred)
    final s57Path = getTestChartS57Path(chartId);
    if (s57Path != null) {
      return s57Path;
    }
    
    // Fallback to legacy ZIP format
    return getTestChartZipPath(chartId);
  }
  
  /// Get S57 format test chart path
  static String? getTestChartS57Path(String chartId) {
    switch (chartId) {
      case 'US5WA50M':
        return 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000';
      case 'US3WA01M':
        return 'test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000';
      default:
        return null;
    }
  }
  
  /// Get legacy ZIP format test chart path
  static String? getTestChartZipPath(String chartId) {
    switch (chartId) {
      case 'US5WA50M':
        return 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
      case 'US3WA01M':
        return 'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip';
      default:
        return null;
    }
  }
}