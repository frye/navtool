import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Depth Sanity Check Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should generate info warning for depth out of reasonable range', () {
      collector.info(
        S57WarningCodes.depthOutOfRange,
        'Depth value -15000.0m outside expected range for coastal waters',
        recordId: 'SOUNDG_RECORD_001',
        featureId: 'SOUNDG_001',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));
      
      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.depthOutOfRange));
      expect(warning.severity, equals(S57WarningSeverity.info));
      expect(warning.message, contains('Depth value -15000.0m'));
      expect(warning.message, contains('outside expected range'));
      expect(warning.recordId, equals('SOUNDG_RECORD_001'));
      expect(warning.featureId, equals('SOUNDG_001'));
    });

    test('should not throw in strict mode for depth sanity info', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Depth sanity warnings are info level, not errors
      strictCollector.info(
        S57WarningCodes.depthOutOfRange,
        'Unusually deep sounding detected',
        featureId: 'DEEP_001',
      );

      expect(strictCollector.totalWarnings, equals(1));
      expect(strictCollector.infoCount, equals(1));
      expect(strictCollector.hasErrors, isFalse);
    });

    test('should handle various out-of-range depth scenarios', () {
      final depthScenarios = [
        {
          'depth': 15000.0,
          'context': 'Excessive depth for continental shelf',
          'featureId': 'DEEP_OCEAN_001',
        },
        {
          'depth': -50.0,
          'context': 'Negative depth indicating elevation above sea level',
          'featureId': 'LAND_ELEVATION_001',
        },
        {
          'depth': 0.001,
          'context': 'Extremely shallow depth near precision limit',
          'featureId': 'SHALLOW_001',
        },
        {
          'depth': 999999.0,
          'context': 'Suspicious depth value possibly indicating data error',
          'featureId': 'SUSPECT_001',
        },
      ];

      for (final scenario in depthScenarios) {
        collector.info(
          S57WarningCodes.depthOutOfRange,
          'Depth ${scenario['depth']}m: ${scenario['context']}',
          featureId: scenario['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(4));
      expect(collector.infoCount, equals(4));

      final depthWarnings = collector.getWarningsByCode(S57WarningCodes.depthOutOfRange);
      expect(depthWarnings, hasLength(4));
      
      expect(depthWarnings[0].message, contains('15000.0m'));
      expect(depthWarnings[1].message, contains('-50.0m'));
      expect(depthWarnings[2].message, contains('0.001m'));
      expect(depthWarnings[3].message, contains('999999.0m'));
    });

    test('should provide context for different water body types', () {
      final waterBodyContexts = [
        {
          'type': 'Coastal waters',
          'expectedRange': '0-200m',
          'actualDepth': 5000.0,
          'featureId': 'COASTAL_DEEP_001',
        },
        {
          'type': 'Harbor area',
          'expectedRange': '0-50m',
          'actualDepth': 150.0,
          'featureId': 'HARBOR_DEEP_001',
        },
        {
          'type': 'River channel',
          'expectedRange': '0-30m',
          'actualDepth': 85.0,
          'featureId': 'RIVER_DEEP_001',
        },
      ];

      for (final context in waterBodyContexts) {
        collector.info(
          S57WarningCodes.depthOutOfRange,
          '${context['type']} depth ${context['actualDepth']}m exceeds expected range ${context['expectedRange']}',
          featureId: context['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('Coastal waters'));
      expect(warnings[1].message, contains('Harbor area'));
      expect(warnings[2].message, contains('River channel'));
    });

    test('should handle depth attribute validation for different object types', () {
      final objectDepthChecks = [
        {
          'objectType': 'SOUNDG',
          'attribute': 'VALSOU',
          'value': 12000.0,
          'message': 'SOUNDG VALSOU 12000.0m exceeds typical sounding range',
        },
        {
          'objectType': 'DEPARE',
          'attribute': 'DRVAL1',
          'value': -100.0,
          'message': 'DEPARE DRVAL1 -100.0m indicates land elevation in depth area',
        },
        {
          'objectType': 'WRECKS',
          'attribute': 'VALSOU',
          'value': 0.0,
          'message': 'WRECKS VALSOU 0.0m may indicate drying wreck',
        },
      ];

      for (final check in objectDepthChecks) {
        collector.info(
          S57WarningCodes.depthOutOfRange,
          check['message'] as String,
          recordId: '${check['objectType']}_DEPTH_CHECK',
          featureId: '${check['objectType']}_${check['value']}'.replaceAll('.', '_'),
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('SOUNDG VALSOU'));
      expect(warnings[1].message, contains('DEPARE DRVAL1'));
      expect(warnings[2].message, contains('WRECKS VALSOU'));
    });

    test('should track depth sanity check statistics', () {
      // Add various warning types including depth checks
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth 1 out of range');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth 2 out of range');
      collector.info(S57WarningCodes.polygonClosedAuto, 'Polygon auto-closed');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing attr');

      final summary = collector.createSummaryReport();
      
      expect(summary['totalWarnings'], equals(4));
      expect(summary['warningsByCode'][S57WarningCodes.depthOutOfRange], equals(2));
      expect(summary['warningsBySeverity']['info'], equals(3));
      expect(summary['warningsBySeverity']['warning'], equals(1));
    });

    test('should log depth sanity warnings correctly', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.info(
        S57WarningCodes.depthOutOfRange,
        'Sounding depth 8000.0m exceeds expected continental shelf range',
        recordId: 'LOG_DEPTH_001',
        featureId: 'SOUNDG_LOG_001',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('INFO:'));
      expect(outputs.first, contains('[DEPTH_OUT_OF_RANGE]'));
      expect(outputs.first, contains('8000.0m exceeds expected'));
      expect(outputs.first, contains('(record:LOG_DEPTH_001, feature:SOUNDG_LOG_001)'));
    });

    test('should handle depth precision and unit conversion warnings', () {
      final precisionScenarios = [
        {
          'message': 'Depth precision 0.00001m exceeds sensor accuracy - possible over-precision',
          'featureId': 'PRECISION_001',
        },
        {
          'message': 'Depth unit conversion: 500 fathoms = 914.4m - unusually deep for charted area',
          'featureId': 'FATHOMS_001',
        },
        {
          'message': 'Depth value 12.345678m has excessive decimal places - rounded to 12.3m',
          'featureId': 'DECIMAL_001',
        },
      ];

      for (final scenario in precisionScenarios) {
        collector.info(
          S57WarningCodes.depthOutOfRange,
          scenario['message'] as String,
          featureId: scenario['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('precision 0.00001m'));
      expect(warnings[1].message, contains('500 fathoms'));
      expect(warnings[2].message, contains('excessive decimal places'));
    });

    test('should handle bathymetric survey context', () {
      collector.info(
        S57WarningCodes.depthOutOfRange,
        'Survey sounding 11,034m (Challenger Deep vicinity) - verify this abyssal depth measurement',
        recordId: 'SURVEY_DEEP_001',
        featureId: 'CHALLENGER_DEEP_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('11,034m'));
      expect(warning.message, contains('Challenger Deep'));
      expect(warning.message, contains('verify this abyssal depth'));
    });

    test('should handle depth range validation with geographic context', () {
      final geographicContexts = [
        {
          'region': 'Mediterranean Sea',
          'maxExpected': 5000.0,
          'actualDepth': 6000.0,
          'featureId': 'MED_DEEP_001',
        },
        {
          'region': 'Great Lakes',
          'maxExpected': 400.0,
          'actualDepth': 1000.0,
          'featureId': 'LAKES_DEEP_001',
        },
        {
          'region': 'Arctic Ocean',
          'maxExpected': 4000.0,
          'actualDepth': 5500.0,
          'featureId': 'ARCTIC_DEEP_001',
        },
      ];

      for (final context in geographicContexts) {
        collector.info(
          S57WarningCodes.depthOutOfRange,
          '${context['region']} depth ${context['actualDepth']}m exceeds regional maximum ${context['maxExpected']}m',
          featureId: context['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('Mediterranean Sea'));
      expect(warnings[1].message, contains('Great Lakes'));
      expect(warnings[2].message, contains('Arctic Ocean'));
    });

    test('should handle edge cases with depth validation', () {
      // Test with minimal context
      collector.info(
        S57WarningCodes.depthOutOfRange,
        'Depth out of range',
      );

      // Test with partial context
      collector.info(
        S57WarningCodes.depthOutOfRange,
        'Unusual depth reading detected',
        recordId: 'PARTIAL_001',
      );

      expect(collector.totalWarnings, equals(2));
      
      final warnings = collector.warnings;
      expect(warnings[0].recordId, isNull);
      expect(warnings[0].featureId, isNull);
      expect(warnings[1].recordId, equals('PARTIAL_001'));
      expect(warnings[1].featureId, isNull);
    });

    test('should work with file processing context', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.startFile('/charts/bathymetry/US5CN11M.000');
      
      loggedCollector.info(
        S57WarningCodes.depthOutOfRange,
        'Deep ocean sounding requires verification',
        featureId: 'SOUNDG_VERIFY_001',
      );
      
      loggedCollector.finishFile('/charts/bathymetry/US5CN11M.000');

      expect(outputs, hasLength(3));
      expect(outputs[0], contains('Starting: /charts/bathymetry/US5CN11M.000'));
      expect(outputs[1], contains('[DEPTH_OUT_OF_RANGE]'));
      expect(outputs[2], contains('Finished: /charts/bathymetry/US5CN11M.000 (1 warnings)'));
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