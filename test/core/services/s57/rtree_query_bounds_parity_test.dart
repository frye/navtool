import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/spatial_index_interface.dart';

void main() {
  group('R-tree Bounds Query Parity', () {
    late List<S57Feature> testFeatures;
    late SpatialIndex linearIndex;
    late SpatialIndex rtreeIndex;

    setUpAll(() {
      testFeatures = _createVariedTestFeatures();
      
      // Create both index types
      linearIndex = S57SpatialIndex();
      linearIndex.addFeatures(testFeatures);
      
      rtreeIndex = S57SpatialTree.bulkLoad(testFeatures);
    });

    test('should return identical results for bounds queries', () {
      final testBounds = [
        // Small bounds
        S57Bounds(north: 47.66, south: 47.64, east: -122.33, west: -122.35),
        // Large bounds
        S57Bounds(north: 47.70, south: 47.60, east: -122.30, west: -122.40),
        // Edge case: very small bounds
        S57Bounds(north: 47.641, south: 47.639, east: -122.339, west: -122.341),
        // Edge case: bounds outside data
        S57Bounds(north: 48.0, south: 47.9, east: -122.0, west: -122.1),
      ];

      for (final bounds in testBounds) {
        final linearResults = linearIndex.queryBounds(bounds);
        final rtreeResults = rtreeIndex.queryBounds(bounds);

        // Sort by record ID for comparison
        linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
        rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));

        expect(rtreeResults.length, equals(linearResults.length),
               reason: 'Result count mismatch for bounds $bounds');

        for (int i = 0; i < linearResults.length; i++) {
          expect(rtreeResults[i].recordId, equals(linearResults[i].recordId),
                 reason: 'Feature ID mismatch at index $i for bounds $bounds');
        }
      }
    });

    test('should return identical results for point queries', () {
      final testPoints = [
        // Point in data area
        [47.65, -122.35, 0.01],
        [47.64, -122.34, 0.02],
        // Point with larger radius
        [47.66, -122.36, 0.05],
        // Point outside data
        [47.8, -122.2, 0.01],
      ];

      for (final pointData in testPoints) {
        final lat = pointData[0];
        final lon = pointData[1];
        final radius = pointData[2];

        final linearResults = linearIndex.queryPoint(lat, lon, radiusDegrees: radius);
        final rtreeResults = rtreeIndex.queryPoint(lat, lon, radiusDegrees: radius);

        // Sort by record ID for comparison
        linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
        rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));

        expect(rtreeResults.length, equals(linearResults.length),
               reason: 'Result count mismatch for point ($lat, $lon) radius $radius');

        for (int i = 0; i < linearResults.length; i++) {
          expect(rtreeResults[i].recordId, equals(linearResults[i].recordId),
                 reason: 'Feature ID mismatch at index $i for point ($lat, $lon) radius $radius');
        }
      }
    });

    test('should return identical results for type queries', () {
      final testTypes = [
        S57FeatureType.buoy,
        S57FeatureType.depthContour,
        S57FeatureType.lighthouse,
        S57FeatureType.unknown, // Should return empty
      ];

      for (final type in testTypes) {
        final linearResults = linearIndex.queryByType(type);
        final rtreeResults = rtreeIndex.queryByType(type);

        // Sort by record ID for comparison
        linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
        rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));

        expect(rtreeResults.length, equals(linearResults.length),
               reason: 'Result count mismatch for type $type');

        for (int i = 0; i < linearResults.length; i++) {
          expect(rtreeResults[i].recordId, equals(linearResults[i].recordId),
                 reason: 'Feature ID mismatch at index $i for type $type');
        }
      }
    });

    test('should return identical results for navigation aids queries', () {
      final linearResults = linearIndex.queryNavigationAids();
      final rtreeResults = rtreeIndex.queryNavigationAids();

      // Sort by record ID for comparison
      linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));

      expect(rtreeResults.length, equals(linearResults.length),
             reason: 'Result count mismatch for navigation aids');

      for (int i = 0; i < linearResults.length; i++) {
        expect(rtreeResults[i].recordId, equals(linearResults[i].recordId),
               reason: 'Feature ID mismatch at index $i for navigation aids');
      }
    });

    test('should return identical results for depth features queries', () {
      final linearResults = linearIndex.queryDepthFeatures();
      final rtreeResults = rtreeIndex.queryDepthFeatures();

      // Sort by record ID for comparison
      linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));

      expect(rtreeResults.length, equals(linearResults.length),
             reason: 'Result count mismatch for depth features');

      for (int i = 0; i < linearResults.length; i++) {
        expect(rtreeResults[i].recordId, equals(linearResults[i].recordId),
               reason: 'Feature ID mismatch at index $i for depth features');
      }
    });

    test('should return identical bounds calculations', () {
      final linearBounds = linearIndex.calculateBounds();
      final rtreeBounds = rtreeIndex.calculateBounds();

      if (linearBounds == null) {
        expect(rtreeBounds, isNull);
      } else {
        expect(rtreeBounds, isNotNull);
        expect(rtreeBounds!.north, closeTo(linearBounds.north, 0.000001));
        expect(rtreeBounds.south, closeTo(linearBounds.south, 0.000001));
        expect(rtreeBounds.east, closeTo(linearBounds.east, 0.000001));
        expect(rtreeBounds.west, closeTo(linearBounds.west, 0.000001));
      }
    });

    test('should return identical feature counts and types', () {
      expect(rtreeIndex.featureCount, equals(linearIndex.featureCount));
      expect(rtreeIndex.presentFeatureTypes, equals(linearIndex.presentFeatureTypes));
      
      final linearFeatures = List<S57Feature>.from(linearIndex.getAllFeatures());
      final rtreeFeatures = List<S57Feature>.from(rtreeIndex.getAllFeatures());
      
      linearFeatures.sort((a, b) => a.recordId.compareTo(b.recordId));
      rtreeFeatures.sort((a, b) => a.recordId.compareTo(b.recordId));
      
      expect(rtreeFeatures.length, equals(linearFeatures.length));
      for (int i = 0; i < linearFeatures.length; i++) {
        expect(rtreeFeatures[i].recordId, equals(linearFeatures[i].recordId));
      }
    });
  });
}

