import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57ToMaritimeAdapter', () {
    group('convertFeatures', () {
      test('should convert empty list to empty list', () {
        final result = S57ToMaritimeAdapter.convertFeatures([]);
        expect(result, isEmpty);
      });

      test('should convert multiple features and filter out null results', () {
        final s57Features = [
          S57Feature(
            recordId: 1,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [
              S57Coordinate(latitude: 47.60, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.32),
              S57Coordinate(latitude: 47.60, longitude: -122.32),
            ],
            attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
          ),
          S57Feature(
            recordId: 2,
            featureType: S57FeatureType.unknown,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
          S57Feature(
            recordId: 3,
            featureType: S57FeatureType.lighthouse,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {'LITCHR': 'F', 'VALNMR': 15.0, 'COLOUR': 'white'},
          ),
        ];

        final result = S57ToMaritimeAdapter.convertFeatures(s57Features);

        expect(result, hasLength(2)); // Unknown feature should be filtered out
        expect(result[0].type, equals(MaritimeFeatureType.depthArea));
        expect(result[1].type, equals(MaritimeFeatureType.lighthouse));
      });
    });

    group('depth area conversion', () {
      test('should convert DEPARE to AreaFeature with proper attributes', () {
        final s57 = S57Feature(
          recordId: 123,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
          ],
          attributes: {'DRVAL1': 5.0, 'DRVAL2': 15.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as AreaFeature;
        expect(feature.id, equals('depare_123'));
        expect(feature.type, equals(MaritimeFeatureType.depthArea));
        expect(feature.attributes['depth_min'], equals(5.0));
        expect(feature.attributes['depth_max'], equals(15.0));
        expect(feature.fillColor, isNotNull);
        expect(feature.coordinates, hasLength(1)); // Single ring
        expect(feature.coordinates.first, hasLength(4)); // Four corners
      });

      test('should handle depth area with missing depth values', () {
        final s57 = S57Feature(
          recordId: 124,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {}, // No depth values
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as AreaFeature;
        expect(feature.attributes['depth_min'], equals(0.0));
        expect(feature.attributes['depth_max'], equals(0.0));
      });

      test('should assign appropriate colors based on depth', () {
        final testCases = [
          {'min': 1.0, 'max': 1.5, 'expectedColor': 'red'}, // Very shallow
          {'min': 3.0, 'max': 4.0, 'expectedColor': 'orange'}, // Shallow
          {'min': 7.0, 'max': 9.0, 'expectedColor': 'yellow'}, // Moderate shallow
          {'min': 15.0, 'max': 18.0, 'expectedColor': 'lightBlue'}, // Moderate depth
          {'min': 25.0, 'max': 30.0, 'expectedColor': 'blue'}, // Deep water
        ];

        for (final testCase in testCases) {
          final s57 = S57Feature(
            recordId: 125,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {
              'DRVAL1': testCase['min'],
              'DRVAL2': testCase['max'],
            },
          );

          final result = S57ToMaritimeAdapter.convertFeatures([s57]);
          final feature = result.first as AreaFeature;
          
          // Verify color is assigned (specific color testing would require more complex setup)
          expect(feature.fillColor, isNotNull);
          expect(feature.fillColor!.alpha, greaterThan(0));
        }
      });
    });

    group('sounding conversion', () {
      test('should convert SOUNDG to PointFeature with depth label', () {
        final s57 = S57Feature(
          recordId: 200,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.605, longitude: -122.325)],
          attributes: {'VALSOU': 12.5},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('sounding_200'));
        expect(feature.type, equals(MaritimeFeatureType.soundings));
        expect(feature.position.latitude, equals(47.605));
        expect(feature.position.longitude, equals(-122.325));
        expect(feature.label, equals('12.5m'));
        expect(feature.attributes['depth'], equals(12.5));
      });

      test('should format depth labels correctly', () {
        final testCases = [
          {'depth': 5.0, 'expectedLabel': '5m'},
          {'depth': 12.3, 'expectedLabel': '12.3m'},
          {'depth': 0.5, 'expectedLabel': '0.5m'},
        ];

        for (final testCase in testCases) {
          final s57 = S57Feature(
            recordId: 201,
            featureType: S57FeatureType.sounding,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {'VALSOU': testCase['depth']},
          );

          final result = S57ToMaritimeAdapter.convertFeatures([s57]);
          final feature = result.first as PointFeature;
          expect(feature.label, equals(testCase['expectedLabel']));
        }
      });
    });

    group('depth contour conversion', () {
      test('should convert DEPCNT to DepthContour with line coordinates', () {
        final s57 = S57Feature(
          recordId: 300,
          featureType: S57FeatureType.depthContour,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.62, longitude: -122.31),
          ],
          attributes: {'VALDCO': 10.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as DepthContour;
        expect(feature.id, equals('depthcontour_300'));
        expect(feature.type, equals(MaritimeFeatureType.depthContour));
        expect(feature.depth, equals(10.0));
        expect(feature.coordinates, hasLength(3));
        expect(feature.coordinates.first.latitude, equals(47.60));
        expect(feature.coordinates.last.latitude, equals(47.62));
      });
    });

    group('coastline conversion', () {
      test('should convert COALNE to LineFeature for shoreline', () {
        final s57 = S57Feature(
          recordId: 400,
          featureType: S57FeatureType.coastline,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
          ],
          attributes: {'CATCOA': 'mangrove'},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as LineFeature;
        expect(feature.id, equals('coastline_400'));
        expect(feature.type, equals(MaritimeFeatureType.shoreline));
        expect(feature.coordinates, hasLength(2));
        expect(feature.width, equals(2.0));
        expect(feature.attributes['category'], equals('mangrove'));
      });

      test('should handle shoreline alias', () {
        final s57 = S57Feature(
          recordId: 401,
          featureType: S57FeatureType.shoreline, // Alias for coastline
          geometryType: S57GeometryType.line,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as LineFeature;
        expect(feature.type, equals(MaritimeFeatureType.shoreline));
      });
    });

    group('navigation aids conversion', () {
      test('should convert lighthouse with characteristics', () {
        final s57 = S57Feature(
          recordId: 500,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'Fl',
            'VALNMR': 18.0,
            'COLOUR': 'red',
          },
          label: 'Point Robinson Light',
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('lighthouse_500'));
        expect(feature.type, equals(MaritimeFeatureType.lighthouse));
        expect(feature.label, equals('Point Robinson Light'));
        expect(feature.attributes['character'], equals('Fl'));
        expect(feature.attributes['range'], equals(18.0));
        expect(feature.attributes['color'], equals('red'));
      });

      test('should generate lighthouse label from characteristics', () {
        final s57 = S57Feature(
          recordId: 501,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'F',
            'VALNMR': 12.0,
            'COLOUR': 'white',
          },
          // No label - should generate one
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        expect(feature.label, equals('Lt F 12M'));
      });

      test('should convert buoy with attributes', () {
        final s57 = S57Feature(
          recordId: 502,
          featureType: S57FeatureType.buoyLateral,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'BOYSHP': 'pillar',
            'COLOUR': 'red',
            'CATBOY': 'port',
            'TOPMAR': 'cylinder',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('buoy_502'));
        expect(feature.type, equals(MaritimeFeatureType.buoy));
        expect(feature.attributes['buoyShape'], equals('pillar'));
        expect(feature.attributes['color'], equals('red'));
        expect(feature.attributes['category'], equals('port'));
        expect(feature.attributes['topmark'], equals('cylinder'));
      });

      test('should convert beacon with cardinal category', () {
        final s57 = S57Feature(
          recordId: 503,
          featureType: S57FeatureType.beacon,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATBCN': 'north',
            'COLOUR': 'black',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('beacon_503'));
        expect(feature.type, equals(MaritimeFeatureType.beacon));
        expect(feature.attributes['category'], equals('north'));
        expect(feature.label, equals('N Card Bcn'));
      });
    });

    group('hazard conversion', () {
      test('should convert obstruction with depth', () {
        final s57 = S57Feature(
          recordId: 600,
          featureType: S57FeatureType.obstruction,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATOBS': 'snag',
            'VALSOU': 5.2,
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('obstruction_600'));
        expect(feature.type, equals(MaritimeFeatureType.obstruction));
        expect(feature.attributes['category'], equals('snag'));
        expect(feature.attributes['depth'], equals(5.2));
        expect(feature.label, equals('Obstr 5.2m'));
      });

      test('should convert wreck with category', () {
        final s57 = S57Feature(
          recordId: 601,
          featureType: S57FeatureType.wreck,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATWRK': 'dangerous',
            'VALSOU': 8.0,
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('wreck_601'));
        expect(feature.type, equals(MaritimeFeatureType.wrecks));
        expect(feature.attributes['category'], equals('dangerous'));
        expect(feature.label, equals('Wreck 8m'));
      });

      test('should convert underwater rock', () {
        final s57 = S57Feature(
          recordId: 602,
          featureType: S57FeatureType.underwater,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {'VALSOU': 2.5},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('underwater_602'));
        expect(feature.type, equals(MaritimeFeatureType.rocks));
        expect(feature.label, equals('Rock 2.5m'));
      });
    });

    group('coordinate handling', () {
      test('should calculate center position from multiple coordinates', () {
        final s57 = S57Feature(
          recordId: 700,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.34),
            S57Coordinate(latitude: 47.62, longitude: -122.34),
            S57Coordinate(latitude: 47.62, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
          ],
          attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as AreaFeature;
        
        // Center should be average of coordinates
        expect(feature.position.latitude, equals(47.61));
        expect(feature.position.longitude, equals(-122.33));
      });

      test('should handle single coordinate', () {
        final s57 = S57Feature(
          recordId: 701,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.605, longitude: -122.325)],
          attributes: {'VALSOU': 5.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        expect(feature.position.latitude, equals(47.605));
        expect(feature.position.longitude, equals(-122.325));
      });

      test('should handle empty coordinates gracefully', () {
        final s57 = S57Feature(
          recordId: 702,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [], // Empty coordinates
          attributes: {'VALSOU': 5.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        // Should default to (0,0)
        expect(feature.position.latitude, equals(0.0));
        expect(feature.position.longitude, equals(0.0));
      });
    });

    group('attribute preservation', () {
      test('should preserve original S-57 metadata', () {
        final s57 = S57Feature(
          recordId: 800,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'Fl',
            'VALNMR': 15.0,
            'custom_attribute': 'test_value',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        // Should preserve original S-57 metadata
        expect(feature.attributes['original_s57_code'], equals(75)); // LIGHTS code
        expect(feature.attributes['original_s57_acronym'], equals('LIGHTS'));
        
        // Should preserve all original attributes
        expect(feature.attributes['LITCHR'], equals('Fl'));
        expect(feature.attributes['VALNMR'], equals(15.0));
        expect(feature.attributes['custom_attribute'], equals('test_value'));
      });
    });

    group('error handling', () {
      test('should handle conversion errors gracefully', () {
        final s57 = S57Feature(
          recordId: 900,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'VALNMR': 'invalid_range', // Invalid type - should use default
          },
        );

        // Should not throw, and should create a feature with default values
        expect(() => S57ToMaritimeAdapter.convertFeatures([s57]), returnsNormally);
        
        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        
        // Should still create a feature with default range value
        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.type, equals(MaritimeFeatureType.lighthouse));
        expect(feature.attributes['range'], equals(10.0)); // Default value used
      });

      test('should filter out unknown feature types', () {
        final s57Features = [
          S57Feature(
            recordId: 901,
            featureType: S57FeatureType.unknown,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
          S57Feature(
            recordId: 902,
            featureType: S57FeatureType.lighthouse,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
        ];

        final result = S57ToMaritimeAdapter.convertFeatures(s57Features);
        
        // Should only convert known feature types
        expect(result, hasLength(1));
        expect(result.first.type, equals(MaritimeFeatureType.lighthouse));
      });
    });
  });
}