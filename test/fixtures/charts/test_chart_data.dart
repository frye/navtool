import 'dart:io';
import 'package:path/path.dart' as path;

/// Test chart data paths and utilities for accessing NOAA ENC test fixtures
/// 
/// UPDATED: Now uses the correct S57 fixture path as standardized by S57TestFixtures.
/// The old 'noaa_enc' path was incorrect - real fixtures are in 's57_data/ENC_ROOT'.
class TestChartData {
  static const String _baseFixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';

  /// Elliott Bay harbor-scale chart (US5WA50M) - Raw S57 .000 file
  static String get elliottBayHarborChart =>
      path.join(_baseFixturesPath, 'US5WA50M', 'US5WA50M.000');

  /// Puget Sound coastal-scale chart (US3WA01M) - Raw S57 .000 file
  static String get pugetSoundCoastalChart =>
      path.join(_baseFixturesPath, 'US3WA01M', 'US3WA01M.000');

  /// Get absolute path to chart fixture
  static String getAbsolutePath(String relativePath) {
    return path.join(Directory.current.path, relativePath);
  }

  /// Verify chart fixture exists
  static bool chartExists(String chartPath) {
    return File(getAbsolutePath(chartPath)).existsSync();
  }

  /// Get all available test chart paths
  static List<String> getAllTestCharts() {
    return [elliottBayHarborChart, pugetSoundCoastalChart];
  }

  /// Chart metadata for test validation
  static const Map<String, ChartTestMetadata> chartMetadata = {
    'US5WA50M': ChartTestMetadata(
      cellId: 'US5WA50M',
      title: 'ELLIOTT BAY AND SEATTLE HARBOR',
      usageBand: 5,
      scale: '1:20,000',
      region: 'Elliott Bay, Seattle Harbor',
      expectedSizeBytes: 411513, // Raw .000 file size
      sha256: '', // Real S57 file - checksum to be calculated if needed
    ),
    'US3WA01M': ChartTestMetadata(
      cellId: 'US3WA01M', 
      title: 'PUGET SOUND NORTHERN PART',
      usageBand: 3,
      scale: '1:90,000',
      region: 'Puget Sound region',
      expectedSizeBytes: 1583161, // Raw .000 file size
      sha256: '', // Real S57 file - checksum to be calculated if needed
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