/// Create varied test features for comprehensive parity testing
List<S57Feature> _createVariedTestFeatures() {
  return [
    // Points
    S57Feature(
      recordId: 1,
      featureType: S57FeatureType.buoy,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.64, longitude: -122.34)],
      attributes: {'type': 'lateral'},
    ),
    S57Feature(
      recordId: 2,
      featureType: S57FeatureType.lighthouse,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.68, longitude: -122.32)],
      attributes: {'height': 25.0},
    ),
    S57Feature(
      recordId: 3,
      featureType: S57FeatureType.beacon,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.63, longitude: -122.33)],
      attributes: {'type': 'starboard'},
    ),

    // Lines
    S57Feature(
      recordId: 4,
      featureType: S57FeatureType.depthContour,
      geometryType: S57GeometryType.line,
      coordinates: [
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
        const S57Coordinate(latitude: 47.66, longitude: -122.36),
        const S57Coordinate(latitude: 47.67, longitude: -122.37),
      ],
      attributes: {'depth': 10.0},
    ),
    S57Feature(
      recordId: 5,
      featureType: S57FeatureType.coastline,
      geometryType: S57GeometryType.line,
      coordinates: [
        const S57Coordinate(latitude: 47.61, longitude: -122.33),
        const S57Coordinate(latitude: 47.62, longitude: -122.32),
        const S57Coordinate(latitude: 47.63, longitude: -122.31),
      ],
      attributes: {'category': 'natural'},
    ),

    // Areas  
    S57Feature(
      recordId: 6,
      featureType: S57FeatureType.depthArea,
      geometryType: S57GeometryType.area,
      coordinates: [
        const S57Coordinate(latitude: 47.64, longitude: -122.35),
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
        const S57Coordinate(latitude: 47.65, longitude: -122.34),
        const S57Coordinate(latitude: 47.64, longitude: -122.34),
        const S57Coordinate(latitude: 47.64, longitude: -122.35), // Close polygon
      ],
      attributes: {'depth_range': '5-10m'},
    ),

    // Single point features at edges
    S57Feature(
      recordId: 7,
      featureType: S57FeatureType.sounding,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.60, longitude: -122.40)],
      attributes: {'depth': 15.2},
    ),
    S57Feature(
      recordId: 8,
      featureType: S57FeatureType.wreck,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.69, longitude: -122.31)],
      attributes: {'category': 'dangerous'},
    ),

    // Zero-area polygon (degenerate case)
    S57Feature(
      recordId: 9,
      featureType: S57FeatureType.obstruction,
      geometryType: S57GeometryType.area,
      coordinates: [
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
      ],
      attributes: {'type': 'pile'},
    ),
  ];
}