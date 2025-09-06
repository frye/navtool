import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';

void main() {
  group('S57AttributeCatalog Enum Domain Labels', () {
    late S57AttributeCatalog catalog;

    setUp(() {
      final attributeDefs = [
        const S57AttributeDef(
          acronym: 'COLOUR',
          type: S57AttrType.enumType,
          name: 'Colour',
          domain: {'3': 'green', '4': 'blue', '5': 'yellow'},
        ),
        const S57AttributeDef(
          acronym: 'QUASOU',
          type: S57AttrType.enumType,
          name: 'Quality of sounding',
          domain: {'1': 'depth known', '6': 'unreliable'},
        ),
        const S57AttributeDef(
          acronym: 'CATBOY',
          type: S57AttrType.enumType,
          name: 'Buoy category',
          domain: {'1': 'lateral', '2': 'cardinal', '3': 'isolated danger'},
        ),
        const S57AttributeDef(
          acronym: 'COLPAT',
          type: S57AttrType.enumType,
          name: 'Colour pattern',
          domain: {
            '1': 'horizontal stripes',
            '2': 'vertical stripes',
            '3': 'chequered',
          },
        ),
        const S57AttributeDef(
          acronym: 'WATLEV',
          type: S57AttrType.enumType,
          name: 'Water level effect',
          domain: {'1': 'always dry', '3': 'covers at high water'},
        ),
        const S57AttributeDef(
          acronym: 'CATCOA',
          type: S57AttrType.enumType,
          name: 'Coastline category',
          domain: {'1': 'shoreline', '2': 'cliff', '3': 'beach'},
        ),
        const S57AttributeDef(
          acronym: 'CATLMK',
          type: S57AttrType.enumType,
          name: 'Landmark category',
          domain: {'1': 'tower', '3': 'church', '6': 'windmill'},
        ),
        // Enum without domain for testing
        const S57AttributeDef(
          acronym: 'NODOMAIN',
          type: S57AttrType.enumType,
          name: 'No Domain Enum',
        ),
      ];
      catalog = S57AttributeCatalog.fromAttributeDefs(attributeDefs);
    });

    group('COLOUR enum labels', () {
      test('should return label for known COLOUR codes', () {
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

      test('should return code without label for unknown COLOUR codes', () {
        final def = catalog.byAcronym('COLOUR');

        final unknown =
            catalog.decodeAttribute(def, ['99']) as Map<String, dynamic>;
        expect(unknown['code'], equals('99'));
        expect(unknown.containsKey('label'), isFalse);
      });
    });

    group('QUASOU enum labels', () {
      test('should return label for known quality codes', () {
        final def = catalog.byAcronym('QUASOU');

        final known =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(known['code'], equals('1'));
        expect(known['label'], equals('depth known'));

        final unreliable =
            catalog.decodeAttribute(def, ['6']) as Map<String, dynamic>;
        expect(unreliable['code'], equals('6'));
        expect(unreliable['label'], equals('unreliable'));
      });
    });

    group('CATBOY enum labels', () {
      test('should return label for buoy category codes', () {
        final def = catalog.byAcronym('CATBOY');

        final lateral =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(lateral['code'], equals('1'));
        expect(lateral['label'], equals('lateral'));

        final cardinal =
            catalog.decodeAttribute(def, ['2']) as Map<String, dynamic>;
        expect(cardinal['code'], equals('2'));
        expect(cardinal['label'], equals('cardinal'));

        final isolatedDanger =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(isolatedDanger['code'], equals('3'));
        expect(isolatedDanger['label'], equals('isolated danger'));
      });
    });

    group('COLPAT enum labels', () {
      test('should return label for colour pattern codes', () {
        final def = catalog.byAcronym('COLPAT');

        final horizontal =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(horizontal['code'], equals('1'));
        expect(horizontal['label'], equals('horizontal stripes'));

        final vertical =
            catalog.decodeAttribute(def, ['2']) as Map<String, dynamic>;
        expect(vertical['code'], equals('2'));
        expect(vertical['label'], equals('vertical stripes'));

        final chequered =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(chequered['code'], equals('3'));
        expect(chequered['label'], equals('chequered'));
      });
    });

    group('WATLEV enum labels', () {
      test('should return label for water level effect codes', () {
        final def = catalog.byAcronym('WATLEV');

        final alwaysDry =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(alwaysDry['code'], equals('1'));
        expect(alwaysDry['label'], equals('always dry'));

        final coversAtHigh =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(coversAtHigh['code'], equals('3'));
        expect(coversAtHigh['label'], equals('covers at high water'));
      });
    });

    group('CATCOA enum labels', () {
      test('should return label for coastline category codes', () {
        final def = catalog.byAcronym('CATCOA');

        final shoreline =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(shoreline['code'], equals('1'));
        expect(shoreline['label'], equals('shoreline'));

        final cliff =
            catalog.decodeAttribute(def, ['2']) as Map<String, dynamic>;
        expect(cliff['code'], equals('2'));
        expect(cliff['label'], equals('cliff'));

        final beach =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(beach['code'], equals('3'));
        expect(beach['label'], equals('beach'));
      });
    });

    group('CATLMK enum labels', () {
      test('should return label for landmark category codes', () {
        final def = catalog.byAcronym('CATLMK');

        final tower =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(tower['code'], equals('1'));
        expect(tower['label'], equals('tower'));

        final church =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(church['code'], equals('3'));
        expect(church['label'], equals('church'));

        final windmill =
            catalog.decodeAttribute(def, ['6']) as Map<String, dynamic>;
        expect(windmill['code'], equals('6'));
        expect(windmill['label'], equals('windmill'));
      });
    });

    group('enum without domain', () {
      test('should handle enum attributes without domain gracefully', () {
        final def = catalog.byAcronym('NODOMAIN');

        final result =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(result['code'], equals('1'));
        expect(result.containsKey('label'), isFalse);
      });
    });

    group('edge cases', () {
      test('should handle empty enum codes', () {
        final def = catalog.byAcronym('COLOUR');

        final empty =
            catalog.decodeAttribute(def, ['']) as Map<String, dynamic>;
        expect(empty['code'], equals(''));
        expect(empty.containsKey('label'), isFalse);
      });

      test('should handle whitespace in enum codes', () {
        final def = catalog.byAcronym('COLOUR');

        final trimmed =
            catalog.decodeAttribute(def, ['  3  ']) as Map<String, dynamic>;
        expect(trimmed['code'], equals('3'));
        expect(trimmed['label'], equals('green'));
      });

      test('should handle case sensitivity in domain lookup', () {
        // Domain keys should be exact matches
        final def = catalog.byAcronym('COLOUR');

        final upperCase =
            catalog.decodeAttribute(def, ['3']) as Map<String, dynamic>;
        expect(upperCase['label'], equals('green'));

        // Non-matching case should not find label
        final result =
            catalog.decodeAttribute(def, ['G']) as Map<String, dynamic>;
        expect(result['code'], equals('G'));
        expect(result.containsKey('label'), isFalse);
      });

      test('should handle complex domain values', () {
        // Test that domain values with spaces and special characters work
        final def = catalog.byAcronym('COLPAT');

        final result =
            catalog.decodeAttribute(def, ['1']) as Map<String, dynamic>;
        expect(result['label'], equals('horizontal stripes'));

        final result2 =
            catalog.decodeAttribute(def, ['2']) as Map<String, dynamic>;
        expect(result2['label'], equals('vertical stripes'));
      });
    });

    group('consistency checks', () {
      test(
        'should consistently return same structure for all enum decodings',
        () {
          final colourDef = catalog.byAcronym('COLOUR');
          final catboyDef = catalog.byAcronym('CATBOY');

          final colourResult =
              catalog.decodeAttribute(colourDef, ['3']) as Map<String, dynamic>;
          final catboyResult =
              catalog.decodeAttribute(catboyDef, ['1']) as Map<String, dynamic>;

          // Both should have 'code' and 'label' keys
          expect(colourResult.keys, containsAll(['code', 'label']));
          expect(catboyResult.keys, containsAll(['code', 'label']));

          // Both should be exactly 2 keys when label is present
          expect(colourResult.keys, hasLength(2));
          expect(catboyResult.keys, hasLength(2));
        },
      );

      test('should consistently handle unknown codes across all enums', () {
        final enums = [
          'COLOUR',
          'QUASOU',
          'CATBOY',
          'COLPAT',
          'WATLEV',
          'CATCOA',
          'CATLMK',
        ];

        for (final enumName in enums) {
          final def = catalog.byAcronym(enumName);
          final result =
              catalog.decodeAttribute(def, ['999']) as Map<String, dynamic>;

          // All unknown codes should have only 'code' key, no 'label'
          expect(result.keys, equals(['code']), reason: 'Failed for $enumName');
          expect(result['code'], equals('999'));
        }
      });
    });
  });
}
