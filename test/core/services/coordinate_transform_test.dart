import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:navtool/core/services/coordinate_transform.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  group('CoordinateTransform Tests', () {
    const testCenter = LatLng(37.7749, -122.4194); // San Francisco
    const testScreenSize = Size(800, 600);
    const testZoom = 12.0;

    late CoordinateTransform transform;

    setUp(() {
      transform = CoordinateTransform(
        zoom: testZoom,
        center: testCenter,
        screenSize: testScreenSize,
      );
    });

    group('Basic Properties', () {
      test('should store initialization parameters correctly', () {
        expect(transform.zoom, equals(testZoom));
        expect(transform.center, equals(testCenter));
        expect(transform.screenSize, equals(testScreenSize));
        expect(transform.pixelsPerDegree, greaterThan(0));
      });

      test('should calculate chart scale from zoom', () {
        final scale = transform.chartScale;
        expect(scale, equals(ChartScale.coastal)); // Zoom 12 should be coastal
      });

      test('should calculate scale factor correctly', () {
        final scaleFactor = transform.scaleFactor;
        expect(scaleFactor, equals(math.pow(2, testZoom)));
      });
    });

    group('Coordinate Transformations', () {
      test('should convert center point to screen center', () {
        final screenPos = transform.latLngToScreen(testCenter);
        
        // Center point should map to center of screen
        expect(screenPos.dx, closeTo(testScreenSize.width / 2, 1.0));
        expect(screenPos.dy, closeTo(testScreenSize.height / 2, 1.0));
      });

      test('should convert screen center back to geographic center', () {
        const screenCenter = Offset(400, 300); // Center of 800x600 screen
        final latLng = transform.screenToLatLng(screenCenter);
        
        expect(latLng.latitude, closeTo(testCenter.latitude, 0.001));
        expect(latLng.longitude, closeTo(testCenter.longitude, 0.001));
      });

      test('should handle round-trip conversions accurately', () {
        const testPoint = LatLng(37.8, -122.5);
        final screenPos = transform.latLngToScreen(testPoint);
        final backToLatLng = transform.screenToLatLng(screenPos);
        
        expect(backToLatLng.latitude, closeTo(testPoint.latitude, 0.0001));
        expect(backToLatLng.longitude, closeTo(testPoint.longitude, 0.0001));
      });

      test('should calculate visible bounds correctly', () {
        final bounds = transform.visibleBounds;
        
        // Bounds should contain the center point
        expect(bounds.contains(testCenter), isTrue);
        
        // North should be greater than south
        expect(bounds.north, greaterThan(bounds.south));
        
        // East should be greater than west (in normal cases)
        expect(bounds.east, greaterThan(bounds.west));
      });
    });

    group('Distance and Bearing Calculations', () {
      test('should calculate distance between known points correctly', () {
        const point1 = LatLng(37.7749, -122.4194); // San Francisco
        const point2 = LatLng(37.7849, -122.4094); // About 1.5km away
        
        final distance = CoordinateTransform.distanceInMeters(point1, point2);
        
        // Should be approximately 1.5km (allowing for some variation)
        expect(distance, greaterThan(1000));
        expect(distance, lessThan(2000));
      });

      test('should calculate bearing correctly', () {
        const point1 = LatLng(37.7749, -122.4194);
        const point2 = LatLng(37.7849, -122.4094); // Northeast
        
        final bearing = CoordinateTransform.bearing(point1, point2);
        
        // Should be roughly northeast (between 0 and 90 degrees)
        expect(bearing, greaterThan(0));
        expect(bearing, lessThan(90));
      });

      test('should calculate zero distance for identical points', () {
        const point = LatLng(37.7749, -122.4194);
        
        final distance = CoordinateTransform.distanceInMeters(point, point);
        
        expect(distance, equals(0.0));
      });
    });

    group('Scaling and Sizing', () {
      test('should calculate appropriate line width for scale', () {
        const baseWidth = 2.0;
        final lineWidth = transform.getLineWidthForScale(baseWidth);
        
        expect(lineWidth, greaterThanOrEqualTo(1.0)); // Minimum width
        expect(lineWidth, isA<double>());
      });

      test('should calculate appropriate symbol size for scale', () {
        const baseSize = 16.0;
        final symbolSize = transform.getSymbolSizeForScale(baseSize);
        
        expect(symbolSize, greaterThanOrEqualTo(8.0)); // Minimum size
        expect(symbolSize, isA<double>());
      });
    });

    group('Feature Visibility', () {
      test('should correctly identify visible point features', () {
        final visibleFeature = PointFeature(
          id: 'visible',
          type: MaritimeFeatureType.lighthouse,
          position: testCenter, // At center, should be visible
        );
        
        final invisibleFeature = PointFeature(
          id: 'invisible',
          type: MaritimeFeatureType.lighthouse,
          position: const LatLng(0, 0), // Far away, should not be visible
        );
        
        expect(transform.isFeatureVisible(visibleFeature), isTrue);
        expect(transform.isFeatureVisible(invisibleFeature), isFalse);
      });

      test('should correctly identify visible line features', () {
        final visibleLine = LineFeature(
          id: 'visible_line',
          type: MaritimeFeatureType.shoreline,
          position: testCenter,
          coordinates: [
            testCenter,
            LatLng(testCenter.latitude + 0.01, testCenter.longitude + 0.01),
          ],
        );
        
        final invisibleLine = LineFeature(
          id: 'invisible_line',
          type: MaritimeFeatureType.shoreline,
          position: const LatLng(0, 0),
          coordinates: [
            const LatLng(0, 0),
            const LatLng(0.01, 0.01),
          ],
        );
        
        expect(transform.isFeatureVisible(visibleLine), isTrue);
        expect(transform.isFeatureVisible(invisibleLine), isFalse);
      });
    });

    group('Copy and Modification', () {
      test('should create copy with updated zoom', () {
        final newTransform = transform.copyWith(zoom: 15.0);
        
        expect(newTransform.zoom, equals(15.0));
        expect(newTransform.center, equals(transform.center));
        expect(newTransform.screenSize, equals(transform.screenSize));
      });

      test('should create copy with updated center', () {
        const newCenter = LatLng(40.7128, -74.0060); // New York
        final newTransform = transform.copyWith(center: newCenter);
        
        expect(newTransform.center, equals(newCenter));
        expect(newTransform.zoom, equals(transform.zoom));
        expect(newTransform.screenSize, equals(transform.screenSize));
      });

      test('should create copy with updated screen size', () {
        const newSize = Size(1200, 800);
        final newTransform = transform.copyWith(screenSize: newSize);
        
        expect(newTransform.screenSize, equals(newSize));
        expect(newTransform.center, equals(transform.center));
        expect(newTransform.zoom, equals(transform.zoom));
      });
    });
  });

  group('CoordinateUtils Tests', () {
    group('Validation', () {
      test('should validate latitude ranges correctly', () {
        expect(CoordinateUtils.isValidLatitude(90.0), isTrue);
        expect(CoordinateUtils.isValidLatitude(-90.0), isTrue);
        expect(CoordinateUtils.isValidLatitude(0.0), isTrue);
        expect(CoordinateUtils.isValidLatitude(45.0), isTrue);
        
        expect(CoordinateUtils.isValidLatitude(90.1), isFalse);
        expect(CoordinateUtils.isValidLatitude(-90.1), isFalse);
        expect(CoordinateUtils.isValidLatitude(180.0), isFalse);
      });

      test('should validate longitude ranges correctly', () {
        expect(CoordinateUtils.isValidLongitude(180.0), isTrue);
        expect(CoordinateUtils.isValidLongitude(-180.0), isTrue);
        expect(CoordinateUtils.isValidLongitude(0.0), isTrue);
        expect(CoordinateUtils.isValidLongitude(90.0), isTrue);
        
        expect(CoordinateUtils.isValidLongitude(180.1), isFalse);
        expect(CoordinateUtils.isValidLongitude(-180.1), isFalse);
        expect(CoordinateUtils.isValidLongitude(360.0), isFalse);
      });
    });

    group('Normalization', () {
      test('should normalize longitude to valid range', () {
        expect(CoordinateUtils.normalizeLongitude(0.0), equals(0.0));
        expect(CoordinateUtils.normalizeLongitude(180.0), equals(180.0));
        expect(CoordinateUtils.normalizeLongitude(-180.0), equals(-180.0));
        
        expect(CoordinateUtils.normalizeLongitude(270.0), equals(-90.0));
        expect(CoordinateUtils.normalizeLongitude(-270.0), equals(90.0));
        expect(CoordinateUtils.normalizeLongitude(360.0), equals(0.0));
        expect(CoordinateUtils.normalizeLongitude(540.0), equals(180.0));
      });
    });

    group('Conversion', () {
      test('should convert degrees to radians correctly', () {
        expect(CoordinateUtils.degreesToRadians(0.0), equals(0.0));
        expect(CoordinateUtils.degreesToRadians(90.0), closeTo(math.pi / 2, 0.0001));
        expect(CoordinateUtils.degreesToRadians(180.0), closeTo(math.pi, 0.0001));
        expect(CoordinateUtils.degreesToRadians(360.0), closeTo(2 * math.pi, 0.0001));
      });

      test('should convert radians to degrees correctly', () {
        expect(CoordinateUtils.radiansToDegrees(0.0), equals(0.0));
        expect(CoordinateUtils.radiansToDegrees(math.pi / 2), closeTo(90.0, 0.0001));
        expect(CoordinateUtils.radiansToDegrees(math.pi), closeTo(180.0, 0.0001));
        expect(CoordinateUtils.radiansToDegrees(2 * math.pi), closeTo(360.0, 0.0001));
      });
    });

    group('Formatting', () {
      test('should format latitude correctly', () {
        expect(CoordinateUtils.formatLatitude(37.7749), equals('37°46.494\'N'));
        expect(CoordinateUtils.formatLatitude(-37.7749), equals('37°46.494\'S'));
        expect(CoordinateUtils.formatLatitude(0.0), equals('00°0.000\'N'));
        expect(CoordinateUtils.formatLatitude(90.0), equals('90°0.000\'N'));
        expect(CoordinateUtils.formatLatitude(-90.0), equals('90°0.000\'S'));
      });

      test('should format longitude correctly', () {
        expect(CoordinateUtils.formatLongitude(-122.4194), equals('122°25.164\'W'));
        expect(CoordinateUtils.formatLongitude(122.4194), equals('122°25.164\'E'));
        expect(CoordinateUtils.formatLongitude(0.0), equals('000°0.000\'E'));
        expect(CoordinateUtils.formatLongitude(180.0), equals('180°0.000\'E'));
        expect(CoordinateUtils.formatLongitude(-180.0), equals('180°0.000\'W'));
      });
    });
  });
}
