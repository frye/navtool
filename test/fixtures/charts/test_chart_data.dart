import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/fixture_paths.dart';

/// Test chart data paths and utilities for accessing NOAA ENC test fixtures
/// 
/// DEPRECATED: Use FixturePaths.ChartPaths constants instead for new code.
/// This class is maintained for backward compatibility only.
class TestChartData {
  @Deprecated('Use FixturePaths.s57Data instead')
  static const String _baseFixturesPath = 'test/fixtures/charts/s57_data';

  /// Elliott Bay harbor-scale chart (US5WA50M)
  @Deprecated('Use FixturePaths.ChartPaths.elliottBayZip instead')
  static String get elliottBayHarborChart => FixturePaths.ChartPaths.elliottBayZip;

  /// Puget Sound coastal-scale chart (US3WA01M)
  @Deprecated('Use FixturePaths.ChartPaths.pugetSoundZip instead')
  static String get pugetSoundCoastalChart => FixturePaths.ChartPaths.pugetSoundZip;

  /// Get absolute path to chart fixture
  @Deprecated('Use FixtureUtils.getAbsolutePath instead')
  static String getAbsolutePath(String relativePath) {
    return FixtureUtils.getAbsolutePath(relativePath);
  }

  /// Verify chart fixture exists
  @Deprecated('Use FixtureUtils.exists instead')
  static bool chartExists(String chartPath) {
    return FixtureUtils.exists(chartPath);
  }

  /// Get all available test chart paths
  @Deprecated('Use FixturePaths.ChartPaths constants instead')
  static List<String> getAllTestCharts() {
    return [FixturePaths.ChartPaths.elliottBayZip, FixturePaths.ChartPaths.pugetSoundZip];
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
