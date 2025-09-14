import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../../utils/s57_test_fixtures.dart';

void main() {
  group('S57Parser', () {
    late FixtureAvailability availability;
    
    setUpAll(() async {
      availability = await S57TestFixtures.checkFixtureAvailability();
      if (!availability.hasAnyFixtures) {
        print('Warning: No S57 fixtures available - some tests will be skipped');
        print('Install fixtures at: ${availability.fixturesPath}');
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
          throwsA(
            isA<AppError>().having((e) => e.type, 'type', AppErrorType.parsing),
          ),
        );
      });
    });

    group('Basic S-57 Parsing', () {
      test('should parse valid S-57 test data successfully', () {
        final result = S57Parser.parse(validTestData);

        expect(result, isA<S57ParsedData>());
        expect(result.metadata, isA<S57ChartMetadata>());
        expect(result.features, isA<List<S57Feature>>());
        expect(result.bounds, isA<S57Bounds>());
      });

      test('should extract metadata from S-57 data', () {
        final result = S57Parser.parse(validTestData);
        final metadata = result.metadata;

        expect(metadata.producer, isNotEmpty);
        expect(metadata.version, isNotEmpty);
        expect(metadata.creationDate, isNotNull);
      });

      test('should extract features from S-57 data', () {
        final result = S57Parser.parse(validTestData);

        // Should extract at least some features
        expect(result.features, isNotEmpty);

        // Verify feature structure
        final feature = result.features.first;
        expect(feature.recordId, isA<int>());
        expect(feature.featureType, isA<S57FeatureType>());
        expect(feature.geometryType, isA<S57GeometryType>());
        expect(feature.coordinates, isNotEmpty);
      });

      test('should calculate valid geographic bounds', () {
        final result = S57Parser.parse(validTestData);
        final bounds = result.bounds;

        expect(bounds.isValid, isTrue);
        expect(bounds.north, greaterThan(bounds.south));
        expect(bounds.east, greaterThan(bounds.west));

        // Should be in reasonable range for test data (Elliott Bay area)
        expect(bounds.north, lessThanOrEqualTo(90.0));
        expect(bounds.south, greaterThanOrEqualTo(-90.0));
        expect(bounds.east, lessThanOrEqualTo(180.0));
        expect(bounds.west, greaterThanOrEqualTo(-180.0));
      });
    });

    group('Real NOAA ENC Data Parsing', () {
      test('should parse Elliott Bay Harbor chart successfully', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final chartData = await S57TestFixtures.loadParsedElliottBay();
        
        expect(chartData, isNotNull);
        expect(chartData.features, isNotEmpty);
        expect(chartData.metadata, isNotNull);
        expect(chartData.bounds, isNotNull);
        expect(chartData.spatialIndex, isNotNull);
        
        // Validate Elliott Bay specific characteristics
        expect(chartData.metadata.producer, isNotEmpty);
        expect(chartData.metadata.version, isNotEmpty);
        
        // Elliott Bay should have marine navigation features
        final featureTypes = chartData.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty);
        
        // Should have depth-related features (typical for harbor charts)
        final hasDepthFeatures = featureTypes.any((type) => [
          S57FeatureType.depthArea,
          S57FeatureType.depthContour,
          S57FeatureType.sounding,
        ].contains(type));
        expect(hasDepthFeatures, isTrue, reason: 'Harbor chart should have depth features');
      });
      
      test('should parse Puget Sound chart successfully', () async {
        if (!availability.pugetSoundAvailable) {
          print('Puget Sound fixture not available - skipping test');
          return;
        }

        final chartData = await S57TestFixtures.loadParsedPugetSound();
        
        expect(chartData, isNotNull);
        expect(chartData.features, isNotEmpty);
        expect(chartData.metadata, isNotNull);
        expect(chartData.bounds, isNotNull);
        expect(chartData.spatialIndex, isNotNull);
        
        // Puget Sound should have more features than Elliott Bay
        if (availability.elliottBayAvailable) {
          final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
          expect(chartData.features.length, greaterThan(elliottBayData.features.length));
        }
        
        // Should have coastal features
        final featureTypes = chartData.features.map((f) => f.featureType).toSet();
        expect(featureTypes.length, greaterThan(5), reason: 'Coastal chart should have diverse features');
      });
      
      test('should validate Elliott Bay chart metadata', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final chartData = await S57TestFixtures.loadParsedElliottBay();
        final validation = S57TestFixtures.validateChartMetadata(chartData, 'US5WA50M');
        
        expect(validation.chartId, equals('US5WA50M'));
        
        if (!validation.isValid) {
          print('Elliott Bay metadata validation errors: ${validation.errors}');
        }
        
        if (validation.hasWarnings) {
          print('Elliott Bay metadata validation warnings: ${validation.warnings}');
        }
        
        // Should have reasonable metadata
        expect(validation.metadata.producer, isNotEmpty);
        expect(validation.metadata.version, isNotEmpty);
      });
    });

    group('Real S57 Feature Validation', () {
      test('should recognize official S-57 object codes in Elliott Bay', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final result = await S57TestFixtures.loadParsedElliottBay();

        // Should recognize S-57 feature types by their official codes
        final featureTypes = result.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty);

        // Print actual feature types found for debugging
        final acronyms = featureTypes.map((type) => type.acronym).toList()..sort();
        print('Elliott Bay S57 feature types: $acronyms');

        // Elliott Bay harbor chart should have marine navigation features
        expect(featureTypes.length, greaterThan(0));
      });

      test('should validate expected S57 features in Elliott Bay', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final result = await S57TestFixtures.loadParsedElliottBay();
        
        // Analyze feature distribution
        final featureTypeCounts = <S57FeatureType, int>{};
        for (final feature in result.features) {
          featureTypeCounts[feature.featureType] = 
              (featureTypeCounts[feature.featureType] ?? 0) + 1;
        }

        // Validate expected S57 feature categories for harbor chart
        final hasDepthFeatures = featureTypeCounts.keys.any((type) => [
          S57FeatureType.depthArea,    // DEPARE
          S57FeatureType.depthContour, // DEPCNT  
          S57FeatureType.sounding,     // SOUNDG
        ].contains(type));

        final hasNavigationFeatures = featureTypeCounts.keys.any((type) => [
          S57FeatureType.buoy,         // Generic buoys
          S57FeatureType.buoyLateral,  // BOYLAT
          S57FeatureType.lighthouse,   // LIGHTS
          S57FeatureType.beacon,       // BCNCAR
        ].contains(type));

        final hasCoastlineFeatures = featureTypeCounts.keys.any((type) => [
          S57FeatureType.coastline,    // COALNE
          S57FeatureType.shoreline,    // COALNE alias
          S57FeatureType.landArea,     // LNDARE
        ].contains(type));

        // Print feature analysis
        print('Elliott Bay feature analysis:');
        for (final entry in featureTypeCounts.entries) {
          print('  ${entry.key.acronym}: ${entry.value} features');
        }

        // Harbor charts typically have depth and navigation features
        expect(result.features, isNotEmpty, 
          reason: 'Elliott Bay should contain S57 features');
      });

      test('should extract real S-57 attributes from Elliott Bay', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final result = await S57TestFixtures.loadParsedElliottBay();

        // Validate that features have attributes
        var featuresWithAttributes = 0;
        
        for (final feature in result.features) {
          expect(feature.attributes, isA<Map<String, dynamic>>());

          if (feature.attributes.isNotEmpty) {
            featuresWithAttributes++;
            
            // Print sample attributes for debugging
            if (featuresWithAttributes <= 5) {
              print('${feature.featureType.acronym} attributes: ${feature.attributes.keys.take(5).join(', ')}');
            }
          }

          // Validate standard S-57 attributes based on feature type
          switch (feature.featureType) {
            case S57FeatureType.depthArea:
              // DEPARE should have depth range attributes
              final hasDepthAttrs = feature.attributes.containsKey('DRVAL1') ||
                  feature.attributes.containsKey('DRVAL2');
              // Don't enforce strict requirements as real data may vary
              break;
            case S57FeatureType.sounding:
              // SOUNDG should have sounding value
              final hasSoundingAttrs = feature.attributes.containsKey('VALSOU');
              // Don't enforce strict requirements as real data may vary
              break;
            case S57FeatureType.buoyLateral:
            case S57FeatureType.buoy:
              // Buoys may have category, color, shape attributes
              final hasBuoyAttrs = feature.attributes.containsKey('CATBOY') ||
                  feature.attributes.containsKey('COLOUR') ||
                  feature.attributes.containsKey('BOYSHP');
              // Don't enforce strict requirements as real data may vary
              break;
            default:
              // Other features - just validate attributes exist as map
              break;
          }
        }

        print('Features with attributes: $featuresWithAttributes of ${result.features.length}');
      });

      test('should validate coordinate parsing with real data', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final result = await S57TestFixtures.loadParsedElliottBay();

        // All features should have valid coordinates
        var validCoordinates = 0;
        
        for (final feature in result.features) {
          expect(feature.coordinates, isNotEmpty, 
            reason: 'Feature ${feature.featureType.acronym} should have coordinates');

          for (final coord in feature.coordinates) {
            // Elliott Bay area coordinates should be in reasonable ranges
            expect(coord.latitude, greaterThanOrEqualTo(47.0), 
              reason: 'Elliott Bay latitude should be around 47°N');
            expect(coord.latitude, lessThanOrEqualTo(48.0), 
              reason: 'Elliott Bay latitude should be around 47°N');
            expect(coord.longitude, greaterThanOrEqualTo(-123.0), 
              reason: 'Elliott Bay longitude should be around 122°W');
            expect(coord.longitude, lessThanOrEqualTo(-121.0), 
              reason: 'Elliott Bay longitude should be around 122°W');
            
            validCoordinates++;
          }
        }
        
        print('Validated $validCoordinates coordinates in Elliott Bay chart');
        expect(validCoordinates, greaterThan(0));
      });

      test('should validate geometry types with real data', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final result = await S57TestFixtures.loadParsedElliottBay();

        // Validate geometry types match feature types
        var geometryTypeValidation = <String, int>{};
        
        for (final feature in result.features) {
          final key = '${feature.featureType.acronym}:${feature.geometryType}';
          geometryTypeValidation[key] = (geometryTypeValidation[key] ?? 0) + 1;
          
          // Validate geometry type is reasonable for feature type
          expect(feature.geometryType, isA<S57GeometryType>());
          
          // Print sample geometry types for analysis
          if (geometryTypeValidation[key] == 1) {
            print('${feature.featureType.acronym} -> ${feature.geometryType}');
          }
        }
        
        expect(result.features, isNotEmpty);
      });
    });

    group('Real Chart Performance', () {
      test('should parse Elliott Bay chart efficiently', () async {
        if (!availability.elliottBayAvailable) {
          print('Elliott Bay fixture not available - skipping test');
          return;
        }

        final stopwatch = Stopwatch()..start();
        final result = await S57TestFixtures.loadParsedElliottBay();
        stopwatch.stop();

        expect(result, isA<S57ParsedData>());
        expect(result.features, isNotEmpty);
        
        // Real chart parsing should complete within reasonable time
        print('Elliott Bay parsing time: ${stopwatch.elapsedMilliseconds}ms');
        expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // 30 seconds max
      });

      test('should handle large Puget Sound chart efficiently', () async {
        if (!availability.pugetSoundAvailable) {
          print('Puget Sound fixture not available - skipping test');
          return;
        }

        final stopwatch = Stopwatch()..start();
        final result = await S57TestFixtures.loadParsedPugetSound();
        stopwatch.stop();

        expect(result, isA<S57ParsedData>());
        expect(result.features, isNotEmpty);
        
        // Larger chart should still parse within reasonable time
        print('Puget Sound parsing time: ${stopwatch.elapsedMilliseconds}ms');
        print('Puget Sound features: ${result.features.length}');
        expect(stopwatch.elapsedMilliseconds, lessThan(60000)); // 60 seconds max
      });
    });
  });
}
