/// Tests for backward compatibility with legacy S57FeatureType enum
/// 
/// Validates that legacy enum lookups yield same acronym features
/// according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_backward_compatibility.dart';

void main() {
  group('S57 Backward Compatibility', () {
    test('should map legacy enum values to correct acronyms', () {
      // Test key legacy mappings
      final testCases = [
        (S57FeatureType.depthArea, 'DEPARE'),
        (S57FeatureType.lighthouse, 'LIGHTS'),
        (S57FeatureType.buoyLateral, 'BOYLAT'),
        (S57FeatureType.sounding, 'SOUNDG'),
        (S57FeatureType.coastline, 'COALNE'),
      ];
      
      for (final (legacyType, expectedAcronym) in testCases) {
        final acronym = S57BackwardCompatibilityAdapter.legacyToAcronym(legacyType);
        expect(acronym, equals(expectedAcronym));
        print('${legacyType.name} -> $acronym');
      }
    });

    test('should find same features using legacy enum and acronym', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      // Test depth area features
      final legacyDepthFeatures = result.features
          .where((f) => f.featureType == S57FeatureType.depthArea)
          .toList();
      
      final acronymDepthFeatures = result.findFeatures(types: {'DEPARE'});
      
      // Should find the same features
      expect(legacyDepthFeatures.length, equals(acronymDepthFeatures.length));
      
      // Feature IDs should match
      final legacyIds = legacyDepthFeatures.map((f) => f.recordId).toSet();
      final acronymIds = acronymDepthFeatures.map((f) => f.recordId).toSet();
      expect(legacyIds, equals(acronymIds));
      
      print('Legacy depth features: ${legacyDepthFeatures.length}');
      print('Acronym depth features: ${acronymDepthFeatures.length}');
    });

    test('should maintain consistency between enum and acronym searches', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      // Test multiple feature types
      final testTypes = [
        S57FeatureType.lighthouse,
        S57FeatureType.depthArea,
        S57FeatureType.coastline,
      ];
      
      for (final legacyType in testTypes) {
        final acronym = S57BackwardCompatibilityAdapter.legacyToAcronym(legacyType);
        
        // Find using legacy enum direct comparison
        final legacyResults = result.features
            .where((f) => f.featureType == legacyType)
            .toList();
        
        // Find using new acronym-based query
        final acronymResults = result.findFeatures(types: {acronym});
        
        expect(legacyResults.length, equals(acronymResults.length));
        
        print('${legacyType.name} ($acronym): ${legacyResults.length} features');
      }
    });

    test('should handle reverse mapping from acronym to legacy', () {
      final testAcronyms = ['DEPARE', 'LIGHTS', 'BOYLAT', 'SOUNDG', 'COALNE'];
      
      for (final acronym in testAcronyms) {
        final legacyType = S57BackwardCompatibilityAdapter.acronymToLegacy(acronym);
        expect(legacyType, isNot(equals(S57FeatureType.unknown)));
        
        // Verify round-trip consistency
        final backToAcronym = S57BackwardCompatibilityAdapter.legacyToAcronym(legacyType);
        expect(backToAcronym, equals(acronym));
        
        print('$acronym -> ${legacyType.name} -> $backToAcronym');
      }
    });

    test('should provide mapping statistics for validation', () {
      final stats = S57BackwardCompatibilityAdapter.getMappingStats();
      
      expect(stats.keys, contains('total_legacy_types'));
      expect(stats.keys, contains('mapped_to_official'));
      expect(stats.keys, contains('official_acronyms'));
      expect(stats.keys, contains('unknown_mappings'));
      
      // Should have reasonable coverage
      final totalTypes = stats['total_legacy_types'] as int;
      final mappedTypes = stats['mapped_to_official'] as int;
      final unknownMappings = stats['unknown_mappings'] as int;
      
      expect(totalTypes, greaterThan(0));
      expect(mappedTypes, greaterThan(0));
      expect(mappedTypes, lessThanOrEqualTo(totalTypes));
      expect(unknownMappings, greaterThanOrEqualTo(0));
      
      print('Mapping statistics: $stats');
      
      // Most types should have official mappings
      final mappingCoverage = mappedTypes / totalTypes;
      expect(mappingCoverage, greaterThan(0.5)); // At least 50% coverage
    });

    test('should handle unknown legacy types gracefully', () {
      final unknownAcronym = S57BackwardCompatibilityAdapter
          .legacyToAcronym(S57FeatureType.unknown);
      expect(unknownAcronym, equals('UNKNOW'));
      
      final backToUnknown = S57BackwardCompatibilityAdapter
          .acronymToLegacy('UNKNOW');
      expect(backToUnknown, equals(S57FeatureType.unknown));
    });

    test('should support official S-57 equivalents check', () {
      // Test types that should have official equivalents
      final officialTypes = [
        S57FeatureType.depthArea,
        S57FeatureType.lighthouse,
        S57FeatureType.sounding,
      ];
      
      for (final type in officialTypes) {
        final hasOfficial = S57BackwardCompatibilityAdapter
            .hasOfficialEquivalent(type);
        expect(hasOfficial, isTrue);
        print('${type.name} has official equivalent: $hasOfficial');
      }
      
      // Unknown type should not have official equivalent
      final unknownHasOfficial = S57BackwardCompatibilityAdapter
          .hasOfficialEquivalent(S57FeatureType.unknown);
      expect(unknownHasOfficial, isFalse);
    });

    test('should maintain feature attribute compatibility', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      // Find features using both approaches
      final legacyFeatures = result.features
          .where((f) => f.featureType == S57FeatureType.lighthouse)
          .toList();
      
      final acronymFeatures = result.findFeatures(types: {'LIGHTS'});
      
      if (legacyFeatures.isNotEmpty && acronymFeatures.isNotEmpty) {
        // Compare attributes of corresponding features
        for (int i = 0; i < legacyFeatures.length && i < acronymFeatures.length; i++) {
          final legacyAttrs = legacyFeatures[i].attributes;
          final acronymAttrs = acronymFeatures[i].attributes;
          
          // Should have same attribute keys
          expect(legacyAttrs.keys.toSet(), equals(acronymAttrs.keys.toSet()));
          
          print('Feature $i attributes match: ${legacyAttrs.keys.length} keys');
        }
      }
    });
  });
}

/// Create test data that generates features for compatibility testing
List<int> _createTestDataWithFeatures() {
  const ddrHeader = [
    0x30, 0x30, 0x31, 0x32, 0x30, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x1e,
  ];
  
  final data = List<int>.from(ddrHeader);
  while (data.length < 120) {
    data.add(0x20);
  }
  
  return data;
}