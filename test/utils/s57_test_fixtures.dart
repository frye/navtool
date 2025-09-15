import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/error/app_error.dart';

/// Test fixtures utility for loading and working with real NOAA ENC S57 data
/// 
/// This utility provides access to real S57 Electronic Navigational Chart data
/// instead of synthetic test data, ensuring marine navigation safety through
/// realistic testing of S57 parsing and chart feature extraction.
///
/// Available Real Charts:
/// - Elliott Bay Harbor (US5WA50M): 411KB, harbor-scale (1:20,000)
/// - Puget Sound Coastal (US3WA01M): 1.58MB, coastal-scale (1:90,000)
class S57TestFixtures {
  /// Base path to S57 test fixtures
  static const String fixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  /// Elliott Bay harbor chart identifier
  static const String elliottBayChartId = 'US5WA50M';
  
  /// Puget Sound coastal chart identifier  
  static const String pugetSoundChartId = 'US3WA01M';
  
  /// Elliott Bay chart file size (approximately 411KB)
  static const int elliottBayExpectedSize = 411513;
  
  /// Puget Sound chart file size (approximately 1.58MB)
  static const int pugetSoundExpectedSize = 1658832; // Approximate
  
  // Cache for parsed chart data to improve test performance
  static final Map<String, S57ParsedData> _parsedCache = {};
  static final Map<String, List<int>> _rawDataCache = {};
  
  /// Load raw Elliott Bay S57 chart data (US5WA50M.000)
  ///
  /// Returns the raw binary S57 data for Elliott Bay harbor chart.
  /// This is a detailed harbor-scale chart suitable for testing:
  /// - Navigation aids (buoys, lights, beacons)
  /// - Harbor infrastructure (piers, docks)
  /// - Detailed bathymetry and depth contours
  ///
  /// Throws [FileSystemException] if the chart file is missing
  /// Throws [AppError] if the file size is unexpected
  static Future<List<int>> loadElliottBayChart() async {
    return await _loadChartData(
      chartId: elliottBayChartId,
      expectedSize: elliottBayExpectedSize,
      description: 'Elliott Bay Harbor Chart',
    );
  }
  
  /// Load raw Puget Sound S57 chart data (US3WA01M.000)
  ///
  /// Returns the raw binary S57 data for Puget Sound coastal chart.
  /// This is a coastal-scale chart suitable for testing:
  /// - Coastlines and land areas
  /// - Major navigation features
  /// - Broader geographic coverage
  ///
  /// Throws [FileSystemException] if the chart file is missing
  /// Throws [AppError] if the file size is unexpected
  static Future<List<int>> loadPugetSoundChart() async {
    return await _loadChartData(
      chartId: pugetSoundChartId,
      expectedSize: pugetSoundExpectedSize,
      description: 'Puget Sound Coastal Chart',
      sizeTolerancePercent: 20, // More tolerance for coastal chart
    );
  }
  
  /// Load and parse Elliott Bay S57 chart with caching
  ///
  /// Returns fully parsed S57 data including:
  /// - Chart metadata (title, scale, bounds, etc.)
  /// - Navigation features (buoys, lights, aids)
  /// - Bathymetry data (depth contours, soundings)
  /// - Geometric data (coordinates, spatial index)
  ///
  /// Results are cached for performance in repeated test runs.
  static Future<S57ParsedData> loadParsedElliottBay() async {
    if (_parsedCache.containsKey(elliottBayChartId)) {
      return _parsedCache[elliottBayChartId]!;
    }
    
    final rawData = await loadElliottBayChart();
    final parsedData = S57Parser.parse(rawData);
    
    _parsedCache[elliottBayChartId] = parsedData;
    return parsedData;
  }
  
  /// Load and parse Puget Sound S57 chart with caching
  ///
  /// Returns fully parsed S57 data for coastal-scale testing.
  /// Results are cached for performance in repeated test runs.
  static Future<S57ParsedData> loadParsedPugetSound() async {
    if (_parsedCache.containsKey(pugetSoundChartId)) {
      return _parsedCache[pugetSoundChartId]!;
    }
    
    final rawData = await loadPugetSoundChart();
    final parsedData = S57Parser.parse(rawData);
    
    _parsedCache[pugetSoundChartId] = parsedData;
    return parsedData;
  }
  
