import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';
import 'package:navtool/core/services/s57/s57_attribute_validator.dart';

void main() {
  group('S57RequiredAttributeValidator', () {
    group('validateRequired', () {
      test('should warn when DEPARE missing DRVAL1', () {
        const depareClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        // Missing DRVAL1 - should produce warning
        final attributes = <String, Object?>{
          'DRVAL2': 20.0,
          'OTHER_ATTR': 'some_value',
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          depareClass,
          attributes,
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].objectAcronym, equals('DEPARE'));
        expect(warnings[0].missingAttribute, equals('DRVAL1'));
        expect(warnings[0].message, contains('Missing required attribute DRVAL1'));
        expect(warnings[0].message, contains('DEPARE'));
        expect(warnings[0].message, contains('Depth Area'));
      });

      test('should not warn when DEPARE has DRVAL1', () {
        const depareClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        // Has DRVAL1 - no warning
        final attributes = <String, Object?>{
          'DRVAL1': 10.0,
          'DRVAL2': 20.0,
          'OTHER_ATTR': 'some_value',
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          depareClass,
          attributes,
        );

        expect(warnings, isEmpty);
      });

      test('should warn when DRVAL1 is null', () {
        const depareClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        // DRVAL1 is present but null - should warn
        final attributes = <String, Object?>{
          'DRVAL1': null,
          'DRVAL2': 20.0,
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          depareClass,
          attributes,
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].missingAttribute, equals('DRVAL1'));
      });

      test('should warn when SOUNDG missing VALSOU', () {
        const soundgClass = S57ObjectClass(
          code: 74,
          acronym: 'SOUNDG',
          name: 'Sounding',
        );

        // Missing VALSOU - should produce warning
        final attributes = <String, Object?>{
          'QUASOU': 1,
          'OTHER_ATTR': 'some_value',
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          soundgClass,
          attributes,
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].objectAcronym, equals('SOUNDG'));
        expect(warnings[0].missingAttribute, equals('VALSOU'));
        expect(warnings[0].message, contains('Missing required attribute VALSOU'));
        expect(warnings[0].message, contains('SOUNDG'));
        expect(warnings[0].message, contains('Sounding'));
      });

      test('should not warn when SOUNDG has VALSOU', () {
        const soundgClass = S57ObjectClass(
          code: 74,
          acronym: 'SOUNDG',
          name: 'Sounding',
        );

        // Has VALSOU - no warning
        final attributes = <String, Object?>{
          'VALSOU': 15.5,
          'QUASOU': 1,
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          soundgClass,
          attributes,
        );

        expect(warnings, isEmpty);
      });

      test('should warn when buoy missing CATBOY', () {
        const boylatClass = S57ObjectClass(
          code: 38,
          acronym: 'BOYLAT',
          name: 'Lateral Buoy',
        );

        // Missing CATBOY - should produce warning
        final attributes = <String, Object?>{
          'COLOUR': 3,
          'OBJNAM': 'Port Hand Buoy',
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          boylatClass,
          attributes,
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].objectAcronym, equals('BOYLAT'));
        expect(warnings[0].missingAttribute, equals('CATBOY'));
      });

      test('should not warn for object classes without required attributes', () {
        const coastlineClass = S57ObjectClass(
          code: 121,
          acronym: 'COALNE',
          name: 'Coastline',
        );

        // COALNE has no required attributes defined
        final attributes = <String, Object?>{
          'WATLEV': 3,
          'CATCOA': 1,
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          coastlineClass,
          attributes,
        );

        expect(warnings, isEmpty);
      });

      test('should handle null object class', () {
        final attributes = <String, Object?>{
          'SOME_ATTR': 'value',
        };

        final warnings = S57RequiredAttributeValidator.validateRequired(
          null,
          attributes,
        );

        expect(warnings, isEmpty);
      });

      test('should handle empty attributes map', () {
        const depareClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        final warnings = S57RequiredAttributeValidator.validateRequired(
          depareClass,
          {},
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].missingAttribute, equals('DRVAL1'));
      });

      test('should handle multiple missing required attributes', () {
        // Create a hypothetical object class with multiple required attributes
        // (This would require extending the validator rules for testing)
        const testClass = S57ObjectClass(
          code: 999,
          acronym: 'TESTOBJ',
          name: 'Test Object',
        );

        // For now, test with objects that have single required attributes
        const boyisdClass = S57ObjectClass(
          code: 40,
          acronym: 'BOYISD',
          name: 'Isolated Danger Buoy',
        );

        final warnings = S57RequiredAttributeValidator.validateRequired(
          boyisdClass,
          {},
        );

        expect(warnings, hasLength(1));
        expect(warnings[0].missingAttribute, equals('CATBOY'));
      });
    });

    group('utility methods', () {
      test('should return required attributes for known object classes', () {
        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('DEPARE'),
          equals(['DRVAL1']),
        );

        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('SOUNDG'),
          equals(['VALSOU']),
        );

        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('BOYLAT'),
          equals(['CATBOY']),
        );

        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('BOYISD'),
          equals(['CATBOY']),
        );

        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('BOYSPP'),
          equals(['CATBOY']),
        );
      });

      test('should return empty list for unknown object classes', () {
        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('UNKNOWN'),
          isEmpty,
        );

        expect(
          S57RequiredAttributeValidator.getRequiredAttributes('COALNE'),
          isEmpty,
        );
      });

      test('should check if attribute is required correctly', () {
        expect(
          S57RequiredAttributeValidator.isAttributeRequired('DEPARE', 'DRVAL1'),
          isTrue,
        );

        expect(
          S57RequiredAttributeValidator.isAttributeRequired('DEPARE', 'DRVAL2'),
          isFalse,
        );

        expect(
          S57RequiredAttributeValidator.isAttributeRequired('SOUNDG', 'VALSOU'),
          isTrue,
        );

        expect(
          S57RequiredAttributeValidator.isAttributeRequired('SOUNDG', 'QUASOU'),
          isFalse,
        );

        expect(
          S57RequiredAttributeValidator.isAttributeRequired('UNKNOWN', 'ANYTHING'),
          isFalse,
        );
      });

      test('should return object classes with required attributes', () {
        final objectClasses = S57RequiredAttributeValidator.getObjectClassesWithRequiredAttributes();
        
        expect(objectClasses, contains('DEPARE'));
        expect(objectClasses, contains('SOUNDG'));
        expect(objectClasses, contains('BOYLAT'));
        expect(objectClasses, contains('BOYISD'));
        expect(objectClasses, contains('BOYSPP'));
        
        // Should not contain classes without required attributes
        expect(objectClasses, isNot(contains('COALNE')));
        expect(objectClasses, isNot(contains('LIGHTS')));
      });
    });

    group('S57ValidationWarning', () {
      test('should implement equality correctly', () {
        const warning1 = S57ValidationWarning(
          objectAcronym: 'DEPARE',
          missingAttribute: 'DRVAL1',
          message: 'Missing required attribute DRVAL1 for DEPARE',
        );

        const warning2 = S57ValidationWarning(
          objectAcronym: 'DEPARE',
          missingAttribute: 'DRVAL1',
          message: 'Missing required attribute DRVAL1 for DEPARE',
        );

        const warning3 = S57ValidationWarning(
          objectAcronym: 'SOUNDG',
          missingAttribute: 'VALSOU',
          message: 'Missing required attribute VALSOU for SOUNDG',
        );

        expect(warning1, equals(warning2));
        expect(warning1, isNot(equals(warning3)));
        expect(warning1.hashCode, equals(warning2.hashCode));
      });

      test('should have readable toString', () {
        const warning = S57ValidationWarning(
          objectAcronym: 'DEPARE',
          missingAttribute: 'DRVAL1',
          message: 'Missing required attribute DRVAL1 for DEPARE',
        );

        final str = warning.toString();
        expect(str, contains('S57ValidationWarning:'));
        expect(str, contains('Missing required attribute DRVAL1 for DEPARE'));
      });
    });
  });
}