import 'dart:io';
import 'package:path/path.dart' as path;

/// Test chart data paths and utilities for accessing NOAA ENC test fixtures
class TestChartData {
  static const String _baseFixturesPath = 'test/fixtures/charts/noaa_enc';

  /// Elliott Bay harbor-scale chart (US5WA50M)
  static String get elliottBayHarborChart =>
      path.join(_baseFixturesPath, 'US5WA50M_harbor_elliott_bay.zip');

  /// Puget Sound coastal-scale chart (US3WA01M)
  static String get pugetSoundCoastalChart =>
      path.join(_baseFixturesPath, 'US3WA01M_coastal_puget_sound.zip');

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
