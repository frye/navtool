import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Unknown Object Code Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should generate warning for unknown object code', () {
      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 999 encountered',
        recordId: 'FRID_001',
        featureId: 'UNK999',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));

      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.unknownObjCode));
      expect(warning.severity, equals(S57WarningSeverity.warning));
      expect(warning.message, contains('Unknown object code 999'));
      expect(warning.recordId, equals('FRID_001'));
      expect(warning.featureId, equals('UNK999'));
    });

    test('should handle multiple unknown object codes', () {
      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 888',
        recordId: 'FRID_001',
      );

      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 999',
        recordId: 'FRID_002',
      );

      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 777',
        recordId: 'FRID_003',
      );

      expect(collector.totalWarnings, equals(3));
      expect(collector.warningCount, equals(3));

      final unknownWarnings = collector.getWarningsByCode(
        S57WarningCodes.unknownObjCode,
      );
      expect(unknownWarnings, hasLength(3));

      expect(unknownWarnings[0].message, contains('888'));
      expect(unknownWarnings[1].message, contains('999'));
      expect(unknownWarnings[2].message, contains('777'));
    });

    test('should optionally deduplicate repeated unknown codes', () {
      // Test current behavior (no deduplication)
      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 999',
        recordId: 'FRID_001',
      );

      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 999', // Same code, different record
        recordId: 'FRID_002',
      );

      expect(collector.totalWarnings, equals(2));

      final unknownWarnings = collector.getWarningsByCode(
        S57WarningCodes.unknownObjCode,
      );
      expect(unknownWarnings, hasLength(2));

      // Both warnings should be present (no deduplication)
      expect(unknownWarnings[0].recordId, equals('FRID_001'));
      expect(unknownWarnings[1].recordId, equals('FRID_002'));
    });

    test('should provide context for unknown object warning', () {
      const objectCode = 12345;
      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Object code $objectCode not found in S-57 catalog',
        recordId: 'FRID_${objectCode}',
        featureId: 'FEAT_${objectCode}_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('12345'));
      expect(warning.message, contains('not found in S-57 catalog'));
      expect(warning.recordId, equals('FRID_12345'));
      expect(warning.featureId, equals('FEAT_12345_001'));
    });

    test('should handle unknown codes in strict mode appropriately', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Unknown object codes are warnings, not errors, so should not throw
      strictCollector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code 999',
      );

      expect(strictCollector.totalWarnings, equals(1));
      expect(strictCollector.warningCount, equals(1));
      expect(strictCollector.hasErrors, isFalse);
    });

    test('should include unknown code warnings in summary report', () {
      collector.warning(S57WarningCodes.unknownObjCode, 'Unknown 1');
      collector.warning(S57WarningCodes.unknownObjCode, 'Unknown 2');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth info');

      final summary = collector.createSummaryReport();

      expect(summary['totalWarnings'], equals(3));
      expect(
        summary['warningsByCode'][S57WarningCodes.unknownObjCode],
        equals(2),
      );
      expect(
        summary['warningsByCode'][S57WarningCodes.depthOutOfRange],
        equals(1),
      );
      expect(summary['warningsBySeverity']['warning'], equals(2));
      expect(summary['warningsBySeverity']['info'], equals(1));
    });

    test('should work with console logger for unknown codes', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);

      final loggedCollector = S57WarningCollector(logger: testLogger);

      loggedCollector.warning(
        S57WarningCodes.unknownObjCode,
        'Object code 888 not recognized',
        recordId: 'FRID_888',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('WARN:'));
      expect(outputs.first, contains('[UNKNOWN_OBJ_CODE]'));
      expect(outputs.first, contains('Object code 888 not recognized'));
      expect(outputs.first, contains('(record:FRID_888)'));
    });

    test('should handle invalid/malformed object codes', () {
      // Test various invalid object code scenarios
      final testCases = [
        {'code': -1, 'description': 'negative object code'},
        {'code': 0, 'description': 'zero object code'},
        {'code': 99999, 'description': 'extremely large object code'},
      ];

      for (final testCase in testCases) {
        collector.warning(
          S57WarningCodes.unknownObjCode,
          'Invalid object code ${testCase['code']}: ${testCase['description']}',
          recordId: 'INVALID_${testCase['code']}',
        );
      }

      expect(collector.totalWarnings, equals(3));

      final warnings = collector.warnings;
      expect(warnings[0].message, contains('negative object code'));
      expect(warnings[1].message, contains('zero object code'));
      expect(warnings[2].message, contains('extremely large object code'));
    });

    test('should handle unknown codes with missing context gracefully', () {
      // Test warning without recordId or featureId
      collector.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code without context',
      );

      final warning = collector.warnings.first;
      expect(warning.recordId, isNull);
      expect(warning.featureId, isNull);
      expect(warning.message, equals('Unknown object code without context'));
    });
  });
}

/// Test logger implementation for capturing output
class TestLogger implements S57ParseLogger {
  final List<String> outputs;

  TestLogger(this.outputs);

  @override
  void onWarning(S57ParseWarning warning) {
    final severityPrefix = _getSeverityPrefix(warning.severity);
    final contextSuffix = _getContextSuffix(warning);
    outputs.add(
      '$severityPrefix[${warning.code}] ${warning.message}$contextSuffix',
    );
  }

  @override
  void onStartFile(String path) {
    outputs.add('Starting: $path');
  }

  @override
  void onFinishFile(String path, {required List<S57ParseWarning> warnings}) {
    outputs.add('Finished: $path (${warnings.length} warnings)');
  }

  String _getSeverityPrefix(S57WarningSeverity severity) {
    switch (severity) {
      case S57WarningSeverity.error:
        return 'ERROR: ';
      case S57WarningSeverity.warning:
        return 'WARN: ';
      case S57WarningSeverity.info:
        return 'INFO: ';
    }
  }

  String _getContextSuffix(S57ParseWarning warning) {
    final parts = <String>[];
    if (warning.recordId != null) parts.add('record:${warning.recordId}');
    if (warning.featureId != null) parts.add('feature:${warning.featureId}');
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }
}