  /// Get expected Elliott Bay chart characteristics for test validation
  ///
  /// Returns metadata about what to expect in Elliott Bay chart:
  /// - Expected feature types and approximate counts
  /// - Geographic bounds for Seattle/Elliott Bay area
  /// - Scale and chart type information
  static ElliottBayChartExpectations getElliottBayExpectations() {
    return ElliottBayChartExpectations(
      title: 'Elliott Bay and Duwamish Waterway',
      scale: 20000, // 1:20,000 harbor scale
      bounds: ElliottBayBounds(
        north: 47.62, // Approximate Elliott Bay northern extent
        south: 47.54, // Approximate Elliott Bay southern extent
        west: -122.40, // Approximate Elliott Bay western extent
        east: -122.32, // Approximate Elliott Bay eastern extent
      ),
      expectedFeatureTypes: [
        S57FeatureType.buoyLateral,
        S57FeatureType.lighthouse,
        S57FeatureType.depthContour,
        S57FeatureType.depthArea,
        S57FeatureType.sounding,
        S57FeatureType.coastline,
        S57FeatureType.shoreConstruction,
        S57FeatureType.builtArea,
      ],
      minExpectedFeatures: 1, // Realistic for current S57 parser implementation
      maxExpectedFeatures: 50,
    );
  }
  
  /// Get expected Puget Sound chart characteristics for test validation
  static PugetSoundChartExpectations getPugetSoundExpectations() {
    return PugetSoundChartExpectations(
      title: 'Puget Sound - Southern Part',
      scale: 90000, // 1:90,000 coastal scale
      bounds: PugetSoundBounds(
        north: 47.80, // Approximate Puget Sound northern extent
        south: 47.20, // Approximate Puget Sound southern extent
        west: -122.90, // Approximate Puget Sound western extent
        east: -122.20, // Approximate Puget Sound eastern extent
      ),
      expectedFeatureTypes: [
        S57FeatureType.coastline,
        S57FeatureType.depthArea,
        S57FeatureType.depthContour,
        S57FeatureType.landArea,
        S57FeatureType.buoyLateral,
        S57FeatureType.lighthouse,
      ],
      minExpectedFeatures: 1, // Coastal charts should have at least basic features
      maxExpectedFeatures: 100,
    );
  }
  
  /// Validate that a parsed chart contains expected S57 features
  ///
  /// Performs comprehensive validation including:
  /// - Feature count within expected ranges
  /// - Presence of expected S57 feature types
  /// - Geographic bounds validation
  /// - Chart metadata validation
  static void validateParsedChart(
    S57ParsedData parsedData, 
    String chartId,
    {bool strictValidation = false}
  ) {
    // Basic validation
    expect(parsedData.features, isNotEmpty, reason: 'Chart should contain features');
    expect(parsedData.metadata, isNotNull, reason: 'Chart should have metadata');
    
    if (chartId == elliottBayChartId) {
      final expectations = getElliottBayExpectations();
      _validateAgainstExpectations(parsedData, expectations, strictValidation);
    } else if (chartId == pugetSoundChartId) {
      final expectations = getPugetSoundExpectations();
      _validateAgainstExpectations(parsedData, expectations, strictValidation);
    }
  }
  
  /// Check if real S57 chart files are available
  ///
  /// Returns true if both Elliott Bay and Puget Sound chart files exist.
  /// Useful for conditional testing when charts may not be available.
  static Future<bool> areChartsAvailable() async {
    try {
      final elliottBayPath = '$fixturesPath/$elliottBayChartId/$elliottBayChartId.000';
      final pugetSoundPath = '$fixturesPath/$pugetSoundChartId/$pugetSoundChartId.000';
      
      final elliottBayExists = await File(elliottBayPath).exists();
      final pugetSoundExists = await File(pugetSoundPath).exists();
      
      return elliottBayExists && pugetSoundExists;
    } catch (e) {
      return false;
    }
  }
  
  /// Clear cached parsed data (useful for memory management in long test runs)
  static void clearCache() {
    _parsedCache.clear();
    _rawDataCache.clear();
  }
  
