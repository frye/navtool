/// Tests for S57ParsedData.toGeoJson() GeoJSON structure validation
/// 
/// Validates GeoJSON export structure according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 GeoJSON Structure', () {
    test('should produce valid FeatureCollection structure', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final geoJson = result.toGeoJson();
      
      // Should be a FeatureCollection
      expect(geoJson['type'], equals('FeatureCollection'));
      expect(geoJson.keys, contains('features'));
      expect(geoJson['features'], isA<List>());
      
      print('GeoJSON type: ${geoJson['type']}');
      print('Features count: ${(geoJson['features'] as List).length}');
    });

    test('should export features with required GeoJSON properties', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final geoJson = result.toGeoJson();
      final features = geoJson['features'] as List;
      
      if (features.isNotEmpty) {
        final feature = features.first as Map<String, dynamic>;
        
        // Required GeoJSON Feature properties
        expect(feature['type'], equals('Feature'));
        expect(feature.keys, contains('id'));
        expect(feature.keys, contains('properties'));
        expect(feature.keys, contains('geometry'));
        
        // Properties should contain typeAcronym and attrs
        final properties = feature['properties'] as Map<String, dynamic>;
        expect(properties.keys, contains('typeAcronym'));
        expect(properties.keys, contains('attrs'));
        
        // Geometry should have type and coordinates
        final geometry = feature['geometry'] as Map<String, dynamic>;
        expect(geometry.keys, contains('type'));
        expect(geometry.keys, contains('coordinates'));
        
        print('Sample feature ID: ${feature['id']}');
        print('Sample type acronym: ${properties['typeAcronym']}');
        print('Sample geometry type: ${geometry['type']}');
      }
    });

    test('should handle different geometry types correctly', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final geoJson = result.toGeoJson();
      final features = geoJson['features'] as List;
      
      final geometryTypes = <String>{};
      
      for (final featureJson in features) {
        final feature = featureJson as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final geometryType = geometry['type'] as String;
        
        geometryTypes.add(geometryType);
        
        // Validate geometry structure based on type
        switch (geometryType) {
          case 'Point':
            final coords = geometry['coordinates'] as List;
            expect(coords.length, equals(2));
            expect(coords[0], isA<num>()); // longitude
            expect(coords[1], isA<num>()); // latitude
            break;
            
          case 'LineString':
            final coords = geometry['coordinates'] as List;
            expect(coords, isNotEmpty);
            for (final coord in coords) {
              final coordList = coord as List;
              expect(coordList.length, equals(2));
            }
            break;
            
          case 'Polygon':
            final coords = geometry['coordinates'] as List;
            expect(coords, isNotEmpty);
            final ring = coords[0] as List;
            expect(ring, isNotEmpty);
            for (final coord in ring) {
              final coordList = coord as List;
              expect(coordList.length, equals(2));
            }
            break;
        }
      }
      
      print('Geometry types found: $geometryTypes');
    });

    test('should export with WGS84 coordinate order (lon, lat)', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final geoJson = result.toGeoJson();
      final features = geoJson['features'] as List;
      
      for (final featureJson in features) {
        final feature = featureJson as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        
        if (geometry['type'] == 'Point') {
          final coords = geometry['coordinates'] as List;
          final lon = coords[0] as num;
          final lat = coords[1] as num;
          
          // Check coordinate ranges (rough validation)
          expect(lon, greaterThanOrEqualTo(-180));
          expect(lon, lessThanOrEqualTo(180));
          expect(lat, greaterThanOrEqualTo(-90));
          expect(lat, lessThanOrEqualTo(90));
          
          // For Elliott Bay test data, expect roughly these ranges
          if (lon > -130 && lon < -120) {
            expect(lat, greaterThan(45));
            expect(lat, lessThan(50));
          }
        }
      }
    });

    test('should filter attributes appropriately for export', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final geoJson = result.toGeoJson();
      final features = geoJson['features'] as List;
      
      for (final featureJson in features) {
        final feature = featureJson as Map<String, dynamic>;
        final properties = feature['properties'] as Map<String, dynamic>;
        final attrs = properties['attrs'] as Map<String, dynamic>;
        
        // Should not contain internal rendering keys
        expect(attrs.keys, isNot(contains('type')));
        expect(attrs.keys, isNot(contains('color')));
        expect(attrs.keys, isNot(contains('name')));
        expect(attrs.keys, isNot(contains('height')));
        
        print('Filtered attributes: ${attrs.keys}');
      }
    });

    test('should handle empty feature collection', () {
      // Create data that results in no features
      final testData = _createMinimalTestData();
      final result = S57Parser.parse(testData);
      
      // Filter to get empty result
      final geoJson = result.toGeoJson(types: {'NONEXISTENT'});
      
      expect(geoJson['type'], equals('FeatureCollection'));
      expect(geoJson['features'], isEmpty);
    });
  });
}

/// Create test data that generates features for GeoJSON testing
List<int> _createTestDataWithFeatures() {
  return createValidS57TestData();
}

/// Create minimal test data for empty collections
List<int> _createMinimalTestData() {
  return createValidS57TestData();
}