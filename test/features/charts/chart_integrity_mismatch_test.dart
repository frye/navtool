/// TDD Widget Test for Integrity Mismatch Error UI (T011 - ENHANCED)
/// Tests MUST FAIL until T024 implementation is complete.
///
/// Requirements Coverage:
/// - FR-001: Detect and report integrity mismatch
/// - FR-012: Show retry/dismiss buttons in error dialog
/// - Scenario 3 from quickstart.md (integrity mismatch)
library;

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
  group('Chart Integrity Mismatch (T011 - ENHANCED)', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('LEGACY: forces integrity mismatch error path', (tester) async {
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

    testWidgets('T011.1: Error dialog appears with retry and dismiss buttons', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      ChartIntegrityRegistry().seed({'US5WA50M': 'DEADBEEF'});
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // Wait for error dialog to appear
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Error dialog displayed
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'Should show error dialog for integrity mismatch');

      // ASSERT: Dialog contains error details
      expect(find.textContaining('integrity'), findsOneWidget,
          reason: 'Error dialog should mention integrity issue');
      expect(find.textContaining('US5WA50M'), findsOneWidget,
          reason: 'Error dialog should mention chart ID');

      // ASSERT: Retry button present
      final retryButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Retry'),
      );
      expect(retryButton, findsOneWidget,
          reason: 'Error dialog must have Retry button');

      // ASSERT: Dismiss button present
      final dismissButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Dismiss'),
      );
      expect(dismissButton, findsOneWidget,
          reason: 'Error dialog must have Dismiss button');
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T011.2: Retry button triggers new load attempt', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      ChartIntegrityRegistry().seed({'US5WA50M': 'DEADBEEF'});
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Find and tap retry button
      final retryButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Retry'),
      );

      // ACT: Tap retry button
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      // ASSERT: Dialog dismissed
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Dialog should close after retry button tap');

      // ASSERT: Loading overlay appears (new attempt started)
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Should show loading indicator for retry attempt');
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T011.3: Dismiss button closes dialog and returns', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      ChartIntegrityRegistry().seed({'US5WA50M': 'DEADBEEF'});
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Find and tap dismiss button
      final dismissButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Dismiss'),
      );

      // ACT: Tap dismiss button
      await tester.tap(dismissButton);
      await tester.pumpAndSettle();

      // ASSERT: Dialog dismissed
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Dialog should close after dismiss button tap');

      // ASSERT: No loading overlay (not retrying)
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Should not start loading after dismiss');
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T011.4: Chart does NOT render when integrity fails', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      ChartIntegrityRegistry().seed({'US5WA50M': 'DEADBEEF'});
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Error dialog is visible
      expect(find.byType(AlertDialog), findsOneWidget);

      // ASSERT: Chart features NOT rendered
      // (Looking for absence of chart-specific widgets)
      // This would check for absence of maritime feature layers, depth contours, etc.
      expect(find.textContaining('features loaded'), findsNothing,
          reason: 'Should not show feature count for failed chart load');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
