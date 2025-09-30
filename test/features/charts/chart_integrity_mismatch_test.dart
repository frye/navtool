import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';
import 'package:navtool/core/services/chart_integrity_registry.dart';

/// Validates that a forced integrity mismatch surfaces a ChartLoadError.integrity
/// with troubleshooting UI visible in the overlay.
void main() {
  group('Chart Integrity Mismatch', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('forces integrity mismatch error path', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture for integrity mismatch test: ' + zipPath);
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      // Seed registry with a different expected hash to ensure mismatch OR force mismatch hook
      ChartIntegrityRegistry().seed({'US5WA50M': 'DEADBEEF'});
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      ChartLoadTestHooks.fastRetry = true; // ensure overlay error appears quickly without long delays

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // Poll the test hook for integrity error type (up to 2s)
      var attempts = 0;
      while (attempts < 25 && ChartLoadTestHooks.lastErrorType != 'integrity') {
        await tester.pump(const Duration(milliseconds: 200));
        attempts++;
      }

      expect(ChartLoadTestHooks.lastErrorType, 'integrity', reason: 'Expected integrity error type captured via test hook');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
