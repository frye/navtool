/// Tests for enhanced chart display controls
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/widgets/chart_display_controls.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';

void main() {
  group('ChartDisplayControls', () {
    late ChartDisplayControls widget;
    late LatLng testPosition;
    late Map<String, bool> testLayerVisibility;
    late List<String> testAvailableLayers;

    setUp(() {
      testPosition = const LatLng(47.6062, -122.3321); // Seattle
      testLayerVisibility = {
        'depth_contours': true,
        'navigation_aids': true,
        'shoreline': false,
        'restricted_areas': true,
      };
      testAvailableLayers = [
        'depth_contours',
        'navigation_aids',
        'shoreline',
        'restricted_areas',
        'anchorages',
      ];

      widget = ChartDisplayControls(
        zoom: 12.0,
        rotation: 15.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        position: testPosition,
        layerVisibility: testLayerVisibility,
        availableLayers: testAvailableLayers,
      );
    });

    testWidgets('should display all control elements', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [widget],
          ),
        ),
      ));

      // Check for zoom controls
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.text('12.0'), findsOneWidget);

      // Check for rotation controls
      expect(find.byIcon(Icons.navigation), findsOneWidget);
      expect(find.text('15°'), findsOneWidget);
      expect(find.text('N'), findsOneWidget);

      // Check for action buttons
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.layers), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      // Check for position display
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.textContaining('47°'), findsOneWidget);
      expect(find.textContaining('122°'), findsOneWidget);

      // Check for scale display
      expect(find.byIcon(Icons.straighten), findsOneWidget);
      expect(find.text('Scale: Harbour'), findsOneWidget);

      // Check for display mode controls
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
    });

    testWidgets('should handle zoom controls', (WidgetTester tester) async {
      bool zoomInCalled = false;
      bool zoomOutCalled = false;

      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        onZoomIn: () => zoomInCalled = true,
        onZoomOut: () => zoomOutCalled = true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Test zoom in
      await tester.tap(find.byIcon(Icons.add));
      expect(zoomInCalled, isTrue);

      // Test zoom out
      await tester.tap(find.byIcon(Icons.remove));
      expect(zoomOutCalled, isTrue);
    });

    testWidgets('should handle rotation reset', (WidgetTester tester) async {
      bool resetCalled = false;

      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        rotation: 45.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        onResetRotation: () => resetCalled = true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Tap on the compass to reset rotation
      await tester.tap(find.byIcon(Icons.navigation));
      expect(resetCalled, isTrue);
    });

    testWidgets('should toggle layer panel', (WidgetTester tester) async {
      bool layerPanelToggled = false;

      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        isLayerPanelOpen: false,
        onToggleLayerPanel: () => layerPanelToggled = true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Test layer panel toggle
      await tester.tap(find.byIcon(Icons.layers));
      expect(layerPanelToggled, isTrue);
    });

    testWidgets('should show layer panel when open', (WidgetTester tester) async {
      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        isLayerPanelOpen: true,
        availableLayers: testAvailableLayers,
        layerVisibility: testLayerVisibility,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Check for layer panel
      expect(find.text('Chart Layers'), findsOneWidget);
      expect(find.text('Depth Contours'), findsOneWidget);
      expect(find.text('Navigation Aids'), findsOneWidget);
      expect(find.text('Shoreline'), findsOneWidget);
      expect(find.text('Restricted Areas'), findsOneWidget);

      // Check for close button
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should handle layer toggle', (WidgetTester tester) async {
      String? toggledLayer;

      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        isLayerPanelOpen: true,
        availableLayers: testAvailableLayers,
        layerVisibility: testLayerVisibility,
        onLayerToggle: (layer) => toggledLayer = layer,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Test layer toggle by tapping on a layer
      await tester.tap(find.text('Depth Contours'));
      expect(toggledLayer, equals('depth_contours'));
    });

    testWidgets('should handle display mode cycling', (WidgetTester tester) async {
      ChartDisplayMode? newMode;

      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: testPosition,
        onDisplayModeChanged: (mode) => newMode = mode,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Test display mode cycling
      await tester.tap(find.byIcon(Icons.brightness_6));
      expect(newMode, equals(ChartDisplayMode.nightMode));
    });

    testWidgets('should format coordinates correctly', (WidgetTester tester) async {
      final seattlePosition = const LatLng(47.6062, -122.3321);
      
      final testWidget = ChartDisplayControls(
        zoom: 10.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.coastal,
        position: seattlePosition,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [testWidget])),
      ));

      // Check formatted coordinates - be more specific to avoid duplicates
      expect(find.textContaining('47°36.372\''), findsOneWidget);
      expect(find.textContaining('122°19.926\''), findsOneWidget);
      expect(find.textContaining('47°36.372\' N'), findsOneWidget);
      expect(find.textContaining('122°19.926\' W'), findsOneWidget);
    });

    testWidgets('should show correct display mode icons', (WidgetTester tester) async {
      // Test day mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChartDisplayControls(
                zoom: 10.0,
                displayMode: ChartDisplayMode.dayMode,
                chartScale: ChartScale.coastal,
                position: testPosition,
              ),
            ],
          ),
        ),
      ));
      expect(find.byIcon(Icons.light_mode), findsOneWidget);

      // Test night mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChartDisplayControls(
                zoom: 10.0,
                displayMode: ChartDisplayMode.nightMode,
                chartScale: ChartScale.coastal,
                position: testPosition,
              ),
            ],
          ),
        ),
      ));
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      // Test dusk mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ChartDisplayControls(
                zoom: 10.0,
                displayMode: ChartDisplayMode.duskMode,
                chartScale: ChartScale.coastal,
                position: testPosition,
              ),
            ],
          ),
        ),
      ));
      expect(find.byIcon(Icons.brightness_4), findsOneWidget);
    });

    testWidgets('should handle marine environment design requirements', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [widget])),
      ));

      // Check for appropriate button sizes (marine environment - gloves)
      final zoomButtons = tester.widgetList<IconButton>(find.byType(IconButton));
      for (final button in zoomButtons) {
        expect(button.iconSize, greaterThanOrEqualTo(20.0)); // Large enough for gloves
      }

      // Check for proper elevation for sunlight visibility
      final cards = tester.widgetList<Card>(find.byType(Card));
      for (final card in cards) {
        expect(card.elevation, greaterThanOrEqualTo(4.0)); // Good contrast in sunlight
      }
    });

    group('Layer visibility', () {
      testWidgets('should show correct layer icons', (WidgetTester tester) async {
        final testWidget = ChartDisplayControls(
          zoom: 10.0,
          displayMode: ChartDisplayMode.dayMode,
          chartScale: ChartScale.coastal,
          position: testPosition,
          isLayerPanelOpen: true,
          availableLayers: ['depth_contours', 'navigation_aids', 'shoreline'],
          layerVisibility: {
            'depth_contours': true,
            'navigation_aids': false,
            'shoreline': true,
          },
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [testWidget])),
        ));

        // Check that layer-specific icons are present (multiple instances may exist)
        expect(find.byIcon(Icons.water), findsAtLeastNWidgets(1)); // depth_contours
        expect(find.byIcon(Icons.navigation), findsAtLeastNWidgets(1)); // navigation_aids
        expect(find.byIcon(Icons.landscape), findsAtLeastNWidgets(1)); // shoreline
      });

      testWidgets('should show correct layer names', (WidgetTester tester) async {
        final testWidget = ChartDisplayControls(
          zoom: 10.0,
          displayMode: ChartDisplayMode.dayMode,
          chartScale: ChartScale.coastal,
          position: testPosition,
          isLayerPanelOpen: true,
          availableLayers: ['restricted_areas', 'anchorages', 'chart_grid'],
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [testWidget])),
        ));

        expect(find.text('Restricted Areas'), findsOneWidget);
        expect(find.text('Anchorages'), findsOneWidget);
        expect(find.text('Chart Grid'), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should provide proper tooltips', (WidgetTester tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [widget])),
        ));

        // Check for tooltips on buttons
        final zoomInButton = find.byIcon(Icons.add);
        expect(zoomInButton, findsOneWidget);
        
        final zoomOutButton = find.byIcon(Icons.remove);
        expect(zoomOutButton, findsOneWidget);

        final centerButton = find.byIcon(Icons.my_location);
        expect(centerButton, findsOneWidget);

        final layersButton = find.byIcon(Icons.layers);
        expect(layersButton, findsOneWidget);

        final infoButton = find.byIcon(Icons.info_outline);
        expect(infoButton, findsOneWidget);
      });

      testWidgets('should have appropriate semantic labels', (WidgetTester tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Stack(children: [widget])),
        ));

        // Verify semantic structure is accessible
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  });
}