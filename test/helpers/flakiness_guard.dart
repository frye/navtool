import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// Structured predicate wait with diagnostics for reducing test flakiness.
/// Provides:
///  - Bounded retries with exponential backoff option
///  - Periodic diagnostic callback / snapshot capture
///  - Unified failure message including elapsed time and last snapshot
Future<T> waitForCondition<T>(
  FutureOr<T?> Function() supplier, {
  bool Function(T value)? predicate,
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 10),
  Duration? maxPollInterval,
  String? reason,
  FutureOr<void> Function(int attempt)? onPoll,
  FutureOr<String?> Function()? diagnosticSnapshot,
}) async {
  final end = DateTime.now().add(timeout);
  var attempt = 0;
  T? lastValue;
  while (DateTime.now().isBefore(end)) {
    attempt++;
    final current = await supplier();
    if (current != null) {
      lastValue = current;
      if (predicate == null || predicate(current)) {
        return current;
      }
    }
    if (onPoll != null) await onPoll(attempt);
    final remaining = end.difference(DateTime.now());
    if (remaining.isNegative) break;
    var sleep = pollInterval * (attempt < 5 ? 1 : 2);
    if (maxPollInterval != null && sleep > maxPollInterval) {
      sleep = maxPollInterval;
    }
    if (sleep > remaining) sleep = remaining;
    await Future<void>.delayed(sleep);
  }
  final snap = diagnosticSnapshot != null ? await diagnosticSnapshot() : null;
  fail(reason ?? 'Condition not satisfied within $timeout. Last value: $lastValue${snap != null ? '\nSnapshot: ' + snap : ''}');
}
