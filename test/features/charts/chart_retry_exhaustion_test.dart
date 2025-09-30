/// TDD Widget Test for Retry Exhaustion Flow (T013)
/// Tests MUST FAIL until T019+T024 implementation is complete.
///
/// Requirements Coverage:
/// - FR-009: Max 4 retry attempts
/// - FR-012: Failure reporting with retry/dismiss options
/// - Scenario 5 from quickstart.md (retry exhaustion)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';

/// Validates retry exhaustion behavior after max attempts
void main() {
  group('Chart Retry Exhaustion (T013 - MUST FAIL)', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('T013.1: Max 4 retries enforced, then stops', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      // ARRANGE: Fail 5 times (should stop after 4 retries)
      ChartLoadTestHooks.failParsingAttempts = 5;
      ChartLoadTestHooks.fastRetry = true;

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // Allow retries to run
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Error dialog appears with exhaustion message
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'Should show error dialog after exhaustion');
      expect(find.textContaining('4 attempts'), findsOneWidget,
          reason: 'Should mention 4 attempts in error message');
      expect(find.textContaining('retry'), findsWidgets,
          reason: 'Should mention retry exhaustion');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T013.2: Error dialog has Retry button', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      ChartLoadTestHooks.failParsingAttempts = 5;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Retry button present
      final retryButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Retry'),
      );
      expect(retryButton, findsOneWidget,
          reason: 'Should have Retry button in error dialog');

      // ACT: Tap retry button
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      // ASSERT: Dialog dismissed, loading restarts
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Dialog should close after retry');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T013.3: Error dialog has Dismiss button', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      ChartLoadTestHooks.failParsingAttempts = 5;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Dismiss button present
      final dismissButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Dismiss'),
      );
      expect(dismissButton, findsOneWidget,
          reason: 'Should have Dismiss button in error dialog');

      // ACT: Tap dismiss button
      await tester.tap(dismissButton);
      await tester.pumpAndSettle();

      // ASSERT: Dialog dismissed, returns to chart browser
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Dialog should close after dismiss');
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T013.4: Manual retry resets retry counter', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      // First attempt: exhaust retries
      ChartLoadTestHooks.failParsingAttempts = 5;
      ChartLoadTestHooks.fastRetry = true;

      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();
      
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Find and tap retry button
      final retryButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Retry'),
      );
      
      // ACT: Manual retry after exhaustion
      ChartLoadTestHooks.failParsingAttempts = 2; // Succeed after 2 retries
      await tester.tap(retryButton);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // ASSERT: Should retry again with reset counter
      // Success means retry counter was reset
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'Manual retry should reset counter and allow new attempts');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
