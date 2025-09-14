import 'dart:io';
import 'package:path/path.dart' as path;

/// Test chart data paths and utilities for accessing S57 ENC test fixtures
class TestChartData {
  // Standard S57 ENC directory structure
  static const String _baseFixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  // Legacy ZIP fixtures path (for backwards compatibility during transition)
  static const String _legacyZipPath = 'test/fixtures/charts/noaa_enc';

  /// Elliott Bay harbor-scale chart (US5WA50M) - S57 base file
  static String get elliottBayHarborChart =>
      path.join(_baseFixturesPath, 'US5WA50M', 'US5WA50M.000');

  /// Puget Sound coastal-scale chart (US3WA01M) - S57 base file  
  static String get pugetSoundCoastalChart =>
      path.join(_baseFixturesPath, 'US3WA01M', 'US3WA01M.000');
      
  /// Elliott Bay harbor-scale chart - Legacy ZIP format
  static String get elliottBayHarborChartZip =>
      path.join(_legacyZipPath, 'US5WA50M_harbor_elliott_bay.zip');

  /// Puget Sound coastal-scale chart - Legacy ZIP format
  static String get pugetSoundCoastalChartZip =>
      path.join(_legacyZipPath, 'US3WA01M_coastal_puget_sound.zip');

  /// Get absolute path to chart fixture
  static String getAbsolutePath(String relativePath) {
    return path.join(Directory.current.path, relativePath);
  }

  /// Verify chart fixture exists
  static bool chartExists(String chartPath) {
    return File(getAbsolutePath(chartPath)).existsSync();
  }

  /// Get all available test chart paths (S57 format)
  static List<String> getAllTestCharts() {
    return [elliottBayHarborChart, pugetSoundCoastalChart];
  }
  
  /// Get all available test chart paths (Legacy ZIP format)
  static List<String> getAllTestChartsZip() {
    return [elliottBayHarborChartZip, pugetSoundCoastalChartZip];
  }
  
  /// Get chart directory path for a specific chart ID
  static String getChartDirectory(String chartId) {
    return path.join(_baseFixturesPath, chartId);
  }
  
  /// Get S57 base file path for a specific chart ID  
  static String getChartBasePath(String chartId) {
    return path.join(_baseFixturesPath, chartId, '$chartId.000');
  }

  /// Chart metadata for test validation
  static const Map<String, ChartTestMetadata> chartMetadata = {
    'US5WA50M': ChartTestMetadata(
      cellId: 'US5WA50M',
      title: 'APPROACHES TO EVERETT',
      usageBand: 5,
      scale: '1:20,000',
      region: 'Elliott Bay, Seattle Harbor',
      expectedSizeBytes: 147361,
      sha256:
          'B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE',
    ),
    'US3WA01M': ChartTestMetadata(
      cellId: 'US3WA01M',
      title: 'Puget Sound Coastal',
      usageBand: 3,
      scale: '1:90,000',
      region: 'Puget Sound region',
      expectedSizeBytes: 640268,
      sha256: '', // To be filled when available
    ),
  };
}

/// Metadata for test chart validation
class ChartTestMetadata {
  final String cellId;
  final String title;
  final int usageBand;
  final String scale;
  final String region;
  final int expectedSizeBytes;
  final String sha256;

  const ChartTestMetadata({
    required this.cellId,
    required this.title,
    required this.usageBand,
    required this.scale,
    required this.region,
    required this.expectedSizeBytes,
    required this.sha256,
  });
}
