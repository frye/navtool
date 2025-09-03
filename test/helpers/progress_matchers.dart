import 'package:flutter_test/flutter_test.dart';

/// Asserts that a progress value is a normalized double between 0.0 and 1.0.
/// Optionally asserts approximate equality to an expected value.
///
/// This helper centralizes the normalized scale decision (0–1) so future
/// refactors (e.g., switching to a typed Progress class) require edits in
/// only one place rather than across many tests.
void expectNormalizedProgress(
  double progress, {
  double? equals,
  double tolerance = 1e-6,
  String? reason,
}) {
  expect(progress.isNaN, isFalse, reason: reason ?? 'Progress must not be NaN');
  expect(progress.isFinite, isTrue, reason: reason ?? 'Progress must be finite');
  expect(progress >= 0.0 && progress <= 1.0, isTrue,
      reason: reason ?? 'Progress $progress outside normalized range 0..1');
  if (equals != null) {
    expect((progress - equals).abs() <= tolerance, isTrue,
        reason: reason ?? 'Progress $progress not within $tolerance of $equals');
  }
}

/// Issue #139 naming alignment: alias requested helper name.
void expectProgressCloseTo(double progress, double target, {double tolerance = 1e-6, String? reason}) =>
    expectNormalizedProgress(progress, equals: target, tolerance: tolerance, reason: reason);

/// Convenience matcher for a list/stream snapshot of normalized progress
/// samples. Ensures each sample is within [0,1]. Returns the original list so
/// it can be chained in test expectations if desired.
Iterable<double> expectAllNormalized(Iterable<double> samples, {String? reason}) {
  for (final v in samples) {
    expect(v >= 0.0 && v <= 1.0, isTrue,
        reason: reason ?? 'Progress sample $v outside normalized range 0..1');
  }
  return samples;
}

/// Awaits the first emitted value from a progress [Stream<double>] and asserts
/// it is normalized (and optionally near a target value).
Future<double> expectFirstNormalized(Stream<double> stream, {double? equals, double tolerance = 1e-6}) async {
  final first = await stream.first;
  expectNormalizedProgress(first, equals: equals, tolerance: tolerance);
  return first;
}

