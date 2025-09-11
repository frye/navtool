import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';

void main() {
  group('Chart Info Dialog (Real ENC)', () {
    const zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';

    testWidgets('displays real feature stats and metadata', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC fixture: ' + zipPath);
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));

      // Allow parsing
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Open info dialog
      await tester.tap(find.byTooltip('Chart Information'));
      await tester.pumpAndSettle();

      expect(find.text('Chart Information'), findsOneWidget);
      expect(find.textContaining(chart.id), findsWidgets);

      // Should show feature count row text
      expect(find.textContaining('Feature Count'), findsWidgets);

      // Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
