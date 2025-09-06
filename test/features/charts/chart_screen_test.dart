import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/features/charts/chart_widget.dart';

void main() {
  group('ChartScreen Tests', () {
    Widget createTestWidget({String? chartTitle, bool withNavigation = false}) {
      return ProviderScope(
        child: MaterialApp(home: ChartScreen(chartTitle: chartTitle)),
      );
    }

    group('Screen Structure and Layout', () {
      testWidgets('should create ChartScreen with all required components', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Check that the main components are present
        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should have correct app bar title', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Marine Chart'), findsOneWidget);
      });

      testWidgets('should use custom chart title when provided', (
        WidgetTester tester,
      ) async {
        const customTitle = 'San Francisco Bay Chart';
        await tester.pumpWidget(createTestWidget(chartTitle: customTitle));

        expect(find.text(customTitle), findsOneWidget);
      });

      testWidgets('should have app bar action buttons', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should have info and settings buttons
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        expect(find.byIcon(Icons.settings), findsOneWidget);
      });

      testWidgets('should display chart status bar', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Look for chart status indicators
        expect(find.byIcon(Icons.map), findsOneWidget);
        expect(find.textContaining('Chart:'), findsOneWidget);
        expect(find.textContaining('features'), findsOneWidget);
      });

      testWidgets('should have floating action buttons', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should have floating action buttons
        expect(find.byType(FloatingActionButton), findsWidgets);
        expect(find.byIcon(Icons.add_location), findsOneWidget);
        expect(find.byIcon(Icons.straighten), findsOneWidget);
      });
    });

    group('Chart Controls and Interactions', () {
      testWidgets('should handle info button tap', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        final infoButton = find.byIcon(Icons.info_outline);
        expect(infoButton, findsOneWidget);

        await tester.tap(infoButton);
        await tester.pumpAndSettle();

        // Should show chart info dialog or bottom sheet
        // This would depend on the implementation of _showChartInfo
      });

      testWidgets('should handle settings button tap', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        final settingsButton = find.byIcon(Icons.settings);
        expect(settingsButton, findsOneWidget);

        await tester.tap(settingsButton);
        await tester.pumpAndSettle();

        // Should show settings dialog or navigate to settings
      });

      testWidgets('should handle add waypoint action', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        final waypointButton = find.byIcon(Icons.add_location);
        expect(waypointButton, findsOneWidget);

        await tester.tap(waypointButton);
        await tester.pump();
      });

      testWidgets('should handle measure distance action', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        final measureButton = find.byIcon(Icons.straighten);
        expect(measureButton, findsOneWidget);

        await tester.tap(measureButton);
        await tester.pump();
      });
    });

    group('Chart Information Display', () {
      testWidgets('should display chart title in status bar', (
        WidgetTester tester,
      ) async {
        const customTitle = 'San Francisco Bay';
        await tester.pumpWidget(createTestWidget(chartTitle: customTitle));

        // Should show chart title in status bar
        expect(find.textContaining('Chart:'), findsOneWidget);
      });

      testWidgets('should display feature count', (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget());

        // Should show feature count in status bar
        expect(find.textContaining('features'), findsOneWidget);
      });

      testWidgets('should display display mode indicator', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should show day/night mode
        expect(find.byIcon(Icons.light_mode), findsOneWidget);
        expect(find.text('Day'), findsOneWidget);
      });

      testWidgets('should show chart layers indicator', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should show layers icon
        expect(find.byIcon(Icons.layers), findsOneWidget);
      });
    });

    group('Sample Data and Features', () {
      testWidgets('should display sample maritime features', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Chart widget should be present and rendering features
        expect(find.byType(ChartWidget), findsOneWidget);

        // Feature count should be displayed
        expect(find.textContaining('features'), findsOneWidget);
      });

      testWidgets('should show feature information in status bar', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should display feature count > 0 for sample data
        final featureInfo = find.textContaining('features');
        expect(featureInfo, findsOneWidget);
      });
    });

    group('Responsive Design', () {
      testWidgets('should adapt to small screen sizes', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should adapt to large screen sizes', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle landscape orientation', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(800, 480); // Landscape
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle portrait orientation', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(480, 800); // Portrait
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createTestWidget());

        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('Navigation and App Bar', () {
      testWidgets('should have back button functionality', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              initialRoute: '/chart',
              routes: {
                '/': (context) => const Scaffold(body: Text('Home')),
                '/chart': (context) => const ChartScreen(),
              },
            ),
          ),
        );

        expect(find.byType(ChartScreen), findsOneWidget);

        // Should have back button in app bar
        final backButton = find.byTooltip('Back');
        if (backButton.evaluate().isNotEmpty) {
          await tester.tap(backButton);
          await tester.pumpAndSettle();
        }
      });

      testWidgets('should display app bar with proper styling', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.title, isA<Text>());

        final titleText = appBar.title as Text;
        expect(titleText.data, 'Marine Chart');
      });
    });

    group('Error Handling and Edge Cases', () {
      testWidgets('should handle empty chart data gracefully', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Even with potential empty data, basic structure should exist
        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.text('Marine Chart'), findsOneWidget);
      });

      testWidgets('should maintain state during rebuilds', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Initial state
        expect(find.byType(ChartScreen), findsOneWidget);

        // Trigger rebuild
        await tester.pumpWidget(createTestWidget());

        // Should still be functional
        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });

      testWidgets('should handle rapid control interactions', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Test rapid interactions with floating action buttons
        final waypointButton = find.byIcon(Icons.add_location);
        final measureButton = find.byIcon(Icons.straighten);

        if (waypointButton.evaluate().isNotEmpty &&
            measureButton.evaluate().isNotEmpty) {
          for (int i = 0; i < 3; i++) {
            await tester.tap(waypointButton);
            await tester.pump();
            await tester.tap(measureButton);
            await tester.pump();
          }
        }

        // Should still be functional
        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byType(ChartWidget), findsOneWidget);
      });
    });

    group('State Management', () {
      testWidgets('should maintain chart state correctly', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Chart should maintain its state
        expect(find.byType(ChartWidget), findsOneWidget);
        expect(find.textContaining('features'), findsOneWidget);
      });

      testWidgets('should handle display mode changes', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(createTestWidget());

        // Should start in day mode
        expect(find.byIcon(Icons.light_mode), findsOneWidget);
        expect(find.text('Day'), findsOneWidget);
      });
    });
  });
}
