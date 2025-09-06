import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/spatial_index_interface.dart';

void main() {
  group('R-tree Small Dataset Fallback', () {
    test('should use linear index for small datasets', () {
      final smallFeatures = _createTestFeatures(50); // Below threshold of 200
      
      final index = SpatialIndexFactory.create(smallFeatures);
      
      // Should be a linear index (S57SpatialIndex)
      expect(index, isA<S57SpatialIndex>());
      expect(index.featureCount, equals(50));
      
      // Should still work correctly
      final bounds = S57Bounds(
        north: 47.66, south: 47.64, east: -122.34, west: -122.36);
      final results = index.queryBounds(bounds);
      expect(results, isNotEmpty);
    });

    test('should use R-tree for large datasets', () {
      final largeFeatures = _createTestFeatures(500); // Above threshold of 200
      
      final index = SpatialIndexFactory.create(largeFeatures);
      
      // Should be an R-tree index (S57SpatialTree)
      expect(index, isA<S57SpatialTree>());
      expect(index.featureCount, equals(500));
      
      // Should still work correctly
      final bounds = S57Bounds(
        north: 47.66, south: 47.64, east: -122.34, west: -122.36);
      final results = index.queryBounds(bounds);
      expect(results, isNotEmpty);
    });

    test('should respect forceLinear configuration', () {
      final largeFeatures = _createTestFeatures(500); // Above threshold
      final config = RTreeConfig(forceLinear: true);
      
      final index = SpatialIndexFactory.create(largeFeatures, config: config);
      
      // Should be linear despite large dataset
      expect(index, isA<S57SpatialIndex>());
      expect(index.featureCount, equals(500));
    });

    test('should handle exactly threshold-sized datasets', () {
      final thresholdFeatures = _createTestFeatures(200); // Exactly at threshold
      
      final index = SpatialIndexFactory.create(thresholdFeatures);
      
      // At threshold should use R-tree (>= 200 uses R-tree, < 200 uses linear)
      expect(index, isA<S57SpatialTree>());
      expect(index.featureCount, equals(200));
    });

    test('should handle empty datasets', () {
      final emptyFeatures = <S57Feature>[];
      
      final index = SpatialIndexFactory.create(emptyFeatures);
      
      // Empty should use linear
      expect(index, isA<S57SpatialIndex>());
      expect(index.featureCount, equals(0));
      expect(index.getAllFeatures(), isEmpty);
    });

    test('should handle single feature datasets', () {
      final singleFeature = [S57Feature(
        recordId: 1,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
        attributes: const {},
      )];
      
      final index = SpatialIndexFactory.create(singleFeature);
      
      expect(index, isA<S57SpatialIndex>());
      expect(index.featureCount, equals(1));
      
      final pointResults = index.queryPoint(47.65, -122.35, radiusDegrees: 0.01);
      expect(pointResults.length, equals(1));
    });

    test('should provide identical query results regardless of implementation', () {
      final features = _createTestFeatures(300); // Large enough for R-tree
      
      // Create both implementations
      final linearConfig = RTreeConfig(forceLinear: true);
      final linearIndex = SpatialIndexFactory.create(features, config: linearConfig);
      final rtreeIndex = SpatialIndexFactory.create(features);
      
      expect(linearIndex, isA<S57SpatialIndex>());
      expect(rtreeIndex, isA<S57SpatialTree>());
      
      // Test bounds query
      final bounds = S57Bounds(
        north: 47.66, south: 47.64, east: -122.34, west: -122.36);
      
      final linearResults = linearIndex.queryBounds(bounds);
      final rtreeResults = rtreeIndex.queryBounds(bounds);
      
      // Sort for comparison
      linearResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      rtreeResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      
      expect(rtreeResults.length, equals(linearResults.length));
      for (int i = 0; i < linearResults.length; i++) {
        expect(rtreeResults[i].recordId, equals(linearResults[i].recordId));
      }
      
      // Test point query
      final linearPointResults = linearIndex.queryPoint(47.65, -122.35, radiusDegrees: 0.02);
      final rtreePointResults = rtreeIndex.queryPoint(47.65, -122.35, radiusDegrees: 0.02);
      
      linearPointResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      rtreePointResults.sort((a, b) => a.recordId.compareTo(b.recordId));
      
      expect(rtreePointResults.length, equals(linearPointResults.length));
      for (int i = 0; i < linearPointResults.length; i++) {
        expect(rtreePointResults[i].recordId, equals(linearPointResults[i].recordId));
      }
    });

    test('should maintain configuration settings', () {
      final features = _createTestFeatures(500);
      final config = RTreeConfig(maxNodeEntries: 8);
      
      final index = SpatialIndexFactory.create(features, config: config);
      
      expect(index, isA<S57SpatialTree>());
      
      // Verify it works with custom configuration
      final tree = index as S57SpatialTree;
      expect(tree.config.maxNodeEntries, equals(8));
      
      // Should still function correctly
      final bounds = tree.calculateBounds();
      expect(bounds, isNotNull);
      expect(bounds!.isValid, isTrue);
    });
  });
}

/// Create test features for fallback testing
List<S57Feature> _createTestFeatures(int count) {
  final features = <S57Feature>[];
  
  for (int i = 0; i < count; i++) {
    final lat = 47.65 + (i * 0.0001); // Spread features in small area
    final lon = -122.35 + ((i % 10) * 0.0001);
    
    features.add(S57Feature(
      recordId: i,
      featureType: S57FeatureType.values[i % S57FeatureType.values.length],
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: lat, longitude: lon)],
      attributes: {'test_id': i},
    ));
  }
  
  return features;
}