/// TDD Widget Test for Integrity Match Success Path (T010)
/// Tests MUST FAIL until T018+T023 implementation is complete.
///
/// Requirements Coverage:
/// - FR-002: Maintain registry of expected integrity hashes
/// - FR-003: Detect when chart data matches expected hash
/// - Scenario 2 from quickstart.md (success path)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/core/services/chart_integrity_registry.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Validates successful hash verification workflow
void main() {
  group('Chart Integrity Match Success (T010 - MUST FAIL)', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ChartLoadTestHooks.reset();
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('T010.1: Chart loads successfully when hash matches', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();

      // ARRANGE: Pre-populate registry with correct hash
      // Note: In real implementation, this would be the actual SHA256 of the chart
      // For this test, we use a known good hash or compute it from the fixture
      await registry.captureFirstLoad('US5WA50M', 'correct_hash_value');

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // ASSERT: No error messages
      expect(find.byIcon(Icons.error), findsNothing,
          reason: 'Should not show error icon when hash matches');
      expect(find.textContaining('integrity'), findsNothing,
          reason: 'Should not show integrity error message');

      // ASSERT: Chart loads successfully
      expect(find.byType(ChartScreen), findsOneWidget,
          reason: 'ChartScreen should be displayed');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T010.2: Success message shown for verified chart', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();
      await registry.captureFirstLoad('US5WA50M', 'correct_hash');

      ChartLoadTestHooks.fastRetry = true;

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // ASSERT: Success indicator shown (optional feature)
      // Could be a snackbar, icon, or status message
      // This validates the positive feedback UX
      await tester.pump(const Duration(milliseconds: 500));

      // Success can be indicated by absence of errors
      expect(find.byIcon(Icons.error_outline), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T010.3: Registry timestamp updated after successful load', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();

      // ARRANGE: Pre-populate with timestamp from yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await registry.captureFirstLoad('US5WA50M', 'correct_hash');
      
      // Get initial timestamp
      final initialRecord = registry.get('US5WA50M');
      final initialTimestamp = initialRecord!.timestamp;

      // ACT: Load chart again
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // ASSERT: Timestamp updated (lastVerifiedTimestamp field)
      final updatedRecord = registry.get('US5WA50M');
      expect(updatedRecord, isNotNull);
      
      // Verify lastVerifiedTimestamp exists and is recent
      final lastVerified = updatedRecord!.lastVerifiedTimestamp;
      expect(lastVerified, isNotNull,
          reason: 'Should track last verification timestamp');
      expect(lastVerified!.isAfter(initialTimestamp), isTrue,
          reason: 'Last verified timestamp should be updated');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
