import 'dart:io';
import 'dart:convert';

/// Simple coverage summarizer with optional JSON snapshot + delta reporting.
///
/// Usage:
///   dart run tools/coverage_summary.dart               # plain summary
///   dart run tools/coverage_summary.dart --snapshot    # writes coverage/summary.json
///   dart run tools/coverage_summary.dart --delta       # compares to coverage/summary.json then updates it
///
/// JSON format:
///   {
///     "total": 8362,
///     "covered": 5421,
///     "percent": 64.83,
///     "timestamp": "2025-09-03T03:44:00Z"
///   }
void main(List<String> args) {
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info not found');
    exit(1);
  }

  final daLines = file.readAsLinesSync().where((l) => l.startsWith('DA:'));
  int total = 0;
  int covered = 0;
  for (final l in daLines) {
    total++;
    final parts = l.substring(3).split(',');
    if (parts.length == 2) {
      final hits = int.tryParse(parts[1]) ?? 0;
      if (hits > 0) covered++;
    }
  }
  final percentDouble = total == 0 ? 0.0 : (covered / total) * 100;
  final percentStr = percentDouble.toStringAsFixed(2);

  print('COVERAGE_TOTAL_LINES=$total');
  print('COVERAGE_COVERED_LINES=$covered');
  print('COVERAGE_PERCENT=$percentStr');

  final snapshotPath = 'coverage/summary.json';
  final takeSnapshot = args.contains('--snapshot');
  final showDelta = args.contains('--delta');
  Map<String, dynamic>? previous;

  if (showDelta && File(snapshotPath).existsSync()) {
    try {
      previous =
          jsonDecode(File(snapshotPath).readAsStringSync())
              as Map<String, dynamic>;
    } catch (_) {
      stderr.writeln(
        'Warning: Failed to parse existing $snapshotPath; ignoring delta.',
      );
    }
  }

  if (previous != null) {
    final prevPercent = (previous['percent'] as num?)?.toDouble();
    final prevCovered = previous['covered'] as int?;
    final prevTotal = previous['total'] as int?;
    if (prevPercent != null && prevCovered != null && prevTotal != null) {
      final deltaPercent = (percentDouble - prevPercent).toStringAsFixed(2);
      final deltaCovered = covered - prevCovered;
      print('COVERAGE_DELTA_PERCENT=$deltaPercent');
      print('COVERAGE_DELTA_COVERED=$deltaCovered');
    }
  }

  if (takeSnapshot || showDelta) {
    final snapshot = {
      'total': total,
      'covered': covered,
      'percent': double.parse(percentStr),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    File(snapshotPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(snapshot));
    print('WROTE_SNAPSHOT=$snapshotPath');
  }
}
