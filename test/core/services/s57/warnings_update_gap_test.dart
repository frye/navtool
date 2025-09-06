import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Update Gap Detection Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should generate error for missing intermediate update file', () {
      collector.error(
        S57WarningCodes.updateGap,
        'Missing update file between 001 and 003 - gap in update sequence',
        recordId: 'UPDATE_SEQUENCE_001',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));
      
      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.updateGap));
      expect(warning.severity, equals(S57WarningSeverity.error));
      expect(warning.message, contains('Missing update file'));
      expect(warning.message, contains('gap in update sequence'));
      expect(warning.recordId, equals('UPDATE_SEQUENCE_001'));
    });

    test('should throw in strict mode for update gap errors', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Update gaps are errors and should throw in strict mode
      expect(
        () => strictCollector.error(
          S57WarningCodes.updateGap,
          'Critical update gap detected',
        ),
        throwsA(isA<S57StrictModeException>()),
      );
    });

    test('should handle multiple update gaps in sequence', () {
      final updateGaps = [
        {'from': '001', 'to': '003', 'missing': '002'},
        {'from': '003', 'to': '006', 'missing': '004,005'},
        {'from': '008', 'to': '010', 'missing': '009'},
      ];

      for (final gap in updateGaps) {
        collector.error(
          S57WarningCodes.updateGap,
          'Update gap from ${gap['from']} to ${gap['to']} - missing files: ${gap['missing']}',
          recordId: 'GAP_${gap['from']}_${gap['to']}',
        );
      }

      expect(collector.totalWarnings, equals(3));
      expect(collector.errorCount, equals(3));
      expect(collector.hasErrors, isTrue);

      final gapWarnings = collector.getWarningsByCode(S57WarningCodes.updateGap);
      expect(gapWarnings, hasLength(3));
      
      expect(gapWarnings[0].message, contains('missing files: 002'));
      expect(gapWarnings[1].message, contains('missing files: 004,005'));
      expect(gapWarnings[2].message, contains('missing files: 009'));
    });

    test('should provide detailed context for update gap detection', () {
      collector.error(
        S57WarningCodes.updateGap,
        'Update sequence incomplete: found files [001, 004, 005] but missing [002, 003] required for continuous updates',
        recordId: 'UPDATE_VALIDATION_001',
        featureId: 'CHART_UPDATE_SEQUENCE',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('Update sequence incomplete'));
      expect(warning.message, contains('found files [001, 004, 005]'));
      expect(warning.message, contains('missing [002, 003]'));
      expect(warning.recordId, equals('UPDATE_VALIDATION_001'));
      expect(warning.featureId, equals('CHART_UPDATE_SEQUENCE'));
    });

    test('should handle update gap with RVER mismatch context', () {
      collector.error(
        S57WarningCodes.updateGap,
        'Update gap detected: RVER sequence jumps from 5 to 8 without intermediate updates 6,7',
        recordId: 'RVER_GAP_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('RVER sequence jumps'));
      expect(warning.message, contains('without intermediate updates 6,7'));
    });

    test('should escalate to exception in strict mode with context preservation', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      strictCollector.warning(S57WarningCodes.missingRequiredAttr, 'Some attribute missing');

      try {
        strictCollector.error(
          S57WarningCodes.updateGap,
          'Fatal update gap - cannot proceed with incomplete sequence',
          recordId: 'FATAL_GAP_001',
        );
        fail('Expected S57StrictModeException');
      } on S57StrictModeException catch (e) {
        expect(e.triggeredBy.code, equals(S57WarningCodes.updateGap));
        expect(e.triggeredBy.message, contains('Fatal update gap'));
        expect(e.triggeredBy.recordId, equals('FATAL_GAP_001'));
        
        // Should preserve previous warnings
        expect(e.allWarnings, hasLength(2));
        expect(e.allWarnings[0].code, equals(S57WarningCodes.missingRequiredAttr));
        expect(e.allWarnings[1].code, equals(S57WarningCodes.updateGap));
      }
    });

    test('should handle different update file naming patterns', () {
      final namingPatterns = [
        {'pattern': 'Sequential', 'gap': 'UP001.001 to UP001.003 missing UP001.002'},
        {'pattern': 'Date-based', 'gap': '20230101.000 to 20230103.000 missing 20230102.000'},
        {'pattern': 'Version', 'gap': 'v1.0 to v1.2 missing v1.1'},
      ];

      for (final pattern in namingPatterns) {
        collector.error(
          S57WarningCodes.updateGap,
          '${pattern['pattern']} update gap: ${pattern['gap']}',
          recordId: 'PATTERN_${pattern['pattern']!.toUpperCase()}',
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.getWarningsByCode(S57WarningCodes.updateGap);
      expect(warnings[0].message, contains('Sequential update gap'));
      expect(warnings[1].message, contains('Date-based update gap'));
      expect(warnings[2].message, contains('Version update gap'));
    });

    test('should log update gap errors correctly', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.error(
        S57WarningCodes.updateGap,
        'Update file sequence broken - missing intermediate files',
        recordId: 'LOG_GAP_001',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('ERROR:'));
      expect(outputs.first, contains('[UPDATE_GAP]'));
      expect(outputs.first, contains('Update file sequence broken'));
      expect(outputs.first, contains('(record:LOG_GAP_001)'));
    });

    test('should generate summary statistics for update gap errors', () {
      collector.error(S57WarningCodes.updateGap, 'Gap 1');
      collector.error(S57WarningCodes.updateGap, 'Gap 2');
      collector.error(S57WarningCodes.updateRverMismatch, 'RVER error');
      collector.warning(S57WarningCodes.unknownObjCode, 'Unknown warning');

      final summary = collector.createSummaryReport();
      
      expect(summary['totalWarnings'], equals(4));
      expect(summary['warningsByCode'][S57WarningCodes.updateGap], equals(2));
      expect(summary['warningsByCode'][S57WarningCodes.updateRverMismatch], equals(1));
      expect(summary['warningsBySeverity']['error'], equals(3));
      expect(summary['warningsBySeverity']['warning'], equals(1));
      expect(summary['hasErrors'], isTrue);
    });

    test('should handle update gap detection with file system context', () {
      collector.error(
        S57WarningCodes.updateGap,
        'File system scan found gaps in update directory: /charts/updates/ missing files 002.000, 003.000, 005.000',
        recordId: 'FILESYSTEM_SCAN_001',
        featureId: 'CHART_US5CN11M',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('File system scan'));
      expect(warning.message, contains('/charts/updates/'));
      expect(warning.message, contains('missing files 002.000, 003.000, 005.000'));
      expect(warning.featureId, equals('CHART_US5CN11M'));
    });

    test('should handle update gap with integrity check context', () {
      collector.error(
        S57WarningCodes.updateGap,
        'Update integrity check failed: base edition 001 + updates [002, 005] cannot be applied - missing update 003 and 004',
        recordId: 'INTEGRITY_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('Update integrity check failed'));
      expect(warning.message, contains('base edition 001'));
      expect(warning.message, contains('missing update 003 and 004'));
    });

    test('should handle edge cases with update gap detection', () {
      // Test with minimal context
      collector.error(
        S57WarningCodes.updateGap,
        'Update gap detected',
      );

      // Test with malformed update sequence
      collector.error(
        S57WarningCodes.updateGap,
        'Corrupted update sequence - cannot determine gap extent',
        recordId: 'CORRUPTED_001',
      );

      expect(collector.totalWarnings, equals(2));
      expect(collector.errorCount, equals(2));
      
      final warnings = collector.warnings;
      expect(warnings[0].recordId, isNull);
      expect(warnings[0].featureId, isNull);
      expect(warnings[1].recordId, equals('CORRUPTED_001'));
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
    outputs.add('$severityPrefix[${warning.code}] ${warning.message}$contextSuffix');
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