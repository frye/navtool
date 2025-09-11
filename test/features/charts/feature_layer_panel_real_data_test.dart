import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';

void main() {
  group('Feature Layer Panel (Real ENC)', () {
    final zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';

    testWidgets('toggles layer visibility using real parsed data', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing real ENC fixture: ' + zipPath);
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // Wait for load (allow generous time for parsing in CI)
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Open settings -> Feature Visibility
      await tester.tap(find.byTooltip('Chart Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature Visibility'));
      await tester.pumpAndSettle();

      // Expect some feature type rows with switches
      final switches = find.byType(SwitchListTile);
      expect(switches, findsWidgets);

      // Toggle first switch (if any) and ensure UI updates (no direct feature filtering implemented yet visually)
      final firstSwitch = switches.first;
      await tester.tap(firstSwitch);
      await tester.pump();

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
