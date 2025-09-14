import 'package:flutter_test/flutter_test.dart';
import '../utils/s57_test_fixtures.dart';

/// Test suite for S57TestFixtures utility
/// 
/// Validates that the S57TestFixtures utility correctly loads and processes
/// real NOAA ENC S57 chart data for marine navigation testing.
void main() {
  group('S57TestFixtures', () {
    test('should identify available chart fixtures', () {
      expect(S57TestFixtures.areAllChartsAvailable(), isTrue,
          reason: 'Real S57 chart fixtures should be available for testing');
    });

    test('should load Elliott Bay chart bytes', () async {
      final chartBytes = await S57TestFixtures.loadElliottBayChart();
      
      expect(chartBytes, isNotEmpty, reason: 'Elliott Bay chart should contain data');
      expect(chartBytes.length, greaterThan(100000), 
          reason: 'Elliott Bay chart should be substantial size (>100KB)');
    });

    test('should load Puget Sound chart bytes', () async {
      final chartBytes = await S57TestFixtures.loadPugetSoundChart();
      
      expect(chartBytes, isNotEmpty, reason: 'Puget Sound chart should contain data');
      expect(chartBytes.length, greaterThan(500000), 
          reason: 'Puget Sound chart should be substantial size (>500KB)');
    });

    test('should parse Elliott Bay chart with caching', () async {
      // Clear cache to start fresh
      S57TestFixtures.clearCache();
      
      // First load - should parse
      final chartData1 = await S57TestFixtures.loadParsedElliottBay();
      expect(chartData1.features, isNotEmpty, 
          reason: 'Parsed Elliott Bay should contain features');
      
      // Second load - should use cache
      final chartData2 = await S57TestFixtures.loadParsedElliottBay();
      expect(identical(chartData1, chartData2), isTrue,
          reason: 'Second load should return cached data');
    });

    test('should parse Puget Sound chart with caching', () async {
      // Clear cache to start fresh  
      S57TestFixtures.clearCache();
      
      // First load - should parse
      final chartData1 = await S57TestFixtures.loadParsedPugetSound();
      expect(chartData1.features, isNotEmpty,
          reason: 'Parsed Puget Sound should contain features');
      
      // Second load - should use cache
      final chartData2 = await S57TestFixtures.loadParsedPugetSound();
      expect(identical(chartData1, chartData2), isTrue,
          reason: 'Second load should return cached data');
    });

    test('should validate Elliott Bay chart metadata', () async {
      final chartData = await S57TestFixtures.loadParsedElliottBay();
      
      // Should not throw validation errors
      expect(() => S57TestFixtures.validateChartMetadata(chartData, ChartType.harbor),
          returnsNormally);
      
      // Should meet minimum feature requirements
      expect(chartData.features.length, 
          greaterThanOrEqualTo(S57TestFixtures.elliottBayMetadata.expectedMinFeatures));
    });

    test('should validate Puget Sound chart metadata', () async {
      final chartData = await S57TestFixtures.loadParsedPugetSound();
      
      // Should not throw validation errors
      expect(() => S57TestFixtures.validateChartMetadata(chartData, ChartType.coastal),
          returnsNormally);
      
      // Should meet minimum feature requirements
      expect(chartData.features.length,
          greaterThanOrEqualTo(S57TestFixtures.pugetSoundMetadata.expectedMinFeatures));
    });

    test('should calculate chart bounds correctly', () async {
      final chartData = await S57TestFixtures.loadParsedElliottBay();
      final bounds = S57TestFixtures.getChartBounds(chartData);
      
      expect(bounds.isValidForMarine, isTrue,
          reason: 'Chart bounds should be valid for marine navigation');
      
      // Elliott Bay should be in the Pacific Northwest
      expect(bounds.north, greaterThan(47.0), reason: 'Elliott Bay is in Seattle area');
      expect(bounds.south, lessThan(48.0), reason: 'Elliott Bay is in Seattle area');
      expect(bounds.west, lessThan(-122.0), reason: 'Elliott Bay is west of -122°');
      expect(bounds.east, greaterThan(-123.0), reason: 'Elliott Bay is east of -123°');
    });

    test('should get feature type distribution', () async {
      final chartData = await S57TestFixtures.loadParsedElliottBay();
      final distribution = S57TestFixtures.getFeatureTypeDistribution(chartData);
      
      expect(distribution, isNotEmpty, reason: 'Should have feature types');
      expect(distribution.values.every((count) => count > 0), isTrue,
          reason: 'All feature type counts should be positive');
      
      final totalFeatures = distribution.values.reduce((a, b) => a + b);
      expect(totalFeatures, equals(chartData.features.length),
          reason: 'Distribution should account for all features');
    });

    test('should filter features by type', () async {
      final chartData = await S57TestFixtures.loadParsedElliottBay();
      final distribution = S57TestFixtures.getFeatureTypeDistribution(chartData);
      
      // Test filtering for a feature type that exists
      final firstType = distribution.keys.first;
      final filteredFeatures = S57TestFixtures.getFeaturesOfType(chartData, firstType);
      
      expect(filteredFeatures.length, equals(distribution[firstType]),
          reason: 'Filtered count should match distribution count');
      expect(filteredFeatures.every((f) => f.featureType == firstType), isTrue,
          reason: 'All filtered features should be of requested type');
    });

    test('should provide chart metadata for validation', () {
      final elliottMetadata = S57TestFixtures.elliottBayMetadata;
      expect(elliottMetadata.cellId, equals('US5WA50M'));
      expect(elliottMetadata.usageBand, equals(5)); // Harbor scale
      
      final pugetMetadata = S57TestFixtures.pugetSoundMetadata;
      expect(pugetMetadata.cellId, equals('US3WA01M'));
      expect(pugetMetadata.usageBand, equals(3)); // Coastal scale
    });
  });
}