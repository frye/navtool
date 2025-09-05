import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';

void main() {
  group('S57ObjectCatalog Performance', () {
    late S57ObjectCatalog catalog;
    late S57AttributeCatalog attributeCatalog;

    setUp(() {
      // Create a reasonably sized catalog for performance testing
      final objectClasses = <S57ObjectClass>[];
      for (int i = 1; i <= 100; i++) {
        objectClasses.add(S57ObjectClass(
          code: i,
          acronym: 'OBJ${i.toString().padLeft(3, '0')}',
          name: 'Object $i',
        ));
      }
      catalog = S57ObjectCatalog.fromObjectClasses(objectClasses);

      final attributeDefs = <S57AttributeDef>[];
      for (int i = 1; i <= 50; i++) {
        attributeDefs.add(S57AttributeDef(
          acronym: 'ATTR${i.toString().padLeft(3, '0')}',
          type: S57AttrType.string,
          name: 'Attribute $i',
        ));
      }
      attributeCatalog = S57AttributeCatalog.fromAttributeDefs(attributeDefs);
    });

    test('repeated lookups should complete within reasonable time', () {
      const int lookupCount = 10000;
      const int maxMilliseconds = 1000; // 1 second threshold

      // Test object code lookups
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < lookupCount; i++) {
        final code = (i % 100) + 1; // Cycle through codes 1-100
        catalog.byCode(code);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '$lookupCount code lookups took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('repeated acronym lookups should complete within reasonable time', () {
      const int lookupCount = 10000;
      const int maxMilliseconds = 1000; // 1 second threshold

      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < lookupCount; i++) {
        final acronym = 'OBJ${((i % 100) + 1).toString().padLeft(3, '0')}';
        catalog.byAcronym(acronym);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '$lookupCount acronym lookups took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('attribute decoding should complete within reasonable time', () {
      const int decodeCount = 10000;
      const int maxMilliseconds = 1000; // 1 second threshold

      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < decodeCount; i++) {
        final acronym = 'ATTR${((i % 50) + 1).toString().padLeft(3, '0')}';
        final def = attributeCatalog.byAcronym(acronym);
        attributeCatalog.decodeAttribute(def, ['test_value_$i']);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '$decodeCount attribute decodings took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('mixed operations should maintain O(1) performance', () {
      const int operationCount = 5000;
      const int maxMilliseconds = 500; // 0.5 second threshold

      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < operationCount; i++) {
        // Mix of operations to simulate real usage
        final code = (i % 100) + 1;
        final acronym = 'OBJ${code.toString().padLeft(3, '0')}';
        final attrAcronym = 'ATTR${((i % 50) + 1).toString().padLeft(3, '0')}';
        
        // Object lookups
        catalog.byCode(code);
        catalog.byAcronym(acronym);
        
        // Attribute operations
        final def = attributeCatalog.byAcronym(attrAcronym);
        attributeCatalog.decodeAttribute(def, ['value_$i']);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '${operationCount * 4} mixed operations took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('unknown lookups should not significantly impact performance', () {
      const int lookupCount = 1000;
      const int maxMilliseconds = 200; // 0.2 second threshold (adjusted for warning overhead)

      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < lookupCount; i++) {
        // Use the same unknown codes repeatedly to test warning suppression
        catalog.byCode(999); // Same unknown code
        catalog.byAcronym('UNKNOWN'); // Same unknown acronym
        attributeCatalog.byAcronym('UNKNOWNATTR'); // Same unknown attribute
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '${lookupCount * 3} repeated unknown lookups took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('catalog initialization overhead should be minimal', () {
      const int maxMilliseconds = 100; // 0.1 second threshold

      final stopwatch = Stopwatch()..start();
      
      // Create multiple catalogs to test initialization overhead
      for (int i = 0; i < 10; i++) {
        final objectClasses = [
          S57ObjectClass(code: i + 1, acronym: 'TEST$i', name: 'Test Object $i'),
        ];
        S57ObjectCatalog.fromObjectClasses(objectClasses);
        
        final attributeDefs = [
          S57AttributeDef(acronym: 'TESTATTR$i', type: S57AttrType.string, name: 'Test Attribute $i'),
        ];
        S57AttributeCatalog.fromAttributeDefs(attributeDefs);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '10 catalog initializations took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });

    test('large catalog should maintain good performance', () {
      // Create a large catalog similar to a full S-57 implementation
      final largeObjectClasses = <S57ObjectClass>[];
      for (int i = 1; i <= 500; i++) {
        largeObjectClasses.add(S57ObjectClass(
          code: i,
          acronym: 'LRG${i.toString().padLeft(3, '0')}',
          name: 'Large Object $i',
        ));
      }
      final largeCatalog = S57ObjectCatalog.fromObjectClasses(largeObjectClasses);

      const int lookupCount = 5000;
      const int maxMilliseconds = 500; // 0.5 second threshold

      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < lookupCount; i++) {
        final code = (i % 500) + 1;
        final acronym = 'LRG${code.toString().padLeft(3, '0')}';
        
        largeCatalog.byCode(code);
        largeCatalog.byAcronym(acronym);
      }
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(maxMilliseconds),
          reason: '$lookupCount lookups in large catalog (500 objects) took ${stopwatch.elapsedMilliseconds}ms (expected < ${maxMilliseconds}ms)');
    });
  });
}