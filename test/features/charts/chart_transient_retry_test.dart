/// TDD Widget Test for Transient Retry with Exponential Backoff (T012 - ENHANCED)
/// Tests MUST FAIL until T019+T023 implementation is complete.
///
/// Requirements Coverage:
/// - FR-007: Exponential backoff (100ms, 200ms, 400ms, 800ms)
/// - FR-008: Retry counting and tracking
/// - Scenario 6 from quickstart.md (transient retry)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';

/// Validates auto-retry behavior for transient parsing failures using test hooks.
void main() {
  group('Chart Transient Retry (T012 - ENHANCED)', () {
    late String zipPath;

    setUpAll(() {
      zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    });

    tearDown() {
      ChartLoadTestHooks.reset();
    });

    testWidgets('LEGACY: auto-retries transient parsing failures then succeeds', (tester) async {
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
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // Success criteria: either overlay gone or complete state with check icon
      final overlayStillVisible = find.byKey(const Key('chart-loading-overlay')).evaluate().isNotEmpty;
      if (overlayStillVisible) {
        // If still visible it must be complete (no error icon)
        expect(find.byIcon(Icons.error_outline), findsNothing, reason: 'Should not remain in error state after retries');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T012.1: Exponential backoff timing (100ms, 200ms, 400ms)', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      // ARRANGE: Fail 3 times, succeed on 4th
      ChartLoadTestHooks.failParsingAttempts = 3;
      ChartLoadTestHooks.fastRetry = false; // Use real exponential backoff timing

      final stopwatch = Stopwatch()..start();

      // ACT: Start loading
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // Track timing of retries
      final List<int> retryTimings = [];

      // First attempt (immediate)
      await tester.pump(const Duration(milliseconds: 50));
      retryTimings.add(stopwatch.elapsedMilliseconds);

      // First retry after 100ms backoff (±20ms tolerance)
      await tester.pump(const Duration(milliseconds: 120));
      retryTimings.add(stopwatch.elapsedMilliseconds);

      // Second retry after 200ms backoff (±20ms tolerance)
      await tester.pump(const Duration(milliseconds: 220));
      retryTimings.add(stopwatch.elapsedMilliseconds);

      // Third retry after 400ms backoff (±20ms tolerance)
      await tester.pump(const Duration(milliseconds: 420));
      retryTimings.add(stopwatch.elapsedMilliseconds);

      stopwatch.stop();

      // ASSERT: Verify exponential backoff pattern
      // Expected: ~0ms, ~100ms, ~300ms (100+200), ~700ms (100+200+400)
      expect(retryTimings[1] - retryTimings[0], greaterThanOrEqualTo(80),
          reason: 'First backoff should be ~100ms');
      expect(retryTimings[1] - retryTimings[0], lessThanOrEqualTo(150),
          reason: 'First backoff should be ~100ms');

      expect(retryTimings[2] - retryTimings[1], greaterThanOrEqualTo(180),
          reason: 'Second backoff should be ~200ms');
      expect(retryTimings[2] - retryTimings[1], lessThanOrEqualTo(250),
          reason: 'Second backoff should be ~200ms');

      expect(retryTimings[3] - retryTimings[2], greaterThanOrEqualTo(380),
          reason: 'Third backoff should be ~400ms');
      expect(retryTimings[3] - retryTimings[2], lessThanOrEqualTo(450),
          reason: 'Third backoff should be ~400ms');

      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('T012.2: Retry count included in success result', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      ChartLoadTestHooks.failParsingAttempts = 2;
      ChartLoadTestHooks.fastRetry = true;

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // ASSERT: Success message includes retry count
      // Expected: "Loaded successfully after 3 attempts"
      await tester.pump(const Duration(milliseconds: 500));

      // Check for snackbar or status message with retry count
      final retryCountMessage = find.textContaining('attempts');
      expect(retryCountMessage, findsOneWidget,
          reason: 'Should display retry count in success message');

      final message = retryCountMessage.evaluate().first.widget as Text;
      expect(message.data, contains('3'),
          reason: 'Should show 3 attempts (1 initial + 2 retries)');
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T012.3: Progress indicator visible during all retries', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      ChartLoadTestHooks.failParsingAttempts = 2;
      ChartLoadTestHooks.fastRetry = true;
      ChartLoadTestHooks.simulateLoadDuration = 800; // Ensure >500ms threshold

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // ASSERT: Progress indicator appears after 500ms
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Should show progress indicator during first attempt');

      // ASSERT: Progress indicator persists through retries
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Should maintain progress indicator during first retry');

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Should maintain progress indicator during second retry');

      // ASSERT: Progress indicator disappears on success
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Should dismiss progress indicator after success');
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('T012.4: Fast retry mode uses accelerated timing', (tester) async {
      if (!File(zipPath).existsSync()) {
        return tester.printToConsole('[SKIP] Missing ENC test fixture: $zipPath');
      }

      final chart = WashingtonTestCharts.getElliottBayCharts().first;

      ChartLoadTestHooks.failParsingAttempts = 2;
      ChartLoadTestHooks.fastRetry = true; // Should use 10ms instead of 100/200/400

      final stopwatch = Stopwatch()..start();

      // ACT: Load chart
      await tester.pumpWidget(MaterialApp(home: ChartScreen(chart: chart)));
      await tester.pump();

      // All retries should complete quickly with fast mode
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      stopwatch.stop();

      // ASSERT: Total time much less than normal backoff (would be 700ms+)
      expect(stopwatch.elapsedMilliseconds, lessThan(500),
          reason: 'Fast retry mode should complete much faster than normal backoff');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
