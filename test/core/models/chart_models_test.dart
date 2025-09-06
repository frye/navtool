import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  group('Chart Models Tests', () {
    group('LatLng Tests', () {
      test('should create LatLng with valid coordinates', () {
        const latLng = LatLng(37.7749, -122.4194);
        expect(latLng.latitude, equals(37.7749));
        expect(latLng.longitude, equals(-122.4194));
      });

      test('should implement equality correctly', () {
        const latLng1 = LatLng(37.7749, -122.4194);
        const latLng2 = LatLng(37.7749, -122.4194);
        const latLng3 = LatLng(37.7750, -122.4194);

        expect(latLng1, equals(latLng2));
        expect(latLng1, isNot(equals(latLng3)));
      });

      test('should implement hashCode correctly', () {
        const latLng1 = LatLng(37.7749, -122.4194);
        const latLng2 = LatLng(37.7749, -122.4194);
        const latLng3 = LatLng(37.7750, -122.4194);

        expect(latLng1.hashCode, equals(latLng2.hashCode));
        expect(latLng1.hashCode, isNot(equals(latLng3.hashCode)));
      });

      test('should return proper string representation', () {
        const latLng = LatLng(37.7749, -122.4194);
        expect(latLng.toString(), equals('LatLng(37.7749, -122.4194)'));
      });
    });

    group('LatLngBounds Tests', () {
      test('should create bounds with valid coordinates', () {
        const bounds = LatLngBounds(
          north: 37.8,
          south: 37.7,
          east: -122.3,
          west: -122.5,
        );

        expect(bounds.north, equals(37.8));
        expect(bounds.south, equals(37.7));
        expect(bounds.east, equals(-122.3));
        expect(bounds.west, equals(-122.5));
      });

      test('should correctly identify points within bounds', () {
        const bounds = LatLngBounds(
          north: 37.8,
          south: 37.7,
          east: -122.3,
          west: -122.5,
        );

        // Point inside bounds
        const insidePoint = LatLng(37.75, -122.4);
        expect(bounds.contains(insidePoint), isTrue);

        // Point outside bounds
        const outsidePoint = LatLng(37.9, -122.4);
        expect(bounds.contains(outsidePoint), isFalse);

        // Point on boundary
        const boundaryPoint = LatLng(37.8, -122.4);
        expect(bounds.contains(boundaryPoint), isTrue);
      });

      test('should calculate center correctly', () {
        const bounds = LatLngBounds(
          north: 37.8,
          south: 37.6,
          east: -122.2,
          west: -122.6,
        );

        final center = bounds.center;
        expect(center.latitude, equals(37.7));
        expect(center.longitude, equals(-122.4));
      });

      test('should return proper string representation', () {
        const bounds = LatLngBounds(
          north: 37.8,
          south: 37.7,
          east: -122.3,
          west: -122.5,
        );

        expect(
          bounds.toString(),
          equals('LatLngBounds(N:37.8, S:37.7, E:-122.3, W:-122.5)'),
        );
      });
    });

    group('ChartScale Tests', () {
      test('should return correct scale from zoom level', () {
        expect(ChartScale.fromZoom(7), equals(ChartScale.overview));
        expect(ChartScale.fromZoom(9), equals(ChartScale.general));
        expect(ChartScale.fromZoom(11), equals(ChartScale.coastal));
        expect(ChartScale.fromZoom(13), equals(ChartScale.approach));
        expect(ChartScale.fromZoom(15), equals(ChartScale.harbour));
        expect(ChartScale.fromZoom(17), equals(ChartScale.berthing));
      });

      test('should have correct scale values', () {
        expect(ChartScale.overview.scale, equals(1000000));
        expect(ChartScale.general.scale, equals(500000));
        expect(ChartScale.coastal.scale, equals(100000));
        expect(ChartScale.approach.scale, equals(50000));
        expect(ChartScale.harbour.scale, equals(25000));
        expect(ChartScale.berthing.scale, equals(10000));
      });

      test('should have correct labels', () {
        expect(ChartScale.overview.label, equals('Overview'));
        expect(ChartScale.general.label, equals('General'));
        expect(ChartScale.coastal.label, equals('Coastal'));
        expect(ChartScale.approach.label, equals('Approach'));
        expect(ChartScale.harbour.label, equals('Harbour'));
        expect(ChartScale.berthing.label, equals('Berthing'));
      });
    });

    group('PointFeature Tests', () {
      test('should create point feature with required properties', () {
        const feature = PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(37.8199, -122.4783),
          label: 'Alcatraz Light',
        );

        expect(feature.id, equals('lighthouse_1'));
        expect(feature.type, equals(MaritimeFeatureType.lighthouse));
        expect(feature.position, equals(const LatLng(37.8199, -122.4783)));
        expect(feature.label, equals('Alcatraz Light'));
      });

      test('should return correct visibility at different scales', () {
        const lighthouse = PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(37.8199, -122.4783),
        );

        const buoy = PointFeature(
          id: 'buoy_1',
          type: MaritimeFeatureType.buoy,
          position: LatLng(37.7849, -122.4594),
        );

        // Lighthouse should be visible at larger scales
        expect(lighthouse.isVisibleAtScale(ChartScale.overview), isTrue);
        expect(lighthouse.isVisibleAtScale(ChartScale.general), isTrue);
        expect(lighthouse.isVisibleAtScale(ChartScale.coastal), isTrue);

        // Buoy should only be visible at smaller scales
        expect(buoy.isVisibleAtScale(ChartScale.overview), isFalse);
        expect(buoy.isVisibleAtScale(ChartScale.approach), isTrue);
        expect(buoy.isVisibleAtScale(ChartScale.harbour), isTrue);
      });

      test('should return correct render priorities', () {
        const lighthouse = PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(37.8199, -122.4783),
        );

        const buoy = PointFeature(
          id: 'buoy_1',
          type: MaritimeFeatureType.buoy,
          position: LatLng(37.7849, -122.4594),
        );

        const beacon = PointFeature(
          id: 'beacon_1',
          type: MaritimeFeatureType.beacon,
          position: LatLng(37.8049, -122.4394),
        );

        // Lighthouse should have highest priority
        expect(lighthouse.renderPriority, equals(100));
        expect(beacon.renderPriority, equals(90));
        expect(buoy.renderPriority, equals(80));
        expect(lighthouse.renderPriority > beacon.renderPriority, isTrue);
        expect(beacon.renderPriority > buoy.renderPriority, isTrue);
      });
    });

    group('LineFeature Tests', () {
      test('should create line feature with coordinates', () {
        final coordinates = [
          const LatLng(37.7649, -122.4094),
          const LatLng(37.7749, -122.4194),
          const LatLng(37.7849, -122.4294),
        ];

        final feature = LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: coordinates.first,
          coordinates: coordinates,
          width: 2.0,
        );

        expect(feature.id, equals('shoreline_1'));
        expect(feature.type, equals(MaritimeFeatureType.shoreline));
        expect(feature.coordinates, equals(coordinates));
        expect(feature.width, equals(2.0));
      });

      test('should return correct visibility for different line types', () {
        final shoreline = LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: const LatLng(37.7749, -122.4194),
          coordinates: [const LatLng(37.7749, -122.4194)],
        );

        final cable = LineFeature(
          id: 'cable_1',
          type: MaritimeFeatureType.cable,
          position: const LatLng(37.7749, -122.4194),
          coordinates: [const LatLng(37.7749, -122.4194)],
        );

        // Shoreline should always be visible
        expect(shoreline.isVisibleAtScale(ChartScale.overview), isTrue);
        expect(shoreline.isVisibleAtScale(ChartScale.berthing), isTrue);

        // Cable should only be visible at detailed scales
        expect(cable.isVisibleAtScale(ChartScale.overview), isFalse);
        expect(cable.isVisibleAtScale(ChartScale.coastal), isTrue);
      });
    });

    group('AreaFeature Tests', () {
      test('should create area feature with polygon coordinates', () {
        final coordinates = [
          [
            const LatLng(37.7649, -122.4094),
            const LatLng(37.7649, -122.3994),
            const LatLng(37.7849, -122.3994),
            const LatLng(37.7849, -122.4094),
          ],
        ];

        final feature = AreaFeature(
          id: 'land_1',
          type: MaritimeFeatureType.landArea,
          position: const LatLng(37.7749, -122.4094),
          coordinates: coordinates,
          fillColor: Colors.brown,
          strokeColor: Colors.black,
        );

        expect(feature.id, equals('land_1'));
        expect(feature.type, equals(MaritimeFeatureType.landArea));
        expect(feature.coordinates, equals(coordinates));
        expect(feature.fillColor, equals(Colors.brown));
        expect(feature.strokeColor, equals(Colors.black));
      });

      test('should return correct visibility for different area types', () {
        final landArea = AreaFeature(
          id: 'land_1',
          type: MaritimeFeatureType.landArea,
          position: const LatLng(37.7749, -122.4094),
          coordinates: [[]],
        );

        final anchorage = AreaFeature(
          id: 'anchorage_1',
          type: MaritimeFeatureType.anchorage,
          position: const LatLng(37.7949, -122.4594),
          coordinates: [[]],
        );

        // Land area should always be visible
        expect(landArea.isVisibleAtScale(ChartScale.overview), isTrue);
        expect(landArea.isVisibleAtScale(ChartScale.berthing), isTrue);

        // Anchorage should only be visible at detailed scales
        expect(anchorage.isVisibleAtScale(ChartScale.overview), isFalse);
        expect(anchorage.isVisibleAtScale(ChartScale.coastal), isTrue);
      });

      test('should return correct render priorities', () {
        final landArea = AreaFeature(
          id: 'land_1',
          type: MaritimeFeatureType.landArea,
          position: const LatLng(37.7749, -122.4094),
          coordinates: [[]],
        );

        final anchorage = AreaFeature(
          id: 'anchorage_1',
          type: MaritimeFeatureType.anchorage,
          position: const LatLng(37.7949, -122.4594),
          coordinates: [[]],
        );

        // Land should render first (lowest priority), anchorage on top
        expect(landArea.renderPriority, equals(0));
        expect(anchorage.renderPriority, equals(40));
        expect(anchorage.renderPriority > landArea.renderPriority, isTrue);
      });
    });

    group('DepthContour Tests', () {
      test('should create depth contour with depth value', () {
        const coordinates = [
          LatLng(37.7649, -122.4094),
          LatLng(37.7749, -122.4194),
          LatLng(37.7849, -122.4294),
        ];

        const contour = DepthContour(
          id: 'depth_10m',
          coordinates: coordinates,
          depth: 10.0,
        );

        expect(contour.id, equals('depth_10m'));
        expect(contour.type, equals(MaritimeFeatureType.depthContour));
        expect(contour.coordinates, equals(coordinates));
        expect(contour.depth, equals(10.0));
        expect(contour.renderPriority, equals(5));
      });

      test('should return correct visibility based on scale and depth', () {
        const contour100m = DepthContour(
          id: 'depth_100m',
          coordinates: [LatLng(37.7749, -122.4194)],
          depth: 100.0,
        );

        const contour50m = DepthContour(
          id: 'depth_50m',
          coordinates: [LatLng(37.7749, -122.4194)],
          depth: 50.0,
        );

        const contour10m = DepthContour(
          id: 'depth_10m',
          coordinates: [LatLng(37.7749, -122.4194)],
          depth: 10.0,
        );

        const contour5m = DepthContour(
          id: 'depth_5m',
          coordinates: [LatLng(37.7749, -122.4194)],
          depth: 5.0,
        );

        // Overview scale should only show major contours
        expect(contour100m.isVisibleAtScale(ChartScale.overview), isTrue);
        expect(contour50m.isVisibleAtScale(ChartScale.overview), isFalse);
        expect(contour10m.isVisibleAtScale(ChartScale.overview), isFalse);

        // Harbour scale should show more detailed contours
        expect(contour100m.isVisibleAtScale(ChartScale.harbour), isTrue);
        expect(contour50m.isVisibleAtScale(ChartScale.harbour), isTrue);
        expect(contour10m.isVisibleAtScale(ChartScale.harbour), isTrue);
        expect(contour5m.isVisibleAtScale(ChartScale.harbour), isTrue);

        // Berthing scale should show very detailed contours
        expect(contour5m.isVisibleAtScale(ChartScale.berthing), isTrue);
      });
    });
  });
}
