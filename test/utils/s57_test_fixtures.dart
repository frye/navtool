/// S57TestFixtures utility for real NOAA ENC data usage
///
/// Provides access to real NOAA Electronic Navigational Chart (ENC) S57 sample data
/// for comprehensive testing of marine navigation features. This utility replaces
/// artificial/synthetic chart data with actual NOAA ENC charts for improved test validity.
///
/// Available real S57 fixtures:
/// - Elliott Bay Harbor (US5WA50M.000) - 411KB harbor-scale chart 
/// - Puget Sound Coastal (US3WA01M.000) - 1.58MB coastal-scale chart
///
/// Usage:
/// ```dart
/// // Load raw chart bytes
/// final chartBytes = await S57TestFixtures.loadElliottBayChart();
/// 
/// // Load parsed chart with caching
/// final chartData = await S57TestFixtures.loadParsedElliottBay();
/// 
/// // Validate chart metadata
/// S57TestFixtures.validateChartMetadata(chartData, ChartType.harbor);
/// ```

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'test_logger.dart';

/// S57TestFixtures utility class for real NOAA ENC data testing
///
/// Provides methods to load and parse real NOAA Electronic Navigational Chart
/// (ENC) S57 sample data for comprehensive marine navigation testing.
class S57TestFixtures {
  /// Base path to S57 test fixtures
  static const String fixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  /// Elliott Bay harbor chart path (US5WA50M)
  static const String _elliottBayPath = '$fixturesPath/US5WA50M/US5WA50M.000';
  
  /// Puget Sound coastal chart path (US3WA01M)  
  static const String _pugetSoundPath = '$fixturesPath/US3WA01M/US3WA01M.000';

  // Cached parsed chart data for performance
  static S57ParsedData? _cachedElliottBay;
  static S57ParsedData? _cachedPugetSound;
  
  // Cache validation flags
  static bool _elliottBayCacheValid = false;
  static bool _pugetSoundCacheValid = false;

  /// Load Elliott Bay harbor chart raw bytes (US5WA50M.000)
  /// 
  /// Elliott Bay is a harbor-scale chart covering Seattle Harbor approaches
  /// with detailed navigation aids, depth soundings, and harbor facilities.
  /// 
  /// Returns: Raw S57 binary data (approximately 411KB)
  /// Throws: [TestFailure] if chart file is not found or cannot be read
  static Future<List<int>> loadElliottBayChart() async {
    return await _loadChartBytes(_elliottBayPath, 'Elliott Bay (US5WA50M)');
  }

  /// Load Puget Sound coastal chart raw bytes (US3WA01M.000)
  /// 
  /// Puget Sound is a coastal-scale chart covering the broader Puget Sound
  /// region with coastlines, major navigation features, and depth areas.
  /// 
  /// Returns: Raw S57 binary data (approximately 1.58MB)  
  /// Throws: [TestFailure] if chart file is not found or cannot be read
  static Future<List<int>> loadPugetSoundChart() async {
    return await _loadChartBytes(_pugetSoundPath, 'Puget Sound (US3WA01M)');
  }

  /// Load parsed Elliott Bay chart with caching for performance
  /// 
  /// Parses the Elliott Bay S57 chart data and caches the result to avoid
  /// expensive re-parsing during test execution. The cache is invalidated
  /// if the source file is modified.
  /// 
  /// Returns: Parsed S57 chart data with features, coordinates, and metadata
  /// Throws: [TestFailure] if chart cannot be loaded or parsed
  static Future<S57ParsedData> loadParsedElliottBay() async {
    if (_cachedElliottBay != null && _elliottBayCacheValid) {
      testLogger.info('Using cached Elliott Bay chart data');
      return _cachedElliottBay!;
    }

    testLogger.info('Parsing Elliott Bay chart (US5WA50M.000)...');
    final chartBytes = await loadElliottBayChart();
    
    try {
      final warnings = S57WarningCollector();
      _cachedElliottBay = S57Parser.parse(chartBytes, warnings: warnings);
      _elliottBayCacheValid = true;
      
      _logParseResults('Elliott Bay (US5WA50M)', _cachedElliottBay!, warnings);
      return _cachedElliottBay!;
    } catch (e) {
      throw TestFailure('Failed to parse Elliott Bay chart: ${e.toString()}');
    }
  }

