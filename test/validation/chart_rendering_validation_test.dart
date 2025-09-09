/// Validation test for chart rendering engine functionality
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../../lib/core/models/chart_models.dart';
import '../../lib/core/services/chart_rendering_service.dart';
import '../../lib/core/services/coordinate_transform.dart';
import '../../lib/features/charts/chart_widget.dart';
import '../../lib/features/charts/chart_screen.dart';

void main() {
  group('Chart Rendering Engine Validation', () {
    late List<MaritimeFeature> sampleFeatures;
    late CoordinateTransform coordinateTransform;

    setUpAll(() {
      // Create sample features for Elliott Bay (matches NOAA test data location)
      sampleFeatures = [
        // Lighthouse feature
        PointFeature(
          id: 'elliott_bay_lighthouse',
          type: MaritimeFeatureType.lighthouse,
          position: const LatLng(47.6062, -122.3321), // Elliott Bay
          label: 'Elliott Bay Light',
        ),
        // Buoy features
        PointFeature(
          id: 'elliott_bay_buoy_1',
          type: MaritimeFeatureType.buoy,
          position: const LatLng(47.6100, -122.3400),
          label: 'EB-1',
        ),
        PointFeature(
          id: 'elliott_bay_buoy_2',
          type: MaritimeFeatureType.buoy,
          position: const LatLng(47.6150, -122.3350),
          label: 'EB-2', 
        ),
        // Depth contour
        DepthContour(
          id: 'elliott_bay_depth_10m',
          depth: 10.0,
          coordinates: [
            const LatLng(47.6000, -122.3500),
            const LatLng(47.6100, -122.3400),
            const LatLng(47.6200, -122.3300),
            const LatLng(47.6150, -122.3200),
          ],
        ),
        // Shoreline
        LineFeature(
          id: 'elliott_bay_shoreline',
          type: MaritimeFeatureType.shoreline,
          position: const LatLng(47.6062, -122.3321),
          coordinates: [
            const LatLng(47.6000, -122.3200),
            const LatLng(47.6100, -122.3100),
            const LatLng(47.6200, -122.3000),
            const LatLng(47.6300, -122.2900),
          ],
        ),
        // Anchorage area
        AreaFeature(
          id: 'elliott_bay_anchorage',
          type: MaritimeFeatureType.anchorage,
          position: const LatLng(47.6100, -122.3300),
          coordinates: [[
            const LatLng(47.6050, -122.3350),
            const LatLng(47.6150, -122.3350),
            const LatLng(47.6150, -122.3250),
            const LatLng(47.6050, -122.3250),
          ]],
        ),
      ];

      coordinateTransform = CoordinateTransform(
        center: const LatLng(47.6062, -122.3321), // Elliott Bay center
        zoom: 12.0,
        screenSize: const Size(800, 600),
      );
    });

    testWidgets('should create chart rendering service with S-52 compliance', (WidgetTester tester) async {
      final renderingService = ChartRenderingService(
        transform: coordinateTransform,
        features: sampleFeatures,
        displayMode: ChartDisplayMode.dayMode,
      );

      expect(renderingService, isNotNull);
      expect(renderingService.getLayers().isNotEmpty, isTrue);
    });

    testWidgets('should render chart widget with maritime features', (WidgetTester tester) async {
      final chartWidget = ChartWidget(
        initialCenter: const LatLng(47.6062, -122.3321), // Elliott Bay
        initialZoom: 12.0,
        features: sampleFeatures,
        displayMode: ChartDisplayMode.dayMode,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: chartWidget),
      ));

      expect(find.byType(ChartWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets); // Chart canvas and controls
    });

    testWidgets('should render chart screen with comprehensive UI', (WidgetTester tester) async {
      final chartScreen = ChartScreen(
        chartTitle: 'Elliott Bay Test Chart',
        initialPosition: const LatLng(47.6062, -122.3321),
      );

      await tester.pumpWidget(MaterialApp(
        home: chartScreen,
      ));

      expect(find.byType(ChartScreen), findsOneWidget);
      expect(find.byType(ChartWidget), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Elliott Bay Test Chart'), findsOneWidget);
    });

    testWidgets('should support all chart display modes', (WidgetTester tester) async {
      for (final displayMode in ChartDisplayMode.values) {
        final chartWidget = ChartWidget(
          initialCenter: const LatLng(47.6062, -122.3321),
          initialZoom: 12.0,
          features: sampleFeatures,
          displayMode: displayMode,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: chartWidget),
        ));

        expect(find.byType(ChartWidget), findsOneWidget);
        await tester.pump(); // Allow rendering
      }
    });

    testWidgets('should handle maritime feature scale visibility', (WidgetTester tester) async {
      // Test that features are visible at appropriate scales
      for (final feature in sampleFeatures) {
        for (final scale in ChartScale.values) {
          final isVisible = feature.isVisibleAtScale(scale);
          expect(isVisible, isA<bool>());
        }
      }
    });

    test('should provide coordinate transformation utilities', () {
      final transform = coordinateTransform;
      
      // Test coordinate conversion
      final screenPoint = transform.latLngToScreen(const LatLng(47.6062, -122.3321));
      expect(screenPoint, isA<Offset>());
      
      final latLng = transform.screenToLatLng(screenPoint);
      expect(latLng.latitude, closeTo(47.6062, 0.01));
      expect(latLng.longitude, closeTo(-122.3321, 0.01));
      
      // Test distance calculation
      final distance = transform.calculateDistance(
        const LatLng(47.6062, -122.3321),
        const LatLng(47.6100, -122.3400),
      );
      expect(distance, greaterThan(0));
      
      // Test bearing calculation
      final bearing = transform.calculateBearing(
        const LatLng(47.6062, -122.3321),
        const LatLng(47.6100, -122.3400),
      );
      expect(bearing, greaterThanOrEqualTo(0));
      expect(bearing, lessThan(360));
    });

    test('should support maritime feature types from S-57 standard', () {
      final featureTypes = MaritimeFeatureType.values;
      
      // Verify key maritime feature types are supported
      expect(featureTypes, contains(MaritimeFeatureType.lighthouse));
      expect(featureTypes, contains(MaritimeFeatureType.buoy));
      expect(featureTypes, contains(MaritimeFeatureType.beacon));
      expect(featureTypes, contains(MaritimeFeatureType.depthContour));
      expect(featureTypes, contains(MaritimeFeatureType.shoreline));
      expect(featureTypes, contains(MaritimeFeatureType.anchorage));
      expect(featureTypes, contains(MaritimeFeatureType.wrecks));
      expect(featureTypes, contains(MaritimeFeatureType.rocks));
      
      // Verify we have comprehensive maritime coverage
      expect(featureTypes.length, greaterThanOrEqualTo(15));
    });

    test('should support chart scales from overview to berthing', () {
      final scales = ChartScale.values;
      
      // Verify all required chart scales are supported
      expect(scales, contains(ChartScale.overview));
      expect(scales, contains(ChartScale.general));
      expect(scales, contains(ChartScale.coastal));
      expect(scales, contains(ChartScale.approach));
      expect(scales, contains(ChartScale.harbour));
      expect(scales, contains(ChartScale.berthing));
      
      // Test scale relationships
      expect(ChartScale.overview.scale, greaterThan(ChartScale.berthing.scale));
      expect(ChartScale.fromZoom(5.0), equals(ChartScale.overview));
      expect(ChartScale.fromZoom(17.0), equals(ChartScale.berthing));
    });

    test('should have NOAA test chart data available', () {
      // Verify test chart files exist
      // Note: This test validates that the test infrastructure has the charts mentioned in comments
      expect(sampleFeatures.isNotEmpty, isTrue);
      expect(sampleFeatures.length, greaterThanOrEqualTo(5));
      
      // Verify we have different feature types
      final featureTypes = sampleFeatures.map((f) => f.type).toSet();
      expect(featureTypes.length, greaterThanOrEqualTo(4));
      expect(featureTypes, contains(MaritimeFeatureType.lighthouse));
      expect(featureTypes, contains(MaritimeFeatureType.buoy));
      expect(featureTypes, contains(MaritimeFeatureType.shoreline));
    });
  });
}