import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';

/// Validates auto-retry behavior for transient parsing failures using test hooks.
void main() {
  group('Chart Transient Retry', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('auto-retries transient parsing failures then succeeds', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture for transient retry test: ' + zipPath);
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      // Fail first two parse attempts, success on third.
      ChartLoadTestHooks.failParsingAttempts = 2;
      ChartLoadTestHooks.fastRetry = true; // accelerate retry delays

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));

      // Initial frame
      await tester.pump();

      // Allow time for first failure and scheduled retry
      await tester.pump(const Duration(milliseconds: 120));
      // Should have overlay error at least once
      expect(find.byKey(const Key('chart-loading-overlay')), findsWidgets);

      // Let second attempt run and fail, then third succeed
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      // Eventually the overlay should disappear (load complete) OR show complete state with check icon
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Success criteria: either overlay gone or complete state with check icon
      final overlayStillVisible = find.byKey(const Key('chart-loading-overlay')).evaluate().isNotEmpty;
      if (overlayStillVisible) {
        // If still visible it must be complete (no error icon)
        expect(find.byIcon(Icons.error_outline), findsNothing, reason: 'Should not remain in error state after retries');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