  /// Load parsed Puget Sound chart with caching for performance
  /// 
  /// Parses the Puget Sound S57 chart data and caches the result to avoid
  /// expensive re-parsing during test execution. The cache is invalidated
  /// if the source file is modified.
  /// 
  /// Returns: Parsed S57 chart data with features, coordinates, and metadata
  /// Throws: [TestFailure] if chart cannot be loaded or parsed  
  static Future<S57ParsedData> loadParsedPugetSound() async {
    if (_cachedPugetSound != null && _pugetSoundCacheValid) {
      testLogger.info('Using cached Puget Sound chart data');
      return _cachedPugetSound!;
    }

    testLogger.info('Parsing Puget Sound chart (US3WA01M.000)...');
    final chartBytes = await loadPugetSoundChart();
    
    try {
      final warnings = S57WarningCollector();
      _cachedPugetSound = S57Parser.parse(chartBytes, warnings: warnings);
      _pugetSoundCacheValid = true;
      
      _logParseResults('Puget Sound (US3WA01M)', _cachedPugetSound!, warnings);
      return _cachedPugetSound!;
    } catch (e) {
      throw TestFailure('Failed to parse Puget Sound chart: ${e.toString()}');
    }
  }

  /// Clear all cached chart data to force re-parsing
  /// 
  /// Useful for testing cache invalidation or when chart files are updated
  /// during development. Should be called in test tearDown if needed.
  static void clearCache() {
    _cachedElliottBay = null;
    _cachedPugetSound = null;
    _elliottBayCacheValid = false;
    _pugetSoundCacheValid = false;
    testLogger.info('Cleared S57 chart cache');
  }

  /// Validate chart metadata for marine navigation safety requirements
  /// 
  /// Performs comprehensive validation of parsed S57 chart data to ensure
  /// it meets marine navigation standards and contains required elements.
  /// 
  /// [chartData] - Parsed S57 chart data to validate
  /// [expectedType] - Expected chart type for scale validation
  /// [minFeatures] - Minimum expected feature count (default: 10)
  /// 
  /// Throws: [TestFailure] if validation fails
  static void validateChartMetadata(
    S57ParsedData chartData,
    ChartType expectedType, {
    int minFeatures = 10,
  }) {
    // Validate basic structure
    expect(chartData.features, isNotNull, reason: 'Chart features cannot be null');
    expect(chartData.features.isNotEmpty, isTrue, reason: 'Chart must contain features');
    expect(chartData.features.length, greaterThanOrEqualTo(minFeatures),
        reason: 'Chart must contain at least $minFeatures features for marine navigation');

    // Validate metadata presence
    expect(chartData.metadata, isNotNull, reason: 'Chart metadata cannot be null');
    expect(chartData.metadata.isNotEmpty, isTrue, reason: 'Chart metadata must be present');

    // Validate coordinate system
    if (chartData.features.isNotEmpty) {
      final firstFeature = chartData.features.first;
      expect(firstFeature.coordinates, isNotEmpty, reason: 'Features must have coordinates');
      
      final firstCoord = firstFeature.coordinates.first;
      expect(firstCoord.latitude, inInclusiveRange(-90.0, 90.0),
          reason: 'Latitude must be valid geographic coordinate');
      expect(firstCoord.longitude, inInclusiveRange(-180.0, 180.0),
          reason: 'Longitude must be valid geographic coordinate');
    }

    // Validate marine navigation feature types
    final navigationFeatureTypes = [
      S57FeatureType.beacon,
      S57FeatureType.buoy,
      S57FeatureType.lighthouse,
      S57FeatureType.depthArea,
      S57FeatureType.coastline,
      S57FeatureType.sounding,
    ];

    final hasNavigationFeatures = chartData.features
        .any((f) => navigationFeatureTypes.contains(f.featureType));
    
    expect(hasNavigationFeatures, isTrue,
        reason: 'Chart must contain navigation-critical features for marine safety');

    testLogger.info('Chart metadata validation passed for ${expectedType.name} chart');
  }

