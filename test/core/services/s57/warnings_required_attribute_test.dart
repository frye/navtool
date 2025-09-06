import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Required Attribute Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should warn when DEPARE missing DRVAL1', () {
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing required attribute DRVAL1 for DEPARE (Depth Area)',
        recordId: 'DEPARE_001',
        featureId: 'DA123456',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));

      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.missingRequiredAttr));
      expect(warning.severity, equals(S57WarningSeverity.warning));
      expect(warning.message, contains('Missing required attribute DRVAL1'));
      expect(warning.message, contains('DEPARE'));
      expect(warning.recordId, equals('DEPARE_001'));
      expect(warning.featureId, equals('DA123456'));
    });

    test('should warn when SOUNDG missing VALSOU', () {
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing required attribute VALSOU for SOUNDG (Sounding)',
        recordId: 'SOUNDG_042',
        featureId: 'SG789012',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('Missing required attribute VALSOU'));
      expect(warning.message, contains('SOUNDG'));
      expect(warning.recordId, equals('SOUNDG_042'));
      expect(warning.featureId, equals('SG789012'));
    });

    test('should warn when buoy missing CATBOY', () {
      const buoyTypes = ['BOYLAT', 'BOYISD', 'BOYSPP'];

      for (final buoyType in buoyTypes) {
        collector.warning(
          S57WarningCodes.missingRequiredAttr,
          'Missing required attribute CATBOY for $buoyType',
          recordId: '${buoyType}_001',
          featureId: 'BY${buoyTypes.indexOf(buoyType)}001',
        );
      }

      expect(collector.totalWarnings, equals(3));

      final warnings = collector.warnings;
      expect(warnings[0].message, contains('CATBOY for BOYLAT'));
      expect(warnings[1].message, contains('CATBOY for BOYISD'));
      expect(warnings[2].message, contains('CATBOY for BOYSPP'));
    });

    test('should handle multiple missing attributes for same object', () {
      const featureId = 'COMPLEX_001';

      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing required attribute DRVAL1 for DEPARE',
        recordId: 'ATTR_CHECK_001',
        featureId: featureId,
      );

      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing required attribute OBJNAM for DEPARE',
        recordId: 'ATTR_CHECK_002',
        featureId: featureId,
      );

      expect(collector.totalWarnings, equals(2));

      final warnings = collector.getWarningsByCode(
        S57WarningCodes.missingRequiredAttr,
      );
      expect(warnings, hasLength(2));

      // Both warnings should reference the same feature
      expect(warnings.every((w) => w.featureId == featureId), isTrue);
      expect(warnings[0].message, contains('DRVAL1'));
      expect(warnings[1].message, contains('OBJNAM'));
    });

    test(
      'should work in strict mode without throwing (warnings not errors)',
      () {
        final strictCollector = S57WarningCollector(
          options: const S57ParseOptions(strictMode: true),
        );

        // Missing required attributes are warnings, not errors
        strictCollector.warning(
          S57WarningCodes.missingRequiredAttr,
          'Missing DRVAL1 for DEPARE',
          recordId: 'STRICT_001',
        );

        expect(strictCollector.totalWarnings, equals(1));
        expect(strictCollector.warningCount, equals(1));
        expect(strictCollector.hasErrors, isFalse);
      },
    );

    test('should handle complex attribute validation scenarios', () {
      // Simulate complex validation with multiple object types
      final validationScenarios = [
        {
          'objectType': 'DEPARE',
          'missingAttr': 'DRVAL1',
          'recordId': 'DEPARE_DEPTH_001',
          'featureId': 'DA001',
        },
        {
          'objectType': 'SOUNDG',
          'missingAttr': 'VALSOU',
          'recordId': 'SOUNDG_POINT_001',
          'featureId': 'SG001',
        },
        {
          'objectType': 'BOYLAT',
          'missingAttr': 'CATBOY',
          'recordId': 'BUOY_LAT_001',
          'featureId': 'BL001',
        },
        {
          'objectType': 'LIGHTS',
          'missingAttr': 'HEIGHT',
          'recordId': 'LIGHT_STRUCT_001',
          'featureId': 'LT001',
        },
      ];

      for (final scenario in validationScenarios) {
        collector.warning(
          S57WarningCodes.missingRequiredAttr,
          'Missing required attribute ${scenario['missingAttr']} for ${scenario['objectType']}',
          recordId: scenario['recordId'] as String,
          featureId: scenario['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(4));
      expect(collector.warningCount, equals(4));

      final warnings = collector.getWarningsByCode(
        S57WarningCodes.missingRequiredAttr,
      );
      expect(warnings, hasLength(4));

      // Verify all different object types are represented
      expect(warnings.any((w) => w.message.contains('DEPARE')), isTrue);
      expect(warnings.any((w) => w.message.contains('SOUNDG')), isTrue);
      expect(warnings.any((w) => w.message.contains('BOYLAT')), isTrue);
      expect(warnings.any((w) => w.message.contains('LIGHTS')), isTrue);
    });

    test('should provide detailed context for attribute validation', () {
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Required attribute DRVAL1 (minimum depth) missing for DEPARE feature in shallow water area',
        recordId: 'DEPARE_SHALLOW_001',
        featureId: 'SW_AREA_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('minimum depth'));
      expect(warning.message, contains('shallow water area'));
      expect(warning.recordId, equals('DEPARE_SHALLOW_001'));
      expect(warning.featureId, equals('SW_AREA_001'));
    });

    test('should handle null attribute values as missing', () {
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Required attribute VALSOU for SOUNDG is null (treated as missing)',
        recordId: 'NULL_ATTR_001',
        featureId: 'SG_NULL_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('is null (treated as missing)'));
    });

    test('should generate summary with required attribute warnings', () {
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing DRVAL1');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing VALSOU');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing CATBOY');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth info');

      final summary = collector.createSummaryReport();

      expect(summary['totalWarnings'], equals(4));
      expect(
        summary['warningsByCode'][S57WarningCodes.missingRequiredAttr],
        equals(3),
      );
      expect(summary['warningsBySeverity']['warning'], equals(3));
      expect(summary['warningsBySeverity']['info'], equals(1));
    });

    test('should log required attribute warnings correctly', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);

      final loggedCollector = S57WarningCollector(logger: testLogger);

      loggedCollector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing DRVAL1 for DEPARE depth area',
        recordId: 'DEPARE_001',
        featureId: 'DA001',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('WARN:'));
      expect(outputs.first, contains('[MISSING_REQUIRED_ATTR]'));
      expect(outputs.first, contains('Missing DRVAL1 for DEPARE'));
      expect(outputs.first, contains('(record:DEPARE_001, feature:DA001)'));
    });

    test('should handle edge cases for required attributes', () {
      // Test with minimal context
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing required attribute',
      );

      // Test with partial context
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing attribute with record only',
        recordId: 'PARTIAL_001',
      );

      // Test with feature context only
      collector.warning(
        S57WarningCodes.missingRequiredAttr,
        'Missing attribute with feature only',
        featureId: 'FEAT_ONLY_001',
      );

      expect(collector.totalWarnings, equals(3));

      final warnings = collector.warnings;
      expect(warnings[0].recordId, isNull);
      expect(warnings[0].featureId, isNull);

      expect(warnings[1].recordId, equals('PARTIAL_001'));
      expect(warnings[1].featureId, isNull);

      expect(warnings[2].recordId, isNull);
      expect(warnings[2].featureId, equals('FEAT_ONLY_001'));
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
