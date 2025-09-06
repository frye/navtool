/// Test for S-57 Update Summary Reporting
///
/// Tests summary accumulation and reporting functionality

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_update_models.dart';

void main() {
  group('S57 Update Summary Report', () {
    test('should track summary counters correctly', () {
      final summary = UpdateSummary();

      // Initial state
      expect(summary.inserted, equals(0));
      expect(summary.modified, equals(0));
      expect(summary.deleted, equals(0));
      expect(summary.finalRver, equals(0));
      expect(summary.applied, isEmpty);
      expect(summary.warnings, isEmpty);

      // Update counters
      summary.inserted = 2;
      summary.modified = 1;
      summary.deleted = 1;
      summary.finalRver = 3;

      expect(summary.inserted, equals(2));
      expect(summary.modified, equals(1));
      expect(summary.deleted, equals(1));
      expect(summary.finalRver, equals(3));
    });

    test('should track applied update files', () {
      final summary = UpdateSummary();

      summary.applied.add('SAMPLE.001');
      summary.applied.add('SAMPLE.002');
      summary.applied.add('SAMPLE.003');

      expect(summary.applied, hasLength(3));
      expect(summary.applied, contains('SAMPLE.001'));
      expect(summary.applied, contains('SAMPLE.002'));
      expect(summary.applied, contains('SAMPLE.003'));
    });

    test('should track warnings', () {
      final summary = UpdateSummary();

      summary.addWarning('INSERT_EXISTS: Feature F1 already exists');
      summary.addWarning('DELETE_MISSING: Feature F2 not found');
      summary.addWarning('MODIFY_MISSING: Feature F3 not found');

      expect(summary.warnings, hasLength(3));
      expect(summary.warnings[0], contains('INSERT_EXISTS'));
      expect(summary.warnings[1], contains('DELETE_MISSING'));
      expect(summary.warnings[2], contains('MODIFY_MISSING'));
    });

    test('should reset all values', () {
      final summary = UpdateSummary();

      // Set some values
      summary.inserted = 5;
      summary.modified = 3;
      summary.deleted = 2;
      summary.finalRver = 10;
      summary.applied.addAll(['SAMPLE.001', 'SAMPLE.002']);
      summary.addWarning('Test warning');

      // Verify values are set
      expect(summary.inserted, equals(5));
      expect(summary.applied, hasLength(2));
      expect(summary.warnings, hasLength(1));

      // Reset
      summary.reset();

      // Verify all values are reset
      expect(summary.inserted, equals(0));
      expect(summary.modified, equals(0));
      expect(summary.deleted, equals(0));
      expect(summary.finalRver, equals(0));
      expect(summary.applied, isEmpty);
      expect(summary.warnings, isEmpty);
    });

    test('should convert to map correctly', () {
      final summary = UpdateSummary();
      summary.inserted = 1;
      summary.modified = 2;
      summary.deleted = 1;
      summary.finalRver = 3;
      summary.applied.addAll(['SAMPLE.001', 'SAMPLE.002', 'SAMPLE.003']);
      summary.addWarning('INSERT_EXISTS: Feature already exists');

      final map = summary.toMap();

      expect(map['inserted'], equals(1));
      expect(map['modified'], equals(2));
      expect(map['deleted'], equals(1));
      expect(map['finalRver'], equals(3));
      expect(
        map['applied'],
        equals(['SAMPLE.001', 'SAMPLE.002', 'SAMPLE.003']),
      );
      expect(
        map['warnings'],
        equals(['INSERT_EXISTS: Feature already exists']),
      );
    });

    test('should have meaningful toString', () {
      final summary = UpdateSummary();
      summary.inserted = 1;
      summary.modified = 1;
      summary.deleted = 1;
      summary.finalRver = 3;
      summary.applied.addAll(['SAMPLE.001', 'SAMPLE.002', 'SAMPLE.003']);
      summary.addWarning('Test warning 1');
      summary.addWarning('Test warning 2');

      final str = summary.toString();

      expect(str, contains('inserted: 1'));
      expect(str, contains('modified: 1'));
      expect(str, contains('deleted: 1'));
      expect(str, contains('finalRver: 3'));
      expect(str, contains('[SAMPLE.001, SAMPLE.002, SAMPLE.003]'));
      expect(str, contains('warnings: 2'));
    });

    test('should test FOID helper functions', () {
      // Test createFoid
      final foid1 = FoidHelper.createFoid(550, 12345, 1);
      expect(foid1, equals('550_12345_1'));

      // Test createFoidFromMap
      final foidData = {'agency': 550, 'feature_id': 98765, 'subdivision': 2};
      final foid2 = FoidHelper.createFoidFromMap(foidData);
      expect(foid2, equals('550_98765_2'));

      // Test createFoidFromMap with missing values
      final incompleteFoidData = {'feature_id': 123};
      final foid3 = FoidHelper.createFoidFromMap(incompleteFoidData);
      expect(foid3, equals('0_123_0')); // Missing values default to 0

      // Test parseFoid
      final parsed1 = FoidHelper.parseFoid('550_12345_1');
      expect(parsed1['agency'], equals(550));
      expect(parsed1['feature_id'], equals(12345));
      expect(parsed1['subdivision'], equals(1));

      // Test parseFoid with simple numeric string
      final parsed2 = FoidHelper.parseFoid('98765');
      expect(parsed2['agency'], equals(0));
      expect(parsed2['feature_id'], equals(98765));
      expect(parsed2['subdivision'], equals(0));

      // Test parseFoid with invalid format
      final parsed3 = FoidHelper.parseFoid('invalid_foid_format');
      expect(parsed3['agency'], equals(0));
      expect(parsed3['feature_id'], isA<int>()); // Should be a hash
      expect(parsed3['subdivision'], equals(0));
    });

    test('should track expected final state for sample sequence', () {
      // Simulates the expected result for the sample fixture chain:
      // Base: F1(DEPARE), F2(SOUNDG), F3(LIGHTS)
      // .001: Delete F2
      // .002: Modify F1
      // .003: Insert F4(OBSTRN)
      // Final: F1(modified), F3(unaffected), F4(added)

      final summary = UpdateSummary();

      // Apply update .001 (delete F2)
      summary.deleted = 1;
      summary.applied.add('SAMPLE.001');
      summary.finalRver = 1;

      // Apply update .002 (modify F1)
      summary.modified = 1;
      summary.applied.add('SAMPLE.002');
      summary.finalRver = 2;

      // Apply update .003 (insert F4)
      summary.inserted = 1;
      summary.applied.add('SAMPLE.003');
      summary.finalRver = 3;

      // Verify expected final state
      expect(
        summary.inserted,
        equals(1),
        reason: 'Should have inserted 1 feature (F4)',
      );
      expect(
        summary.modified,
        equals(1),
        reason: 'Should have modified 1 feature (F1)',
      );
      expect(
        summary.deleted,
        equals(1),
        reason: 'Should have deleted 1 feature (F2)',
      );
      expect(
        summary.finalRver,
        equals(3),
        reason: 'Final RVER should be 3 from last update',
      );
      expect(
        summary.applied,
        hasLength(3),
        reason: 'Should have applied 3 updates',
      );

      // Verify the sequence
      expect(summary.applied[0], equals('SAMPLE.001'));
      expect(summary.applied[1], equals('SAMPLE.002'));
      expect(summary.applied[2], equals('SAMPLE.003'));

      print('Expected sample sequence summary: $summary');
    });
  });
}
