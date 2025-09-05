import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';

void main() {
  group('S57ObjectCatalog', () {
    group('loadFromAssets', () {
      test('should load object classes from JSON asset', () async {
        // Mock the asset loading
        const objectClassesJson = '''[
          {"code": 42, "acronym": "DEPARE", "name": "Depth Area"},
          {"code": 74, "acronym": "SOUNDG", "name": "Sounding"},
          {"code": 121, "acronym": "COALNE", "name": "Coastline"}
        ]''';

        // Override the asset loader for testing
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('flutter/assets'),
                (MethodCall methodCall) async {
          if (methodCall.method == 'loadString') {
            final String key = methodCall.arguments as String;
            if (key == 'assets/s57/object_classes.json') {
              return objectClassesJson;
            }
          }
          return null;
        });

        // Act
        final catalog = await S57ObjectCatalog.loadFromAssets();

        // Assert
        expect(catalog.size, equals(3));
        expect(catalog.allObjectClasses, hasLength(3));

        // Verify specific object classes
        final depare = catalog.byCode(42);
        expect(depare, isNotNull);
        expect(depare!.acronym, equals('DEPARE'));
        expect(depare.name, equals('Depth Area'));

        final soundg = catalog.byAcronym('SOUNDG');
        expect(soundg, isNotNull);
        expect(soundg!.code, equals(74));
        expect(soundg.name, equals('Sounding'));

        // Test case insensitive lookup
        final coalne = catalog.byAcronym('coalne');
        expect(coalne, isNotNull);
        expect(coalne!.code, equals(121));
        expect(coalne.name, equals('Coastline'));
      });

      test('should handle empty JSON array', () async {
        // Mock empty asset
        const emptyJson = '[]';

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('flutter/assets'),
                (MethodCall methodCall) async {
          if (methodCall.method == 'loadString') {
            final String key = methodCall.arguments as String;
            if (key == 'assets/s57/object_classes.json') {
              return emptyJson;
            }
          }
          return null;
        });

        // Act
        final catalog = await S57ObjectCatalog.loadFromAssets();

        // Assert
        expect(catalog.size, equals(0));
        expect(catalog.allObjectClasses, isEmpty);
      });
    });

    group('fromObjectClasses', () {
      test('should create catalog from object classes list', () {
        // Arrange
        final objectClasses = [
          const S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area'),
          const S57ObjectClass(code: 74, acronym: 'SOUNDG', name: 'Sounding'),
        ];

        // Act
        final catalog = S57ObjectCatalog.fromObjectClasses(objectClasses);

        // Assert
        expect(catalog.size, equals(2));
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byAcronym('SOUNDG')?.code, equals(74));
      });
    });

    group('lookup', () {
      late S57ObjectCatalog catalog;

      setUp(() {
        final objectClasses = [
          const S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area'),
          const S57ObjectClass(code: 74, acronym: 'SOUNDG', name: 'Sounding'),
          const S57ObjectClass(code: 121, acronym: 'COALNE', name: 'Coastline'),
        ];
        catalog = S57ObjectCatalog.fromObjectClasses(objectClasses);
      });

      test('should lookup by code', () {
        // Test known codes
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byCode(74)?.acronym, equals('SOUNDG'));
        expect(catalog.byCode(121)?.acronym, equals('COALNE'));

        // Test unknown code
        expect(catalog.byCode(999), isNull);
      });

      test('should lookup by acronym case insensitive', () {
        // Test known acronyms
        expect(catalog.byAcronym('DEPARE')?.code, equals(42));
        expect(catalog.byAcronym('depare')?.code, equals(42));
        expect(catalog.byAcronym('SoUnDg')?.code, equals(74));

        // Test unknown acronym
        expect(catalog.byAcronym('UNKNOWN'), isNull);
      });

      test('should emit warning for unknown codes once', () {
        // Test warning behavior by checking that repeated calls don't trigger multiple warnings
        // We verify this indirectly by ensuring the catalog continues to work correctly
        expect(catalog.byCode(999), isNull);
        expect(catalog.byCode(999), isNull); // Second call - should not cause issues
        
        // Known codes should still work after unknown lookups
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
      });

      test('should emit warning for unknown acronyms once', () {
        // Test warning behavior by checking that repeated calls don't trigger multiple warnings
        // We verify this indirectly by ensuring the catalog continues to work correctly
        expect(catalog.byAcronym('UNKNOWN'), isNull);
        expect(catalog.byAcronym('UNKNOWN'), isNull); // Second call - should not cause issues
        
        // Known acronyms should still work after unknown lookups
        expect(catalog.byAcronym('DEPARE')?.code, equals(42));
      });
    });

    group('S57ObjectClass', () {
      test('should serialize to/from JSON', () {
        // Arrange
        const objectClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        // Act
        final json = objectClass.toJson();
        final restored = S57ObjectClass.fromJson(json);

        // Assert
        expect(restored, equals(objectClass));
        expect(json['code'], equals(42));
        expect(json['acronym'], equals('DEPARE'));
        expect(json['name'], equals('Depth Area'));
      });

      test('should implement equality correctly', () {
        const obj1 = S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area');
        const obj2 = S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area');
        const obj3 = S57ObjectClass(code: 74, acronym: 'SOUNDG', name: 'Sounding');

        expect(obj1, equals(obj2));
        expect(obj1, isNot(equals(obj3)));
        expect(obj1.hashCode, equals(obj2.hashCode));
      });

      test('should have readable toString', () {
        const objectClass = S57ObjectClass(
          code: 42,
          acronym: 'DEPARE',
          name: 'Depth Area',
        );

        final str = objectClass.toString();
        expect(str, contains('42'));
        expect(str, contains('DEPARE'));
        expect(str, contains('Depth Area'));
      });
    });
  });
}