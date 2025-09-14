/// S57 test fixtures utility for real NOAA ENC data usage
/// 
/// Loads actual NOAA ENC S57 chart data for testing instead of artificial/synthetic data.
/// Provides caching and error handling for performance and reliability.
///
/// Usage:
/// ```dart
/// // Load Elliott Bay Harbor chart (US5WA50M - 411KB)
/// final elliottBayData = await S57TestFixtures.loadElliottBayChart();
/// final parsedChart = await S57TestFixtures.loadParsedElliottBay();
/// 
/// // Load Puget Sound chart (US3WA01M - 1.58MB)  
/// final pugetSoundData = await S57TestFixtures.loadPugetSoundChart();
/// final parsedChart = await S57TestFixtures.loadParsedPugetSound();
/// ```

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';
import 'package:navtool/core/error/app_error.dart';
import 'test_logger.dart';

/// S57 test fixtures utility for real NOAA ENC data
/// 
/// Provides methods to load actual NOAA ENC S57 charts for testing,
/// replacing artificial/synthetic chart data with real marine navigation data.
class S57TestFixtures {
  /// Base path to S57 chart fixtures
  static const String fixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  /// Elliott Bay Harbor chart (US5WA50M) - Harbor scale, ~411KB
  static const String _elliottBayPath = '$fixturesPath/US5WA50M/US5WA50M.000';
  static const String _elliottBayId = 'US5WA50M';
  
  /// Puget Sound chart (US3WA01M) - Coastal scale, ~1.58MB
  static const String _pugetSoundPath = '$fixturesPath/US3WA01M/US3WA01M.000';
  static const String _pugetSoundId = 'US3WA01M';
  
  // Cache for parsed chart data to improve test performance
  static S57ParsedData? _cachedElliottBay;
  static S57ParsedData? _cachedPugetSound;
  static List<int>? _cachedElliottBayRaw;
  static List<int>? _cachedPugetSoundRaw;
  
  /// Load Elliott Bay Harbor chart raw S57 data
  /// 
  /// Returns the raw binary S57 data as bytes for US5WA50M.000
  /// This is the smaller chart (411KB) suitable for fast unit tests.
  static Future<List<int>> loadElliottBayChart() async {
    if (_cachedElliottBayRaw != null) {
      testLogger.debug('Using cached Elliott Bay raw data');
      return _cachedElliottBayRaw!;
    }
    
    testLogger.debug('Loading Elliott Bay chart: $_elliottBayPath');
    
    final file = File(_elliottBayPath);
    if (!await file.exists()) {
      throw TestFailure(
        'Elliott Bay chart fixture not found: $_elliottBayPath\n'
        'Ensure NOAA ENC test fixtures are properly installed.',
      );
    }
    
    try {
      final data = await file.readAsBytes();
      _cachedElliottBayRaw = data;
      
      testLogger.info(
        'Loaded Elliott Bay chart: ${data.length} bytes ($_elliottBayId)',
      );
      
      return data;
    } catch (e) {
      throw TestFailure(
        'Failed to load Elliott Bay chart: $e\n'
        'Path: $_elliottBayPath',
      );
    }
  }
  
  /// Load Puget Sound chart raw S57 data
  /// 
  /// Returns the raw binary S57 data as bytes for US3WA01M.000
  /// This is the larger chart (1.58MB) suitable for integration tests.
  static Future<List<int>> loadPugetSoundChart() async {
    if (_cachedPugetSoundRaw != null) {
      testLogger.debug('Using cached Puget Sound raw data');
      return _cachedPugetSoundRaw!;
    }
    
    testLogger.debug('Loading Puget Sound chart: $_pugetSoundPath');
    
    final file = File(_pugetSoundPath);
    if (!await file.exists()) {
      throw TestFailure(
        'Puget Sound chart fixture not found: $_pugetSoundPath\n'
        'Ensure NOAA ENC test fixtures are properly installed.',
      );
    }
    
    try {
      final data = await file.readAsBytes();
      _cachedPugetSoundRaw = data;
      
      testLogger.info(
        'Loaded Puget Sound chart: ${data.length} bytes ($_pugetSoundId)',
      );
      
      return data;
    } catch (e) {
      throw TestFailure(
        'Failed to load Puget Sound chart: $e\n'
        'Path: $_pugetSoundPath',
      );
    }
  }
  
