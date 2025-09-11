import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';

/// Real ENC data widget test validating loading overlay stages with actual NOAA ENC fixture
void main() {
  group('Chart Loading Overlay (Real ENC Data)', () {
    late String elliottBayZipPath;

    setUpAll(() async {
      elliottBayZipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
      if (!File(elliottBayZipPath).existsSync()) {
        // Provide clear guidance if fixture missing
        print('[RealDataTest] MISSING required ENC fixture: ' + elliottBayZipPath);
      } else {
        // Quick parse smoke test to confirm viability before widget pumping
        final parsed = await S57Parser.loadFromZip(elliottBayZipPath);
        print('[RealDataTest] Pre-parse success. Feature count: ${parsed.features.length}');
      }
    });

    testWidgets('shows staged loading messages and real feature count', (tester) async {
      if (!File(elliottBayZipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Real ENC test fixture missing; see README in noaa_enc directory.');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final app = MaterialApp(home: ChartScreen(chart: chart));

      await tester.pumpWidget(app);

      // Initial frame
      await tester.pump();

      // Expect an initial loading stage message (current implementation phrase may evolve)
      expect(
        find.textContaining('Loading'),
        findsWidgets,
        reason: 'Should show at least one loading stage message',
      );

      // Allow time for parse + conversion pipeline (progress stages should update)
      await tester.pump(const Duration(seconds: 2));

      // After some progress, we should still have a loading/progress indicator unless parsing is extremely fast
      // We accept either in-progress or completed state; if completed we assert feature stats present
      final progressStillVisible = find.textContaining('Loading').evaluate().isNotEmpty;

      if (!progressStillVisible) {
        // Loading finished quickly; verify feature stats UI artifacts
        final featureCountFinder = find.textContaining('features');
        expect(featureCountFinder, findsWidgets, reason: 'Feature statistics should appear after load completes');
      }

      // Settle up to 8 more seconds for slower CI runs
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Final assertions: no fatal fallback message, real feature indicators present
      expect(find.textContaining('chart boundary only'), findsNothing);
      expect(find.textContaining('S-57 feature loading may be incomplete'), findsNothing);
      expect(find.textContaining('features'), findsWidgets);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
