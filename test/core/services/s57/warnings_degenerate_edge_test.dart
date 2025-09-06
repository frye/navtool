import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Degenerate Edge Warnings', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should warn when edge has zero nodes', () {
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge EDGE_001 has 0 nodes - cannot form valid geometry',
        recordId: 'EDGE_RECORD_001',
        featureId: 'EDGE_001',
      );

      final warnings = collector.warnings;
      expect(warnings, hasLength(1));
      
      final warning = warnings.first;
      expect(warning.code, equals(S57WarningCodes.degenerateEdge));
      expect(warning.severity, equals(S57WarningSeverity.warning));
      expect(warning.message, contains('0 nodes'));
      expect(warning.message, contains('cannot form valid geometry'));
      expect(warning.recordId, equals('EDGE_RECORD_001'));
      expect(warning.featureId, equals('EDGE_001'));
    });

    test('should warn when edge has only one node', () {
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge EDGE_002 has only 1 node - requires at least 2 nodes to form line',
        recordId: 'EDGE_RECORD_002',
        featureId: 'EDGE_002',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('only 1 node'));
      expect(warning.message, contains('requires at least 2 nodes'));
      expect(warning.featureId, equals('EDGE_002'));
    });

    test('should handle multiple degenerate edges', () {
      final degenerateEdges = [
        {'id': 'EDGE_001', 'nodes': 0, 'record': 'REC_001'},
        {'id': 'EDGE_002', 'nodes': 1, 'record': 'REC_002'},
        {'id': 'EDGE_003', 'nodes': 0, 'record': 'REC_003'},
      ];

      for (final edge in degenerateEdges) {
        collector.warning(
          S57WarningCodes.degenerateEdge,
          'Edge ${edge['id']} has ${edge['nodes']} nodes - degenerate geometry',
          recordId: edge['record'] as String,
          featureId: edge['id'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      expect(collector.warningCount, equals(3));

      final edgeWarnings = collector.getWarningsByCode(S57WarningCodes.degenerateEdge);
      expect(edgeWarnings, hasLength(3));
      
      expect(edgeWarnings[0].featureId, equals('EDGE_001'));
      expect(edgeWarnings[1].featureId, equals('EDGE_002'));
      expect(edgeWarnings[2].featureId, equals('EDGE_003'));
    });

    test('should provide context for edge geometry construction', () {
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge connecting nodes [123, 456] has insufficient coordinate data - only 1 valid point',
        recordId: 'SPATIAL_EDGE_001',
        featureId: 'COASTLINE_SEGMENT_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('connecting nodes [123, 456]'));
      expect(warning.message, contains('insufficient coordinate data'));
      expect(warning.featureId, equals('COASTLINE_SEGMENT_001'));
    });

    test('should work in strict mode without throwing (warnings not errors)', () {
      final strictCollector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Degenerate edges are warnings, not errors
      strictCollector.warning(
        S57WarningCodes.degenerateEdge,
        'Degenerate edge detected',
        featureId: 'EDGE_STRICT_001',
      );

      expect(strictCollector.totalWarnings, equals(1));
      expect(strictCollector.warningCount, equals(1));
      expect(strictCollector.hasErrors, isFalse);
    });

    test('should handle edge validation in different geometry types', () {
      final geometryTypes = [
        {'type': 'COASTLINE', 'edge': 'COAST_001'},
        {'type': 'DEPTH_CONTOUR', 'edge': 'DEPTH_001'},
        {'type': 'TRAFFIC_LANE', 'edge': 'LANE_001'},
        {'type': 'PIPELINE', 'edge': 'PIPE_001'},
      ];

      for (final geom in geometryTypes) {
        collector.warning(
          S57WarningCodes.degenerateEdge,
          'Degenerate edge in ${geom['type']} geometry - edge ${geom['edge']} has no nodes',
          recordId: 'GEOM_${geom['type']}_REC',
          featureId: geom['edge'] as String,
        );
      }

      expect(collector.totalWarnings, equals(4));
      
      final warnings = collector.getWarningsByCode(S57WarningCodes.degenerateEdge);
      expect(warnings, hasLength(4));
      
      expect(warnings.any((w) => w.message.contains('COASTLINE')), isTrue);
      expect(warnings.any((w) => w.message.contains('DEPTH_CONTOUR')), isTrue);
      expect(warnings.any((w) => w.message.contains('TRAFFIC_LANE')), isTrue);
      expect(warnings.any((w) => w.message.contains('PIPELINE')), isTrue);
    });

    test('should handle edge node reference errors', () {
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge EDGE_001 references missing node 999 - edge geometry incomplete',
        recordId: 'EDGE_REF_001',
        featureId: 'EDGE_001',
      );

      final warning = collector.warnings.first;
      expect(warning.message, contains('references missing node 999'));
      expect(warning.message, contains('edge geometry incomplete'));
    });

    test('should provide statistics for degenerate edge warnings', () {
      // Add multiple types of warnings including degenerate edges
      collector.warning(S57WarningCodes.degenerateEdge, 'Edge 1 degenerate');
      collector.warning(S57WarningCodes.degenerateEdge, 'Edge 2 degenerate');
      collector.warning(S57WarningCodes.degenerateEdge, 'Edge 3 degenerate');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing attribute');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth info');

      final summary = collector.createSummaryReport();
      
      expect(summary['totalWarnings'], equals(5));
      expect(summary['warningsByCode'][S57WarningCodes.degenerateEdge], equals(3));
      expect(summary['warningsBySeverity']['warning'], equals(4));
      expect(summary['warningsBySeverity']['info'], equals(1));
    });

    test('should log degenerate edge warnings correctly', () {
      final outputs = <String>[];
      final testLogger = TestLogger(outputs);
      
      final loggedCollector = S57WarningCollector(logger: testLogger);
      
      loggedCollector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge has insufficient nodes for line geometry',
        recordId: 'EDGE_LOG_001',
        featureId: 'LINE_001',
      );

      expect(outputs, hasLength(1));
      expect(outputs.first, contains('WARN:'));
      expect(outputs.first, contains('[DEGENERATE_EDGE]'));
      expect(outputs.first, contains('insufficient nodes'));
      expect(outputs.first, contains('(record:EDGE_LOG_001, feature:LINE_001)'));
    });

    test('should handle complex edge topology scenarios', () {
      // Simulate complex topology validation
      final complexScenarios = [
        {
          'message': 'Edge forms self-loop with single point - topologically invalid',
          'edgeId': 'SELF_LOOP_001',
          'recordId': 'TOPO_001',
        },
        {
          'message': 'Edge has coincident start and end nodes but no intermediate geometry',
          'edgeId': 'COINCIDENT_001',
          'recordId': 'TOPO_002',
        },
        {
          'message': 'Edge references deleted node - connectivity broken',
          'edgeId': 'BROKEN_001',
          'recordId': 'TOPO_003',
        },
      ];

      for (final scenario in complexScenarios) {
        collector.warning(
          S57WarningCodes.degenerateEdge,
          scenario['message'] as String,
          recordId: scenario['recordId'] as String,
          featureId: scenario['edgeId'] as String,
        );
      }

      expect(collector.totalWarnings, equals(3));
      
      final warnings = collector.warnings;
      expect(warnings[0].message, contains('self-loop'));
      expect(warnings[1].message, contains('coincident start and end'));
      expect(warnings[2].message, contains('references deleted node'));
    });

    test('should handle edge warnings with missing context', () {
      // Test with minimal context
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Degenerate edge detected during geometry processing',
      );

      // Test with partial context
      collector.warning(
        S57WarningCodes.degenerateEdge,
        'Edge validation failed',
        recordId: 'PARTIAL_001',
      );

      expect(collector.totalWarnings, equals(2));
      
      final warnings = collector.warnings;
      expect(warnings[0].recordId, isNull);
      expect(warnings[0].featureId, isNull);
      expect(warnings[1].recordId, equals('PARTIAL_001'));
      expect(warnings[1].featureId, isNull);
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