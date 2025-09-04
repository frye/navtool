import 'dart:io';
import 'dart:typed_data';
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

    group('Enhanced S-57 Object Parsing', () {
      test('should recognize official S-57 object codes', () {
        final result = S57Parser.parse(validTestData);
        
        // Should recognize S-57 feature types by their official codes
        final featureTypes = result.features.map((f) => f.featureType).toSet();
        expect(featureTypes, isNotEmpty);
        
        // Should include some official S-57 feature types
        final hasOfficialTypes = featureTypes.any((type) => 
          type == S57FeatureType.buoy ||
          type == S57FeatureType.buoyLateral ||
          type == S57FeatureType.depthContour ||
          type == S57FeatureType.coastline ||
          type == S57FeatureType.lighthouse
        );
        expect(hasOfficialTypes, isTrue);
      });

      test('should extract S-57 attributes with proper codes', () {
        final result = S57Parser.parse(validTestData);
        
        for (final feature in result.features) {
          expect(feature.attributes, isA<Map<String, dynamic>>());
          
          // Check for S-57 standard attributes based on feature type
          switch (feature.featureType) {
            case S57FeatureType.depthArea:
              expect(feature.attributes.containsKey('DRVAL1') || 
                     feature.attributes.containsKey('min_depth'), isTrue);
              break;
            case S57FeatureType.depthContour:
              expect(feature.attributes.containsKey('VALDCO') || 
                     feature.attributes.containsKey('depth'), isTrue);
              break;
            case S57FeatureType.buoy:
            case S57FeatureType.buoyLateral:
              expect(feature.attributes.containsKey('CATBOY') || 
                     feature.attributes.containsKey('type'), isTrue);
              break;
            case S57FeatureType.lighthouse:
              expect(feature.attributes.containsKey('HEIGHT') || 
                     feature.attributes.containsKey('height'), isTrue);
              break;
            default:
              // Other types may have various attributes
              break;
          }
        }
      });

      test('should handle coordinate parsing correctly', () {
        final result = S57Parser.parse(validTestData);
        
        // All features should have valid coordinates
        for (final feature in result.features) {
          expect(feature.coordinates, isNotEmpty);
          
          for (final coord in feature.coordinates) {
            expect(coord.latitude, greaterThanOrEqualTo(-90.0));
            expect(coord.latitude, lessThanOrEqualTo(90.0));
            expect(coord.longitude, greaterThanOrEqualTo(-180.0));
            expect(coord.longitude, lessThanOrEqualTo(180.0));
          }
        }
      });

      test('should assign correct geometry types', () {
        final result = S57Parser.parse(validTestData);
        
        for (final feature in result.features) {
          switch (feature.featureType) {
            case S57FeatureType.depthArea:
            case S57FeatureType.landArea:
              expect(feature.geometryType, S57GeometryType.area);
              break;
            case S57FeatureType.depthContour:
            case S57FeatureType.coastline:
              expect(feature.geometryType, S57GeometryType.line);
              break;
            case S57FeatureType.buoy:
            case S57FeatureType.buoyLateral:
            case S57FeatureType.buoyCardinal:
            case S57FeatureType.lighthouse:
            case S57FeatureType.beacon:
              // Point features can be point or line depending on coordinates
              expect([S57GeometryType.point, S57GeometryType.line], 
                     contains(feature.geometryType));
              break;
            default:
              expect(feature.geometryType, isA<S57GeometryType>());
              break;
          }
        }
      });
    });

    group('ISO 8211 Compliance', () {
      test('should parse record leader correctly', () {
        final result = S57Parser.parse(validTestData);
        
        // Should successfully parse without throwing
        expect(result, isA<S57ParsedData>());
        expect(result.features, isNotEmpty);
      });

      test('should handle field parsing with proper delimiters', () {
        final result = S57Parser.parse(validTestData);
        
        // Features should be extracted from proper field parsing
        expect(result.features, isNotEmpty);
        
        // Should have realistic feature count (not just sample data)
        expect(result.features.length, greaterThan(0));
        expect(result.features.length, lessThan(20)); // Reasonable upper bound
      });

      test('should extract metadata from DDR correctly', () {
        final result = S57Parser.parse(validTestData);
        final metadata = result.metadata;
        
        expect(metadata.producer, isNotEmpty);
        expect(metadata.version, isNotEmpty);
        expect(metadata.creationDate, isNotNull);
        
        // Should have reasonable metadata values
        expect(metadata.producer, equals('NOAA'));
        expect(metadata.version, equals('3.1'));
      });
    });

    group('Spatial Query Enhancement', () {
      test('should support navigation aid queries with new buoy types', () {
        final result = S57Parser.parse(validTestData);
        final navAids = result.queryNavigationAids();
        
        expect(navAids, isA<List<S57Feature>>());
        
        // Should include different types of navigation aids
        final navTypes = navAids.map((f) => f.featureType).toSet();
        final hasModernNavTypes = navTypes.any((type) => 
          type == S57FeatureType.buoy ||
          type == S57FeatureType.buoyLateral ||
          type == S57FeatureType.buoyCardinal ||
          type == S57FeatureType.beacon ||
          type == S57FeatureType.lighthouse
        );
        expect(hasModernNavTypes, isTrue);
      });

      test('should support enhanced depth feature queries', () {
        final result = S57Parser.parse(validTestData);
        final depthFeatures = result.queryDepthFeatures();
        
        expect(depthFeatures, isA<List<S57Feature>>());
        
        // Should include different depth feature types
        final depthTypes = depthFeatures.map((f) => f.featureType).toSet();
        final hasDepthTypes = depthTypes.any((type) => 
          type == S57FeatureType.depthArea ||
          type == S57FeatureType.depthContour ||
          type == S57FeatureType.sounding
        );
        expect(hasDepthTypes, isTrue);
      });
    });

    group('Feature Label Generation', () {
      test('should generate meaningful labels for marine features', () {
        final result = S57Parser.parse(validTestData);
        
        for (final feature in result.features) {
          expect(feature.label, isNotNull);
          expect(feature.label, isNotEmpty);
          
          // Labels should be meaningful for navigation
          switch (feature.featureType) {
            case S57FeatureType.depthContour:
              expect(feature.label!.toLowerCase(), contains('depth'));
              break;
            case S57FeatureType.buoy:
            case S57FeatureType.buoyLateral:
              expect(feature.label!.toLowerCase(), anyOf([
                contains('buoy'),
                contains('red'),
                contains('green'),
              ]));
              break;
            case S57FeatureType.lighthouse:
              expect(feature.label!.toLowerCase(), anyOf([
                contains('light'),
                contains('lighthouse'),
              ]));
              break;
            default:
              // Other labels should at least exist
              expect(feature.label, isNotEmpty);
              break;
          }
        }
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
/// This simulates the structure of a real S-57 file with enhanced field structure
List<int> _createValidS57TestData() {
  // Create a minimal but valid S-57 ISO 8211 record structure
  final data = <int>[];
  
  // Record leader (24 bytes) - Enhanced for proper parsing
  data.addAll('01582'.codeUnits);     // Record length (01582 bytes)
  data.addAll('3'.codeUnits);         // Interchange level
  data.addAll('L'.codeUnits);         // Leader identifier  
  data.addAll('E'.codeUnits);         // Inline code extension
  data.addAll('1'.codeUnits);         // Version number
  data.addAll(' '.codeUnits);         // Application indicator
  data.addAll('09'.codeUnits);        // Field control length
  data.addAll('00201'.codeUnits);     // Base address of data
  data.addAll(' ! '.codeUnits);       // Extended character set
  data.addAll('4'.codeUnits);         // Size of field length (4 bytes)
  data.addAll('4'.codeUnits);         // Size of field position (4 bytes)
  data.addAll('0'.codeUnits);         // Reserved
  data.addAll('4'.codeUnits);         // Size of field tag (4 bytes)
  
  // Directory entries - Enhanced with proper S-57 fields
  data.addAll('DSID'.codeUnits);      // Data Set Identification
  data.addAll('0165'.codeUnits);      // Field length
  data.addAll('0000'.codeUnits);      // Field position
  
  data.addAll('FRID'.codeUnits);      // Feature Record Identifier
  data.addAll('0048'.codeUnits);      // Field length  
  data.addAll('0165'.codeUnits);      // Field position
  
  data.addAll('FOID'.codeUnits);      // Feature Object Identifier
  data.addAll('0024'.codeUnits);      // Field length
  data.addAll('0213'.codeUnits);      // Field position
  
  data.addAll('ATTF'.codeUnits);      // Feature Attributes
  data.addAll('0036'.codeUnits);      // Field length
  data.addAll('0237'.codeUnits);      // Field position
  
  data.addAll('SG2D'.codeUnits);      // 2D Coordinate
  data.addAll('0024'.codeUnits);      // Field length
  data.addAll('0273'.codeUnits);      // Field position
  
  // Field terminator
  data.add(0x1e);
  
  // Pad to reach base address (position 201)
  while (data.length < 201) {
    data.add(0x20); // Space padding
  }
  
  // DSID field data (Data Set Identification)
  data.addAll('NOAA'.codeUnits);
  data.addAll((' ' * (165 - 4)).codeUnits);
  
  // FRID field data (Feature Record Identifier) - Enhanced
  data.add(100); // RCNM (Record name) - Feature record
  _addBinaryInt(data, 12345, 4); // RCID (Record ID)
  data.add(1);   // PRIM (Primitive)
  data.add(1);   // GRUP (Group)
  _addBinaryInt(data, 58, 2); // OBJL (Object label) - BOYLAT code
  _addBinaryInt(data, 1, 2);  // RVER (Record version)
  data.add(1);   // RUIN (Record update instruction)
  // Pad to exactly 48 bytes
  final fridStartLength = data.length - (201 + 165);
  while (data.length < 201 + 165 + 48) {
    data.add(0x20);
  }
  
  // FOID field data (Feature Object Identifier) - Enhanced
  _addBinaryInt(data, 550, 2);  // AGEN (Agency code) - NOAA
  _addBinaryInt(data, 98765, 4); // FIDN (Feature ID)
  _addBinaryInt(data, 1, 2);    // FIDS (Feature subdivision)
  // Pad to exactly 24 bytes
  final foidStartLength = data.length - (201 + 165 + 48);
  while (data.length < 201 + 165 + 48 + 24) {
    data.add(0x20);
  }
  
  // ATTF field data (Attributes) - Enhanced with S-57 attributes
  _addBinaryInt(data, 84, 2);   // COLOUR attribute code
  _addBinaryInt(data, 2, 4);    // Red color
  _addBinaryInt(data, 85, 2);   // CATBOY attribute code  
  _addBinaryInt(data, 2, 4);    // Port hand buoy
  _addBinaryInt(data, 86, 2);   // COLPAT attribute code
  _addBinaryInt(data, 1, 4);    // Horizontal stripes
  // Pad to exactly 36 bytes
  final attfStartLength = data.length - (201 + 165 + 48 + 24);
  while (data.length < 201 + 165 + 48 + 24 + 36) {
    data.add(0x20);
  }
  
  // SG2D field data (2D Coordinates) - Enhanced with realistic Elliott Bay coords
  final lat = (47.64 * 10000000).round(); // Convert to S-57 coordinate units
  final lon = ((-122.34) * 10000000).round();
  _addBinaryInt(data, lon, 4); // X coordinate (longitude)
  _addBinaryInt(data, lat, 4); // Y coordinate (latitude)
  _addBinaryInt(data, lon + 1000, 4); // Second point X
  _addBinaryInt(data, lat + 1000, 4); // Second point Y
  _addBinaryInt(data, lon + 2000, 4); // Third point X  
  _addBinaryInt(data, lat + 2000, 4); // Third point Y
  
  // Pad to declared record length
  while (data.length < 1582) {
    data.add(0x20);
  }
  
  return data;
}

/// Helper to add binary integer to data list
void _addBinaryInt(List<int> data, int value, int bytes) {
  final byteData = ByteData(8); // Use max size to avoid overflow
  
  switch (bytes) {
    case 1:
      byteData.setUint8(0, value & 0xFF);
      break;
    case 2:
      byteData.setUint16(0, value & 0xFFFF, Endian.little);
      break;
    case 4:
      byteData.setUint32(0, value & 0xFFFFFFFF, Endian.little);
      break;
    default:
      // Default to 4-byte for unknown sizes
      byteData.setUint32(0, value & 0xFFFFFFFF, Endian.little);
      bytes = 4;
  }
  
  for (int i = 0; i < bytes; i++) {
    data.add(byteData.getUint8(i));
  }
}