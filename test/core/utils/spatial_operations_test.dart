import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/spatial_operations.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'dart:math' as math;

void main() {
  group('SpatialOperations Tests', () {
    group('Point-in-Polygon Tests', () {
      test('should correctly identify point inside simple rectangle polygon', () {
        // Arrange
        final polygon = [
          const LatLng(38.0, -123.0), // NW
          const LatLng(38.0, -122.0), // NE
          const LatLng(37.0, -122.0), // SE
          const LatLng(37.0, -123.0), // SW
        ];
        const pointInside = LatLng(37.5, -122.5);
        const pointOutside = LatLng(39.0, -122.5);

        // Act & Assert
        expect(SpatialOperations.isPointInPolygon(pointInside, polygon), isTrue);
        expect(SpatialOperations.isPointInPolygon(pointOutside, polygon), isFalse);
      });

      test('should correctly identify point on polygon boundary', () {
        // Arrange
        final polygon = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        const pointOnBoundary = LatLng(38.0, -122.5); // On north edge

        // Act & Assert
        expect(SpatialOperations.isPointInPolygon(pointOnBoundary, polygon), isTrue);
      });

      test('should handle complex polygons with concave shapes', () {
        // Arrange - L-shaped polygon
        final polygon = [
          const LatLng(40.0, -124.0), // Top-left
          const LatLng(40.0, -122.0), // Top-right
          const LatLng(39.0, -122.0), // Middle-right
          const LatLng(39.0, -123.0), // Middle-left
          const LatLng(38.0, -123.0), // Bottom-left
          const LatLng(38.0, -124.0), // Bottom-left corner
        ];
        
        const pointInside = LatLng(39.5, -123.5); // In top part
        const pointInConcavity = LatLng(38.5, -122.5); // In concave area
        
        // Act & Assert
        expect(SpatialOperations.isPointInPolygon(pointInside, polygon), isTrue);
        expect(SpatialOperations.isPointInPolygon(pointInConcavity, polygon), isFalse);
      });

      test('should handle edge case with very small polygon', () {
        // Arrange - tiny triangle
        final polygon = [
          const LatLng(37.001, -122.001),
          const LatLng(37.001, -122.000),
          const LatLng(37.000, -122.0005),
        ];
        const pointInside = LatLng(37.0005, -122.0007);
        const pointOutside = LatLng(37.002, -122.002);

        // Act & Assert
        expect(SpatialOperations.isPointInPolygon(pointInside, polygon), isTrue);
        expect(SpatialOperations.isPointInPolygon(pointOutside, polygon), isFalse);
      });
    });

    group('Polygon Intersection Tests', () {
      test('should detect intersection between overlapping rectangles', () {
        // Arrange
        final polygon1 = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        
        final polygon2 = [
          const LatLng(37.5, -122.5),
          const LatLng(37.5, -121.5),
          const LatLng(36.5, -121.5),
          const LatLng(36.5, -122.5),
        ];

        // Act
        final intersects = SpatialOperations.doPolygonsIntersect(polygon1, polygon2);

        // Assert
        expect(intersects, isTrue);
      });

      test('should detect no intersection between non-overlapping rectangles', () {
        // Arrange
        final polygon1 = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        
        final polygon2 = [
          const LatLng(36.0, -121.0),
          const LatLng(36.0, -120.0),
          const LatLng(35.0, -120.0),
          const LatLng(35.0, -121.0),
        ];

        // Act
        final intersects = SpatialOperations.doPolygonsIntersect(polygon1, polygon2);

        // Assert
        expect(intersects, isFalse);
      });

      test('should detect intersection when one polygon is inside another', () {
        // Arrange - larger outer polygon
        final outerPolygon = [
          const LatLng(40.0, -125.0),
          const LatLng(40.0, -120.0),
          const LatLng(35.0, -120.0),
          const LatLng(35.0, -125.0),
        ];
        
        // Smaller inner polygon
        final innerPolygon = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];

        // Act
        final intersects = SpatialOperations.doPolygonsIntersect(outerPolygon, innerPolygon);

        // Assert
        expect(intersects, isTrue);
      });

      test('should detect intersection for polygons that share only an edge', () {
        // Arrange - adjacent rectangles
        final polygon1 = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        
        final polygon2 = [
          const LatLng(38.0, -122.0), // Shares edge with polygon1
          const LatLng(38.0, -121.0),
          const LatLng(37.0, -121.0),
          const LatLng(37.0, -122.0),
        ];

        // Act
        final intersects = SpatialOperations.doPolygonsIntersect(polygon1, polygon2);

        // Assert
        expect(intersects, isTrue);
      });
    });

    group('Coverage Percentage Calculation Tests', () {
      test('should calculate 100% coverage for identical polygons', () {
        // Arrange
        final polygon1 = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        
        final polygon2 = List<LatLng>.from(polygon1); // Identical

        // Act
        final coverage = SpatialOperations.calculateCoveragePercentage(polygon1, polygon2);

        // Assert
        expect(coverage, closeTo(1.0, 0.01)); // 100% coverage
      });

      test('should calculate partial coverage for overlapping polygons', () {
        // Arrange - chart polygon (2x2 degrees)
        final chartPolygon = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -121.0),
          const LatLng(36.0, -121.0),
          const LatLng(36.0, -123.0),
        ];
        
        // State polygon that covers half the chart (1x2 degrees)
        final statePolygon = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(36.0, -122.0),
          const LatLng(36.0, -123.0),
        ];

        // Act
        final coverage = SpatialOperations.calculateCoveragePercentage(statePolygon, chartPolygon);

        // Assert
        expect(coverage, closeTo(0.5, 0.1)); // Approximately 50% coverage
      });

      test('should calculate 0% coverage for non-overlapping polygons', () {
        // Arrange
        final polygon1 = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];
        
        final polygon2 = [
          const LatLng(36.0, -121.0),
          const LatLng(36.0, -120.0),
          const LatLng(35.0, -120.0),
          const LatLng(35.0, -121.0),
        ];

        // Act
        final coverage = SpatialOperations.calculateCoveragePercentage(polygon1, polygon2);

        // Assert
        expect(coverage, equals(0.0));
      });

      test('should handle very small coverage percentages', () {
        // Arrange - large chart, tiny state overlap
        final chartPolygon = [
          const LatLng(40.0, -125.0),
          const LatLng(40.0, -120.0),
          const LatLng(35.0, -120.0),
          const LatLng(35.0, -125.0),
        ];
        
        // Tiny overlap at corner
        final statePolygon = [
          const LatLng(35.1, -124.9),
          const LatLng(35.1, -124.8),
          const LatLng(35.0, -124.8),
          const LatLng(35.0, -124.9),
        ];

        // Act
        final coverage = SpatialOperations.calculateCoveragePercentage(statePolygon, chartPolygon);

        // Assert
        expect(coverage, lessThan(0.01)); // Less than 1%
        expect(coverage, greaterThanOrEqualTo(0.0));
      });
    });

    group('Bounds Conversion Tests', () {
      test('should convert GeographicBounds to polygon correctly', () {
        // Arrange
        final bounds = GeographicBounds(
          north: 38.0,
          south: 37.0,
          east: -122.0,
          west: -123.0,
        );

        // Act
        final polygon = SpatialOperations.boundsToPolygon(bounds);

        // Assert
        expect(polygon, hasLength(4));
        expect(polygon[0], equals(const LatLng(38.0, -123.0))); // NW
        expect(polygon[1], equals(const LatLng(38.0, -122.0))); // NE
        expect(polygon[2], equals(const LatLng(37.0, -122.0))); // SE
        expect(polygon[3], equals(const LatLng(37.0, -123.0))); // SW
      });

      test('should convert polygon to bounds correctly', () {
        // Arrange
        final polygon = [
          const LatLng(38.0, -123.0),
          const LatLng(38.0, -122.0),
          const LatLng(37.0, -122.0),
          const LatLng(37.0, -123.0),
        ];

        // Act
        final bounds = SpatialOperations.getPolygonBounds(polygon);

        // Assert
        expect(bounds.north, equals(38.0));
        expect(bounds.south, equals(37.0));
        expect(bounds.east, equals(-122.0));
        expect(bounds.west, equals(-123.0));
      });

      test('should handle irregular polygon bounds correctly', () {
        // Arrange - triangle
        final polygon = [
          const LatLng(38.0, -123.0),
          const LatLng(37.5, -122.0),
          const LatLng(37.0, -122.5),
        ];

        // Act
        final bounds = SpatialOperations.getPolygonBounds(polygon);

        // Assert
        expect(bounds.north, equals(38.0));
        expect(bounds.south, equals(37.0));
        expect(bounds.east, equals(-122.0));
        expect(bounds.west, equals(-123.0));
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle empty polygon gracefully', () {
        // Arrange
        final emptyPolygon = <LatLng>[];
        const testPoint = LatLng(37.5, -122.5);

        // Act & Assert
        expect(
          () => SpatialOperations.isPointInPolygon(testPoint, emptyPolygon),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle single point polygon', () {
        // Arrange
        final singlePointPolygon = [const LatLng(37.5, -122.5)];
        const testPoint = LatLng(37.5, -122.5);

        // Act & Assert
        expect(
          () => SpatialOperations.isPointInPolygon(testPoint, singlePointPolygon),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle two point polygon', () {
        // Arrange
        final twoPointPolygon = [
          const LatLng(37.0, -122.0),
          const LatLng(38.0, -123.0),
        ];
        const testPoint = LatLng(37.5, -122.5);

        // Act & Assert
        expect(
          () => SpatialOperations.isPointInPolygon(testPoint, twoPointPolygon),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle degenerate polygon (all points collinear)', () {
        // Arrange - all points on same line
        final collinearPolygon = [
          const LatLng(37.0, -122.0),
          const LatLng(37.5, -122.5),
          const LatLng(38.0, -123.0),
        ];
        const testPoint = LatLng(37.25, -122.25);

        // Act
        final result = SpatialOperations.isPointInPolygon(testPoint, collinearPolygon);

        // Assert - collinear polygon has no area, so point should be outside
        expect(result, isFalse);
      });

      test('should handle very large coordinates', () {
        // Arrange - coordinates at extremes of valid lat/lng
        final extremePolygon = [
          const LatLng(89.0, -179.0),
          const LatLng(89.0, 179.0),
          const LatLng(88.0, 179.0),
          const LatLng(88.0, -179.0),
        ];
        const testPoint = LatLng(88.5, 0.0);

        // Act
        final result = SpatialOperations.isPointInPolygon(testPoint, extremePolygon);

        // Assert
        expect(result, isTrue);
      });
    });

    group('Performance Tests', () {
      test('should handle large polygons efficiently', () {
        // Arrange - polygon with many vertices (simulating complex coastline)
        final largePolygon = <LatLng>[];
        const numVertices = 1000;
        const centerLat = 37.5;
        const centerLng = -122.5;
        const radius = 0.5;
        
        for (int i = 0; i < numVertices; i++) {
          final angle = (i / numVertices) * 2 * math.pi;
          final lat = centerLat + radius * math.cos(angle);
          final lng = centerLng + radius * math.sin(angle);
          largePolygon.add(LatLng(lat, lng));
        }
        
        const testPoint = LatLng(37.5, -122.5); // Center point

        // Act & measure time
        final stopwatch = Stopwatch()..start();
        final result = SpatialOperations.isPointInPolygon(testPoint, largePolygon);
        stopwatch.stop();

        // Assert
        expect(result, isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });
    });
  });
}