  /// Load and parse Elliott Bay Harbor chart
  /// 
  /// Returns parsed S57 data with features, metadata, and spatial indexing.
  /// Results are cached for performance in subsequent test calls.
  static Future<S57ParsedData> loadParsedElliottBay({
    bool useWarningCollector = false,
  }) async {
    if (_cachedElliottBay != null) {
      testLogger.debug('Using cached Elliott Bay parsed data');
      return _cachedElliottBay!;
    }
    
    testLogger.debug('Parsing Elliott Bay chart data');
    
    try {
      final rawData = await loadElliottBayChart();
      final warnings = useWarningCollector ? S57WarningCollector() : null;
      
      final stopwatch = Stopwatch()..start();
      final parsedData = S57Parser.parse(rawData, warnings: warnings);
      stopwatch.stop();
      
      _cachedElliottBay = parsedData;
      
      testLogger.info(
        'Parsed Elliott Bay chart: ${parsedData.features.length} features '
        'in ${stopwatch.elapsedMilliseconds}ms ($_elliottBayId)',
      );
      
      if (warnings != null && warnings.hasWarnings) {
        testLogger.warn(
          'Elliott Bay parsing warnings: ${warnings.warningCount} total',
        );
      }
      
      return parsedData;
    } catch (e) {
      if (e is AppError) {
        throw TestFailure(
          'Failed to parse Elliott Bay chart: ${e.message}\n'
          'Error type: ${e.type}\n'
          'Chart: $_elliottBayId',
        );
      }
      throw TestFailure(
        'Failed to parse Elliott Bay chart: $e\n'
        'Chart: $_elliottBayId',
      );
    }
  }
  
  /// Load and parse Puget Sound chart
  /// 
  /// Returns parsed S57 data with features, metadata, and spatial indexing.
  /// Results are cached for performance in subsequent test calls.
  static Future<S57ParsedData> loadParsedPugetSound({
    bool useWarningCollector = false,
  }) async {
    if (_cachedPugetSound != null) {
      testLogger.debug('Using cached Puget Sound parsed data');
      return _cachedPugetSound!;
    }
    
    testLogger.debug('Parsing Puget Sound chart data');
    
    try {
      final rawData = await loadPugetSoundChart();
      final warnings = useWarningCollector ? S57WarningCollector() : null;
      
      final stopwatch = Stopwatch()..start();
      final parsedData = S57Parser.parse(rawData, warnings: warnings);
      stopwatch.stop();
      
      _cachedPugetSound = parsedData;
      
      testLogger.info(
        'Parsed Puget Sound chart: ${parsedData.features.length} features '
        'in ${stopwatch.elapsedMilliseconds}ms ($_pugetSoundId)',
      );
      
      if (warnings != null && warnings.hasWarnings) {
        testLogger.warn(
          'Puget Sound parsing warnings: ${warnings.warningCount} total',
        );
      }
      
      return parsedData;
    } catch (e) {
      if (e is AppError) {
        throw TestFailure(
          'Failed to parse Puget Sound chart: ${e.message}\n'
          'Error type: ${e.type}\n'
          'Chart: $_pugetSoundId',
        );
      }
      throw TestFailure(
        'Failed to parse Puget Sound chart: $e\n'
        'Chart: $_pugetSoundId',
      );
    }
  }
  
