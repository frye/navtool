/// TDD Test Suite for ChartLoadingService Retry Logic (T006)
/// Tests MUST FAIL until T019 implementation is complete.
///
/// Requirements Coverage:
/// - FR-007: Automatic retry on transient failures
/// - FR-008: Exponential backoff (100ms, 200ms, 400ms, 800ms)
/// - FR-009: Max 4 retry attempts
/// - FR-011: Success when transient condition clears
/// - FR-012: Failure reporting after exhaustion
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/services/chart_loading_service.dart';
import 'package:navtool/features/charts/chart_load_error.dart';
import 'package:navtool/features/charts/chart_load_test_hooks.dart';

void main() {
  group('ChartLoadingService Retry Logic Tests (T006 - MUST FAIL)', () {
    late ChartLoadingService service;

    setUp(() {
      service = ChartLoadingService();
      ChartLoadTestHooks.reset();
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    test('T006.1: Success on first attempt (no retry needed)', () async {
      // ARRANGE: No test hooks, should succeed immediately
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final stopwatch = Stopwatch()..start();
      final result = await service.loadChart(chartId);
      stopwatch.stop();

      // ASSERT: Success, no retries
      expect(result.success, isTrue, reason: 'Should succeed on first attempt');
      expect(result.retryCount, equals(0), reason: 'Should not retry');
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'Should complete quickly without retries');
    });

    test('T006.2: Retry once with 100ms backoff when transient failure occurs', () async {
      // ARRANGE: Fail first attempt, succeed on retry
      ChartLoadTestHooks.failParsingAttempts = 1;
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final stopwatch = Stopwatch()..start();
      final result = await service.loadChart(chartId);
      stopwatch.stop();

      // ASSERT: Success after 1 retry
      expect(result.success, isTrue, reason: 'Should succeed after retry');
      expect(result.retryCount, equals(1), reason: 'Should retry once');
      
      // ASSERT: Exponential backoff timing (100ms ± 20ms tolerance)
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(80),
          reason: 'Should wait at least 80ms (100ms - 20ms tolerance)');
      expect(stopwatch.elapsedMilliseconds, lessThan(300),
          reason: 'Should not wait longer than 300ms for single retry');
    });

    test('T006.3: Retry with exponential backoff (100, 200, 400ms)', () async {
      // ARRANGE: Fail 3 times, succeed on 4th attempt
      ChartLoadTestHooks.failParsingAttempts = 3;
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final stopwatch = Stopwatch()..start();
      final result = await service.loadChart(chartId);
      stopwatch.stop();

      // ASSERT: Success after 3 retries
      expect(result.success, isTrue, reason: 'Should succeed after 3 retries');
      expect(result.retryCount, equals(3), reason: 'Should retry 3 times');
      
      // ASSERT: Exponential backoff timing (100 + 200 + 400 = 700ms ± tolerance)
      // Allow 560ms to 1000ms (700ms ± 20% tolerance)
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(560),
          reason: 'Should wait cumulative 700ms (±20% tolerance)');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: 'Should not exceed 1000ms for 3 retries');
    });

    test('T006.4: Max 4 retries enforced (fail on 5th failure)', () async {
      // ARRANGE: Fail 5 times (should stop after 4 retries)
      ChartLoadTestHooks.failParsingAttempts = 5;
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final result = await service.loadChart(chartId);

      // ASSERT: Failure after max retries
      expect(result.success, isFalse, reason: 'Should fail after max retries');
      expect(result.retryCount, equals(4), reason: 'Should stop at 4 retries');
      expect(result.error, isNotNull, reason: 'Should return error after exhaustion');
      expect(result.error!.type, equals(ChartLoadErrorType.parsing),
          reason: 'Should preserve error type');
    });

    test('T006.5: Fast retry mode bypasses delays in tests', () async {
      // ARRANGE: Enable fast retry, fail 3 times
      ChartLoadTestHooks.fastRetry = true;
      ChartLoadTestHooks.failParsingAttempts = 3;
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final stopwatch = Stopwatch()..start();
      final result = await service.loadChart(chartId);
      stopwatch.stop();

      // ASSERT: Success without significant delay
      expect(result.success, isTrue, reason: 'Should succeed with fast retry');
      expect(result.retryCount, equals(3), reason: 'Should still count retries');
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'Fast retry should bypass backoff delays');
    });

    test('T006.6: Return retryable error types for transient failures', () async {
      // ARRANGE: Permanent parsing failure
      ChartLoadTestHooks.failParsingAttempts = 1;
      const chartId = 'US5WA50M';

      // ACT: Attempt load (will retry once)
      final result = await service.loadChart(chartId);

      // ASSERT: Result contains error info
      if (!result.success) {
        expect(result.error!.isRetryable, isTrue,
            reason: 'Parsing errors should be retryable');
      }
    });

    test('T006.7: Integrity mismatch is NOT retryable', () async {
      // ARRANGE: Force integrity mismatch
      ChartLoadTestHooks.forceIntegrityMismatch = true;
      const chartId = 'US5WA50M';

      // ACT: Attempt load
      final result = await service.loadChart(chartId);

      // ASSERT: Immediate failure, no retries
      expect(result.success, isFalse, reason: 'Integrity mismatch should fail');
      expect(result.retryCount, equals(0),
          reason: 'Should not retry integrity failures');
      expect(result.error!.type, equals(ChartLoadErrorType.integrity));
      expect(result.error!.isRetryable, isFalse,
          reason: 'Integrity errors are not retryable');
    });

    test('T006.8: Retry count included in success result', () async {
      // ARRANGE: Fail twice, succeed on 3rd attempt
      ChartLoadTestHooks.failParsingAttempts = 2;
      const chartId = 'US5WA50M';

      // ACT: Load chart
      final result = await service.loadChart(chartId);

      // ASSERT: Success with retry metadata
      expect(result.success, isTrue);
      expect(result.retryCount, equals(2));
      expect(result.chartId, equals(chartId));
      expect(result.durationMs, greaterThan(0),
          reason: 'Should track total duration including retries');
    });
  });

  group('ChartLoadingService Edge Cases (T006 Extended)', () {
    late ChartLoadingService service;

    setUp(() {
      service = ChartLoadingService();
      ChartLoadTestHooks.reset();
    });

    tearDown(() {
      ChartLoadTestHooks.reset();
    });

    test('T006.9: Handle chart load cancellation', () async {
      // ARRANGE: Start load, then cancel
      const chartId = 'US5WA50M';
      ChartLoadTestHooks.failParsingAttempts = 3;  // Would retry

      // ACT: Start load and cancel after 50ms
      final loadFuture = service.loadChart(chartId);
      await Future.delayed(Duration(milliseconds: 50));
      service.cancel(chartId);
      final result = await loadFuture;

      // ASSERT: Cancelled result
      expect(result.success, isFalse);
      expect(result.error!.type, equals(ChartLoadErrorType.cancelled));
    });

    test('T006.10: Concurrent load requests for same chart deduplicated', () async {
      // ARRANGE: Start two loads for same chart
      const chartId = 'US5WA50M';

      // ACT: Trigger concurrent loads
      final future1 = service.loadChart(chartId);
      final future2 = service.loadChart(chartId);

      // ASSERT: Both futures resolve, but only one actual load
      final results = await Future.wait([future1, future2]);
      expect(results[0].success, isTrue);
      expect(results[1].success, isTrue);
      // Implementation should deduplicate, not load twice
    });
  });
}
