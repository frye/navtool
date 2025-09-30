import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/chart_integrity_registry.dart';

void main() {
  test('ChartIntegrityRegistry seed and compare', () {
    final reg = ChartIntegrityRegistry();
    reg.seed({'US5WA50M': 'DEADBEEF'});

    final match = reg.compare('US5WA50M', 'DEADBEEF');
    expect(match, isNull);

    final mismatch = reg.compare('US5WA50M', 'CAFEBABE');
    expect(mismatch, isNotNull);
    expect(mismatch!.chartId, 'US5WA50M');
  });
}
