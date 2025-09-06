import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

/// Fake ticker / logical clock for deterministic test advancement.
class FakeTicker {
  int _tick = 0;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  Stream<int> get ticks => _controller.stream;
  int get currentTick => _tick;

  void advance([int count = 1]) {
    for (var i = 0; i < count; i++) {
      _tick++;
      _controller.add(_tick);
    }
  }

  Future<void> pumpUntil(
    bool Function() predicate, {
    int maxTicks = 100,
    int step = 1,
  }) async {
    for (var i = 0; i < maxTicks; i += step) {
      if (predicate()) return;
      advance(step);
      await pumpEventQueue();
    }
    fail('pumpUntil maxTicks($maxTicks) exhausted without predicate success');
  }

  void dispose() => _controller.close();
}

@Deprecated(
  'Use waitForCondition in flakiness_guard.dart for diagnostics and adaptive backoff',
)
/// Poll-based predicate wait (legacy). Prefer using waitForCondition in
/// flakiness_guard.dart for richer diagnostics and adaptive backoff.
Future<void> waitForPredicate(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 10),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (predicate()) return;
    await Future<void>.delayed(pollInterval);
  }
  fail(reason ?? 'Predicate not satisfied within $timeout');
}
