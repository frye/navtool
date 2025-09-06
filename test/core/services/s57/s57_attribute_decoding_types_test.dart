import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';

void main() {
  group('S57AttributeCatalog Decoding', () {
    late S57AttributeCatalog catalog;

    setUp(() {
      final attributeDefs = [
        const S57AttributeDef(
          acronym: 'DRVAL1',
          type: S57AttrType.float,
          name: 'Minimum depth',
        ),
        const S57AttributeDef(
          acronym: 'VALNMR',
          type: S57AttrType.int,
          name: 'Numeric value',
        ),
        const S57AttributeDef(
          acronym: 'OBJNAM',
          type: S57AttrType.string,
          name: 'Object name',
        ),
        const S57AttributeDef(
          acronym: 'COLOUR',
          type: S57AttrType.enumType,
          name: 'Colour',
          domain: {'3': 'green', '4': 'blue', '5': 'yellow'},
        ),
      ];
      catalog = S57AttributeCatalog.fromAttributeDefs(attributeDefs);
    });

    group('float decoding', () {
      test('should decode valid float values', () {
        final def = catalog.byAcronym('DRVAL1');

        expect(catalog.decodeAttribute(def, ['10.5']), equals(10.5));
        expect(catalog.decodeAttribute(def, ['0.0']), equals(0.0));
        expect(catalog.decodeAttribute(def, ['-5.25']), equals(-5.25));
        expect(catalog.decodeAttribute(def, ['1000']), equals(1000.0));
      });

      test('should handle invalid float values', () {
        final def = catalog.byAcronym('DRVAL1');

        expect(catalog.decodeAttribute(def, ['not_a_number']), isNull);
        expect(catalog.decodeAttribute(def, ['']), isNull);
        expect(catalog.decodeAttribute(def, ['10.5.5']), isNull);
        expect(catalog.decodeAttribute(def, ['abc123']), isNull);
      });

      test('should handle empty or missing values', () {
        final def = catalog.byAcronym('DRVAL1');

        expect(catalog.decodeAttribute(def, []), isNull);
      });
    });

    group('int decoding', () {
      test('should decode valid integer values', () {
        final def = catalog.byAcronym('VALNMR');

        expect(catalog.decodeAttribute(def, ['123']), equals(123));
        expect(catalog.decodeAttribute(def, ['0']), equals(0));
        expect(catalog.decodeAttribute(def, ['-456']), equals(-456));
      });

      test('should handle invalid integer values', () {
        final def = catalog.byAcronym('VALNMR');

        expect(catalog.decodeAttribute(def, ['10.5']), isNull);
        expect(catalog.decodeAttribute(def, ['not_a_number']), isNull);
        expect(catalog.decodeAttribute(def, ['']), isNull);
        expect(catalog.decodeAttribute(def, ['123abc']), isNull);
      });
    });

    group('string decoding', () {
      test('should decode string values with trimming', () {
        final def = catalog.byAcronym('OBJNAM');

        expect(
          catalog.decodeAttribute(def, ['Test Name']),
          equals('Test Name'),
        );
        expect(
          catalog.decodeAttribute(def, ['  Trimmed  ']),
          equals('Trimmed'),
        );
        expect(catalog.decodeAttribute(def, ['']), equals(''));
        expect(catalog.decodeAttribute(def, ['123']), equals('123'));
      });

      test('should handle multi-character strings', () {
        final def = catalog.byAcronym('OBJNAM');

        const longString = 'Very Long Object Name With Spaces And Numbers 123';
        expect(catalog.decodeAttribute(def, [longString]), equals(longString));
      });
    });

    group('enum decoding', () {
      test('should decode enum values with known codes', () {
        final def = catalog.byAcronym('COLOUR');

        final green =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(green['code'], equals('3'));
        expect(green['label'], equals('green'));

        final blue =
            catalog.decodeAttribute(def, ['4']) as Map<String, dynamic>;
        expect(blue['code'], equals('4'));
        expect(blue['label'], equals('blue'));

        final yellow =
            catalog.decodeAttribute(def, ['5']) as Map<String, dynamic>;
        expect(yellow['code'], equals('5'));
        expect(yellow['label'], equals('yellow'));
      });

      test('should decode enum values with unknown codes', () {
        final def = catalog.byAcronym('COLOUR');

        final unknown =
            catalog.decodeAttribute(def, ['99']) as Map<String, dynamic>;
        expect(unknown['code'], equals('99'));
        expect(unknown.containsKey('label'), isFalse);
      });

      test('should handle trimming for enum codes', () {
        final def = catalog.byAcronym('COLOUR');

        final trimmed =
            catalog.decodeAttribute(def, ['  3  ']) as Map<String, dynamic>;
        expect(trimmed['code'], equals('3'));
        expect(trimmed['label'], equals('green'));
      });
    });

    group('unknown attribute handling', () {
      test('should pass through values for unknown attributes', () {
        // Single value should be returned as-is
        expect(
          catalog.decodeAttribute(null, ['single_value']),
          equals('single_value'),
        );

        // Multiple values should be returned as list
        expect(
          catalog.decodeAttribute(null, ['val1', 'val2']),
          equals(['val1', 'val2']),
        );

        // Empty list should be returned as empty list
        expect(catalog.decodeAttribute(null, []), equals([]));
      });

      test('should not emit warnings for unknown attributes in decoding', () {
        // Decoding with null definition should work correctly
        expect(
          catalog.decodeAttribute(null, ['some_value']),
          equals('some_value'),
        );
        expect(
          catalog.decodeAttribute(null, ['val1', 'val2']),
          equals(['val1', 'val2']),
        );
        expect(catalog.decodeAttribute(null, []), equals([]));

        // Should continue to work with repeated calls
        expect(
          catalog.decodeAttribute(null, ['another_value']),
          equals('another_value'),
        );
      });
    });

    group('edge cases', () {
      test('should handle multiple values gracefully', () {
        final def = catalog.byAcronym('DRVAL1');

        // For known attributes, should only use first value
        expect(catalog.decodeAttribute(def, ['10.5', '20.0']), equals(10.5));
      });

      test('should handle empty and whitespace strings', () {
        final stringDef = catalog.byAcronym('OBJNAM');
        final enumDef = catalog.byAcronym('COLOUR');

        expect(catalog.decodeAttribute(stringDef, ['']), equals(''));
        expect(catalog.decodeAttribute(stringDef, ['   ']), equals(''));

        final emptyEnum =
            catalog.decodeAttribute(enumDef, ['']) as Map<String, dynamic>;
        expect(emptyEnum['code'], equals(''));
        expect(emptyEnum.containsKey('label'), isFalse);
      });
    });

    group('S57AttributeDef', () {
      test('should serialize to/from JSON correctly', () {
        const attrDef = S57AttributeDef(
          acronym: 'COLOUR',
          type: S57AttrType.enumType,
          name: 'Colour',
          domain: {'3': 'green', '4': 'blue'},
        );

        final json = attrDef.toJson();
        final restored = S57AttributeDef.fromJson(json);

        expect(restored, equals(attrDef));
        expect(json['acronym'], equals('COLOUR'));
        expect(json['type'], equals('enum'));
        expect(json['name'], equals('Colour'));
        expect(json['domain'], equals({'3': 'green', '4': 'blue'}));
      });

      test('should handle attributes without domains', () {
        const attrDef = S57AttributeDef(
          acronym: 'OBJNAM',
          type: S57AttrType.string,
          name: 'Object name',
        );

        final json = attrDef.toJson();
        final restored = S57AttributeDef.fromJson(json);

        expect(restored, equals(attrDef));
        expect(json.containsKey('domain'), isFalse);
      });

      test('should implement equality correctly', () {
        const attr1 = S57AttributeDef(
          acronym: 'TEST',
          type: S57AttrType.string,
          name: 'Test',
        );
        const attr2 = S57AttributeDef(
          acronym: 'TEST',
          type: S57AttrType.string,
          name: 'Test',
        );
        const attr3 = S57AttributeDef(
          acronym: 'OTHER',
          type: S57AttrType.string,
          name: 'Other',
        );

        expect(attr1, equals(attr2));
        expect(attr1, isNot(equals(attr3)));
        expect(attr1.hashCode, equals(attr2.hashCode));
      });

      test('should handle unknown type in JSON', () {
        expect(
          () => S57AttributeDef.fromJson({
            'acronym': 'TEST',
            'type': 'unknown_type',
            'name': 'Test',
          }),
          throwsArgumentError,
        );
      });
    });
  });
}
