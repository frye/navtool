import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/download_metrics_collector.dart';
import 'package:navtool/core/state/download_state.dart';

void main() {
  group('DownloadMetricsCollector', () {
    test('empty snapshot', () {
      final c = DownloadMetricsCollector();
      final snap = c.snapshot();
      expect(snap.successCount, 0);
      expect(snap.failureCount, 0);
      expect(snap.averageDurationSeconds, 0);
      expect(snap.medianDurationSeconds, 0);
      expect(snap.retryCount, 0);
    });

    test('records success & failure with durations and median', () async {
      final c = DownloadMetricsCollector();
      c.start('A');
      await Future.delayed(const Duration(milliseconds: 30));
      c.completeSuccess('A');
      c.start('B');
      await Future.delayed(const Duration(milliseconds: 10));
      c.completeFailure('B', 'network');
      final snap = c.snapshot();
      expect(snap.successCount, 1);
      expect(snap.failureCount, 1);
      expect(snap.failureByCategory['network'], 1);
      expect(snap.medianDurationSeconds, greaterThan(0));
    });

    test('retry increments', () async {
      final c = DownloadMetricsCollector();
      c.start('X');
      c.incrementRetry('X');
      c.incrementRetry('X');
      await Future.delayed(const Duration(milliseconds: 5));
      c.completeSuccess('X');
      final snap = c.snapshot();
      expect(snap.retryCount, 2);
    });
  });
}
