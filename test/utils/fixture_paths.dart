import 'dart:io' as io;
import 'package:path/path.dart' as path;

/// Centralized fixture path constants to prevent path inconsistencies
/// 
/// All test files should use these constants instead of hardcoded paths
/// to ensure consistency across the NavTool test suite.
class FixturePaths {
  /// Base path for all chart-related test fixtures
  static const String charts = 'test/fixtures/charts';
  
  /// Base path for S57 chart data (both ZIP and extracted files)
  static const String s57Data = '$charts/s57_data';
  
  /// Path to S57 extracted chart files (.000 format)
  static const String s57EncRoot = '$s57Data/ENC_ROOT';
  
  /// Path to golden snapshot files for regression testing
  static const String golden = 'test/fixtures/golden';
  
  /// Chart-specific paths
  static class ChartPaths {
    /// Elliott Bay Harbor chart (US5WA50M) ZIP file
    static const String elliottBayZip = '$s57Data/US5WA50M_harbor_elliott_bay.zip';
    
    /// Elliott Bay Harbor chart (US5WA50M) extracted S57 file
    static const String elliottBayS57 = '$s57EncRoot/US5WA50M/US5WA50M.000';
    
    /// Puget Sound Coastal chart (US3WA01M) ZIP file
    static const String pugetSoundZip = '$s57Data/US3WA01M_coastal_puget_sound.zip';
    
    /// Puget Sound Coastal chart (US3WA01M) extracted S57 file
    static const String pugetSoundS57 = '$s57EncRoot/US3WA01M/US3WA01M.000';
  }
  
  /// Other fixture categories
  static class OtherFixtures {
    /// Geometry test fixtures
    static const String geometry = 'test/fixtures/geometry';
    
    /// ISO8211 test fixtures
    static const String iso8211 = 'test/fixtures/iso8211';
    
    /// S57 object test fixtures
    static const String s57Objects = 'test/fixtures/s57';
    
    /// State boundaries test fixtures
    static const String stateBoundaries = 'test/fixtures/state_boundaries_sample.json';
    
    /// Enhanced NOAA catalog fixtures
    static const String enhancedNoaaCatalog = 'test/fixtures/enhanced_noaa_catalog.json';
    
    /// Updates test fixtures
    static const String updates = 'test/fixtures/updates';
  }
}

/// Utility methods for working with fixture paths
class FixtureUtils {
  /// Check if a fixture file exists
  static bool exists(String fixturePath) {
    final file = io.File(fixturePath);
    return file.existsSync();
  }
  
  /// Get absolute path for a fixture
  static String getAbsolutePath(String relativePath) {
    return path.join(io.Directory.current.path, relativePath);
  }
  
  /// Validate that required chart fixtures are available
  static FixtureValidationResult validateChartFixtures() {
    final missing = <String>[];
    
    // Check ZIP files
    if (!exists(FixturePaths.ChartPaths.elliottBayZip)) {
      missing.add('Elliott Bay ZIP: ${FixturePaths.ChartPaths.elliottBayZip}');
    }
    if (!exists(FixturePaths.ChartPaths.pugetSoundZip)) {
      missing.add('Puget Sound ZIP: ${FixturePaths.ChartPaths.pugetSoundZip}');
    }
    
    // Check extracted S57 files
    if (!exists(FixturePaths.ChartPaths.elliottBayS57)) {
      missing.add('Elliott Bay S57: ${FixturePaths.ChartPaths.elliottBayS57}');
    }
    if (!exists(FixturePaths.ChartPaths.pugetSoundS57)) {
      missing.add('Puget Sound S57: ${FixturePaths.ChartPaths.pugetSoundS57}');
    }
    
    return FixtureValidationResult(
      allAvailable: missing.isEmpty,
      missingFixtures: missing,
      basePath: FixturePaths.s57Data,
    );
  }
}

/// Result of fixture validation
class FixtureValidationResult {
  final bool allAvailable;
  final List<String> missingFixtures;
  final String basePath;
  
  const FixtureValidationResult({
    required this.allAvailable,
    required this.missingFixtures,
    required this.basePath,
  });
  
  String get statusMessage {
    if (allAvailable) {
      return 'All chart fixtures are available';
    } else {
      return 'Missing fixtures: ${missingFixtures.join(', ')}. '
             'Install fixtures at: $basePath';
    }
  }
}