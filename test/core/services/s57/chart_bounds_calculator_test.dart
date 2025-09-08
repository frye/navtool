import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/chart_bounds_calculator.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'dart:math';

void main() {
  group('ChartBoundsCalculator', () {
    late List<MaritimeFeature> testFeatures;
    late List<S57Feature> testS57Features;

    setUp(() {
      testFeatures = _createTestMaritimeFeatures();
      testS57Features = _createTestS57Features();
    });

    group('Bounds Calculation', () {
      test('should calculate optimal bounds from maritime features', () {
        final bounds = ChartBoundsCalculator.calculateOptimalBounds(testFeatures);
        
        expect(bounds.north, greaterThan(bounds.south));
        expect(bounds.east, greaterThan(bounds.west));
        
        // Should contain all feature positions
        for (final feature in testFeatures) {
          expect(bounds.contains(feature.position), isTrue);
        }
      });

      test('should add padding to bounds', () {
        final boundsNoPadding = ChartBoundsCalculator.calculateOptimalBounds(
          testFeatures,
          paddingPercent: 0.0,
        );
        final boundsWithPadding = ChartBoundsCalculator.calculateOptimalBounds(
          testFeatures,
          paddingPercent: 0.1,
        );
        
        expect(boundsWithPadding.north, greaterThan(boundsNoPadding.north));
        expect(boundsWithPadding.south, lessThan(boundsNoPadding.south));
        expect(boundsWithPadding.east, greaterThan(boundsNoPadding.east));
        expect(boundsWithPadding.west, lessThan(boundsNoPadding.west));
      });

      test('should calculate S-57 bounds', () {
        final bounds = ChartBoundsCalculator.calculateS57Bounds(testS57Features);
        
        expect(bounds.north, greaterThan(bounds.south));
        expect(bounds.east, greaterThan(bounds.west));
        expect(bounds.isValid, isTrue);
      });

      test('should throw on empty feature list', () {
        expect(
          () => ChartBoundsCalculator.calculateOptimalBounds([]),
          throwsArgumentError,
        );
      });
    });

    group('Feature Density Calculation', () {
      test('should calculate feature density correctly', () {
        final bounds = LatLngBounds(
          north: 47.7,
          south: 47.6,
          east: -122.3,
          west: -122.4,
        );
        
        final density = ChartBoundsCalculator.calculateFeatureDensity(
          testFeatures,
          bounds,
        );
        
        expect(density, greaterThan(0.0));
        
        // Density should be features per square degree
        final area = (bounds.north - bounds.south) * (bounds.east - bounds.west);
        final expectedDensity = testFeatures.length / area;
        expect(density, closeTo(expectedDensity, 0.001));
      });

      test('should return zero density for zero area', () {
        final pointBounds = LatLngBounds(
          north: 47.6,
          south: 47.6,
          east: -122.3,
          west: -122.3,
        );
        
        final density = ChartBoundsCalculator.calculateFeatureDensity(
          testFeatures,
          pointBounds,
        );
        
        expect(density, equals(0.0));
      });
    });

    group('Scale Determination', () {
      test('should determine optimal scale based on area and density', () {
        final largeBounds = LatLngBounds(
          north: 48.0,
          south: 47.0,
          east: -122.0,
          west: -123.0,
        );
        
        final scale = ChartBoundsCalculator.determineOptimalScale(
          bounds: largeBounds,
          features: testFeatures,
          viewportSizeDegrees: 1.0,
        );
        
        // Large area with few features should be overview scale
        expect(scale, equals(ChartScale.overview));
      });

      test('should determine berthing scale for small dense areas', () {
        final smallBounds = LatLngBounds(
          north: 47.61,
          south: 47.60,
          east: -122.32,
          west: -122.33,
        );
        
        final denseFeatures = List.generate(2000, (i) => PointFeature(
          id: 'dense_$i',
          type: MaritimeFeatureType.buoy,
          position: LatLng(
            47.605 + (i % 100) * 0.0001,
            -122.325 + (i ~/ 100) * 0.0001,
          ),
        ));
        
        final scale = ChartBoundsCalculator.determineOptimalScale(
          bounds: smallBounds,
          features: denseFeatures,
          viewportSizeDegrees: 0.01,
        );
        
        expect(scale, equals(ChartScale.berthing));
      });
    });

    group('Bounds Operations', () {
      test('should calculate intersection of overlapping bounds', () {
        final bounds1 = LatLngBounds(
          north: 47.7,
          south: 47.6,
          east: -122.3,
          west: -122.4,
        );
        final bounds2 = LatLngBounds(
          north: 47.65,
          south: 47.55,
          east: -122.25,
          west: -122.35,
        );
        
        final intersection = ChartBoundsCalculator.calculateIntersection(
          bounds1,
          bounds2,
        );
        
        expect(intersection, isNotNull);
        expect(intersection!.north, equals(47.65));
        expect(intersection.south, equals(47.6));
        expect(intersection.east, equals(-122.3));
        expect(intersection.west, equals(-122.35));
      });

      test('should return null for non-overlapping bounds', () {
        final bounds1 = LatLngBounds(
          north: 47.7,
          south: 47.6,
          east: -122.3,
          west: -122.4,
        );
        final bounds2 = LatLngBounds(
          north: 47.5,
          south: 47.4,
          east: -122.2,
          west: -122.25,
        );
        
        final intersection = ChartBoundsCalculator.calculateIntersection(
          bounds1,
          bounds2,
        );
        
        expect(intersection, isNull);
      });

      test('should calculate union of multiple bounds', () {
        final boundsList = [
          LatLngBounds(north: 47.7, south: 47.6, east: -122.3, west: -122.4),
          LatLngBounds(north: 47.65, south: 47.55, east: -122.25, west: -122.35),
          LatLngBounds(north: 47.8, south: 47.75, east: -122.2, west: -122.3),
        ];
        
        final union = ChartBoundsCalculator.calculateUnion(boundsList);
        
        expect(union.north, equals(47.8));
        expect(union.south, equals(47.55));
        expect(union.east, equals(-122.2));
        expect(union.west, equals(-122.4));
      });
    });

    group('Distance and Coordinate Calculations', () {
      test('should convert degrees to meters accurately', () {
        const latitude = 47.6; // Seattle latitude
        const degrees = 0.01; // About 1km at this latitude
        
        final meters = ChartBoundsCalculator.degreesToMeters(degrees, latitude);
        
        // Should be approximately 1111 meters at equator, less at higher latitudes
        expect(meters, greaterThan(700));
        expect(meters, lessThan(1200));
      });

      test('should convert meters to degrees accurately', () {
        const latitude = 47.6;
        const meters = 1000.0; // 1km
        
        final degrees = ChartBoundsCalculator.metersToDegrees(meters, latitude);
        
        // Should be close to 0.01 degrees
        expect(degrees, greaterThan(0.008));
        expect(degrees, lessThan(0.015));
      });

      test('should calculate distance using Haversine formula', () {
        final point1 = LatLng(47.6062, -122.3321); // Alki Point
        final point2 = LatLng(47.6235, -122.3517); // Elliott Bay
        
        final distance = ChartBoundsCalculator.calculateDistance(point1, point2);
        
        // Distance should be approximately 2.4km (Elliott Bay area)
        expect(distance, greaterThan(2400));
        expect(distance, lessThan(2600));
      });

      test('should calculate bearing between points', () {
        final from = LatLng(47.6062, -122.3321); // Alki Point
        final to = LatLng(47.6235, -122.3517); // Elliott Bay (northwest)
        
        final bearing = ChartBoundsCalculator.calculateBearing(from, to);
        
        // Should be roughly northwest (around 315 degrees)
        expect(bearing, greaterThan(300));
        expect(bearing, lessThan(340));
      });
    });
  });

  group('ScaleCalculator', () {
    test('should calculate scale ratio from display parameters', () {
      final chartBounds = LatLngBounds(
        north: 47.7,
        south: 47.6,
        east: -122.3,
        west: -122.4,
      );
      
      final scaleRatio = ScaleCalculator.calculateScaleRatio(
        chartBounds: chartBounds,
        displayWidthPixels: 1920,
        displayHeightPixels: 1080,
        dpi: 96.0,
      );
      
      expect(scaleRatio, greaterThan(1000));
      expect(scaleRatio, lessThan(100000));
    });

    test('should convert scale ratio to natural scale', () {
      const scaleRatio = 25000.7;
      final naturalScale = ScaleCalculator.scaleRatioToNaturalScale(scaleRatio);
      
      expect(naturalScale, equals(25001));
    });

    test('should convert natural scale to ChartScale enum', () {
      expect(ScaleCalculator.naturalScaleToChartScale(5000), equals(ChartScale.berthing));
      expect(ScaleCalculator.naturalScaleToChartScale(30000), equals(ChartScale.harbour));
      expect(ScaleCalculator.naturalScaleToChartScale(75000), equals(ChartScale.approach));
      expect(ScaleCalculator.naturalScaleToChartScale(150000), equals(ChartScale.coastal));
      expect(ScaleCalculator.naturalScaleToChartScale(750000), equals(ChartScale.general));
      expect(ScaleCalculator.naturalScaleToChartScale(1500000), equals(ChartScale.overview));
    });

    test('should provide scale-appropriate feature visibility thresholds', () {
      final berththingThresholds = ScaleCalculator.getFeatureVisibilityThresholds(
        ChartScale.berthing,
      );
      final overviewThresholds = ScaleCalculator.getFeatureVisibilityThresholds(
        ChartScale.overview,
      );
      
      // Berthing should have more feature types visible
      expect(berththingThresholds.length, greaterThan(overviewThresholds.length));
      
      // Both should include lighthouses
      expect(berththingThresholds.containsKey(MaritimeFeatureType.lighthouse), isTrue);
      expect(overviewThresholds.containsKey(MaritimeFeatureType.lighthouse), isTrue);
      
      // Only berthing should include cables
      expect(berththingThresholds.containsKey(MaritimeFeatureType.cable), isTrue);
      expect(overviewThresholds.containsKey(MaritimeFeatureType.cable), isFalse);
    });
  });
}

