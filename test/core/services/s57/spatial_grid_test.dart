import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/spatial_grid.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('SpatialGrid', () {
    late SpatialGrid spatialGrid;
    late List<S57Feature> testFeatures;

    setUp(() {
      final bounds = S57Bounds(
        north: 47.70,
        south: 47.60,
        east: -122.30,
        west: -122.40,
      );
      
      spatialGrid = SpatialGrid(
        bounds: bounds,
        cellSizeDegrees: 0.01, // 1km cells
      );
      
      testFeatures = _createTestFeatures();
    });

    group('Grid Management', () {
      test('should initialize with empty grid', () {
        expect(spatialGrid.featureCount, equals(0));
        expect(spatialGrid.getAllFeatures(), isEmpty);
        expect(spatialGrid.presentFeatureTypes, isEmpty);
      });

      test('should add features to grid cells', () {
        spatialGrid.addFeatures(testFeatures);
        
        expect(spatialGrid.featureCount, equals(testFeatures.length));
        expect(spatialGrid.getAllFeatures().length, equals(testFeatures.length));
        expect(spatialGrid.presentFeatureTypes, isNotEmpty);
      });

      test('should clear all features', () {
        spatialGrid.addFeatures(testFeatures);
        spatialGrid.clear();
        
        expect(spatialGrid.featureCount, equals(0));
        expect(spatialGrid.getAllFeatures(), isEmpty);
      });
    });

    group('Spatial Queries', () {
      setUp(() {
        spatialGrid.addFeatures(testFeatures);
      });

      test('should query features within bounds efficiently', () {
        final queryBounds = S57Bounds(
          north: 47.65,
          south: 47.62,
          east: -122.32,
          west: -122.38,
        );

        final stopwatch = Stopwatch()..start();
        final results = spatialGrid.queryBounds(queryBounds);
        stopwatch.stop();

        expect(results, isNotEmpty);
        expect(stopwatch.elapsedMilliseconds, lessThan(10)); // Should be very fast
        
        // Verify all results are within bounds
        for (final feature in results) {
          bool withinBounds = false;
          for (final coord in feature.coordinates) {
            if (coord.latitude >= queryBounds.south &&
                coord.latitude <= queryBounds.north &&
                coord.longitude >= queryBounds.west &&
                coord.longitude <= queryBounds.east) {
              withinBounds = true;
              break;
            }
          }
          expect(withinBounds, isTrue);
        }
      });

      test('should query features near point efficiently', () {
        const testLat = 47.63;
        const testLon = -122.35;
        const radius = 0.02; // 2km radius

        final stopwatch = Stopwatch()..start();
        final results = spatialGrid.queryPoint(
          testLat,
          testLon,
          radiusDegrees: radius,
        );
        stopwatch.stop();

        expect(results, isNotEmpty);
        expect(stopwatch.elapsedMilliseconds, lessThan(5));
      });

      test('should query by feature type', () {
        final buoys = spatialGrid.queryByType(S57FeatureType.buoy);
        final lighthouses = spatialGrid.queryByType(S57FeatureType.lighthouse);
        
        expect(buoys, isNotEmpty);
        expect(lighthouses, isNotEmpty);
        
        // Verify all features are of correct type
        for (final buoy in buoys) {
          expect(buoy.featureType, equals(S57FeatureType.buoy));
        }
      });

      test('should query navigation aids', () {
        final navAids = spatialGrid.queryNavigationAids();
        expect(navAids, isNotEmpty);
        
        // Should include buoys, beacons, lighthouses
        final types = navAids.map((f) => f.featureType).toSet();
        expect(types, contains(S57FeatureType.buoy));
        expect(types, contains(S57FeatureType.lighthouse));
      });

      test('should query depth features', () {
        final depthFeatures = spatialGrid.queryDepthFeatures();
        expect(depthFeatures, isNotEmpty);
        
        final types = depthFeatures.map((f) => f.featureType).toSet();
        expect(types, contains(S57FeatureType.depthContour));
        expect(types, contains(S57FeatureType.sounding));
      });
    });

    group('Performance Analysis', () {
      test('should provide grid statistics', () {
        spatialGrid.addFeatures(testFeatures);
        
        final stats = spatialGrid.getStats();
        
        expect(stats.totalFeatures, equals(testFeatures.length));
        expect(stats.cellSizeDegrees, equals(0.01));
        expect(stats.totalCells, greaterThan(0));
        expect(stats.cellUtilization, greaterThan(0.0));
        expect(stats.cellUtilization, lessThanOrEqualTo(1.0));
        expect(stats.averageFeaturesPerCell, greaterThan(0.0));
      });

      test('should handle large datasets efficiently', () {
        final largeFeatureSet = _createLargeTestFeatureSet(5000);
        
        final stopwatch = Stopwatch()..start();
        spatialGrid.addFeatures(largeFeatureSet);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(spatialGrid.featureCount, equals(5000));
        
        // Test query performance on large dataset
        final queryBounds = S57Bounds(
          north: 47.65,
          south: 47.62,
          east: -122.32,
          west: -122.38,
        );
        
        stopwatch.reset();
        stopwatch.start();
        final results = spatialGrid.queryBounds(queryBounds);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(20));
        expect(results, isNotEmpty);
      });
    });

    group('Edge Cases', () {
      test('should handle empty queries gracefully', () {
        final emptyBounds = S57Bounds(
          north: 45.0,
          south: 44.0,
          east: -120.0,
          west: -121.0,
        );
        
        final results = spatialGrid.queryBounds(emptyBounds);
        expect(results, isEmpty);
      });

      test('should handle features at grid boundaries', () {
        // Add feature exactly at grid boundary
        final boundaryFeature = S57Feature(
          recordId: 9999,
          featureType: S57FeatureType.buoy,
          geometryType: S57GeometryType.point,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.40), // Exact corner
          ],
          attributes: const {'name': 'Boundary Buoy'},
        );
        
        spatialGrid.addFeature(boundaryFeature);
        
        final results = spatialGrid.queryPoint(47.60, -122.40, radiusDegrees: 0.001);
        expect(results, contains(boundaryFeature));
      });
    });
  });
}

