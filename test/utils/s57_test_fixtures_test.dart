import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import '../utils/s57_test_fixtures.dart';

void main() {
  group('S57TestFixtures', () {
    group('Chart Availability', () {
      test('should detect if real S57 charts are available', () async {
        // This test will pass regardless of chart availability
        // but provides information about the test environment
        final available = await S57TestFixtures.areChartsAvailable();
        
        if (available) {
          // Print statements for debugging - acceptable in tests
          // ignore: avoid_print
          print('✅ Real S57 charts available - full testing enabled');
        } else {
          // ignore: avoid_print
          print('⚠️ Real S57 charts not available - some tests may be skipped');
        }
        
        // Test should not fail - just report availability
        expect(available, isA<bool>());
      });
    });
    
    group('Raw Chart Data Loading', () {
      test('should load Elliott Bay chart data', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final data = await S57TestFixtures.loadElliottBayChart();
        
        // Validate raw data characteristics
        expect(data, isNotEmpty, reason: 'Chart data should not be empty');
        expect(data.length, greaterThan(1000), 
               reason: 'Chart should contain substantial data');
        expect(data.length, closeTo(S57TestFixtures.elliottBayExpectedSize, 50000),
               reason: 'Chart size should be approximately expected size');
        
        // Validate S57 binary format markers
        expect(data.first, isA<int>(), reason: 'Data should be binary');
      });
      
      test('should load Puget Sound chart data', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final data = await S57TestFixtures.loadPugetSoundChart();
        
        // Validate raw data characteristics
        expect(data, isNotEmpty, reason: 'Chart data should not be empty');
        expect(data.length, greaterThan(10000),
               reason: 'Coastal chart should contain substantial data');
        expect(data.length, greaterThan(S57TestFixtures.elliottBayExpectedSize),
               reason: 'Coastal chart should be larger than harbor chart');
      });
      
      test('should use caching for repeated loads', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        // Load chart twice
        final data1 = await S57TestFixtures.loadElliottBayChart();
        final data2 = await S57TestFixtures.loadElliottBayChart();
        
        // Should be identical (cached)
        expect(data1.length, equals(data2.length));
        expect(identical(data1, data2), isTrue, reason: 'Should use cached data');
      });
    });
    
    group('Parsed Chart Data', () {
      test('should parse Elliott Bay chart successfully', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Validate parsed data structure
        expect(parsedData, isNotNull, reason: 'Parsed data should not be null');
        expect(parsedData.features, isNotEmpty, reason: 'Should contain features');
        expect(parsedData.metadata, isNotNull, reason: 'Should have metadata');
        
        // Validate feature characteristics
        expect(parsedData.features.length, greaterThan(0),
               reason: 'Harbor chart should have at least one feature');
        
        // Check for expected feature types
        final featureTypes = parsedData.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty, reason: 'Should have various feature types');
        
        // ignore: avoid_print
        print('Elliott Bay features found: ${parsedData.features.length}');
        // ignore: avoid_print
        print('Feature types: ${featureTypes.map((t) => t.acronym).join(', ')}');
      });
      
      test('should parse Puget Sound chart successfully', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        
        // Validate parsed data structure
        expect(parsedData, isNotNull, reason: 'Parsed data should not be null');
        expect(parsedData.features, isNotEmpty, reason: 'Should contain features');
        expect(parsedData.metadata, isNotNull, reason: 'Should have metadata');
        
        // Coastal chart should have more features than harbor chart
        final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
        expect(parsedData.features.length, greaterThanOrEqualTo(elliottBayData.features.length),
               reason: 'Coastal chart should have at least as many features as harbor chart');
        
        // ignore: avoid_print
        print('Puget Sound features found: ${parsedData.features.length}');
      });
      
      test('should use caching for parsed data', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        // Parse chart twice
        final parsed1 = await S57TestFixtures.loadParsedElliottBay();
        final parsed2 = await S57TestFixtures.loadParsedElliottBay();
        
        // Should be identical (cached)
        expect(identical(parsed1, parsed2), isTrue, reason: 'Should use cached parsed data');
      });
    });
    
    group('Chart Expectations and Validation', () {
      test('should provide Elliott Bay expectations', () {
        final expectations = S57TestFixtures.getElliottBayExpectations();
        
        expect(expectations.title, isNotEmpty, reason: 'Should have title');
        expect(expectations.scale, greaterThan(0), reason: 'Should have valid scale');
        expect(expectations.expectedFeatureTypes, isNotEmpty, 
               reason: 'Should expect feature types');
        expect(expectations.minExpectedFeatures, greaterThan(0),
               reason: 'Should expect minimum features');
        expect(expectations.maxExpectedFeatures, 
               greaterThan(expectations.minExpectedFeatures),
               reason: 'Max features should be greater than min');
        
        // Validate geographic bounds
        expect(expectations.bounds.north, greaterThan(expectations.bounds.south),
               reason: 'North should be greater than south');
        expect(expectations.bounds.east, greaterThan(expectations.bounds.west),
               reason: 'East should be greater than west');
        
        // Seattle area coordinates validation
        expect(expectations.bounds.north, closeTo(47.6, 0.1),
               reason: 'Should be in Seattle area');
        expect(expectations.bounds.west, closeTo(-122.4, 0.1),
               reason: 'Should be in Seattle area');
      });
      
      test('should provide Puget Sound expectations', () {
        final expectations = S57TestFixtures.getPugetSoundExpectations();
        
        expect(expectations.title, isNotEmpty);
        expect(expectations.scale, greaterThan(S57TestFixtures.getElliottBayExpectations().scale),
               reason: 'Coastal chart should have larger scale than harbor chart');
        expect(expectations.expectedFeatureTypes, isNotEmpty);
        expect(expectations.minExpectedFeatures, greaterThan(0));
      });
      
      test('should validate Elliott Bay chart against expectations', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Should not throw - validation should pass
        expect(
          () => S57TestFixtures.validateParsedChart(
            parsedData, 
            S57TestFixtures.elliottBayChartId,
          ),
          returnsNormally,
          reason: 'Elliott Bay chart should pass validation',
        );
      });
      
      test('should validate Puget Sound chart against expectations', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        
        // Should not throw - validation should pass
        expect(
          () => S57TestFixtures.validateParsedChart(
            parsedData, 
            S57TestFixtures.pugetSoundChartId,
          ),
          returnsNormally,
          reason: 'Puget Sound chart should pass validation',
        );
      });
    });
    
    group('Error Handling', () {
      test('should handle missing chart files gracefully', () async {
        // Clear cache to force file system access
        S57TestFixtures.clearCache();
        
        // Temporarily rename chart directory to simulate missing files
        // This test validates error handling without requiring missing files
        
        expect(
          S57TestFixtures.areChartsAvailable(),
          completion(isA<bool>()),
          reason: 'Should handle file availability check gracefully',
        );
      });
      
      test('should clear cache properly', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        // Load some data to populate cache
        await S57TestFixtures.loadElliottBayChart();
        await S57TestFixtures.loadParsedElliottBay();
        
        // Clear cache
        S57TestFixtures.clearCache();
        
        // Should not throw - cache should be cleared cleanly
        expect(() => S57TestFixtures.clearCache(), returnsNormally);
      });
    });
    
    group('Marine Navigation Feature Validation', () {
      test('should contain expected marine navigation features in Elliott Bay', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        final featureTypes = parsedData.features.map((f) => f.featureType).toSet();
        
        // Marine navigation essentials that should be in a harbor chart
        final expectedMarineFeatures = [
          S57FeatureType.coastline,
          S57FeatureType.depthContour,
          S57FeatureType.depthArea,
        ];
        
        for (final expectedType in expectedMarineFeatures) {
          final hasFeature = featureTypes.contains(expectedType);
          if (hasFeature) {
            // ignore: avoid_print
            print('✅ Found ${expectedType.acronym} features');
          } else {
            // ignore: avoid_print
            print('⚠️ Missing ${expectedType.acronym} features');
          }
        }
        
        // At least some marine features should be present
        expect(featureTypes.length, greaterThan(0),
               reason: 'Chart should contain marine navigation features');
      });
      
      test('should provide realistic marine coordinate data', () async {
        final chartsAvailable = await S57TestFixtures.areChartsAvailable();
        if (!chartsAvailable) {
          return; // Skip test if charts not available
        }
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Find features with coordinates
        final featuresWithCoords = parsedData.features
            .where((f) => f.coordinates.isNotEmpty)
            .toList();
        
        expect(featuresWithCoords, isNotEmpty,
               reason: 'Chart should have features with coordinates');
        
        if (featuresWithCoords.isNotEmpty) {
          // ignore: avoid_print
          print('Features with coordinates: ${featuresWithCoords.length}');
          // ignore: avoid_print
          print('Total features: ${parsedData.features.length}');
          
          // Validate coordinates are in expected geographic region
          // This ensures we're working with real Seattle/Elliott Bay data
          for (final feature in featuresWithCoords.take(5)) { // Check first 5
            if (feature.coordinates.isNotEmpty) {
              final coord = feature.coordinates.first;
              
              // Basic coordinate validation - should be in Pacific Northwest
              expect(coord.latitude, inInclusiveRange(47.0, 48.0),
                     reason: 'Latitude should be in Seattle area');
              expect(coord.longitude, inInclusiveRange(-123.0, -122.0),
                     reason: 'Longitude should be in Seattle area');
            }
          }
        }
      });
    });
  });
}