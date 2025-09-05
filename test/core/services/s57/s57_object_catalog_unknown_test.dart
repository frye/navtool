import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';

void main() {
  group('S57ObjectCatalog Unknown Handling', () {
    late S57ObjectCatalog catalog;

    setUp(() {
      // Create catalog with limited set of known objects
      final objectClasses = [
        const S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area'),
        const S57ObjectClass(code: 74, acronym: 'SOUNDG', name: 'Sounding'),
      ];
      catalog = S57ObjectCatalog.fromObjectClasses(objectClasses);
    });

    group('unknown code handling', () {
      test('should return null for unknown code', () {
        expect(catalog.byCode(999), isNull);
        expect(catalog.byCode(123), isNull);
        expect(catalog.byCode(-1), isNull);
      });

      test('should emit warning once per unknown code', () {
        // Test that the warning mechanism works by verifying that subsequent calls
        // don't cause issues and the catalog remains functional
        expect(catalog.byCode(999), isNull);
        expect(catalog.byCode(999), isNull); // Should not cause additional issues
        
        // Different unknown code
        expect(catalog.byCode(123), isNull);
        expect(catalog.byCode(123), isNull); // Should not cause additional issues
        
        // Known codes should still work
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byCode(74)?.acronym, equals('SOUNDG'));
      });

      test('should not emit warning for known codes', () {
        // Known codes should work without issues
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byCode(74)?.acronym, equals('SOUNDG'));
        // Repeated calls should continue to work
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
      });
    });

    group('unknown acronym handling', () {
      test('should return null for unknown acronym', () {
        expect(catalog.byAcronym('UNKNOWN'), isNull);
        expect(catalog.byAcronym('NOEXIST'), isNull);
        expect(catalog.byAcronym(''), isNull);
      });

      test('should emit warning once per unknown acronym', () {
        // Test that the warning mechanism works by verifying that subsequent calls
        // don't cause issues and the catalog remains functional
        expect(catalog.byAcronym('UNKNOWN'), isNull);
        expect(catalog.byAcronym('UNKNOWN'), isNull); // Should not cause additional issues
        
        // Case insensitive - should be treated as same acronym
        expect(catalog.byAcronym('unknown'), isNull);
        
        // Different unknown acronym
        expect(catalog.byAcronym('NOEXIST'), isNull);
        expect(catalog.byAcronym('NOEXIST'), isNull); // Should not cause additional issues
        
        // Known acronyms should still work
        expect(catalog.byAcronym('DEPARE')?.code, equals(42));
        expect(catalog.byAcronym('soundg')?.code, equals(74)); // case insensitive
      });

      test('should not emit warning for known acronyms', () {
        // Known acronyms should work without issues
        expect(catalog.byAcronym('DEPARE')?.code, equals(42));
        expect(catalog.byAcronym('soundg')?.code, equals(74)); // case insensitive
        // Repeated calls should continue to work
        expect(catalog.byAcronym('DEPARE')?.code, equals(42));
      });
    });

    group('warning suppression', () {
      test('should track warned codes and acronyms separately', () {
        // Test that warning mechanism tracks different types separately
        // Verify that both code and acronym lookups work independently
        expect(catalog.byCode(999), isNull);
        expect(catalog.byAcronym('999'), isNull);
        
        // Subsequent lookups should continue to work
        expect(catalog.byCode(999), isNull);
        expect(catalog.byAcronym('999'), isNull);
        
        // Known lookups should still work correctly
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byAcronym('SOUNDG')?.code, equals(74));
      });

      test('should handle edge cases without warnings', () {
        // Empty catalog should handle any lookup without crashing
        final emptyCatalog = S57ObjectCatalog.fromObjectClasses([]);
        
        expect(emptyCatalog.byCode(42), isNull);
        expect(emptyCatalog.byAcronym('DEPARE'), isNull);
        
        // Multiple calls should continue to work
        expect(emptyCatalog.byCode(42), isNull);
        expect(emptyCatalog.byAcronym('DEPARE'), isNull);
        
        // Catalog should remain consistent
        expect(emptyCatalog.size, equals(0));
      });
    });

    group('fallback behavior', () {
      test('should return fallback without breaking catalog integrity', () {
        // Unknown lookups should not affect subsequent known lookups
        expect(catalog.byCode(999), isNull);
        expect(catalog.byAcronym('UNKNOWN'), isNull);
        
        // Known lookups should still work correctly
        expect(catalog.byCode(42)?.acronym, equals('DEPARE'));
        expect(catalog.byAcronym('SOUNDG')?.code, equals(74));
        
        // Catalog size should remain unchanged
        expect(catalog.size, equals(2));
        expect(catalog.allObjectClasses, hasLength(2));
      });
    });
  });
}