/// Create test features for Elliott Bay area
List<S57Feature> _createTestFeatures() {
  return [
    // Navigation aids
    S57Feature(
      recordId: 1001,
      featureType: S57FeatureType.buoy,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6235, longitude: -122.3517)],
      attributes: const {'name': 'Elliott Bay Entrance Buoy'},
    ),
    S57Feature(
      recordId: 1002,
      featureType: S57FeatureType.lighthouse,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6062, longitude: -122.3321)],
      attributes: const {'name': 'Alki Point Light'},
    ),
    S57Feature(
      recordId: 1003,
      featureType: S57FeatureType.beacon,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6167, longitude: -122.3656)],
      attributes: const {'name': 'Harbor Beacon'},
    ),
    
    // Depth features
    S57Feature(
      recordId: 2001,
      featureType: S57FeatureType.depthContour,
      geometryType: S57GeometryType.line,
      coordinates: [
        S57Coordinate(latitude: 47.620, longitude: -122.360),
        S57Coordinate(latitude: 47.625, longitude: -122.355),
        S57Coordinate(latitude: 47.630, longitude: -122.350),
      ],
      attributes: const {'depth': 10.0},
    ),
    S57Feature(
      recordId: 2002,
      featureType: S57FeatureType.sounding,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6289, longitude: -122.3478)],
      attributes: const {'depth': 15.2},
    ),
    
    // Coastline features
    S57Feature(
      recordId: 3001,
      featureType: S57FeatureType.coastline,
      geometryType: S57GeometryType.line,
      coordinates: [
        S57Coordinate(latitude: 47.610, longitude: -122.340),
        S57Coordinate(latitude: 47.615, longitude: -122.345),
        S57Coordinate(latitude: 47.620, longitude: -122.350),
        S57Coordinate(latitude: 47.625, longitude: -122.355),
      ],
      attributes: const {'type': 'natural'},
    ),
  ];
}

/// Create large test feature set for performance testing
List<S57Feature> _createLargeTestFeatureSet(int count) {
  final features = <S57Feature>[];
  final random = List.generate(count, (i) => i);
  
  for (int i = 0; i < count; i++) {
    final lat = 47.60 + (random[i] % 1000) / 10000.0; // 47.60 to 47.70
    final lon = -122.40 + (random[i] % 1000) / 10000.0; // -122.40 to -122.30
    
    features.add(S57Feature(
      recordId: 10000 + i,
      featureType: S57FeatureType.values[i % S57FeatureType.values.length],
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: lat, longitude: lon)],
      attributes: {'id': i, 'test_feature': true},
    ));
  }
  
  return features;
}