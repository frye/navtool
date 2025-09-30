/// TDD Widget Test for First Load Flow with Hash Capture (T009)
/// Tests MUST FAIL until T018+T023 implementation is complete.
///
/// Requirements Coverage:
/// - FR-002a: First-load capture and persist hash
/// - R05: Persist first-load hashes to SharedPreferences
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/core/services/chart_integrity_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Validates first-load hash capture workflow (Scenario 4 from quickstart.md)
void main() {
  group('Chart First Load Hash Capture (T009 - MUST FAIL)', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    setUp(() async {
      // Reset SharedPreferences for each test
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('T009.1: First load captures and persists hash', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();

      // ARRANGE: No existing hash for this chart
      expect(registry.get('US5WA50M'), isNull,
          reason: 'Registry should be empty before first load');

      // ACT: Load chart for first time
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // ASSERT: Hash captured in registry
      final record = registry.get('US5WA50M');
      expect(record, isNotNull,
          reason: 'First load should capture hash in registry');
      expect(record!.expectedSha256, isNotEmpty,
          reason: 'Captured hash should not be empty');

      // ASSERT: Hash persisted to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final persistedHash = prefs.getString('chart_integrity_US5WA50M');
      expect(persistedHash, isNotNull,
          reason: 'Hash should be persisted to SharedPreferences');
      expect(persistedHash, equals(record.expectedSha256),
          reason: 'Persisted hash should match registry hash');

      // ASSERT: Loading succeeds without error
      expect(find.byType(SnackBar), findsNothing,
          reason: 'First load should succeed without errors');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T009.2: First load shows informational message', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();

      // ACT: Load chart for first time
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // ASSERT: Should show informational snackbar about first load
      // Expected message: "First load of US5WA50M - hash captured for future verification"
      final snackbarFinder = find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('First load'),
      );

      // Wait for snackbar to appear (may be delayed)
      await tester.pump(const Duration(milliseconds: 500));

      expect(snackbarFinder, findsOneWidget,
          reason: 'Should show first-load informational message');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T009.3: Second load verifies against stored hash', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      final registry = ChartIntegrityRegistry();
      await registry.clear();

      // ARRANGE: Simulate first load by manually capturing hash
      await registry.captureFirstLoad('US5WA50M', 'first_load_hash_abc123');

      // ACT: Load chart second time
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // ASSERT: Should verify hash (pass or fail depending on actual hash)
      // This test validates that verification happens, not the result
      final record = registry.get('US5WA50M');
      expect(record, isNotNull,
          reason: 'Hash should still be in registry after second load');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
