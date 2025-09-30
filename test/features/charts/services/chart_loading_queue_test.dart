/// TDD Test Suite for ChartLoadingQueue FIFO Processing (T007)
/// Tests MUST FAIL until T020 implementation is complete.
///
/// Requirements Coverage:
/// - FR-026: Queue multiple chart load requests
/// - FR-027: Display queue position/status
/// - R08: Sequential FIFO processing
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/services/chart_loading_queue.dart';
import 'package:navtool/features/charts/services/chart_loading_service.dart';

void main() {
  group('ChartLoadingQueue FIFO Tests (T007 - MUST FAIL)', () {
    late ChartLoadingQueue queue;
    late MockChartLoadingService mockService;

    setUp(() {
      mockService = MockChartLoadingService();
      queue = ChartLoadingQueue(loadingService: mockService);
    });

    tearDown(() {
      queue.dispose();
    });

    test('T007.1: Enqueue single chart, process immediately', () async {
      // ARRANGE: Empty queue
      const chartId = 'US5WA50M';

      // ACT: Enqueue chart
      final queueEntry = queue.enqueue(chartId);

      // ASSERT: Queue position is 0 (processing immediately)
      expect(queueEntry.position, equals(0),
          reason: 'First chart should process immediately');
      expect(queue.length, equals(1), reason: 'Queue should have 1 item');
      expect(queue.isProcessing, isTrue,
          reason: 'Queue should be processing');

      // Wait for completion
      await queueEntry.future;

      // ASSERT: Queue empty after completion
      expect(queue.length, equals(0), reason: 'Queue should be empty');
      expect(queue.isProcessing, isFalse,
          reason: 'Queue should not be processing');
    });

    test('T007.2: Enqueue multiple charts, process sequentially', () async {
      // ARRANGE: Three charts to load
      const chart1 = 'US5WA50M';
      const chart2 = 'US3WA01M';
      const chart3 = 'US4CA09M';

      // ACT: Enqueue all three
      final entry1 = queue.enqueue(chart1);
      final entry2 = queue.enqueue(chart2);
      final entry3 = queue.enqueue(chart3);

      // ASSERT: Queue positions
      expect(entry1.position, equals(0), reason: 'First chart at position 0');
      expect(entry2.position, equals(1), reason: 'Second chart at position 1');
      expect(entry3.position, equals(2), reason: 'Third chart at position 2');
      expect(queue.length, equals(3), reason: 'Queue should have 3 items');

      // ASSERT: Processing order (FIFO)
      expect(queue.currentChartId, equals(chart1),
          reason: 'Should process chart1 first');

      // Wait for first to complete
      await entry1.future;
      
      // ASSERT: Second chart now processing
      expect(queue.currentChartId, equals(chart2),
          reason: 'Should process chart2 second');
      expect(entry2.position, equals(0),
          reason: 'Chart2 now at front (position 0)');
      expect(entry3.position, equals(1),
          reason: 'Chart3 moved up to position 1');

      // Wait for all to complete
      await Future.wait([entry2.future, entry3.future]);

      // ASSERT: Queue empty
      expect(queue.length, equals(0));
      expect(queue.isProcessing, isFalse);
    });

    test('T007.3: Duplicate chart ID deduplicated (don\'t add twice)', () async {
      // ARRANGE: Same chart enqueued twice
      const chartId = 'US5WA50M';

      // ACT: Enqueue same chart twice
      final entry1 = queue.enqueue(chartId);
      final entry2 = queue.enqueue(chartId);

      // ASSERT: Only one entry in queue
      expect(queue.length, equals(1),
          reason: 'Duplicate chart should not be added');
      
      // ASSERT: Both entries resolve to same future
      expect(identical(entry1.future, entry2.future), isTrue,
          reason: 'Duplicate entries should share same future');

      // Wait for completion
      await entry1.future;
      
      // ASSERT: Only loaded once
      expect(mockService.loadCount, equals(1),
          reason: 'Chart should only be loaded once');
    });

    test('T007.4: Queue position updates as charts complete', () async {
      // ARRANGE: Three charts enqueued
      final entry1 = queue.enqueue('US5WA50M');
      final entry2 = queue.enqueue('US3WA01M');
      final entry3 = queue.enqueue('US4CA09M');

      // Initial positions: 0, 1, 2
      expect(entry1.position, equals(0));
      expect(entry2.position, equals(1));
      expect(entry3.position, equals(2));

      // ACT: Complete first chart
      await entry1.future;

      // ASSERT: Positions shifted
      expect(entry2.position, equals(0),
          reason: 'Chart2 should move to position 0');
      expect(entry3.position, equals(1),
          reason: 'Chart3 should move to position 1');

      // ACT: Complete second chart
      await entry2.future;

      // ASSERT: Chart3 now processing
      expect(entry3.position, equals(0),
          reason: 'Chart3 should move to position 0');
    });

    test('T007.5: Cancel queued chart before processing starts', () async {
      // ARRANGE: Three charts enqueued
      final entry1 = queue.enqueue('US5WA50M');
      final entry2 = queue.enqueue('US3WA01M');
      final entry3 = queue.enqueue('US4CA09M');

      // ACT: Cancel chart2 while chart1 processing
      queue.cancel('US3WA01M');

      // ASSERT: Chart2 removed from queue
      expect(queue.length, equals(2),
          reason: 'Queue should have 2 items after cancellation');
      expect(queue.contains('US3WA01M'), isFalse,
          reason: 'Cancelled chart should be removed');

      // ASSERT: Cancelled entry completes with error
      await expectLater(
        entry2.future,
        throwsA(isA<StateError>()),
        reason: 'Cancelled chart should throw StateError',
      );

      // Wait for chart1 to complete
      await entry1.future;

      // ASSERT: Chart3 processes next (chart2 was cancelled)
      expect(queue.currentChartId, equals('US4CA09M'),
          reason: 'Should skip cancelled chart2 and process chart3');
      
      // Wait for chart3 to complete to clean up
      await entry3.future;
    });

    test('T007.6: Clear queue cancels all pending charts', () async {
      // ARRANGE: Multiple charts enqueued
      final entry1 = queue.enqueue('US5WA50M');
      final entry2 = queue.enqueue('US3WA01M');
      final entry3 = queue.enqueue('US4CA09M');

      // ACT: Clear queue
      queue.clear();

      // ASSERT: Queue empty immediately (except current)
      expect(queue.length, equals(1),
          reason: 'Only current chart should remain');
      
      // ASSERT: Cleared entries complete with error
      await expectLater(
        entry2.future,
        throwsA(isA<StateError>()),
        reason: 'Cleared chart should throw StateError',
      );
      await expectLater(
        entry3.future,
        throwsA(isA<StateError>()),
        reason: 'Cleared chart should throw StateError',
      );

      // Wait for current to complete
      await entry1.future;

      // ASSERT: Queue completely empty
      expect(queue.length, equals(0));
      expect(queue.isProcessing, isFalse);
    });

    test('T007.7: Queue status provides summary', () async {
      // ARRANGE: Multiple charts enqueued
      final entry1 = queue.enqueue('US5WA50M');
      final entry2 = queue.enqueue('US3WA01M');
      final entry3 = queue.enqueue('US4CA09M');

      // ACT: Get queue status
      final status = queue.getStatus();

      // ASSERT: Status contains correct information
      expect(status.currentChartId, equals('US5WA50M'));
      expect(status.queueLength, equals(3));
      expect(status.pendingChartIds, equals(['US3WA01M', 'US4CA09M']));
      expect(status.isProcessing, isTrue);
      
      // Wait for all to complete to clean up
      await Future.wait([
        entry1.future,
        entry2.future,
        entry3.future,
      ]);
    });
  });

  group('ChartLoadingQueue Edge Cases (T007 Extended)', () {
    late ChartLoadingQueue queue;
    late MockChartLoadingService mockService;

    setUp(() {
      mockService = MockChartLoadingService();
      queue = ChartLoadingQueue(loadingService: mockService);
    });

    tearDown(() {
      queue.dispose();
    });

    test('T007.8: Handle service load failure without blocking queue', () async {
      // ARRANGE: Service configured to fail on chart1
      mockService.failChartIds.add('US5WA50M');
      
      final entry1 = queue.enqueue('US5WA50M');  // Will fail
      final entry2 = queue.enqueue('US3WA01M');  // Should succeed

      // ACT: Wait for both
      try {
        await entry1.future;
      } catch (e) {
        // Expected failure
      }

      // ASSERT: Queue continued processing despite failure
      await entry2.future;
      expect(mockService.loadCount, equals(2),
          reason: 'Queue should process both charts despite failure');
    });

    test('T007.9: Enqueue after dispose throws error', () {
      // ACT: Dispose queue
      queue.dispose();

      // ASSERT: Enqueue throws
      expect(
        () => queue.enqueue('US5WA50M'),
        throwsStateError,
        reason: 'Should not allow enqueue after dispose',
      );
    });
  });
}

/// Mock ChartLoadingService for testing
class MockChartLoadingService extends ChartLoadingService {
  int loadCount = 0;
  Set<String> failChartIds = {};

  @override
  Future<ChartLoadResult> loadChart(String chartId) async {
    loadCount++;
    
    // Simulate load time
    await Future.delayed(Duration(milliseconds: 50));

    if (failChartIds.contains(chartId)) {
      return ChartLoadResult(
        chartId: chartId,
        success: false,
        retryCount: 0,
        durationMs: 50,
      );
    }

    return ChartLoadResult(
      chartId: chartId,
      success: true,
      retryCount: 0,
      durationMs: 50,
    );
  }
}
