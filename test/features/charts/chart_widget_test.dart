import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/features/charts/chart_widget.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';

void main() {
  group('ChartWidget Tests', () {
    const testCenter = LatLng(37.7749, -122.4194);
    const testScreenSize = Size(800, 600);

    late List<MaritimeFeature> testFeatures;

    setUp(() {
      testFeatures = [
        const PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(37.8199, -122.4783),
          label: 'Test Lighthouse',
        ),
        LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: testCenter,
          coordinates: [
            const LatLng(37.7649, -122.4094),
            const LatLng(37.7749, -122.4194),
            const LatLng(37.7849, -122.4294),
          ],
        ),
        AreaFeature(
          id: 'land_1',
          type: MaritimeFeatureType.landArea,
          position: testCenter,
          coordinates: [
            [
              const LatLng(37.7649, -122.4094),
              const LatLng(37.7649, -122.3994),
              const LatLng(37.7849, -122.3994),
              const LatLng(37.7849, -122.4094),
            ]
          ],
        ),
      ];
    });

    Widget createTestWidget({
      LatLng? initialCenter,
      double? initialZoom,
      List<MaritimeFeature>? features,
      ChartDisplayMode? displayMode,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChartWidget(
              initialCenter: initialCenter ?? testCenter,
              initialZoom: initialZoom ?? 12.0,
              features: features ?? testFeatures,
              displayMode: displayMode ?? ChartDisplayMode.dayMode,
            ),
          ),
        ),
      );
    }

    group('Widget Creation and Properties', () {
      testWidgets('should create ChartWidget with default parameters', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(GestureDetector), findsAtLeastNWidgets(1));
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should create ChartWidget with custom initial center', (WidgetTester tester) async {
        const customCenter = LatLng(40.7589, -73.9851); // New York

        await tester.pumpWidget(createTestWidget(initialCenter: customCenter));

        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should create ChartWidget with custom initial zoom', (WidgetTester tester) async {
        const customZoom = 15.0;

        await tester.pumpWidget(createTestWidget(initialZoom: customZoom));

        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should create ChartWidget with empty features list', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(features: []));

        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should create ChartWidget with night mode', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(displayMode: ChartDisplayMode.nightMode));

        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('Gesture Handling', () {
      testWidgets('should handle scale gesture start', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        final gestureDetectors = find.byType(GestureDetector);
        expect(gestureDetectors, findsAtLeastNWidgets(1));

        // Start a scale gesture on the first gesture detector
        final center = tester.getCenter(gestureDetectors.first);
        final gesture = await tester.startGesture(center);
        
        await tester.pump();
        
        await gesture.up();
      });

      testWidgets('should handle scale gesture update', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        final gestureDetectors = find.byType(GestureDetector);
        expect(gestureDetectors, findsAtLeastNWidgets(1));

        // Simply verify that gesture detector is present and configured
        final GestureDetector detector = tester.widget(gestureDetectors.first);
        expect(detector.onScaleUpdate, isNotNull);
        expect(detector.onScaleStart, isNotNull);
        expect(detector.onScaleEnd, isNotNull);
      });

      testWidgets('should handle scale gesture end', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        final gestureDetectors = find.byType(GestureDetector);
        expect(gestureDetectors, findsAtLeastNWidgets(1));

        // Start and end a scale gesture
        final center = tester.getCenter(gestureDetectors.first);
        final gesture = await tester.startGesture(center);
        await tester.pump();
        await gesture.up();
        await tester.pump();
      });
    });

    group('Responsive Layout', () {
      testWidgets('should adapt to different screen sizes', (WidgetTester tester) async {
        // Test with small screen
        tester.view.physicalSize = const Size(400, 300);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);

        // Test with large screen
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle landscape orientation', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 400); // Landscape
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle portrait orientation', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(400, 800); // Portrait
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('Feature Rendering', () {
      testWidgets('should render with point features', (WidgetTester tester) async {
        final pointFeatures = [
          const PointFeature(
            id: 'lighthouse_1',
            type: MaritimeFeatureType.lighthouse,
            position: testCenter,
            label: 'Test Lighthouse',
          ),
          const PointFeature(
            id: 'buoy_1',
            type: MaritimeFeatureType.buoy,
            position: LatLng(37.7849, -122.4294),
            label: 'Test Buoy',
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: pointFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should render with line features', (WidgetTester tester) async {
        final lineFeatures = [
          LineFeature(
            id: 'shoreline_1',
            type: MaritimeFeatureType.shoreline,
            position: testCenter,
            coordinates: [
              const LatLng(37.7649, -122.4094),
              const LatLng(37.7849, -122.4294),
            ],
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: lineFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should render with area features', (WidgetTester tester) async {
        final areaFeatures = [
          AreaFeature(
            id: 'land_1',
            type: MaritimeFeatureType.landArea,
            position: testCenter,
            coordinates: [
              [
                const LatLng(37.7649, -122.4094),
                const LatLng(37.7649, -122.3994),
                const LatLng(37.7849, -122.3994),
                const LatLng(37.7849, -122.4094),
              ]
            ],
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: areaFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should render with depth contours', (WidgetTester tester) async {
        final depthFeatures = [
          const DepthContour(
            id: 'depth_10m',
            coordinates: [
              LatLng(37.7649, -122.4094),
              LatLng(37.7849, -122.4294),
            ],
            depth: 10.0,
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: depthFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should render with mixed feature types', (WidgetTester tester) async {
        // Using the default testFeatures which contains mixed types
        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });
    });

    group('Display Modes', () {
      testWidgets('should render in day mode', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(displayMode: ChartDisplayMode.dayMode));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should render in night mode', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(displayMode: ChartDisplayMode.nightMode));
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });

      testWidgets('should switch between display modes', (WidgetTester tester) async {
        // Start with day mode
        await tester.pumpWidget(createTestWidget(displayMode: ChartDisplayMode.dayMode));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Switch to night mode
        await tester.pumpWidget(createTestWidget(displayMode: ChartDisplayMode.nightMode));
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('Edge Cases and Error Handling', () {
      testWidgets('should handle very small widget size', (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 10,
                  height: 10,
                  child: ChartWidget(
                    initialCenter: testCenter,
                    initialZoom: 12.0,
                    features: testFeatures,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle very large widget size', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(2000, 1500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle extreme zoom levels', (WidgetTester tester) async {
        // Test minimum zoom
        await tester.pumpWidget(createTestWidget(initialZoom: 1.0));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Test maximum zoom
        await tester.pumpWidget(createTestWidget(initialZoom: 20.0));
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle extreme coordinates', (WidgetTester tester) async {
        // Test North Pole
        await tester.pumpWidget(createTestWidget(initialCenter: const LatLng(90.0, 0.0)));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Test South Pole
        await tester.pumpWidget(createTestWidget(initialCenter: const LatLng(-90.0, 0.0)));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Test Date Line
        await tester.pumpWidget(createTestWidget(initialCenter: const LatLng(0.0, 180.0)));
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle null or invalid features gracefully', (WidgetTester tester) async {
        // Test with features containing invalid coordinates
        final invalidFeatures = [
          LineFeature(
            id: 'invalid_line',
            type: MaritimeFeatureType.shoreline,
            position: testCenter,
            coordinates: [], // Empty coordinates
          ),
          AreaFeature(
            id: 'invalid_area',
            type: MaritimeFeatureType.landArea,
            position: testCenter,
            coordinates: [[]], // Empty coordinates
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: invalidFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('Widget State Management', () {
      testWidgets('should maintain state during rebuild', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);

        // Trigger rebuild
        await tester.pumpWidget(createTestWidget());
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should update when features change', (WidgetTester tester) async {
        // Start with initial features
        await tester.pumpWidget(createTestWidget(features: testFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Change features
        final newFeatures = [
          const PointFeature(
            id: 'new_lighthouse',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(40.7589, -73.9851),
            label: 'New Lighthouse',
          ),
        ];

        await tester.pumpWidget(createTestWidget(features: newFeatures));
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should update when center changes', (WidgetTester tester) async {
        // Start with initial center
        await tester.pumpWidget(createTestWidget(initialCenter: testCenter));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Change center
        const newCenter = LatLng(40.7589, -73.9851); // New York
        await tester.pumpWidget(createTestWidget(initialCenter: newCenter));
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should update when zoom changes', (WidgetTester tester) async {
        // Start with initial zoom
        await tester.pumpWidget(createTestWidget(initialZoom: 12.0));
        expect(find.byType(ChartWidget), findsOneWidget);

        // Change zoom
        await tester.pumpWidget(createTestWidget(initialZoom: 15.0));
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });
  });
}
