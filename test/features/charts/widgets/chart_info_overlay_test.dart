/// Tests for enhanced chart information overlay
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/widgets/chart_info_overlay.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';

void main() {
  group('ChartInfoOverlay', () {
    late List<MaritimeFeature> testFeatures;
    late LatLng testPosition;
    late Map<MaritimeFeatureType, int> testFeatureCounts;
    late Chart testChart;

    setUp(() {
      testPosition = const LatLng(47.6062, -122.3321); // Seattle

      testFeatures = [
        const PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(47.6100, -122.3350),
          label: 'Test Lighthouse',
        ),
        const PointFeature(
          id: 'buoy_1',
          type: MaritimeFeatureType.buoy,
          position: LatLng(47.6050, -122.3300),
          label: 'Test Buoy',
        ),
        const LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: LatLng(47.6000, -122.3250),
          coordinates: [
            LatLng(47.6000, -122.3250),
            LatLng(47.6020, -122.3270),
          ],
        ),
      ];

      testFeatureCounts = {
        MaritimeFeatureType.lighthouse: 1,
        MaritimeFeatureType.buoy: 1,
        MaritimeFeatureType.shoreline: 1,
      };

      testChart = Chart(
        id: 'US5WA50M',
        title: 'Elliott Bay and Seattle Harbor',
        scale: 25000,
        bounds: GeographicBounds(
          north: 47.650,
          south: 47.550,
          east: -122.300,
          west: -122.400,
        ),
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.harbor,
        source: ChartSource.noaa,
      );
    });

    testWidgets('should display basic chart information in compact mode', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        chart: testChart,
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        featureCounts: testFeatureCounts,
        isExpanded: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check header
      expect(find.text('Elliott Bay and Seattle Harbor'), findsOneWidget);
      expect(find.byIcon(Icons.map), findsOneWidget);

      // Check basic position information
      expect(find.textContaining('47°'), findsOneWidget);
      expect(find.textContaining('122°'), findsOneWidget);

      // Check chart scale
      expect(find.text('Harbour (1:25000)'), findsOneWidget);

      // Check zoom level
      expect(find.text('12.0'), findsOneWidget);

      // Check feature summary
      expect(find.text('Features'), findsOneWidget);

      // Check expand/collapse button
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      // Check close button
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should display detailed information in expanded mode', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        chart: testChart,
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        featureCounts: testFeatureCounts,
        isExpanded: true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check for expanded content sections
      expect(find.text('Chart Metadata'), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);
      expect(find.text('Display Settings'), findsOneWidget);

      // Check chart metadata
      expect(find.text('US5WA50M'), findsOneWidget);
      expect(find.text('NOAA'), findsOneWidget);

      // Check navigation info
      expect(find.text('Day Mode'), findsOneWidget);
      expect(find.text('WGS84 Geographic'), findsOneWidget);
      expect(find.text('Mercator'), findsOneWidget);

      // Check display settings
      expect(find.text('S-57/S-52 Compatible'), findsOneWidget);
      expect(find.text('Spatial Indexing Enabled'), findsOneWidget);
      expect(find.text('Marine Standards Compliant'), findsOneWidget);

      // Check collapse button
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('should show feature counts as chips', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        featureCounts: testFeatureCounts,
        isExpanded: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check for feature type chips
      expect(find.text('Lighthouses: 1'), findsOneWidget);
      expect(find.text('Buoys: 1'), findsOneWidget);
      expect(find.text('Shoreline: 1'), findsOneWidget);

      // Check for appropriate icons
      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
      expect(find.byIcon(Icons.anchor), findsOneWidget);
      expect(find.byIcon(Icons.landscape), findsOneWidget);
    });

    testWidgets('should handle toggle expand/collapse', (WidgetTester tester) async {
      bool toggleCalled = false;

      final widget = ChartInfoOverlay(
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        isExpanded: false,
        onToggleExpanded: () => toggleCalled = true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Test expand button
      await tester.tap(find.byIcon(Icons.expand_more));
      expect(toggleCalled, isTrue);
    });

    testWidgets('should handle close action', (WidgetTester tester) async {
      bool closeCalled = false;

      final widget = ChartInfoOverlay(
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        onClose: () => closeCalled = true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Test close button
      await tester.tap(find.byIcon(Icons.close));
      expect(closeCalled, isTrue);
    });

    testWidgets('should format coordinates correctly', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check coordinate formatting
      expect(find.textContaining('47°36.372\' N'), findsOneWidget);
      expect(find.textContaining('122°19.926\' W'), findsOneWidget);
    });

    testWidgets('should display different display modes correctly', (WidgetTester tester) async {
      // Test day mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChartInfoOverlay(
            features: testFeatures,
            currentPosition: testPosition,
            zoom: 12.0,
            displayMode: ChartDisplayMode.dayMode,
            chartScale: ChartScale.harbour,
            isExpanded: true,
          ),
        ),
      ));
      expect(find.text('Day Mode'), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);

      // Test night mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChartInfoOverlay(
            features: testFeatures,
            currentPosition: testPosition,
            zoom: 12.0,
            displayMode: ChartDisplayMode.nightMode,
            chartScale: ChartScale.harbour,
            isExpanded: true,
          ),
        ),
      ));
      expect(find.text('Night Mode'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      // Test dusk mode
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChartInfoOverlay(
            features: testFeatures,
            currentPosition: testPosition,
            zoom: 12.0,
            displayMode: ChartDisplayMode.duskMode,
            chartScale: ChartScale.harbour,
            isExpanded: true,
          ),
        ),
      ));
      expect(find.text('Dusk Mode'), findsOneWidget);
      expect(find.byIcon(Icons.brightness_4), findsOneWidget);
    });

    testWidgets('should handle missing chart data gracefully', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        // No chart provided
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        isExpanded: true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Should show default title
      expect(find.text('Marine Chart'), findsOneWidget);

      // Should still show basic navigation info
      expect(find.text('Navigation'), findsOneWidget);
    });

    testWidgets('should show chart bounds in expanded mode', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        chart: testChart,
        features: testFeatures,
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
        isExpanded: true,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Check for formatted bounds
      expect(find.textContaining('N:47.65°'), findsOneWidget);
      expect(find.textContaining('S:47.55°'), findsOneWidget);
      expect(find.textContaining('E:-122.30°'), findsOneWidget);
      expect(find.textContaining('W:-122.40°'), findsOneWidget);
    });

    testWidgets('should handle empty feature list', (WidgetTester tester) async {
      final widget = ChartInfoOverlay(
        features: [], // Empty features
        currentPosition: testPosition,
        zoom: 12.0,
        displayMode: ChartDisplayMode.dayMode,
        chartScale: ChartScale.harbour,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      // Should show 0 features
      expect(find.text('0 features loaded'), findsOneWidget);
    });

    testWidgets('should animate size changes', (WidgetTester tester) async {
      bool isExpanded = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ChartInfoOverlay(
                features: testFeatures,
                currentPosition: testPosition,
                zoom: 12.0,
                displayMode: ChartDisplayMode.dayMode,
                chartScale: ChartScale.harbour,
                isExpanded: isExpanded,
                onToggleExpanded: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
              );
            },
          ),
        ),
      ));

      // Initial state - compact
      final initialSize = tester.getSize(find.byType(AnimatedContainer));
      expect(initialSize.width, equals(280));

      // Toggle expansion
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150)); // Mid-animation

      // Should be animating
      final midSize = tester.getSize(find.byType(AnimatedContainer));
      expect(midSize.width, greaterThan(280));

      // Complete animation
      await tester.pump(const Duration(milliseconds: 300));
      final finalSize = tester.getSize(find.byType(AnimatedContainer));
      expect(finalSize.width, equals(380));
    });

    group('Marine environment requirements', () {
      testWidgets('should use appropriate text sizes for marine use', (WidgetTester tester) async {
        final widget = ChartInfoOverlay(
          features: testFeatures,
          currentPosition: testPosition,
          zoom: 12.0,
          displayMode: ChartDisplayMode.dayMode,
          chartScale: ChartScale.harbour,
          isExpanded: true,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // Text should be readable in marine conditions
        final texts = tester.widgetList<Text>(find.byType(Text));
        for (final text in texts) {
          if (text.style?.fontSize != null) {
            expect(text.style!.fontSize!, greaterThanOrEqualTo(10.0));
          }
        }
      });

      testWidgets('should have high contrast for sunlight visibility', (WidgetTester tester) async {
        final widget = ChartInfoOverlay(
          features: testFeatures,
          currentPosition: testPosition,
          zoom: 12.0,
          displayMode: ChartDisplayMode.dayMode,
          chartScale: ChartScale.harbour,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // Check for appropriate elevation
        final card = tester.widget<Card>(find.byType(Card));
        expect(card.elevation, greaterThanOrEqualTo(8.0));
      });
    });

    group('Feature type handling', () {
      testWidgets('should handle all maritime feature types', (WidgetTester tester) async {
        final allFeatureTypes = {
          MaritimeFeatureType.lighthouse: 2,
          MaritimeFeatureType.beacon: 3,
          MaritimeFeatureType.buoy: 5,
          MaritimeFeatureType.daymark: 1,
          MaritimeFeatureType.depthContour: 10,
          MaritimeFeatureType.shoreline: 2,
          MaritimeFeatureType.landArea: 1,
          MaritimeFeatureType.anchorage: 2,
          MaritimeFeatureType.restrictedArea: 1,
        };

        final widget = ChartInfoOverlay(
          features: testFeatures,
          currentPosition: testPosition,
          zoom: 12.0,
          displayMode: ChartDisplayMode.dayMode,
          chartScale: ChartScale.harbour,
          featureCounts: allFeatureTypes,
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: widget),
        ));

        // Check that all feature types are displayed
        expect(find.text('Lighthouses: 2'), findsOneWidget);
        expect(find.text('Beacons: 3'), findsOneWidget);
        expect(find.text('Buoys: 5'), findsOneWidget);
        expect(find.text('Daymarks: 1'), findsOneWidget);
        expect(find.text('Depth Contours: 10'), findsOneWidget);
        expect(find.text('Shoreline: 2'), findsOneWidget);
        expect(find.text('Land Areas: 1'), findsOneWidget);
        expect(find.text('Anchorages: 2'), findsOneWidget);
        expect(find.text('Restricted Areas: 1'), findsOneWidget);
      });
    });
  });
}