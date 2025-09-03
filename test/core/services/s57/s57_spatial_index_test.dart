import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57SpatialIndex', () {
    late S57SpatialIndex spatialIndex;
    late List<S57Feature> testFeatures;

    setUp(() {
      spatialIndex = S57SpatialIndex();
      testFeatures = _createTestFeatures();
    });

    group('Feature Management', () {
      test('should add features to index', () {
        spatialIndex.addFeatures(testFeatures);
        
        expect(spatialIndex.featureCount, equals(testFeatures.length));
        expect(spatialIndex.getAllFeatures(), hasLength(testFeatures.length));
      });

      test('should clear all features', () {
        spatialIndex.addFeatures(testFeatures);
        expect(spatialIndex.featureCount, greaterThan(0));
        
        spatialIndex.clear();
        
        expect(spatialIndex.featureCount, equals(0));
        expect(spatialIndex.getAllFeatures(), isEmpty);
      });

      test('should track feature types', () {
        spatialIndex.addFeatures(testFeatures);
        
        final types = spatialIndex.presentFeatureTypes;
        expect(types, contains(S57FeatureType.buoy));
        expect(types, contains(S57FeatureType.depthContour));
        expect(types, contains(S57FeatureType.lighthouse));
      });
    });

    group('Spatial Queries', () {
      setUp(() {
        spatialIndex.addFeatures(testFeatures);
      });

      test('should query features within bounds', () {
        final bounds = S57Bounds(
          north: 47.70,
          south: 47.60,
          east: -122.30,
          west: -122.40,
        );
        
        final results = spatialIndex.queryBounds(bounds);
        
        expect(results, isNotEmpty);
        
        // All results should be within bounds
        for (final feature in results) {
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

      test('should query features near a point', () {
        const testLat = 47.65;
        const testLon = -122.35;
        const radius = 0.05; // degrees
        
        final results = spatialIndex.queryPoint(testLat, testLon, radiusDegrees: radius);
        
        expect(results, isNotEmpty);
        
        // All results should be within radius
        for (final feature in results) {
          bool withinRadius = false;
          for (final coord in feature.coordinates) {
            final dLat = coord.latitude - testLat;
            final dLon = coord.longitude - testLon;
            final distance = (dLat * dLat + dLon * dLon);
            if (distance <= radius * radius) {
              withinRadius = true;
              break;
            }
          }
          expect(withinRadius, isTrue);
        }
      });

      test('should query features by type', () {
        final buoys = spatialIndex.queryByType(S57FeatureType.buoy);
        final contours = spatialIndex.queryByType(S57FeatureType.depthContour);
        
        expect(buoys, isNotEmpty);
        expect(contours, isNotEmpty);
        
        // Verify all results are of correct type
        for (final buoy in buoys) {
          expect(buoy.featureType, equals(S57FeatureType.buoy));
        }
        
        for (final contour in contours) {
          expect(contour.featureType, equals(S57FeatureType.depthContour));
        }
      });

      test('should query navigation aids', () {
        final navAids = spatialIndex.queryNavigationAids();
        
        expect(navAids, isNotEmpty);
        
        // All results should be navigation aids
        for (final feature in navAids) {
          expect([
            S57FeatureType.buoy,
            S57FeatureType.beacon,
            S57FeatureType.lighthouse,
            S57FeatureType.daymark,
          ], contains(feature.featureType));
        }
      });

      test('should query depth features', () {
        final depthFeatures = spatialIndex.queryDepthFeatures();
        
        expect(depthFeatures, isNotEmpty);
        
        // All results should be depth-related
        for (final feature in depthFeatures) {
          expect([
            S57FeatureType.depthContour,
            S57FeatureType.depthArea,
          ], contains(feature.featureType));
        }
      });
    });

    group('Bounds Calculation', () {
      test('should calculate bounds from features', () {
        spatialIndex.addFeatures(testFeatures);
        
        final bounds = spatialIndex.calculateBounds();
        
        expect(bounds, isNotNull);
        expect(bounds!.isValid, isTrue);
        
        // Bounds should encompass all features
        for (final feature in testFeatures) {
          for (final coord in feature.coordinates) {
            expect(coord.latitude, greaterThanOrEqualTo(bounds.south));
            expect(coord.latitude, lessThanOrEqualTo(bounds.north));
            expect(coord.longitude, greaterThanOrEqualTo(bounds.west));
            expect(coord.longitude, lessThanOrEqualTo(bounds.east));
          }
        }
      });

      test('should return null bounds for empty index', () {
        final bounds = spatialIndex.calculateBounds();
        expect(bounds, isNull);
      });
    });

    group('Performance', () {
      test('should handle large number of features efficiently', () {
        final largeFeatureSet = _createLargeTestFeatureSet(1000);
        
        final stopwatch = Stopwatch()..start();
        spatialIndex.addFeatures(largeFeatureSet);
        stopwatch.stop();
        
        // Indexing should be fast
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
        
        // Query should be efficient
        stopwatch.reset();
        stopwatch.start();
        
        final results = spatialIndex.queryPoint(47.65, -122.35, radiusDegrees: 0.1);
        
        stopwatch.stop();
        
        // Query should complete in reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(50));
        expect(results, isNotEmpty);
      });
    });
  });
}