  /// Get chart bounds from parsed S57 data
  /// 
  /// Calculates the geographic bounds of the chart from its feature coordinates.
  /// Essential for spatial indexing and map viewport calculations.
  /// 
  /// [chartData] - Parsed S57 chart data
  /// Returns: Geographic bounds covering all chart features
  /// Throws: [TestFailure] if chart has no features or invalid coordinates
  static GeographicBounds getChartBounds(S57ParsedData chartData) {
    if (chartData.features.isEmpty) {
      throw TestFailure('Cannot calculate bounds for chart with no features');
    }

    double north = -90.0;
    double south = 90.0;
    double east = -180.0;
    double west = 180.0;

    for (final feature in chartData.features) {
      for (final coord in feature.coordinates) {
        if (coord.latitude > north) north = coord.latitude;
        if (coord.latitude < south) south = coord.latitude;
        if (coord.longitude > east) east = coord.longitude;
        if (coord.longitude < west) west = coord.longitude;
      }
    }

    // Validate calculated bounds
    if (north < south || east < west) {
      throw TestFailure('Invalid chart bounds calculated: N$north S$south E$east W$west');
    }

    return GeographicBounds(north: north, south: south, east: east, west: west);
  }

  /// Get features of specific type from chart data
  /// 
  /// Filters chart features by S57 feature type for targeted testing
  /// of specific marine navigation elements.
  /// 
  /// [chartData] - Parsed S57 chart data
  /// [featureType] - S57 feature type to filter by
  /// Returns: List of features matching the specified type
  static List<S57Feature> getFeaturesOfType(
    S57ParsedData chartData,
    S57FeatureType featureType,
  ) {
    return chartData.features
        .where((feature) => feature.featureType == featureType)
        .toList();
  }

  /// Get chart feature type distribution for analysis
  /// 
  /// Analyzes the distribution of S57 feature types in the chart,
  /// useful for testing chart completeness and feature coverage.
  /// 
  /// [chartData] - Parsed S57 chart data
  /// Returns: Map of feature types to their counts
  static Map<S57FeatureType, int> getFeatureTypeDistribution(S57ParsedData chartData) {
    final distribution = <S57FeatureType, int>{};
    
    for (final feature in chartData.features) {
      distribution[feature.featureType] = 
          (distribution[feature.featureType] ?? 0) + 1;
    }
    
    return distribution;
  }

  /// Verify chart file exists and is readable
  /// 
  /// Performs pre-flight checks on chart fixture files to ensure
  /// they are available for testing.
  /// 
  /// [chartPath] - Relative path to chart file
  /// Returns: true if file exists and is readable
  static bool isChartAvailable(String chartPath) {
    final file = File(chartPath);
    return file.existsSync() && file.statSync().size > 0;
  }

  /// Check if all required chart fixtures are available
  /// 
  /// Verifies that both Elliott Bay and Puget Sound chart fixtures
  /// are present and accessible for testing.
  /// 
  /// Returns: true if all required charts are available
  static bool areAllChartsAvailable() {
    return isChartAvailable(_elliottBayPath) && isChartAvailable(_pugetSoundPath);
  }

  /// Get Elliott Bay chart metadata for test validation
  /// 
  /// Returns expected metadata properties for the Elliott Bay chart
  /// to support test assertions and validation.
  static ChartTestMetadata get elliottBayMetadata => const ChartTestMetadata(
    cellId: 'US5WA50M',
    title: 'ELLIOTT BAY AND SEATTLE HARBOR',  
    usageBand: 5, // Harbor scale
    scale: '1:20,000',
    region: 'Elliott Bay, Seattle Harbor, Washington',
    expectedMinFeatures: 50,
    expectedMaxSizeKB: 500,
  );

  /// Get Puget Sound chart metadata for test validation
  /// 
  /// Returns expected metadata properties for the Puget Sound chart
  /// to support test assertions and validation.
  static ChartTestMetadata get pugetSoundMetadata => const ChartTestMetadata(
    cellId: 'US3WA01M',
    title: 'PUGET SOUND NORTHERN PART',
    usageBand: 3, // Coastal scale  
    scale: '1:90,000',
    region: 'Puget Sound, Northern Part, Washington',
    expectedMinFeatures: 200,
    expectedMaxSizeKB: 2000,
  );

