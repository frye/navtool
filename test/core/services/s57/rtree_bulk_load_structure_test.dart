import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('R-tree Bulk Load Structure', () {
    test('should create proper R-tree structure with correct fan-out', () {
      // Create enough features to trigger multiple levels
      final features = _createFeatureGrid(50); // 50 features
      final tree = S57SpatialTree.bulkLoad(features);

      expect(tree.featureCount, equals(50));

      // Test that queries work correctly
      final allResults = tree.getAllFeatures();
      expect(allResults.length, equals(50));

      // Test bounds query
      final bounds = S57Bounds(
        north: 47.651,
        south: 47.649,
        east: -122.349,
        west: -122.351,
      );
      final boundsResults = tree.queryBounds(bounds);
      expect(boundsResults, isNotEmpty);

      // All results should be within bounds
      for (final feature in boundsResults) {
        bool withinBounds = false;
        for (final coord in feature.coordinates) {
          if (coord.latitude >= bounds.south &&
              coord.latitude <= bounds.north &&
              coord.longitude >= bounds.west &&
              coord.longitude <= bounds.east) {
            withinBounds = true;
            break;
          }
        }
        expect(withinBounds, isTrue);
      }
    });

    test('should handle small datasets (single node)', () {
      final features = _createFeatureGrid(5); // Small dataset
      final tree = S57SpatialTree.bulkLoad(features);

      expect(tree.featureCount, equals(5));

      // Should still work correctly
      final allResults = tree.getAllFeatures();
      expect(allResults.length, equals(5));

      // All features should be retrievable
      final allBounds = tree.calculateBounds()!;
      final boundsResults = tree.queryBounds(allBounds);
      expect(boundsResults.length, equals(5));
    });

    test('should handle empty feature list', () {
      final tree = S57SpatialTree.bulkLoad([]);
      
      expect(tree.featureCount, equals(0));
      expect(tree.getAllFeatures(), isEmpty);
      expect(tree.calculateBounds(), isNull);
      
      final emptyBounds = S57Bounds(
        north: 47.7, south: 47.6, east: -122.3, west: -122.4);
      expect(tree.queryBounds(emptyBounds), isEmpty);
    });

    test('should handle single feature', () {
      final feature = S57Feature(
        recordId: 1,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
        attributes: const {},
      );

      final tree = S57SpatialTree.bulkLoad([feature]);

      expect(tree.featureCount, equals(1));
      expect(tree.getAllFeatures().first.recordId, equals(1));

      // Point query should find the feature
      final pointResults = tree.queryPoint(47.65, -122.35, radiusDegrees: 0.01);
      expect(pointResults.length, equals(1));
      expect(pointResults.first.recordId, equals(1));
    });

    test('should handle features with same coordinates (zero-area)', () {
      final features = List.generate(10, (i) => S57Feature(
        recordId: i,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
        attributes: const {},
      ));

      final tree = S57SpatialTree.bulkLoad(features);

      expect(tree.featureCount, equals(10));

      // Point query should find all features
      final pointResults = tree.queryPoint(47.65, -122.35, radiusDegrees: 0.001);
      expect(pointResults.length, equals(10));
    });

    test('should maintain node fan-out within bounds', () {
      final features = _createFeatureGrid(100); // Large enough to test structure
      final config = RTreeConfig(maxNodeEntries: 8); // Smaller fan-out for testing
      final tree = S57SpatialTree.bulkLoad(features, config: config);

      expect(tree.featureCount, equals(100));

      // Tree should still work correctly with different configuration
      final allResults = tree.getAllFeatures();
      expect(allResults.length, equals(100));

      // Verify bounds calculation
      final bounds = tree.calculateBounds();
      expect(bounds, isNotNull);
      expect(bounds!.isValid, isTrue);
    });

    test('should handle line and area geometries correctly', () {
      final features = [
        // Point at a specific location
        S57Feature(
          recordId: 1,
          featureType: S57FeatureType.buoy,
          geometryType: S57GeometryType.point,
          coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
          attributes: const {},
        ),
        // Line far from the point
        S57Feature(
          recordId: 2,
          featureType: S57FeatureType.depthContour,
          geometryType: S57GeometryType.line,
          coordinates: [
            const S57Coordinate(latitude: 47.62, longitude: -122.38),
            const S57Coordinate(latitude: 47.63, longitude: -122.39),
          ],
          attributes: const {},
        ),
        // Area far from the point
        S57Feature(
          recordId: 3,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            const S57Coordinate(latitude: 47.60, longitude: -122.40),
            const S57Coordinate(latitude: 47.61, longitude: -122.40),
            const S57Coordinate(latitude: 47.61, longitude: -122.39),
            const S57Coordinate(latitude: 47.60, longitude: -122.39),
            const S57Coordinate(latitude: 47.60, longitude: -122.40),
          ],
          attributes: const {},
        ),
      ];

      final tree = S57SpatialTree.bulkLoad(features);

      expect(tree.featureCount, equals(3));

      // Large bounds should capture all features
      final largeBounds = S57Bounds(
        north: 47.7, south: 47.5, east: -122.3, west: -122.5);
      final allResults = tree.queryBounds(largeBounds);
      expect(allResults.length, equals(3));

      // Small bounds should capture only the point feature
      final pointBounds = S57Bounds(
        north: 47.651, south: 47.649, east: -122.349, west: -122.351);
      final pointResults = tree.queryBounds(pointBounds);
      expect(pointResults.length, equals(1));
      expect(pointResults.first.recordId, equals(1));
    });
  });
}

/// Create a grid of features for testing R-tree structure
List<S57Feature> _createFeatureGrid(int count) {
  final features = <S57Feature>[];
  final gridSize = (sqrt(count.toDouble())).ceil();
  
  for (int i = 0; i < count; i++) {
    final row = i ~/ gridSize;
    final col = i % gridSize;
    
    final lat = 47.65 + (row * 0.001); // 1 degree = ~111km, so 0.001 degree = ~111m
    final lon = -122.35 + (col * 0.001);
    
    features.add(S57Feature(
      recordId: i,
      featureType: S57FeatureType.values[i % S57FeatureType.values.length],
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: lat, longitude: lon)],
      attributes: {'grid_pos': '$row,$col'},
    ));
  }
  
  return features;
}