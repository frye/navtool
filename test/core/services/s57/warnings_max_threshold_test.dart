import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Max Warning Threshold', () {
    test(
      'should throw exception when warning threshold exceeded in strict mode',
      () {
        final collector = S57WarningCollector(
          options: const S57ParseOptions(strictMode: true, maxWarnings: 3),
        );

        // Add warnings up to threshold
        collector.warning(S57WarningCodes.unknownObjCode, 'Unknown 1');
        collector.warning(S57WarningCodes.fieldBounds, 'Field bounds 1');
        collector.info(S57WarningCodes.depthOutOfRange, 'Depth range 1');

        expect(collector.totalWarnings, equals(3));
        expect(collector.isThresholdExceeded, isFalse);

        // Adding one more should exceed threshold and throw
        expect(
          () => collector.warning(
            S57WarningCodes.missingRequiredAttr,
            'Missing attr',
          ),
          throwsA(isA<S57StrictModeException>()),
        );
      },
    );

    test('should include threshold warning in exception details', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true, maxWarnings: 2),
      );

      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.info(S57WarningCodes.depthOutOfRange, 'Info 1');

      try {
        collector.warning(S57WarningCodes.fieldBounds, 'Warning 2');
        fail('Expected S57StrictModeException');
      } on S57StrictModeException catch (e) {
        expect(e.triggeredBy.code, equals('MAX_WARNINGS_EXCEEDED'));
        expect(
          e.triggeredBy.message,
          contains('Maximum warning threshold (2) exceeded'),
        );
        expect(e.triggeredBy.severity, equals(S57WarningSeverity.error));

        // Should include original warnings plus threshold warning
        expect(e.allWarnings, hasLength(4));
        expect(e.allWarnings[3].code, equals('MAX_WARNINGS_EXCEEDED'));
      }
    });

    test('should not check threshold in non-strict mode', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: false, maxWarnings: 2),
      );

      // Add more warnings than threshold - should not throw
      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.warning(S57WarningCodes.fieldBounds, 'Warning 2');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Warning 3');
      collector.warning(S57WarningCodes.subfieldParse, 'Warning 4');

      expect(collector.totalWarnings, equals(4));
      expect(collector.isThresholdExceeded, isTrue);
      // No exception should be thrown
    });

    test('should handle null maxWarnings (no threshold)', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true, maxWarnings: null),
      );

      // Add many warnings - should not trigger threshold
      for (int i = 0; i < 100; i++) {
        collector.warning(S57WarningCodes.unknownObjCode, 'Warning $i');
      }

      expect(collector.totalWarnings, equals(100));
      expect(collector.isThresholdExceeded, isFalse);

      // Can still add more
      collector.info(S57WarningCodes.depthOutOfRange, 'Info warning');
      expect(collector.totalWarnings, equals(101));
    });

    test('should check threshold before error-level escalation', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true, maxWarnings: 1),
      );

      collector.warning(S57WarningCodes.unknownObjCode, 'First warning');

      // Adding error should trigger threshold before error escalation
      try {
        collector.error(S57WarningCodes.leaderLenMismatch, 'Error warning');
        fail('Expected exception');
      } on S57StrictModeException catch (e) {
        // Should be threshold exception, not error escalation
        expect(e.triggeredBy.code, equals('MAX_WARNINGS_EXCEEDED'));
        expect(e.allWarnings, hasLength(3)); // original + error + threshold
      }
    });

    test('should handle threshold configuration in preset modes', () {
      // Production mode should have maxWarnings
      final prodCollector = S57WarningCollector(
        options: const S57ParseOptions.production(),
      );
      expect(prodCollector.createSummaryReport()['maxWarnings'], equals(100));

      // Testing mode should have lower threshold
      final testCollector = S57WarningCollector(
        options: const S57ParseOptions.testing(),
      );
      expect(testCollector.createSummaryReport()['maxWarnings'], equals(10));

      // Development mode should be permissive
      final devCollector = S57WarningCollector(
        options: const S57ParseOptions.development(),
      );
      expect(devCollector.createSummaryReport()['maxWarnings'], isNull);
    });

    test('should report threshold status correctly', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: false, maxWarnings: 3),
      );

      expect(collector.isThresholdExceeded, isFalse);

      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      expect(collector.isThresholdExceeded, isFalse);

      collector.warning(S57WarningCodes.fieldBounds, 'Warning 2');
      expect(collector.isThresholdExceeded, isFalse);

      collector.warning(S57WarningCodes.missingRequiredAttr, 'Warning 3');
      expect(collector.isThresholdExceeded, isFalse);

      collector.info(S57WarningCodes.depthOutOfRange, 'Warning 4');
      expect(collector.isThresholdExceeded, isTrue);

      final summary = collector.createSummaryReport();
      expect(summary['isThresholdExceeded'], isTrue);
      expect(summary['maxWarnings'], equals(3));
    });

    test('should handle edge cases with threshold of 0', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true, maxWarnings: 0),
      );

      // Any warning should immediately exceed threshold
      expect(
        () => collector.info(S57WarningCodes.depthOutOfRange, 'Any warning'),
        throwsA(isA<S57StrictModeException>()),
      );
    });

    test('should continue working after threshold exception', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true, maxWarnings: 2),
      );

      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.warning(S57WarningCodes.fieldBounds, 'Warning 2');

      // This should throw due to threshold
      expect(
        () => collector.info(S57WarningCodes.depthOutOfRange, 'Warning 3'),
        throwsA(isA<S57StrictModeException>()),
      );

      // Collector should still have the warnings
      expect(
        collector.totalWarnings,
        equals(4),
      ); // 2 original + 1 new + 1 threshold

      // Can clear and continue
      collector.clear();
      expect(collector.totalWarnings, equals(0));
      expect(collector.isThresholdExceeded, isFalse);

      // Should work normally after clear
      collector.warning(S57WarningCodes.subfieldParse, 'New warning');
      expect(collector.totalWarnings, equals(1));
    });

    test('should handle mixed warning levels with threshold', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: false, maxWarnings: 5),
      );

      collector.error(S57WarningCodes.leaderLenMismatch, 'Error 1');
      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');
      collector.info(S57WarningCodes.depthOutOfRange, 'Info 1');
      collector.error(S57WarningCodes.badBaseAddr, 'Error 2');
      collector.warning(S57WarningCodes.fieldBounds, 'Warning 2');

      expect(collector.totalWarnings, equals(5));
      expect(collector.isThresholdExceeded, isFalse);

      // One more should exceed
      collector.info(S57WarningCodes.polygonClosedAuto, 'Info 2');
      expect(collector.isThresholdExceeded, isTrue);

      final summary = collector.createSummaryReport();
      expect(summary['totalWarnings'], equals(6));
      expect(summary['isThresholdExceeded'], isTrue);
      expect(summary['warningsBySeverity']['error'], equals(2));
      expect(summary['warningsBySeverity']['warning'], equals(2));
      expect(summary['warningsBySeverity']['info'], equals(2));
    });
  });
}