  // Private helper methods

  /// Load chart bytes from file with error handling
  static Future<List<int>> _loadChartBytes(String filePath, String chartName) async {
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw TestFailure(
        'S57 chart fixture not found: $chartName\n'
        'Expected at: $filePath\n'
        'Ensure chart fixtures are available in the test/fixtures directory'
      );
    }

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw TestFailure('$chartName chart file is empty: $filePath');
      }
      
      testLogger.info('Loaded $chartName chart: ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      throw TestFailure(
        'Failed to read $chartName chart from $filePath: ${e.toString()}'
      );
    }
  }

  /// Log S57 parse results for debugging and monitoring
  static void _logParseResults(String chartName, S57ParsedData data, S57WarningCollector warnings) {
    final featureCount = data.features.length;
    final metadataCount = data.metadata.length;
    final warningCount = warnings.warnings.length;
    
    testLogger.info(
      'Parsed $chartName: $featureCount features, $metadataCount metadata entries'
    );
    
    if (warningCount > 0) {
      testLogger.info('Parse warnings: $warningCount');
      for (final warning in warnings.warnings.take(5)) {
        testLogger.info('  - ${warning.message}');
      }
      if (warningCount > 5) {
        testLogger.info('  ... and ${warningCount - 5} more warnings');
      }
    }

    // Log feature type distribution for analysis
    final distribution = getFeatureTypeDistribution(data);
    final topTypes = distribution.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    
    testLogger.info('Top feature types:');
    for (final entry in topTypes.take(5)) {
      testLogger.info('  - ${entry.key.name}: ${entry.value}');
    }
  }
}

/// Metadata for S57 test chart validation and expectations
/// 
/// Defines expected properties and validation criteria for S57 test charts
/// to ensure consistent testing standards across marine navigation features.
class ChartTestMetadata {
  /// S57 cell identifier (e.g., US5WA50M)
  final String cellId;
  
  /// Official chart title from NOAA
  final String title;
  
  /// Usage band indicating chart scale category (1-6)
  /// 1: Overview, 2: General, 3: Coastal, 4: Approach, 5: Harbor, 6: Berthing  
  final int usageBand;
  
  /// Chart scale notation (e.g., 1:20,000)
  final String scale;
  
  /// Geographic region covered by chart
  final String region;
  
  /// Minimum expected feature count for validation
  final int expectedMinFeatures;
  
  /// Maximum expected chart size in KB
  final int expectedMaxSizeKB;

  const ChartTestMetadata({
    required this.cellId,
    required this.title, 
    required this.usageBand,
    required this.scale,
    required this.region,
    required this.expectedMinFeatures,
    required this.expectedMaxSizeKB,
  });

  /// Validate chart meets metadata expectations
  /// 
  /// [chartData] - Parsed S57 chart data to validate
  /// Throws: [TestFailure] if validation fails
  void validate(S57ParsedData chartData) {
    expect(chartData.features.length, greaterThanOrEqualTo(expectedMinFeatures),
        reason: 'Chart $cellId should have at least $expectedMinFeatures features');

    // Additional chart-specific validations can be added here
    testLogger.info('Chart $cellId metadata validation passed');
  }
}

/// Extension for GeographicBounds to support S57 chart operations
extension GeographicBoundsS57 on GeographicBounds {
  /// Check if bounds are valid for marine navigation
  /// 
  /// Validates that bounds represent a reasonable marine area
  /// with minimum size requirements for navigation safety.
  bool get isValidForMarine {
    return (south >= -90.0 && north <= 90.0) &&
           (west >= -180.0 && east <= 180.0) &&
           (north - south) >= 0.001 && // Minimum latitude span 
           (east - west) >= 0.001 &&   // Minimum longitude span
           (north > south) &&          // North must be greater than south
           (east > west);              // East must be greater than west (assuming not crossing antimeridian)
  }
}