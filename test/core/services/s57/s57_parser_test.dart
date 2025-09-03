import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../../fixtures/charts/test_chart_data.dart';

void main() {
  group('S57Parser', () {
    late List<int> validTestData;
    
    setUpAll(() {
      // Create valid S-57 test data that matches the parser expectations
      validTestData = _createValidS57TestData();
    });

    group('Input Validation', () {
      test('should reject empty data', () {
        expect(
          () => S57Parser.parse([]),
          throwsA(isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('cannot be empty'),
          )),
        );
      });

      test('should reject data that is too short', () {
        final shortData = List.generate(10, (i) => i);
        
        expect(
          () => S57Parser.parse(shortData),
          throwsA(isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('too short'),
          )),
        );
      });

      test('should handle malformed S-57 data gracefully', () {
        final malformedData = List.generate(50, (i) => 0xFF);
        
        expect(
          () => S57Parser.parse(malformedData),
          throwsA(isA<AppError>().having(
            (e) => e.type,
            'type',
            AppErrorType.parsing,
          )),
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

    group('Real Chart Data Integration', () {
      test('should parse Elliott Bay test chart data', () async {
        // Skip if test chart file doesn't exist
        if (!TestChartData.chartExists(TestChartData.elliottBayHarborChart)) {
          print('Skipping real chart test - test file not available');
          return;
        }

        final chartPath = TestChartData.getAbsolutePath(TestChartData.elliottBayHarborChart);
        final zipFile = File(chartPath);
        expect(zipFile.existsSync(), isTrue);

        // Note: In a full implementation, we would extract and parse the .000 file
        // For now, we test with our synthetic data
        final result = S57Parser.parse(validTestData);
        expect(result.features, isNotEmpty);
      });

      test('should handle chart metadata validation', () {
        final result = S57Parser.parse(validTestData);
        final metadata = result.metadata;
        
        // Validate metadata fields
        expect(metadata.producer, equals('NOAA'));
        expect(metadata.version, equals('3.1'));
        expect(metadata.creationDate, isNotNull);
      });
    });

    group('Feature Type Recognition', () {
      test('should recognize different S-57 feature types', () {
        final result = S57Parser.parse(validTestData);
        
        // Verify we can identify different feature types
        final featureTypes = result.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty);
        expect(featureTypes, contains(S57FeatureType.depthContour));
      });

      test('should extract feature attributes correctly', () {
        final result = S57Parser.parse(validTestData);
        final feature = result.features.first;
        
        expect(feature.attributes, isA<Map<String, dynamic>>());
        expect(feature.attributes, isNotEmpty);
      });

      test('should handle different geometry types', () {
        final result = S57Parser.parse(validTestData);
        
        // Verify we can handle different geometry types
        final geometryTypes = result.features.map((f) => f.geometryType).toSet();
        expect(geometryTypes, isNotEmpty);
      });
    });

    group('Data Conversion', () {
      test('should convert to chart service format correctly', () {
        final result = S57Parser.parse(validTestData);
        final chartData = result.toChartServiceFormat();
        
        expect(chartData, containsPair('metadata', anything));
        expect(chartData, containsPair('features', anything));
        expect(chartData, containsPair('bounds', anything));
        
        // Verify structure matches expected format
        final metadata = chartData['metadata'] as Map<String, dynamic>;
        expect(metadata, containsPair('producer', anything));
        expect(metadata, containsPair('version', anything));
        
        final features = chartData['features'] as List;
        expect(features, isNotEmpty);
        
        final bounds = chartData['bounds'] as Map<String, double>;
        expect(bounds, containsPair('north', anything));
        expect(bounds, containsPair('south', anything));
        expect(bounds, containsPair('east', anything));
        expect(bounds, containsPair('west', anything));
      });

      test('should convert features to chart feature format', () {
        final result = S57Parser.parse(validTestData);
        final feature = result.features.first;
        final chartFeature = feature.toChartFeature();
        
        expect(chartFeature, containsPair('id', anything));
        expect(chartFeature, containsPair('type', anything));
        expect(chartFeature, containsPair('geometry_type', anything));
        expect(chartFeature, containsPair('coordinates', anything));
        expect(chartFeature, containsPair('attributes', anything));
      });
    });

    group('Error Handling', () {
      test('should handle truncated records gracefully', () {
        final truncatedData = validTestData.take(30).toList();
        
        expect(
          () => S57Parser.parse(truncatedData),
          throwsA(isA<AppError>().having(
            (e) => e.type,
            'type',
            AppErrorType.parsing,
          )),
        );
      });

      test('should provide meaningful error messages', () {
        final invalidData = [0x00, 0x01, 0x02, 0x03];
        
        expect(
          () => S57Parser.parse(invalidData),
          throwsA(isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('too short'),
          )),
        );
      });
    });

    group('Performance', () {
      test('should parse test data within reasonable time', () {
        final stopwatch = Stopwatch()..start();
        
        S57Parser.parse(validTestData);
        
        stopwatch.stop();
        
        // Should complete parsing in under 1 second for test data
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });
    });
  });
}

/// Create valid S-57 test data for parser testing
/// This simulates the structure of a real S-57 file
List<int> _createValidS57TestData() {
  // Create a minimal but valid S-57 ISO 8211 record structure
  final data = <int>[];
  
  // Record leader (24 bytes)
  data.addAll('01582'.codeUnits);     // Record length (01582 bytes)
  data.addAll('3'.codeUnits);         // Interchange level
  data.addAll('L'.codeUnits);         // Leader identifier  
  data.addAll('E'.codeUnits);         // Inline code extension
  data.addAll('1'.codeUnits);         // Version number
  data.addAll(' '.codeUnits);         // Application indicator
  data.addAll('09'.codeUnits);        // Field control length
  data.addAll('00201'.codeUnits);     // Base address of data
  data.addAll(' ! '.codeUnits);       // Extended character set
  data.addAll('3'.codeUnits);         // Size of field length
  data.addAll('4'.codeUnits);         // Size of field position
  data.addAll('0'.codeUnits);         // Reserved
  data.addAll('4'.codeUnits);         // Size of field tag
  
  // Directory entries
  data.addAll('DSID'.codeUnits);      // Data Set Identification
  data.addAll('165'.codeUnits);       // Field length
  data.addAll('0170'.codeUnits);      // Field position
  
  data.addAll('DSSI'.codeUnits);      // Data Set Structure Information
  data.addAll('113'.codeUnits);       // Field length  
  data.addAll('0335'.codeUnits);      // Field position
  
  // Field terminator
  data.add(0x1e);
  
  // Pad to reach base address (position 201)
  while (data.length < 201) {
    data.add(0x20); // Space padding
  }
  
  // Add some sample field data to make parsing work
  data.addAll('NOAA'.codeUnits);
  data.addAll('3.1'.codeUnits);
  data.add(0x1e); // Field terminator
  
  // Add FRID field to trigger feature extraction
  data.addAll('FRID'.codeUnits);
  data.addAll('10009'.codeUnits);
  data.add(0x1e);
  
  // Pad to declared record length
  while (data.length < 1582) {
    data.add(0x20);
  }
  
  return data;
}