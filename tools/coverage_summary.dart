import 'dart:io';

void main() {
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info not found');
    exit(1);
  }
  final lines = file.readAsLinesSync().where((l) => l.startsWith('DA:'));
  int total = 0;
  int covered = 0;
  for (final l in lines) {
    total++;
    final parts = l.substring(3).split(',');
    if (parts.length == 2) {
      final hits = int.tryParse(parts[1]) ?? 0;
      if (hits > 0) covered++;
    }
  }
  final percent = total == 0 ? 0 : ((covered / total) * 100).toStringAsFixed(2);
  print('COVERAGE_TOTAL_LINES=$total');
  print('COVERAGE_COVERED_LINES=$covered');
  print('COVERAGE_PERCENT=$percent');
}