  /// Validate chart metadata for correctness
  /// 
  /// Performs validation checks on S57 chart metadata to ensure
  /// the data meets marine navigation standards.
  static ChartMetadataValidation validateChartMetadata(
    S57ParsedData parsedData,
    String expectedChartId,
  ) {
    final warnings = <String>[];
    final errors = <String>[];
    final metadata = parsedData.metadata;
    
    // Validate basic metadata presence
    if (metadata.producer.isEmpty) {
      errors.add('Chart producer is empty or missing');
    }
    
    if (metadata.version.isEmpty) {
      errors.add('Chart version is empty or missing');
    }
    
    // Validate coordinate system
    if (metadata.comf == null || metadata.comf! <= 0) {
      warnings.add('Invalid or missing coordinate multiplication factor (COMF)');
    }
    
    if (metadata.somf == null || metadata.somf! <= 0) {
      warnings.add('Invalid or missing sounding multiplication factor (SOMF)');
    }
    
    // Validate scale
    if (metadata.scale == null || metadata.scale! <= 0) {
      warnings.add('Invalid or missing chart scale');
    }
    
    // Validate bounds
    if (metadata.bounds == null) {
      errors.add('Chart bounds are missing');
    } else {
      final bounds = metadata.bounds!;
      if (bounds.minLatitude >= bounds.maxLatitude) {
        errors.add('Invalid latitude bounds: min >= max');
      }
      if (bounds.minLongitude >= bounds.maxLongitude) {
        errors.add('Invalid longitude bounds: min >= max');
      }
      
      // Check if bounds are in reasonable marine areas
      if (!_isInMarineArea(bounds)) {
        warnings.add('Chart bounds may be outside typical marine areas');
      }
    }
    
    // Validate feature count
    if (parsedData.features.isEmpty) {
      errors.add('Chart contains no features');
    } else if (parsedData.features.length < 10) {
      warnings.add('Chart has very few features (${parsedData.features.length})');
    }
    
    // Validate spatial index
    if (parsedData.spatialIndex.featureCount != parsedData.features.length) {
      errors.add(
        'Spatial index feature count mismatch: '
        'index=${parsedData.spatialIndex.featureCount}, '
        'actual=${parsedData.features.length}',
      );
    }
    
    return ChartMetadataValidation(
      chartId: expectedChartId,
      isValid: errors.isEmpty,
      warnings: warnings,
      errors: errors,
      metadata: metadata,
    );
  }
  
  /// Get chart information for available fixtures
  static List<S57ChartInfo> getAvailableCharts() {
    return [
      S57ChartInfo(
        chartId: _elliottBayId,
        title: 'Elliott Bay Harbor',
        description: 'Harbor scale chart for Seattle area testing',
        filePath: _elliottBayPath,
        usageBand: 5, // Harbor
        approximateSize: 411 * 1024, // ~411KB
        features: [
          'Navigation aids (buoys, lights)',
          'Harbor depth areas',
          'Soundings',
          'Coastline features',
          'Marine facilities',
        ],
        recommendedUse: 'Unit tests, fast feedback testing',
      ),
      S57ChartInfo(
        chartId: _pugetSoundId,
        title: 'Puget Sound',
        description: 'Coastal scale chart for Puget Sound area testing',
        filePath: _pugetSoundPath,
        usageBand: 3, // Coastal
        approximateSize: 1583161, // ~1.58MB
        features: [
          'Extensive coastline data',
          'Large depth area coverage',
          'Many navigation aids',
          'Comprehensive sounding data',
          'Marine obstructions',
        ],
        recommendedUse: 'Integration tests, performance testing',
      ),
    ];
  }
  
  /// Check if all required fixtures are available
  static Future<FixtureAvailability> checkFixtureAvailability() async {
    final elliottBayExists = await File(_elliottBayPath).exists();
    final pugetSoundExists = await File(_pugetSoundPath).exists();
    
    final missing = <String>[];
    if (!elliottBayExists) missing.add('Elliott Bay ($_elliottBayId)');
    if (!pugetSoundExists) missing.add('Puget Sound ($_pugetSoundId)');
    
    return FixtureAvailability(
      allAvailable: missing.isEmpty,
      elliottBayAvailable: elliottBayExists,
      pugetSoundAvailable: pugetSoundExists,
      missingFixtures: missing,
      fixturesPath: fixturesPath,
    );
  }
  
  /// Clear all cached data (useful for memory management in long test runs)
  static void clearCache() {
    _cachedElliottBay = null;
    _cachedPugetSound = null;
    _cachedElliottBayRaw = null;
    _cachedPugetSoundRaw = null;
    testLogger.debug('S57TestFixtures cache cleared');
  }
  
