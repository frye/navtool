import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Warnings Basic Collection', () {
    late S57WarningCollector collector;

    setUp(() {
      collector = S57WarningCollector();
    });

    test('should collect warnings with correct ordering', () {
      // Add warnings in specific order
      collector.warn(
        S57WarningCodes.dirTruncated,
        S57WarningSeverity.warning,
        'Directory terminated unexpectedly',
        recordId: 'R001',
      );
      
      collector.warn(
        S57WarningCodes.fieldBounds,
        S57WarningSeverity.warning,
        'Field exceeds record bounds',
        recordId: 'R002',
      );
      
      collector.warn(
        S57WarningCodes.polygonClosedAuto,
        S57WarningSeverity.info,
        'Polygon auto-closed programmatically',
        featureId: 'F001',
      );

      final warnings = collector.warnings;
      
      // Verify ordering (insertion order)
      expect(warnings, hasLength(3));
      expect(warnings[0].code, equals(S57WarningCodes.dirTruncated));
      expect(warnings[0].recordId, equals('R001'));
      expect(warnings[0].severity, equals(S57WarningSeverity.warning));
      
      expect(warnings[1].code, equals(S57WarningCodes.fieldBounds));
      expect(warnings[1].recordId, equals('R002'));
      
      expect(warnings[2].code, equals(S57WarningCodes.polygonClosedAuto));
      expect(warnings[2].featureId, equals('F001'));
      expect(warnings[2].severity, equals(S57WarningSeverity.info));
    });

    test('should categorize warnings by severity correctly', () {
      collector.error(S57WarningCodes.leaderLenMismatch, 'Leader length mismatch');
      collector.error(S57WarningCodes.badBaseAddr, 'Invalid base address');
      collector.warning(S57WarningCodes.unknownObjCode, 'Unknown object code');
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth out of range');
      collector.info(S57WarningCodes.polygonClosedAuto, 'Auto-closed polygon');

      expect(collector.errorCount, equals(2));
      expect(collector.warningCount, equals(1));
      expect(collector.infoCount, equals(2));
      expect(collector.totalWarnings, equals(5));
      expect(collector.hasErrors, isTrue);
    });

    test('should support filtering by severity', () {
      collector.error(S57WarningCodes.leaderLenMismatch, 'Error 1');
      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.info(S57WarningCodes.depthOutOfRange, 'Info 1');
      collector.error(S57WarningCodes.badBaseAddr, 'Error 2');

      final errors = collector.getWarningsBySeverity(S57WarningSeverity.error);
      final warnings = collector.getWarningsBySeverity(S57WarningSeverity.warning);
      final infos = collector.getWarningsBySeverity(S57WarningSeverity.info);

      expect(errors, hasLength(2));
      expect(warnings, hasLength(1));
      expect(infos, hasLength(1));
      
      expect(errors[0].message, equals('Error 1'));
      expect(errors[1].message, equals('Error 2'));
      expect(warnings[0].message, equals('Warning 1'));
      expect(infos[0].message, equals('Info 1'));
    });

    test('should support filtering by code', () {
      collector.warn(S57WarningCodes.unknownObjCode, S57WarningSeverity.warning, 'First unknown');
      collector.warn(S57WarningCodes.fieldBounds, S57WarningSeverity.warning, 'Field bounds issue');
      collector.warn(S57WarningCodes.unknownObjCode, S57WarningSeverity.warning, 'Second unknown');

      final unknownCodeWarnings = collector.getWarningsByCode(S57WarningCodes.unknownObjCode);
      final fieldBoundsWarnings = collector.getWarningsByCode(S57WarningCodes.fieldBounds);

      expect(unknownCodeWarnings, hasLength(2));
      expect(fieldBoundsWarnings, hasLength(1));
      
      expect(unknownCodeWarnings[0].message, equals('First unknown'));
      expect(unknownCodeWarnings[1].message, equals('Second unknown'));
      expect(fieldBoundsWarnings[0].message, equals('Field bounds issue'));
    });

    test('should preserve warning immutability', () {
      collector.warn(S57WarningCodes.dirTruncated, S57WarningSeverity.warning, 'Test warning');
      
      final warningsSnapshot1 = collector.warnings;
      expect(warningsSnapshot1, hasLength(1));
      
      // Add another warning
      collector.warn(S57WarningCodes.fieldBounds, S57WarningSeverity.info, 'Another warning');
      
      final warningsSnapshot2 = collector.warnings;
      
      // First snapshot should be unchanged (immutable)
      expect(warningsSnapshot1, hasLength(1));
      expect(warningsSnapshot2, hasLength(2));
    });

    test('should clear warnings correctly', () {
      collector.warn(S57WarningCodes.dirTruncated, S57WarningSeverity.warning, 'Test 1');
      collector.warn(S57WarningCodes.fieldBounds, S57WarningSeverity.error, 'Test 2');
      
      expect(collector.totalWarnings, equals(2));
      expect(collector.hasErrors, isTrue);
      
      collector.clear();
      
      expect(collector.totalWarnings, equals(0));
      expect(collector.hasErrors, isFalse);
      expect(collector.warnings, isEmpty);
    });

    test('should generate meaningful summary report', () {
      collector.error(S57WarningCodes.leaderLenMismatch, 'Error 1');
      collector.error(S57WarningCodes.leaderLenMismatch, 'Error 2'); // Same code
      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.info(S57WarningCodes.depthOutOfRange, 'Info 1');

      final summary = collector.createSummaryReport();
      
      expect(summary['totalWarnings'], equals(4));
      expect(summary['hasErrors'], isTrue);
      expect(summary['strictMode'], isFalse);
      expect(summary['isThresholdExceeded'], isFalse);
      
      final bySeverity = summary['warningsBySeverity'] as Map<String, int>;
      expect(bySeverity['error'], equals(2));
      expect(bySeverity['warning'], equals(1));
      expect(bySeverity['info'], equals(1));
      
      final byCode = summary['warningsByCode'] as Map<String, int>;
      expect(byCode[S57WarningCodes.leaderLenMismatch], equals(2));
      expect(byCode[S57WarningCodes.unknownObjCode], equals(1));
      expect(byCode[S57WarningCodes.depthOutOfRange], equals(1));
    });

    test('should include context information in warnings', () {
      collector.warn(
        S57WarningCodes.missingRequiredAttr,
        S57WarningSeverity.warning,
        'Missing DRVAL1 attribute',
        recordId: 'DEPARE_001',
        featureId: 'DA123456',
      );

      final warning = collector.warnings.first;
      expect(warning.recordId, equals('DEPARE_001'));
      expect(warning.featureId, equals('DA123456'));
      expect(warning.timestamp, isA<DateTime>());
      
      // Verify timestamp is recent (within last second)
      final now = DateTime.now();
      final timeDiff = now.difference(warning.timestamp).inMilliseconds;
      expect(timeDiff, lessThan(1000));
    });

    test('should handle timestamp generation correctly', () {
      final beforeTime = DateTime.now();
      
      collector.warn(S57WarningCodes.dirTruncated, S57WarningSeverity.info, 'Test');
      
      final afterTime = DateTime.now();
      final warning = collector.warnings.first;
      
      expect(warning.timestamp.isAfter(beforeTime) || warning.timestamp.isAtSameMomentAs(beforeTime), isTrue);
      expect(warning.timestamp.isBefore(afterTime) || warning.timestamp.isAtSameMomentAs(afterTime), isTrue);
    });
  });

  group('S57ParseWarning', () {
    test('should implement equality correctly', () {
      final warning1 = S57ParseWarning(
        code: S57WarningCodes.dirTruncated,
        message: 'Directory truncated',
        severity: S57WarningSeverity.warning,
        recordId: 'R001',
      );

      final warning2 = S57ParseWarning(
        code: S57WarningCodes.dirTruncated,
        message: 'Directory truncated',
        severity: S57WarningSeverity.warning,
        recordId: 'R001',
      );

      final warning3 = S57ParseWarning(
        code: S57WarningCodes.fieldBounds,
        message: 'Different message',
        severity: S57WarningSeverity.error,
      );

      expect(warning1, equals(warning2));
      expect(warning1, isNot(equals(warning3)));
      expect(warning1.hashCode, equals(warning2.hashCode));
    });

    test('should have meaningful toString representation', () {
      final warning = S57ParseWarning(
        code: S57WarningCodes.missingRequiredAttr,
        message: 'Missing DRVAL1 for DEPARE',
        severity: S57WarningSeverity.warning,
        recordId: 'R001',
        featureId: 'F123',
      );

      final str = warning.toString();
      expect(str, contains('S57ParseWarning(warning)'));
      expect(str, contains('[MISSING_REQUIRED_ATTR]'));
      expect(str, contains('Missing DRVAL1 for DEPARE'));
      expect(str, contains('(record: R001)'));
      expect(str, contains('(feature: F123)'));
    });
  });
}