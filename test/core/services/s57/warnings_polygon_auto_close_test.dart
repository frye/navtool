import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Polygon Auto-Close Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should generate info when polygon auto-closed', () {
      collector.info(
        S57WarningCodes.polygonClosedAuto,
        'Polygon feature DEPARE_001 auto-closed by adding connection from last to first coordinate',
        recordId: 'DEPARE_RECORD_001',
        featureId: 'DEPARE_001',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));
      
      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.polygonClosedAuto));
      expect(warning.severity, equals(S57WarningSeverity.info));
      expect(warning.message, contains('auto-closed'));
      expect(warning.message, contains('adding connection'));
      expect(warning.recordId, equals('DEPARE_RECORD_001'));
      expect(warning.featureId, equals('DEPARE_001'));
    });

    test('should not throw in strict mode for auto-close info', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Auto-close warnings are info level, not errors
      strictCollector.info(
        S57WarningCodes.polygonClosedAuto,
        'Area feature auto-closed programmatically',
        featureId: 'AREA_001',
      );

      expect(strictCollector.totalWarnings, equals(1));
      expect(strictCollector.infoCount, equals(1));
      expect(strictCollector.hasErrors, isFalse);
    });

    test('should handle multiple polygon auto-closures', () {
      final polygonFeatures = [
        {'id': 'DEPARE_001', 'type': 'Depth Area'},
        {'id': 'LNDARE_001', 'type': 'Land Area'},
        {'id': 'RESARE_001', 'type': 'Restricted Area'},
        {'id': 'CTNARE_001', 'type': 'Caution Area'},
      ];

      for (final feature in polygonFeatures) {
        collector.info(
          S57WarningCodes.polygonClosedAuto,
          '${feature['type']} ${feature['id']} auto-closed - first and last coordinates were not equal',
          recordId: '${feature['id']}_RECORD',
          featureId: feature['id'] as String,
        );
      }

      expect(collector.totalWarnings, equals(4));
      expect(collector.infoCount, equals(4));

      final autoCloseWarnings = collector.getWarningsByCode(S57WarningCodes.polygonClosedAuto);
      expect(autoCloseWarnings, hasLength(4));
      
      expect(autoCloseWarnings[0].featureId, equals('DEPARE_001'));
      expect(autoCloseWarnings[1].featureId, equals('LNDARE_001'));
      expect(autoCloseWarnings[2].featureId, equals('RESARE_001'));
      expect(autoCloseWarnings[3].featureId, equals('CTNARE_001'));
    });

    test('should provide detailed coordinate information', () {
      collector.info(
        S57WarningCodes.polygonClosedAuto,
        'Area polygon auto-closed: start(12.345, 56.789) != end(12.346, 56.790) - distance 0.001° - closing segment added',
        recordId: 'COORD_DETAILS_001',
        featureId: 'AREA_PRECISE_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('start(12.345, 56.789)'));
      expect(warning.message, contains('end(12.346, 56.790)'));
      expect(warning.message, contains('distance 0.001°'));
      expect(warning.message, contains('closing segment added'));
    });

    test('should handle different polygon types and contexts', () {
      final polygonContexts = [
        {
          'context': 'Marine area processing',
          'message': 'DEPARE polygon ring auto-closed during marine area assembly',
          'featureId': 'DEPARE_MARINE_001',
        },
        {
          'context': 'Coastline processing',
          'message': 'COALNE polygon auto-closed to form complete coastal boundary',
          'featureId': 'COAST_BOUNDARY_001',
        },
        {
          'context': 'Restriction zone',
          'message': 'RESARE polygon auto-closed for navigation restriction area',
          'featureId': 'RESTRICTION_ZONE_001',
        },
      ];

      for (final context in polygonContexts) {
        collector.info(
          S57WarningCodes.polygonClosedAuto,
          '${context['context']}: ${context['message']}',
          featureId: context['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('Marine area processing'));
      expect(warnings[1].message, contains('Coastline processing'));
      expect(warnings[2].message, contains('Restriction zone'));
    });

    test('should track polygon closure statistics', () {
      // Add various warning types including auto-closures
      collector.info(S57WarningCodes.polygonClosedAuto, 'Auto-close 1');
      collector.info(S57WarningCodes.polygonClosedAuto, 'Auto-close 2');
      collector.info(S57WarningCodes.polygonClosedAuto, 'Auto-close 3');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing attr');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth range');

      final summary = collector.createSummaryReport();
      
      expect(summary['totalWarnings'], equals(5));
      expect(summary['warningsByCode'][S57WarningCodes.polygonClosedAuto], equals(3));
      expect(summary['warningsBySeverity']['info'], equals(4));
      expect(summary['warningsBySeverity']['warning'], equals(1));
    });

    test('should log polygon auto-close warnings correctly', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.info(
        S57WarningCodes.polygonClosedAuto,
        'Area polygon automatically closed during geometry processing',
        recordId: 'LOG_POLYGON_001',
        featureId: 'AREA_LOG_001',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('INFO:'));
      expect(outputs.first, contains('[POLYGON_CLOSED_AUTO]'));
      expect(outputs.first, contains('automatically closed'));
      expect(outputs.first, contains('(record:LOG_POLYGON_001, feature:AREA_LOG_001)'));
    });

    test('should handle complex polygon closure scenarios', () {
      final complexScenarios = [
        {
          'message': 'Multi-ring polygon - outer ring auto-closed, inner rings already closed',
          'featureId': 'COMPLEX_MULTI_001',
        },
        {
          'message': 'Island polygon auto-closed with tolerance 0.0001° due to coordinate precision',
          'featureId': 'ISLAND_PRECISE_001',
        },
        {
          'message': 'Self-intersecting polygon auto-closed - may require manual review',
          'featureId': 'SELF_INTERSECT_001',
        },
      ];

      for (final scenario in complexScenarios) {
        collector.info(
          S57WarningCodes.polygonClosedAuto,
          scenario['message'] as String,
          featureId: scenario['featureId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('Multi-ring polygon'));
      expect(warnings[1].message, contains('tolerance 0.0001°'));
      expect(warnings[2].message, contains('Self-intersecting polygon'));
    });

    test('should handle polygon closure with coordinate system context', () {
      collector.info(
        S57WarningCodes.polygonClosedAuto,
        'Polygon auto-closed in WGS84 coordinates - geographic closure applied with geodesic correction',
        recordId: 'GEODESIC_001',
        featureId: 'WGS84_POLYGON_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('WGS84 coordinates'));
      expect(warning.message, contains('geodesic correction'));
    });

    test('should handle edge cases with polygon auto-closure', () {
      // Test with minimal context
      collector.info(
        S57WarningCodes.polygonClosedAuto,
        'Polygon auto-closed',
      );

      // Test with partial context
      collector.info(
        S57WarningCodes.polygonClosedAuto,
        'Area feature auto-closed during processing',
        recordId: 'PARTIAL_001',
      );

      expect(collector.totalWarnings, equals(2));
      
      final warnings = collector.warnings;
      expect(warnings[0].recordId, isNull);
      expect(warnings[0].featureId, isNull);
      expect(warnings[1].recordId, equals('PARTIAL_001'));
      expect(warnings[1].featureId, isNull);
    });

    test('should work with threshold limits', () {
      final collectorWithThreshold = S57WarningCollector(
        options: const S57ParseOptions(strictMode: false, maxWarnings: 5),
      );

      // Add multiple auto-close warnings
      for (int i = 1; i <= 6; i++) {
        collectorWithThreshold.info(
          S57WarningCodes.polygonClosedAuto,
          'Auto-close polygon $i',
          featureId: 'POLY_$i',
        );
      }

      expect(collectorWithThreshold.totalWarnings, equals(6));
      expect(collectorWithThreshold.isThresholdExceeded, isTrue);
      
      final summary = collectorWithThreshold.createSummaryReport();
      expect(summary['isThresholdExceeded'], isTrue);
      expect(summary['maxWarnings'], equals(5));
    });

    test('should handle polygon auto-closure with file context', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.startFile('/charts/US5CN11M.000');
      
      loggedCollector.info(
        S57WarningCodes.polygonClosedAuto,
        'Depth area polygon auto-closed',
        featureId: 'DEPARE_FILE_001',
      );
      
      loggedCollector.finishFile('/charts/US5CN11M.000');

      expect(outputs, hasLength(3));
      expect(outputs[0], contains('Starting: /charts/US5CN11M.000'));
      expect(outputs[1], contains('[POLYGON_CLOSED_AUTO]'));
      expect(outputs[2], contains('Finished: /charts/US5CN11M.000 (1 warnings)'));
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