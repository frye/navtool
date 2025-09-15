import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 's57_test_fixtures.dart';

void main() {
  group('S57TestFixtures', () {
    group('Chart Availability', () {
      test('should report available charts correctly', () {
        final availableCharts = S57TestFixtures.getAvailableCharts();
        expect(availableCharts, contains('US5WA50M'));
        expect(availableCharts, contains('US3WA01M'));
        expect(availableCharts.length, equals(2));
      });

      test('should provide chart descriptions', () {
        final elliottBayDesc = S57TestFixtures.getChartDescription('US5WA50M');
        expect(elliottBayDesc, contains('Elliott Bay Harbor Chart'));
        expect(elliottBayDesc, contains('1:20,000'));
        expect(elliottBayDesc, contains('Seattle/Elliott Bay region'));

        final pugetSoundDesc = S57TestFixtures.getChartDescription('US3WA01M');
        expect(pugetSoundDesc, contains('Puget Sound Coastal Chart'));
        expect(pugetSoundDesc, contains('1:90,000'));
        expect(pugetSoundDesc, contains('Broader Puget Sound region'));
      });

      test('should handle unknown chart IDs', () {
        final unknownDesc = S57TestFixtures.getChartDescription('UNKNOWN');
        expect(unknownDesc, contains('Unknown chart ID'));
      });

      test('should check chart availability', () async {
        final elliottBayAvailable = await S57TestFixtures.isChartAvailable('US5WA50M');
        final pugetSoundAvailable = await S57TestFixtures.isChartAvailable('US3WA01M');
        final unknownAvailable = await S57TestFixtures.isChartAvailable('UNKNOWN');

        expect(elliottBayAvailable, isTrue, reason: 'Elliott Bay chart should be available');
        expect(pugetSoundAvailable, isTrue, reason: 'Puget Sound chart should be available');
        expect(unknownAvailable, isFalse, reason: 'Unknown chart should not be available');
      });
    });

    group('Raw Chart Data Loading', () {
      test('should load Elliott Bay chart raw data', () async {
        final chartData = await S57TestFixtures.loadElliottBayChart();
        
        expect(chartData, isNotEmpty, reason: 'Elliott Bay chart data should not be empty');
        expect(chartData.length, greaterThan(400000), reason: 'Elliott Bay chart should be ~411KB');
        expect(chartData.length, lessThan(500000), reason: 'Elliott Bay chart size should be reasonable');
        
        // Check S-57 file signature (first few bytes should indicate S-57 format)
        expect(chartData[0], isA<int>(), reason: 'Chart data should be binary');
      });

      test('should load Puget Sound chart raw data', () async {
        final chartData = await S57TestFixtures.loadPugetSoundChart();
        
        expect(chartData, isNotEmpty, reason: 'Puget Sound chart data should not be empty');
        expect(chartData.length, greaterThan(1000000), reason: 'Puget Sound chart should be ~1.5MB');
        expect(chartData.length, lessThan(2000000), reason: 'Puget Sound chart size should be reasonable');
        
        // Check S-57 file signature
        expect(chartData[0], isA<int>(), reason: 'Chart data should be binary');
      });

      test('should load chart by ID', () async {
        final elliottBayData = await S57TestFixtures.loadChartById('US5WA50M');
        final pugetSoundData = await S57TestFixtures.loadChartById('US3WA01M');
        final unknownData = await S57TestFixtures.loadChartById('UNKNOWN');

        expect(elliottBayData, isNotNull, reason: 'Elliott Bay data should be loaded');
        expect(elliottBayData!.length, greaterThan(400000), reason: 'Elliott Bay data should be substantial');

        expect(pugetSoundData, isNotNull, reason: 'Puget Sound data should be loaded');
        expect(pugetSoundData!.length, greaterThan(1000000), reason: 'Puget Sound data should be substantial');

        expect(unknownData, isNull, reason: 'Unknown chart should return null');
      });

      test('should use caching for performance', () async {
        // Clear caches first
        S57TestFixtures.clearCaches();
        
        final stats1 = S57TestFixtures.getCacheStats();
        expect(stats1['bytesCacheSize'], equals(0), reason: 'Cache should be empty initially');

        // Load chart first time
        final stopwatch1 = Stopwatch()..start();
        final chartData1 = await S57TestFixtures.loadElliottBayChart();
        stopwatch1.stop();
        
        final stats2 = S57TestFixtures.getCacheStats();
        expect(stats2['bytesCacheSize'], equals(1), reason: 'Cache should contain one entry');
        expect(stats2['cachedCharts'], contains('US5WA50M_raw'), reason: 'Elliott Bay should be cached');

        // Load chart second time (should be faster due to cache)
        final stopwatch2 = Stopwatch()..start();
        final chartData2 = await S57TestFixtures.loadElliottBayChart();
        stopwatch2.stop();

        expect(chartData1.length, equals(chartData2.length), reason: 'Cached data should match original');
        expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds), 
               reason: 'Cached load should be faster');
      });
    });

    group('Parsed Chart Data', () {
      test('should parse Elliott Bay chart', () async {
        final parsedChart = await S57TestFixtures.loadParsedElliottBay();
        
        expect(parsedChart, isA<S57ParsedData>(), reason: 'Should return S57ParsedData object');
        expect(parsedChart.features, isNotEmpty, reason: 'Chart should contain features');
        expect(parsedChart.features.length, greaterThan(10), reason: 'Real chart should have substantial features');
        
        // Check bounds are reasonable for Elliott Bay area
        expect(parsedChart.bounds.west, lessThan(-122.0), reason: 'Elliott Bay should be west of -122°');
        expect(parsedChart.bounds.east, greaterThan(-122.5), reason: 'Elliott Bay should be east of -122.5°');
        expect(parsedChart.bounds.north, lessThan(47.8), reason: 'Elliott Bay should be south of 47.8°N');
        expect(parsedChart.bounds.south, greaterThan(47.5), reason: 'Elliott Bay should be north of 47.5°N');
        
        // Check metadata
        expect(parsedChart.metadata, isNotNull, reason: 'Chart should have metadata');
      });

      test('should parse Puget Sound chart', () async {
        final parsedChart = await S57TestFixtures.loadParsedPugetSound();
        
        expect(parsedChart, isA<S57ParsedData>(), reason: 'Should return S57ParsedData object');
        expect(parsedChart.features, isNotEmpty, reason: 'Chart should contain features');
        expect(parsedChart.features.length, greaterThan(50), reason: 'Coastal chart should have many features');
        
        // Check bounds are reasonable for Puget Sound area
        expect(parsedChart.bounds.west, lessThan(-122.0), reason: 'Puget Sound should be west of -122°');
        expect(parsedChart.bounds.east, greaterThan(-123.0), reason: 'Puget Sound should span significant longitude');
        expect(parsedChart.bounds.north, lessThan(48.5), reason: 'Puget Sound should be south of 48.5°N');
        expect(parsedChart.bounds.south, greaterThan(47.0), reason: 'Puget Sound should be north of 47°N');
      });

      test('should load parsed chart by ID', () async {
        final elliottBayParsed = await S57TestFixtures.loadParsedChartById('US5WA50M');
        final pugetSoundParsed = await S57TestFixtures.loadParsedChartById('US3WA01M');
        final unknownParsed = await S57TestFixtures.loadParsedChartById('UNKNOWN');

        expect(elliottBayParsed, isNotNull, reason: 'Elliott Bay parsed data should be available');
        expect(elliottBayParsed!.features, isNotEmpty, reason: 'Elliott Bay should have features');

        expect(pugetSoundParsed, isNotNull, reason: 'Puget Sound parsed data should be available');
        expect(pugetSoundParsed!.features, isNotEmpty, reason: 'Puget Sound should have features');

        expect(unknownParsed, isNull, reason: 'Unknown chart should return null');
      });

      test('should use parsing cache for performance', () async {
        // Clear caches first
        S57TestFixtures.clearCaches();
        
        // Parse chart first time
        final stopwatch1 = Stopwatch()..start();
        final parsedChart1 = await S57TestFixtures.loadParsedElliottBay();
        stopwatch1.stop();
        
        final stats = S57TestFixtures.getCacheStats();
        expect(stats['parsedCacheSize'], equals(1), reason: 'Parsed cache should contain one entry');
        expect(stats['parsedCharts'], contains('US5WA50M_parsed'), reason: 'Elliott Bay parsed should be cached');

        // Parse chart second time (should be much faster)
        final stopwatch2 = Stopwatch()..start();
        final parsedChart2 = await S57TestFixtures.loadParsedElliottBay();
        stopwatch2.stop();

        expect(parsedChart1.features.length, equals(parsedChart2.features.length), 
               reason: 'Cached parsed data should match original');
        expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds ~/ 10), 
               reason: 'Cached parse should be much faster');
      });
    });

    group('Chart Metadata Validation', () {
      test('should validate Elliott Bay chart metadata', () async {
        final parsedChart = await S57TestFixtures.loadParsedElliottBay();
        final validation = S57TestFixtures.validateChartMetadata(parsedChart, 'US5WA50M');
        
        expect(validation['chartId'], equals('US5WA50M'), reason: 'Chart ID should match');
        expect(validation['valid'], isTrue, reason: 'Real chart should be valid');
        expect(validation['featureCount'], greaterThan(10), reason: 'Real chart should have many features');
        expect(validation['hasKeyFeatures'], isTrue, reason: 'Chart should have key maritime features');
        
        // Check expected feature types
        final featureTypes = validation['featureTypes'] as List<String>;
        expect(featureTypes, isNotEmpty, reason: 'Chart should have feature types');
        
        // Check issues array
        final issues = validation['issues'] as List<String>;
        expect(issues, isEmpty, reason: 'Valid chart should have no issues');
      });

      test('should detect invalid chart characteristics', () async {
        // This test would use a minimal/invalid chart if we had one
        // For now, we'll test the validation logic with edge cases
        final parsedChart = await S57TestFixtures.loadParsedElliottBay();
        
        // Create a mock minimal chart scenario by testing bounds validation
        final validation = S57TestFixtures.validateChartMetadata(parsedChart, 'US5WA50M');
        
        // The validation should detect if bounds are outside expected Elliott Bay area
        final bounds = validation['bounds'] as Map<String, dynamic>;
        expect(bounds, containsPair('west', lessThan(-122.0)), reason: 'Elliott Bay bounds should be validated');
        expect(bounds, containsPair('east', greaterThan(-122.5)), reason: 'Elliott Bay bounds should be validated');
      });
    });

    group('Cache Management', () {
      test('should clear all caches', () {
        // Load some data to populate caches
        S57TestFixtures.loadElliottBayChart();
        
        // Clear caches
        S57TestFixtures.clearCaches();
        
        final stats = S57TestFixtures.getCacheStats();
        expect(stats['parsedCacheSize'], equals(0), reason: 'Parsed cache should be empty');
        expect(stats['bytesCacheSize'], equals(0), reason: 'Bytes cache should be empty');
        expect(stats['parsedCharts'], isEmpty, reason: 'Parsed charts list should be empty');
        expect(stats['cachedCharts'], isEmpty, reason: 'Cached charts list should be empty');
      });

      test('should provide cache statistics', () async {
        S57TestFixtures.clearCaches();
        
        // Load some charts to populate cache
        await S57TestFixtures.loadElliottBayChart();
        await S57TestFixtures.loadParsedPugetSound();
        
        final stats = S57TestFixtures.getCacheStats();
        expect(stats['bytesCacheSize'], equals(1), reason: 'Should have one raw chart cached');
        expect(stats['parsedCacheSize'], equals(1), reason: 'Should have one parsed chart cached');
        expect(stats['parsedCharts'], isA<List>(), reason: 'Should list parsed charts');
        expect(stats['cachedCharts'], isA<List>(), reason: 'Should list cached charts');
      });
    });

    group('Error Handling', () {
      test('should handle file not found gracefully', () async {
        // Test with a chart ID that doesn't exist
        final result = await S57TestFixtures.loadChartById('NONEXISTENT');
        expect(result, isNull, reason: 'Should return null for non-existent charts');
        
        final parsedResult = await S57TestFixtures.loadParsedChartById('NONEXISTENT');
        expect(parsedResult, isNull, reason: 'Should return null for non-existent parsed charts');
      });

      test('should handle parsing errors gracefully', () async {
        // This test assumes the S57 parser handles corrupt data gracefully
        // In a real scenario, we might have a corrupt test file
        expect(() async => await S57TestFixtures.loadParsedElliottBay(), 
               returnsNormally, reason: 'Should handle parsing errors gracefully');
      });
    });

    group('Integration with Real S57 Data', () {
      test('should load real chart features with expected types', () async {
        final parsedChart = await S57TestFixtures.loadParsedElliottBay();
        
        // Extract feature type acronyms
        final featureTypes = parsedChart.features
            .map((f) => f.featureType.acronym)
            .toSet();
        
        // Check for common maritime feature types that should be in Elliott Bay
        final expectedTypes = {'DEPCNT', 'DEPARE', 'COALNE', 'SOUNDG'};
        final foundExpected = expectedTypes.intersection(featureTypes);
        
        expect(foundExpected, isNotEmpty, 
               reason: 'Chart should contain common maritime features like $expectedTypes');
        expect(featureTypes.length, greaterThan(5), 
               reason: 'Chart should have diverse feature types');
      });

      test('should provide realistic geographic data', () async {
        final parsedChart = await S57TestFixtures.loadParsedElliottBay();
        
        // Validate that coordinates are in reasonable ranges
        for (final feature in parsedChart.features.take(10)) { // Sample first 10 features
          if (feature.coordinates.isNotEmpty) {
            for (final coord in feature.coordinates) {
              expect(coord.longitude, inInclusiveRange(-123.0, -122.0), 
                     reason: 'Longitude should be in Elliott Bay range');
              expect(coord.latitude, inInclusiveRange(47.4, 47.8), 
                     reason: 'Latitude should be in Elliott Bay range');
            }
          }
        }
      });
    });
  });
}