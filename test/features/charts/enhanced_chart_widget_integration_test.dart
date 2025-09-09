/// Integration tests for enhanced chart widget with display controls
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/chart_widget.dart';
import 'package:navtool/features/charts/widgets/chart_display_controls.dart';
import 'package:navtool/features/charts/widgets/chart_info_overlay.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';

void main() {
  group('Enhanced ChartWidget Integration', () {
    late List<MaritimeFeature> testFeatures;
    late LatLng testCenter;

    setUp(() {
      testCenter = const LatLng(47.6062, -122.3321); // Seattle
      
      testFeatures = [
        const PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(47.6100, -122.3350),
          label: 'Elliott Bay Light',
        ),
        const PointFeature(
          id: 'buoy_1',
          type: MaritimeFeatureType.buoy,
          position: LatLng(47.6050, -122.3300),
          label: 'RB "1"',
        ),
        const PointFeature(
          id: 'buoy_2',
          type: MaritimeFeatureType.buoy,
          position: LatLng(47.6040, -122.3280),
          label: 'GB "2"',
        ),
        const LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: LatLng(47.6000, -122.3250),
          coordinates: [
            LatLng(47.6000, -122.3250),
            LatLng(47.6020, -122.3270),
            LatLng(47.6040, -122.3290),
          ],
        ),
        const AreaFeature(
          id: 'anchorage_1',
          type: MaritimeFeatureType.anchorage,
          position: LatLng(47.6030, -122.3320),
          coordinates: [
            [
              LatLng(47.6020, -122.3310),
              LatLng(47.6020, -122.3330),
              LatLng(47.6040, -122.3330),
              LatLng(47.6040, -122.3310),
            ],
          ],
        ),
      ];
    });

    testWidgets('should display enhanced chart widget with all controls', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
        displayMode: ChartDisplayMode.dayMode,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check that ChartDisplayControls is present
      expect(find.byType(ChartDisplayControls), findsOneWidget);

      // Check for main control elements
      expect(find.byIcon(Icons.add), findsOneWidget); // Zoom in
      expect(find.byIcon(Icons.remove), findsOneWidget); // Zoom out
      expect(find.byIcon(Icons.navigation), findsOneWidget); // Compass
      expect(find.byIcon(Icons.my_location), findsOneWidget); // Center
      expect(find.byIcon(Icons.layers), findsOneWidget); // Layers
      expect(find.byIcon(Icons.info_outline), findsOneWidget); // Info

      // Check position display
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.textContaining('47°'), findsOneWidget);

      // Check scale display  
      expect(find.byIcon(Icons.straighten), findsOneWidget);
      expect(find.textContaining('Scale:'), findsOneWidget);

      // Check display mode controls
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
    });

    testWidgets('should handle zoom controls integration', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 10.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Initial zoom level should be displayed
      expect(find.text('10.0'), findsOneWidget);

      // Test zoom in
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('11.0'), findsOneWidget);

      // Test zoom out
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(find.text('10.0'), findsOneWidget);
    });

    testWidgets('should open and close layer panel', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Initially no layer panel
      expect(find.text('Chart Layers'), findsNothing);

      // Open layer panel
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pump();

      // Layer panel should be visible
      expect(find.text('Chart Layers'), findsOneWidget);
      expect(find.text('Depth Contours'), findsOneWidget);
      expect(find.text('Navigation Aids'), findsOneWidget);
      expect(find.text('Shoreline'), findsOneWidget);

      // Close layer panel by tapping close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      // Layer panel should be hidden
      expect(find.text('Chart Layers'), findsNothing);
    });

    testWidgets('should toggle layer visibility', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Open layer panel
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pump();

      // Find the switch for depth contours
      final depthContoursSwitch = find.byType(Switch).first;
      expect(tester.widget<Switch>(depthContoursSwitch).value, isTrue);

      // Toggle layer off
      await tester.tap(depthContoursSwitch);
      await tester.pump();

      // Layer should be toggled off
      expect(tester.widget<Switch>(depthContoursSwitch).value, isFalse);
    });

    testWidgets('should open and close info overlay', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Initially no info overlay
      expect(find.byType(ChartInfoOverlay), findsNothing);

      // Open info overlay
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pump();

      // Info overlay should be visible
      expect(find.byType(ChartInfoOverlay), findsOneWidget);
      expect(find.text('Marine Chart'), findsOneWidget);

      // Close info overlay
      final closeButton = find.byIcon(Icons.close).last; // Last one is in the overlay
      await tester.tap(closeButton);
      await tester.pump();

      // Info overlay should be hidden
      expect(find.byType(ChartInfoOverlay), findsNothing);
    });

    testWidgets('should expand and collapse info overlay', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Open info overlay
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pump();

      // Should be in compact mode initially
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Navigation'), findsNothing); // Only in expanded mode

      // Expand overlay
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();

      // Should be in expanded mode
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);
    });

    testWidgets('should cycle display modes', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
        displayMode: ChartDisplayMode.dayMode,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Should start in day mode
      expect(find.text('Day'), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);

      // Cycle to night mode
      await tester.tap(find.byIcon(Icons.brightness_6));
      await tester.pump();

      expect(find.text('Night'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      // Cycle to dusk mode
      await tester.tap(find.byIcon(Icons.brightness_6));
      await tester.pump();

      expect(find.text('Dusk'), findsOneWidget);
      expect(find.byIcon(Icons.brightness_4), findsOneWidget);

      // Cycle back to day mode
      await tester.tap(find.byIcon(Icons.brightness_6));
      await tester.pump();

      expect(find.text('Day'), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
    });

    testWidgets('should handle rotation controls', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Should start with 0° rotation
      expect(find.text('0°'), findsOneWidget);

      // Test rotation reset (tap on compass)
      await tester.tap(find.byIcon(Icons.navigation));
      await tester.pump();

      // Should still be 0° (no change expected from reset when already at 0)
      expect(find.text('0°'), findsOneWidget);
    });

    testWidgets('should update position display when panning', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Get initial position display
      expect(find.textContaining('47°'), findsOneWidget);
      expect(find.textContaining('122°'), findsOneWidget);

      // Simulate pan gesture
      final chartCanvas = find.byType(CustomPaint);
      await tester.drag(chartCanvas, const Offset(100, 0));
      await tester.pump();

      // Position should still be displayed (though values may have changed)
      expect(find.textContaining('47°'), findsOneWidget);
      expect(find.textContaining('122°'), findsOneWidget);
    });

    testWidgets('should show feature counts in info overlay', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Open info overlay
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pump();

      // Check for feature counts
      expect(find.textContaining('Lighthouses: 1'), findsOneWidget);
      expect(find.textContaining('Buoys: 2'), findsOneWidget);
      expect(find.textContaining('Shoreline: 1'), findsOneWidget);
      expect(find.textContaining('Anchorages: 1'), findsOneWidget);
    });

    testWidgets('should handle marine environment gestures', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 10.0,
        features: testFeatures,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      final chartCanvas = find.byType(CustomPaint);

      // Test simple drag gesture (panning)
      await tester.drag(chartCanvas, const Offset(100, 50));
      await tester.pump();

      // Should handle the gesture without crashing
      expect(chartCanvas, findsOneWidget);
      
      // Test scale gesture by simulating zoom buttons instead
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      
      // Zoom level should have increased
      expect(find.text('11.0'), findsOneWidget);
    });

    testWidgets('should maintain state during orientation changes', (WidgetTester tester) async {
      final widget = ChartWidget(
        initialCenter: testCenter,
        initialZoom: 12.0,
        features: testFeatures,
        displayMode: ChartDisplayMode.nightMode,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Open layer panel and change some settings
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pump();

      // Toggle a layer off
      final switch1 = find.byType(Switch).first;
      await tester.tap(switch1);
      await tester.pump();

      // Open info overlay
      await tester.tap(find.byIcon(Icons.close)); // Close layer panel first
      await tester.pump();
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pump();

      // Simulate orientation change by rebuilding with different size
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pump();

      // State should be maintained
      expect(find.text('Night'), findsOneWidget); // Display mode preserved
      expect(find.byType(ChartInfoOverlay), findsOneWidget); // Info overlay still open
    });

    group('Marine safety compliance', () {
      testWidgets('should provide clear visual feedback for critical actions', (WidgetTester tester) async {
        final widget = ChartWidget(
          initialCenter: testCenter,
          initialZoom: 12.0,
          features: testFeatures,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // All critical buttons should have tooltips for safety
        await tester.longPress(find.byIcon(Icons.add));
        await tester.pump();
        // Tooltip should appear but we don't test the exact text since it's implementation detail

        await tester.longPress(find.byIcon(Icons.my_location));
        await tester.pump();
        // GPS button should have clear tooltip

        await tester.longPress(find.byIcon(Icons.layers));
        await tester.pump();
        // Layer button should indicate its function
      });

      testWidgets('should handle rapid input sequences safely', (WidgetTester tester) async {
        final widget = ChartWidget(
          initialCenter: testCenter,
          initialZoom: 12.0,
          features: testFeatures,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // Rapid zoom operations
        for (int i = 0; i < 5; i++) {
          await tester.tap(find.byIcon(Icons.add));
          await tester.pump();
        }

        // Should not crash and should show reasonable zoom level
        expect(find.textContaining('.'), findsOneWidget); // Some zoom level displayed

        // Rapid display mode changes
        for (int i = 0; i < 6; i++) {
          await tester.tap(find.byIcon(Icons.brightness_6));
          await tester.pump();
        }

        // Should cycle through modes without issues
        expect(find.text('Day'), findsOneWidget); // Should be back to day after 3 full cycles
      });
    });

    group('Performance under marine conditions', () {
      testWidgets('should handle large feature sets efficiently', (WidgetTester tester) async {
        // Create a large set of features to simulate dense chart data
        final largeFeatureSet = <MaritimeFeature>[];
        
        // Add many depth contours
        for (int i = 0; i < 100; i++) {
          largeFeatureSet.add(DepthContour(
            id: 'contour_$i',
            coordinates: [
              LatLng(47.6000 + (i * 0.001), -122.3300),
              LatLng(47.6010 + (i * 0.001), -122.3310),
            ],
            depth: (i * 2).toDouble(),
          ));
        }

        // Add many navigation aids
        for (int i = 0; i < 50; i++) {
          largeFeatureSet.add(PointFeature(
            id: 'buoy_$i',
            type: MaritimeFeatureType.buoy,
            position: LatLng(47.6000 + (i * 0.002), -122.3250 + (i * 0.002)),
            label: 'Buoy $i',
          ));
        }

        final widget = ChartWidget(
          initialCenter: testCenter,
          initialZoom: 12.0,
          features: largeFeatureSet,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // Should render without performance issues
        await tester.pump();

        // Open info overlay to check feature counts
        await tester.tap(find.byIcon(Icons.info_outline));
        await tester.pump();

        // Should show correct counts
        expect(find.textContaining('Depth Contours: 100'), findsOneWidget);
        expect(find.textContaining('Buoys: 50'), findsOneWidget);
      });
    });
  });
}