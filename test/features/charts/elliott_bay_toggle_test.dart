import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';

void main() {
  group('Elliott Bay Charts Toggle', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('should show Elliott Bay test charts banner when toggle enabled', (tester) async {
      await pumpChartBrowserScreen(tester);

      // The banner should be visible by default (toggle enabled)
      expect(find.text('Including Elliott Bay test charts (US5WA50M, US3WA01M)'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });

    testWidgets('should hide Elliott Bay test charts banner when toggle disabled', (tester) async {
      // Set initial state to disabled
      SharedPreferences.setMockInitialValues({'include_test_charts': false});
      
      await pumpChartBrowserScreen(tester);
      await tester.pumpAndSettle();

      // The banner should not be visible when toggle is disabled
      expect(find.text('Including Elliott Bay test charts (US5WA50M, US3WA01M)'), findsNothing);
    });

    testWidgets('should toggle Elliott Bay charts visibility via settings menu', (tester) async {
      await pumpChartBrowserScreen(tester);

      // Find and tap the settings menu
      final settingsButton = find.byType(PopupMenuButton<String>);
      expect(settingsButton, findsOneWidget);
      
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      // Should show the toggle option with "Hide" text (since it's currently enabled)
      expect(find.text('Hide Elliott Bay Charts'), findsOneWidget);
      
      // Tap the toggle option
      await tester.tap(find.text('Hide Elliott Bay Charts'));
      await tester.pumpAndSettle();

      // Banner should now be hidden
      expect(find.text('Including Elliott Bay test charts (US5WA50M, US3WA01M)'), findsNothing);
      
      // Open settings menu again
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      // Should now show "Show" text
      expect(find.text('Show Elliott Bay Charts'), findsOneWidget);
    });

    testWidgets('should preserve toggle state across app restarts', (tester) async {
      // Start with toggle disabled
      SharedPreferences.setMockInitialValues({'include_test_charts': false});
      
      await pumpChartBrowserScreen(tester);
      await tester.pumpAndSettle();

      // Banner should not be visible
      expect(find.text('Including Elliott Bay test charts (US5WA50M, US3WA01M)'), findsNothing);
      
      // Restart the app (pump new instance)
      await pumpChartBrowserScreen(tester);
      await tester.pumpAndSettle();

      // State should be preserved
      expect(find.text('Including Elliott Bay test charts (US5WA50M, US3WA01M)'), findsNothing);
    });

    test('Washington test charts should return correct charts for Washington state', () {
      final washingtonCharts = WashingtonTestCharts.getChartsForState('Washington');
      expect(washingtonCharts.length, equals(6)); // 2 Elliott Bay + 4 synthetic
      
      // Should include the two Elliott Bay charts
      final elliottBayIds = washingtonCharts.map((c) => c.id).toList();
      expect(elliottBayIds, contains('US5WA50M'));
      expect(elliottBayIds, contains('US3WA01M'));
    });

    test('Chart priority comparator should sort Harbor charts first', () {
      final charts = WashingtonTestCharts.getAllCharts();
      final harborChart = charts.firstWhere((c) => c.id == 'US5WA50M'); // Harbor type
      final coastalChart = charts.firstWhere((c) => c.id == 'US3WA01M'); // Coastal type
      
      // Harbor charts should have higher priority (lower number)
      expect(harborChart.typePriority, lessThan(coastalChart.typePriority));
    });
  });
}

/// Helper function to pump the ChartBrowserScreen with required providers
Future<void> pumpChartBrowserScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: const ChartBrowserScreen(),
      ),
    ),
  );
}