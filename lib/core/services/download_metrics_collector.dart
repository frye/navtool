import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../state/download_state.dart';

/// Basic metrics snapshot for downloads (Phase 3 initial implementation)
@immutable
class DownloadMetricsSnapshot {
  final int successCount;
  final int failureCount;
  final Map<String, int> failureByCategory;
  final double averageDurationSeconds;
  final double medianDurationSeconds;
  final int retryCount;

  const DownloadMetricsSnapshot({
    required this.successCount,
    required this.failureCount,
    required this.failureByCategory,
    required this.averageDurationSeconds,
    required this.medianDurationSeconds,
    required this.retryCount,
  });
}

/// Internal record of a single download attempt
class _DownloadAttemptRecord {
  final String chartId;
  final DateTime start;
  DateTime? end;
  bool success = false;
  String? failureCategory;
  int retries = 0;

  _DownloadAttemptRecord(this.chartId, this.start);

  double get durationSeconds => end == null ? 0 : end!.difference(start).inMilliseconds / 1000.0;
}

/// Service responsible for aggregating lightweight metrics for download operations.
/// NOTE: This is intentionally in-memory only for initial phase; persistence can
/// be added later.
class DownloadMetricsCollector {
  final Map<String, _DownloadAttemptRecord> _active = {};
  final List<_DownloadAttemptRecord> _completed = [];

  // Start tracking a download
  void start(String chartId) {
    _active[chartId] = _DownloadAttemptRecord(chartId, DateTime.now());
  }

  // Mark a successful completion
  void completeSuccess(String chartId) {
    final rec = _active.remove(chartId);
    if (rec != null) {
      rec.success = true;
      rec.end = DateTime.now();
      _completed.add(rec);
    }
  }

  // Mark a failure with category
  void completeFailure(String chartId, String category) {
    final rec = _active.remove(chartId);
    if (rec != null) {
      rec.success = false;
      rec.failureCategory = category;
      rec.end = DateTime.now();
      _completed.add(rec);
    }
  }

  // Increment retry count for a chart
  void incrementRetry(String chartId) {
    final rec = _active[chartId];
    if (rec != null) rec.retries += 1;
  }

  DownloadMetricsSnapshot snapshot() {
    if (_completed.isEmpty) {
      return const DownloadMetricsSnapshot(
        successCount: 0,
        failureCount: 0,
        failureByCategory: {},
        averageDurationSeconds: 0,
        medianDurationSeconds: 0,
        retryCount: 0,
      );
    }
    final successes = _completed.where((e) => e.success).toList();
    final failures = _completed.where((e) => !e.success).toList();
    final failureByCat = <String, int>{};
    for (final f in failures) {
      final cat = f.failureCategory ?? 'unknown';
      failureByCat[cat] = (failureByCat[cat] ?? 0) + 1;
    }
    final durations = _completed.map((e) => e.durationSeconds).where((d) => d > 0).toList()..sort();
    final avg = durations.isEmpty ? 0 : durations.reduce((a, b) => a + b) / durations.length;
    final median = durations.isEmpty ? 0 : (durations.length.isOdd
        ? durations[durations.length ~/ 2]
        : (durations[durations.length ~/ 2 - 1] + durations[durations.length ~/ 2]) / 2);
    final retries = _completed.fold<int>(0, (sum, r) => sum + r.retries);
    return DownloadMetricsSnapshot(
      successCount: successes.length,
      failureCount: failures.length,
      failureByCategory: UnmodifiableMapView(failureByCat),
      averageDurationSeconds: avg,
      medianDurationSeconds: median,
      retryCount: retries,
    );
  }
}