List<MaritimeFeature> _createTestMaritimeFeatures() {
  return [
    PointFeature(
      id: 'lighthouse_1',
      type: MaritimeFeatureType.lighthouse,
      position: LatLng(47.6062, -122.3321),
      label: 'Alki Point Light',
    ),
    PointFeature(
      id: 'buoy_1',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6235, -122.3517),
      label: 'Elliott Bay Buoy',
    ),
    LineFeature(
      id: 'shoreline_1',
      type: MaritimeFeatureType.shoreline,
      position: LatLng(47.615, -122.345),
      coordinates: [
        LatLng(47.610, -122.340),
        LatLng(47.615, -122.345),
        LatLng(47.620, -122.350),
      ],
    ),
    AreaFeature(
      id: 'anchorage_1',
      type: MaritimeFeatureType.anchorage,
      position: LatLng(47.618, -122.355),
      coordinates: [[
        LatLng(47.615, -122.350),
        LatLng(47.620, -122.350),
        LatLng(47.620, -122.360),
        LatLng(47.615, -122.360),
        LatLng(47.615, -122.350),
      ]],
    ),
  ];
}

List<S57Feature> _createTestS57Features() {
  return [
    S57Feature(
      recordId: 1001,
      featureType: S57FeatureType.lighthouse,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6062, longitude: -122.3321)],
      attributes: const {'name': 'Alki Point Light'},
    ),
    S57Feature(
      recordId: 1002,
      featureType: S57FeatureType.buoy,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6235, longitude: -122.3517)],
      attributes: const {'name': 'Elliott Bay Buoy'},
    ),
    S57Feature(
      recordId: 2001,
      featureType: S57FeatureType.coastline,
      geometryType: S57GeometryType.line,
      coordinates: [
        S57Coordinate(latitude: 47.610, longitude: -122.340),
        S57Coordinate(latitude: 47.615, longitude: -122.345),
        S57Coordinate(latitude: 47.620, longitude: -122.350),
      ],
      attributes: const {'type': 'natural'},
    ),
  ];
}