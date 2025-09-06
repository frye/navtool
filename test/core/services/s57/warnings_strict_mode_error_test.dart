import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';

void main() {
  group('S57 Strict Mode Error Handling', () {
    test(
      'should throw exception on first error-level warning in strict mode',
      () {
        final collector = S57WarningCollector(
          options: const S57ParseOptions(strictMode: true),
        );

        // Add a warning (should not throw)
        collector.warning(
          S57WarningCodes.unknownObjCode,
          'Unknown object code 999',
        );

        // Add info (should not throw)
        collector.info(S57WarningCodes.depthOutOfRange, 'Depth value unusual');

        expect(collector.totalWarnings, equals(2));
        expect(collector.hasErrors, isFalse);

        // Add error-level warning (should throw in strict mode)
        expect(
          () => collector.error(
            S57WarningCodes.leaderLenMismatch,
            'Leader length inconsistent',
          ),
          throwsA(isA<S57StrictModeException>()),
        );
      },
    );

    test('should include triggering warning in exception', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      collector.warning(S57WarningCodes.fieldBounds, 'Field exceeds bounds');

      try {
        collector.error(
          S57WarningCodes.badBaseAddr,
          'Invalid base address pointer',
        );
        fail('Expected S57StrictModeException to be thrown');
      } on S57StrictModeException catch (e) {
        expect(e.triggeredBy.code, equals(S57WarningCodes.badBaseAddr));
        expect(e.triggeredBy.message, equals('Invalid base address pointer'));
        expect(e.triggeredBy.severity, equals(S57WarningSeverity.error));

        expect(e.allWarnings, hasLength(2));
        expect(e.allWarnings[0].code, equals(S57WarningCodes.fieldBounds));
        expect(e.allWarnings[1].code, equals(S57WarningCodes.badBaseAddr));
      }
    });

    test('should not throw in non-strict mode', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: false),
      );

      // Should not throw regardless of severity
      collector.error(S57WarningCodes.leaderLenMismatch, 'Error 1');
      collector.error(S57WarningCodes.badBaseAddr, 'Error 2');
      collector.warning(S57WarningCodes.unknownObjCode, 'Warning 1');

      expect(collector.totalWarnings, equals(3));
      expect(collector.errorCount, equals(2));
      expect(collector.hasErrors, isTrue);
    });

    test('should preserve partial results before exception', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      collector.warning(
        S57WarningCodes.subfieldParse,
        'Subfield delimiter issue',
      );
      collector.info(S57WarningCodes.polygonClosedAuto, 'Auto-closed polygon');

      try {
        collector.error(S57WarningCodes.updateGap, 'Missing update file');
        fail('Expected exception');
      } on S57StrictModeException catch (e) {
        // Verify all warnings are preserved in exception
        expect(e.allWarnings, hasLength(3));

        // Verify warnings are accessible in correct order
        expect(e.allWarnings[0].code, equals(S57WarningCodes.subfieldParse));
        expect(
          e.allWarnings[1].code,
          equals(S57WarningCodes.polygonClosedAuto),
        );
        expect(e.allWarnings[2].code, equals(S57WarningCodes.updateGap));
      }
    });

    test('should have meaningful exception message', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      collector.warning(S57WarningCodes.fieldBounds, 'Field bounds warning');

      try {
        collector.error(
          S57WarningCodes.updateRverMismatch,
          'RVER sequence broken',
        );
        fail('Expected exception');
      } on S57StrictModeException catch (e) {
        final message = e.toString();
        expect(message, contains('S57StrictModeException'));
        expect(message, contains('RVER sequence broken'));
        expect(message, contains('(2 total warnings)'));
      }
    });

    test('should work with convenience methods in strict mode', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Should not throw
      collector.info(S57WarningCodes.depthOutOfRange, 'Depth sanity check');
      collector.warning(S57WarningCodes.missingRequiredAttr, 'Missing DRVAL1');

      // Should throw
      expect(
        () => collector.error(
          S57WarningCodes.dirTruncated,
          'Directory corrupted',
        ),
        throwsA(isA<S57StrictModeException>()),
      );
    });

    test('should handle record and feature context in strict mode', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      try {
        collector.error(
          S57WarningCodes.leaderLenMismatch,
          'Leader length field inconsistent',
          recordId: 'DDR_001',
          featureId: 'CATALOG',
        );
        fail('Expected exception');
      } on S57StrictModeException catch (e) {
        expect(e.triggeredBy.recordId, equals('DDR_001'));
        expect(e.triggeredBy.featureId, equals('CATALOG'));
      }
    });

    test('should support different strict mode configurations', () {
      // Development mode (non-strict)
      final devCollector = S57WarningCollector(
        options: const S57ParseOptions.development(),
      );

      devCollector.error(S57WarningCodes.badBaseAddr, 'Should not throw');
      expect(devCollector.errorCount, equals(1));

      // Production mode (strict)
      final prodCollector = S57WarningCollector(
        options: const S57ParseOptions.production(),
      );

      expect(
        () => prodCollector.error(S57WarningCodes.badBaseAddr, 'Should throw'),
        throwsA(isA<S57StrictModeException>()),
      );

      // Testing mode (strict)
      final testCollector = S57WarningCollector(
        options: const S57ParseOptions.testing(),
      );

      expect(
        () => testCollector.error(S57WarningCodes.badBaseAddr, 'Should throw'),
        throwsA(isA<S57StrictModeException>()),
      );
    });

    test('should handle multiple errors in sequence (strict mode)', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // First error should throw
      expect(
        () => collector.error(S57WarningCodes.leaderLenMismatch, 'First error'),
        throwsA(isA<S57StrictModeException>()),
      );

      // Collector should still be usable after exception
      expect(collector.totalWarnings, equals(1));
      expect(collector.errorCount, equals(1));

      // Second error should also throw
      expect(
        () => collector.error(S57WarningCodes.badBaseAddr, 'Second error'),
        throwsA(isA<S57StrictModeException>()),
      );

      expect(collector.totalWarnings, equals(2));
    });

    test('should preserve warning collection after non-error warnings', () {
      final collector = S57WarningCollector(
        options: const S57ParseOptions(strictMode: true),
      );

      // Add several non-error warnings
      for (int i = 0; i < 5; i++) {
        collector.warning(S57WarningCodes.unknownObjCode, 'Unknown object $i');
      }

      expect(collector.totalWarnings, equals(5));
      expect(collector.warningCount, equals(5));

      // Now add error - should throw but preserve all previous warnings
      try {
        collector.error(S57WarningCodes.updateGap, 'Critical update error');
        fail('Expected exception');
      } on S57StrictModeException catch (e) {
        expect(e.allWarnings, hasLength(6));
        expect(
          e.allWarnings
              .sublist(0, 5)
              .every((w) => w.severity == S57WarningSeverity.warning),
          isTrue,
        );
        expect(e.allWarnings.last.severity, equals(S57WarningSeverity.error));
      }
    });
  });
}