  /// Get usage recommendations for test scenarios
  static String getUsageRecommendations() {
    return '''
S57TestFixtures Usage Recommendations:

1. UNIT TESTS - Use Elliott Bay (US5WA50M):
   - Fast loading (~411KB)
   - Harbor scale features
   - Good for focused feature testing
   
2. INTEGRATION TESTS - Use Puget Sound (US3WA01M):
   - More comprehensive data (~1.58MB)
   - Coastal scale coverage
   - Better for full workflow testing
   
3. PERFORMANCE TESTING:
   - Start with Elliott Bay for baseline
   - Use Puget Sound for realistic load testing
   - Clear cache between tests if measuring memory usage
   
4. FEATURE TESTING:
   - Both charts contain navigation aids, depth data, coastlines
   - Elliott Bay: More concentrated harbor features
   - Puget Sound: More diverse coastal features
   
5. CACHING BEHAVIOR:
   - Parsed data is cached automatically for performance
   - Use clearCache() between tests if needed
   - Raw data is also cached separately

Example Usage:
```dart
// Fast unit test
final chart = await S57TestFixtures.loadParsedElliottBay();
expect(chart.features.length, greaterThan(0));

// Integration test with warnings
final chart = await S57TestFixtures.loadParsedPugetSound(
  useWarningCollector: true,
);
final validation = S57TestFixtures.validateChartMetadata(chart, 'US3WA01M');
expect(validation.isValid, isTrue);
```
''';
  }
  
  // Helper method to check if bounds are in reasonable marine areas
  static bool _isInMarineArea(S57Bounds bounds) {
    // Check if bounds overlap with major US marine areas
    // This is a simplified check for NOAA chart validation
    final marineAreas = [
      // US East Coast
      _MarineArea(25.0, 45.0, -85.0, -65.0),
      // US West Coast  
      _MarineArea(32.0, 49.0, -130.0, -115.0),
      // Gulf of Mexico
      _MarineArea(18.0, 30.0, -98.0, -80.0),
      // Great Lakes
      _MarineArea(41.0, 49.0, -95.0, -76.0),
      // Alaska (partial)
      _MarineArea(54.0, 71.0, -180.0, -130.0),
      // Hawaii (partial)
      _MarineArea(18.0, 29.0, -179.0, -154.0),
    ];
    
    for (final area in marineAreas) {
      if (area.overlaps(bounds)) {
        return true;
      }
    }
    
    return false;
  }
}

/// Information about available S57 chart fixtures
class S57ChartInfo {
  final String chartId;
  final String title;
  final String description;
  final String filePath;
  final int usageBand;
  final int approximateSize;
  final List<String> features;
  final String recommendedUse;
  
  const S57ChartInfo({
    required this.chartId,
    required this.title,
    required this.description,
    required this.filePath,
    required this.usageBand,
    required this.approximateSize,
    required this.features,
    required this.recommendedUse,
  });
}

/// Result of chart metadata validation
class ChartMetadataValidation {
  final String chartId;
  final bool isValid;
  final List<String> warnings;
  final List<String> errors;
  final S57ChartMetadata metadata;
  
  const ChartMetadataValidation({
    required this.chartId,
    required this.isValid,
    required this.warnings,
    required this.errors,
    required this.metadata,
  });
  
  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
  int get totalIssues => warnings.length + errors.length;
}

/// Result of checking fixture availability
class FixtureAvailability {
  final bool allAvailable;
  final bool elliottBayAvailable;
  final bool pugetSoundAvailable;
  final List<String> missingFixtures;
  final String fixturesPath;
  
  const FixtureAvailability({
    required this.allAvailable,
    required this.elliottBayAvailable,
    required this.pugetSoundAvailable,
    required this.missingFixtures,
    required this.fixturesPath,
  });
  
  bool get hasAnyFixtures => elliottBayAvailable || pugetSoundAvailable;
  
  String get statusMessage {
    if (allAvailable) {
      return 'All S57 test fixtures are available';
    } else if (hasAnyFixtures) {
      return 'Some S57 test fixtures are available, missing: ${missingFixtures.join(', ')}';
    } else {
      return 'No S57 test fixtures found at $fixturesPath';
    }
  }
}

/// Helper class for marine area bounds checking
class _MarineArea {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  
  const _MarineArea(this.minLat, this.maxLat, this.minLon, this.maxLon);
  
  bool overlaps(S57Bounds bounds) {
    return !(bounds.maxLatitude < minLat ||
        bounds.minLatitude > maxLat ||
        bounds.maxLongitude < minLon ||
        bounds.minLongitude > maxLon);
  }
}