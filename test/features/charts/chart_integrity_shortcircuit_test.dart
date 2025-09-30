import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';

void main() {
  group('Chart Integrity Short-Circuit', () {
    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('sets lastErrorType to integrity when forced', (tester) async {
      // Enable the deterministic test-only hook
      ChartLoadTestHooks.forceIntegrityMismatch = true;

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));

      // Allow the microtask to run
      await tester.pump();

      expect(ChartLoadTestHooks.lastErrorType, 'integrity');
    });
  });
}