/// Create test features for Elliott Bay area
List<S57Feature> _createTestFeatures() {
  return [
    // Buoy near Elliott Bay entrance
    S57Feature(
      recordId: 1,
      featureType: S57FeatureType.buoy,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.64, longitude: -122.34)],
      attributes: {'type': 'lateral', 'color': 'red'},
      label: 'Red Buoy 2',
    ),
    
    // Depth contour
    S57Feature(
      recordId: 2,
      featureType: S57FeatureType.depthContour,
      geometryType: S57GeometryType.line,
      coordinates: [
        const S57Coordinate(latitude: 47.65, longitude: -122.35),
        const S57Coordinate(latitude: 47.66, longitude: -122.36),
        const S57Coordinate(latitude: 47.67, longitude: -122.37),
      ],
      attributes: {'depth': 10.0},
      label: '10m Contour',
    ),
    
    // West Point Lighthouse
    S57Feature(
      recordId: 3,
      featureType: S57FeatureType.lighthouse,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.68, longitude: -122.32)],
      attributes: {'height': 25.0, 'range': 15.0},
      label: 'West Point Light',
    ),
    
    // Beacon
    S57Feature(
      recordId: 4,
      featureType: S57FeatureType.beacon,
      geometryType: S57GeometryType.point,
      coordinates: [const S57Coordinate(latitude: 47.63, longitude: -122.33)],
      attributes: {'type': 'starboard'},
      label: 'Green Beacon',
    ),
    
    // Shoreline
    S57Feature(
      recordId: 5,
      featureType: S57FeatureType.shoreline,
      geometryType: S57GeometryType.line,
      coordinates: [
        const S57Coordinate(latitude: 47.61, longitude: -122.33),
        const S57Coordinate(latitude: 47.62, longitude: -122.32),
        const S57Coordinate(latitude: 47.63, longitude: -122.31),
      ],
      attributes: {'category': 'natural'},
      label: 'Shoreline',
    ),
  ];
}

/// Create a large set of test features for performance testing
List<S57Feature> _createLargeTestFeatureSet(int count) {
  final features = <S57Feature>[];
  
  // Generate features in Elliott Bay area
  const baseLat = 47.65;
  const baseLon = -122.35;
  const range = 0.1; // degrees
  
  for (int i = 0; i < count; i++) {
    final lat = baseLat + (i % 100) * range / 100;
    final lon = baseLon + (i ~/ 100) * range / 100;
    
    features.add(S57Feature(
      recordId: i,
      featureType: S57FeatureType.values[i % S57FeatureType.values.length],
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: lat, longitude: lon)],
      attributes: {'test_id': i},
      label: 'Test Feature $i',
    ));
  }
  
  return features;
}