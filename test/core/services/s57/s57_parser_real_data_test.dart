import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../../utils/s57_test_fixtures.dart';

/// Migration test for Issue #211: Real S57 data usage in S57Parser tests
void main() {
  group('S57Parser with Real NOAA ENC Data', () {
    late List<int> realElliottBayData;
    late S57ParsedData realParsedData;
    bool hasRealCharts = false;

    setUpAll(() async {
      // Check if real S57 charts are available
      hasRealCharts = await S57TestFixtures.areChartsAvailable();
      
      if (hasRealCharts) {
        // Load real Elliott Bay chart data
        realElliottBayData = await S57TestFixtures.loadElliottBayChart();
        realParsedData = await S57TestFixtures.loadParsedElliottBay();
        print('S57Parser tests using real NOAA ENC data (Elliott Bay: ${realElliottBayData.length} bytes)');
      } else {
        print('S57Parser tests: Real charts not available, tests will be skipped');
      }
    });

    group('Input Validation', () {
      test('should reject empty data', () {
        expect(
          () => S57Parser.parse([]),
          throwsA(
            isA<AppError>().having(
              (e) => e.message,
              'message',
              contains('cannot be empty'),
            ),
          ),
        );
      });

      test('should reject data that is too short', () {
        final shortData = List.generate(10, (i) => i);

        expect(
          () => S57Parser.parse(shortData),
          throwsA(
            isA<AppError>().having(
              (e) => e.message,
              'message',
              contains('too short'),
            ),
          ),
        );
      });

      test('should handle malformed S-57 data gracefully', () {
        final malformedData = List.generate(50, (i) => 0xFF);

        expect(
          () => S57Parser.parse(malformedData),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Real Elliott Bay Chart Parsing', () {
      test('should parse real Elliott Bay chart successfully', () {
        if (!hasRealCharts) {
          print('Skipping - real Elliott Bay chart not available');
          return;
        }

        final result = S57Parser.parse(realElliottBayData);

        // Validate parsing results with real data
        expect(result, isNotNull);
        expect(result.features, isNotEmpty);
        expect(result.bounds, isNotNull);
        expect(result.metadata, isNotNull);

        // Validate we have expected Elliott Bay marine features
        final featureTypes = result.features.map((f) => f.featureType).toSet();
        expect(featureTypes, contains(S57FeatureType.depthContour)); // DEPCNT
        expect(featureTypes, contains(S57FeatureType.buoyLateral)); // BOYLAT
        expect(featureTypes, contains(S57FeatureType.lighthouse)); // LIGHTS

        print('Real Elliott Bay features: ${featureTypes.map((t) => t.acronym).join(', ')}');
      });

      test('should calculate valid geographic bounds for Elliott Bay', () {
        if (!hasRealCharts) {
          print('Skipping - real chart not available');
          return;
        }

        final result = S57Parser.parse(realElliottBayData);
        final bounds = result.bounds;

        expect(bounds.isValid, isTrue);
        expect(bounds.north, greaterThan(bounds.south));
        expect(bounds.east, greaterThan(bounds.west));

        // Elliott Bay specific geographic bounds (Seattle area)
        final expectations = S57TestFixtures.getElliottBayExpectations();
        
        // Allow for some tolerance in bounds since real data might extend slightly beyond expected
        const tolerance = 0.1;
        expect(bounds.north, lessThanOrEqualTo(expectations.bounds.north + tolerance));
        expect(bounds.south, greaterThanOrEqualTo(expectations.bounds.south - tolerance));
        expect(bounds.west, greaterThanOrEqualTo(expectations.bounds.west - tolerance));
        expect(bounds.east, lessThanOrEqualTo(expectations.bounds.east + tolerance));
        
        // Verify bounds are generally in Seattle area (broad range)
        expect(bounds.north, inInclusiveRange(47.5, 47.8), reason: 'North bound should be in Seattle area');
        expect(bounds.south, inInclusiveRange(47.5, 47.8), reason: 'South bound should be in Seattle area');
        expect(bounds.west, inInclusiveRange(-122.5, -122.0), reason: 'West bound should be in Seattle area');
        expect(bounds.east, inInclusiveRange(-122.5, -122.0), reason: 'East bound should be in Seattle area');

        print('Elliott Bay bounds: N:${bounds.north.toStringAsFixed(4)} S:${bounds.south.toStringAsFixed(4)} E:${bounds.east.toStringAsFixed(4)} W:${bounds.west.toStringAsFixed(4)}');
      });

      test('should validate real marine features and coordinates', () {
        if (!hasRealCharts) {
          print('Skipping - real chart data not available');
          return;
        }

        final result = S57Parser.parse(realElliottBayData);

        // All features should have valid coordinates in Seattle area
        final expectations = S57TestFixtures.getElliottBayExpectations();
        
        for (final feature in result.features) {
          expect(feature.coordinates, isNotEmpty);

          for (final coord in feature.coordinates) {
            // Validate coordinates are within reasonable bounds
            expect(coord.latitude, greaterThanOrEqualTo(-90.0));
            expect(coord.latitude, lessThanOrEqualTo(90.0));
            expect(coord.longitude, greaterThanOrEqualTo(-180.0));
            expect(coord.longitude, lessThanOrEqualTo(180.0));

            // Elliott Bay specific coordinate validation (with generous tolerance for real data)
            const tolerance = 0.2; // More generous tolerance for real S57 data
            expect(coord.latitude, inInclusiveRange(expectations.bounds.south - tolerance, expectations.bounds.north + tolerance),
              reason: 'Latitude should be within Elliott Bay bounds with tolerance');
            expect(coord.longitude, inInclusiveRange(expectations.bounds.west - tolerance, expectations.bounds.east + tolerance),
              reason: 'Longitude should be within Elliott Bay bounds with tolerance');
          }
        }

        print('All ${result.features.length} features have valid Elliott Bay coordinates');
      });

      test('should use cached parsed Elliott Bay data for performance', () {
        if (!hasRealCharts) {
          print('Skipping - real chart data not available');
          return;
        }

        // Test the cached parsed data is consistent with raw parsing
        expect(realParsedData, isNotNull);
        expect(realParsedData.features, isNotEmpty);

        // Verify cached data matches expectations
        S57TestFixtures.validateParsedChart(realParsedData, 'US5WA50M');

        print('Cached parsed data validated successfully');
      });
    });

    group('Real S57 Marine Feature Analysis', () {
      test('should recognize official S-57 object codes from real data', () {
        if (!hasRealCharts) {
          print('Skipping - real chart data not available');
          return;
        }

        final result = S57Parser.parse(realElliottBayData);

        // Should recognize S-57 feature types by their official codes
        final featureTypes = result.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty);

        // Elliott Bay should include official S-57 marine navigation feature types
        final hasMarineTypes = featureTypes.any(
          (type) =>
              type == S57FeatureType.buoyLateral ||
              type == S57FeatureType.depthContour ||
              type == S57FeatureType.lighthouse ||
              type == S57FeatureType.coastline ||
              type == S57FeatureType.depthArea,
        );
        expect(hasMarineTypes, isTrue, reason: 'Elliott Bay chart should contain marine navigation features');

        print('Real S57 feature types found: ${featureTypes.map((t) => t.acronym).toList()}');
      });

      test('should extract real S-57 attributes with proper codes', () {
        if (!hasRealCharts) {
          print('Skipping - real chart data not available');
          return;
        }

        final result = S57Parser.parse(realElliottBayData);

        var validAttributeFeatures = 0;

        for (final feature in result.features) {
          expect(feature.attributes, isA<Map<String, dynamic>>());

          // Check for S-57 standard attributes based on feature type from real data
          switch (feature.featureType) {
            case S57FeatureType.depthArea:
              if (feature.attributes.containsKey('DRVAL1') ||
                  feature.attributes.containsKey('DRVAL2') ||
                  feature.attributes.containsKey('min_depth')) {
                validAttributeFeatures++;
              }
              break;
            case S57FeatureType.depthContour:
              if (feature.attributes.containsKey('VALDCO') ||
                  feature.attributes.containsKey('depth')) {
                validAttributeFeatures++;
              }
              break;
            case S57FeatureType.buoy:
            case S57FeatureType.buoyLateral:
              if (feature.attributes.containsKey('CATBOY') ||
                  feature.attributes.containsKey('type') ||
                  feature.attributes.containsKey('COLOUR')) {
                validAttributeFeatures++;
              }
              break;
            case S57FeatureType.lighthouse:
              if (feature.attributes.containsKey('HEIGHT') ||
                  feature.attributes.containsKey('height') ||
                  feature.attributes.containsKey('LITCHR') ||
                  feature.attributes.containsKey('COLOUR')) {
                validAttributeFeatures++;
              }
              break;
            default:
              // Other types may have various attributes - count them as valid
              if (feature.attributes.isNotEmpty) {
                validAttributeFeatures++;
              }
              break;
          }
        }

        // At least some features should have proper S-57 attributes
        expect(validAttributeFeatures, greaterThan(0), 
          reason: 'Real Elliott Bay data should contain features with valid S-57 attributes');

        print('Features with valid S-57 attributes: $validAttributeFeatures/${result.features.length}');
      });
    });
  });
}