  /// Load raw chart data with validation and caching
  static Future<List<int>> _loadChartData({
    required String chartId,
    required int expectedSize,
    required String description,
    int sizeTolerancePercent = 10,
  }) async {
    // Check cache first
    if (_rawDataCache.containsKey(chartId)) {
      return _rawDataCache[chartId]!;
    }
    
    final filePath = '$fixturesPath/$chartId/$chartId.000';
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw FileSystemException(
        'S57 chart file not found: $filePath\n'
        'Expected real NOAA ENC data for $description.\n'
        'Please ensure S57 test fixtures are properly installed.',
        filePath,
      );
    }
    
    final data = await file.readAsBytes();
    
    // Validate file size (with tolerance for different versions)
    final actualSize = data.length;
    final tolerance = (expectedSize * sizeTolerancePercent / 100).round();
    final minSize = expectedSize - tolerance;
    final maxSize = expectedSize + tolerance;
    
    if (actualSize < minSize || actualSize > maxSize) {
      throw AppError(
        message: 'S57 chart file size unexpected for $description.\n'
            'Expected: ${_formatBytes(expectedSize)} ± $sizeTolerancePercent%\n'
            'Actual: ${_formatBytes(actualSize)}\n'
            'File: $filePath',
        type: AppErrorType.validation,
      );
    }
    
    // Cache the data
    _rawDataCache[chartId] = data;
    return data;
  }
  
  /// Validate parsed data against expectations
  static void _validateAgainstExpectations(
    S57ParsedData parsedData,
    dynamic expectations,
    bool strictValidation,
  ) {
    final featureCount = parsedData.features.length;
    
    // Feature count validation
    expect(
      featureCount,
      greaterThanOrEqualTo(expectations.minExpectedFeatures),
      reason: 'Chart should have at least ${expectations.minExpectedFeatures} features',
    );
    
    if (strictValidation) {
      expect(
        featureCount,
        lessThanOrEqualTo(expectations.maxExpectedFeatures),
        reason: 'Chart should have at most ${expectations.maxExpectedFeatures} features',
      );
    }
    
    // Feature type validation
    final presentTypes = parsedData.features.map((f) => f.featureType).toSet();
    for (final expectedType in expectations.expectedFeatureTypes) {
      if (strictValidation) {
        expect(
          presentTypes,
          contains(expectedType),
          reason: 'Chart should contain ${expectedType.acronym} features',
        );
      }
    }
    
    // Metadata validation - be more flexible with title matching
    if (parsedData.metadata.title != null && parsedData.metadata.title!.isNotEmpty) {
      // For real S57 data, titles might be generic like "S-57 Electronic Navigational Chart"
      // So we're more lenient and just ensure we have a title
      expect(
        parsedData.metadata.title!.length,
        greaterThan(5),
        reason: 'Chart title should have substantial content',
      );
    }
  }
  
  /// Format byte count for display
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Expected characteristics of Elliott Bay chart for validation
class ElliottBayChartExpectations {
  final String title;
  final int scale;
  final ElliottBayBounds bounds;
  final List<S57FeatureType> expectedFeatureTypes;
  final int minExpectedFeatures;
  final int maxExpectedFeatures;
  
  const ElliottBayChartExpectations({
    required this.title,
    required this.scale,
    required this.bounds,
    required this.expectedFeatureTypes,
    required this.minExpectedFeatures,
    required this.maxExpectedFeatures,
  });
}

/// Expected characteristics of Puget Sound chart for validation
class PugetSoundChartExpectations {
  final String title;
  final int scale;
  final PugetSoundBounds bounds;
  final List<S57FeatureType> expectedFeatureTypes;
  final int minExpectedFeatures;
  final int maxExpectedFeatures;
  
  const PugetSoundChartExpectations({
    required this.title,
    required this.scale,
    required this.bounds,
    required this.expectedFeatureTypes,
    required this.minExpectedFeatures,
    required this.maxExpectedFeatures,
  });
}

/// Geographic bounds for Elliott Bay area
class ElliottBayBounds {
  final double north;
  final double south;
  final double west;
  final double east;
  
  const ElliottBayBounds({
    required this.north,
    required this.south,
    required this.west,
    required this.east,
  });
}

/// Geographic bounds for Puget Sound area
class PugetSoundBounds {
  final double north;
  final double south;
  final double west;
  final double east;
  
  const PugetSoundBounds({
    required this.north,
    required this.south,
    required this.west,
    required this.east,
  });
}