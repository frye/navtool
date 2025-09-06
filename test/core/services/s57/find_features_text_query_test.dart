/// Tests for S57ParsedData.findFeatures() text query filtering
/// 
/// Validates text search on OBJNAM attribute according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 FindFeatures Text Query', () {
    test('should find features by case-insensitive OBJNAM substring', () {
      final testData = _createTestDataWithOBJNAM();
      final result = S57Parser.parse(testData);
      
      // Test case-insensitive search
      final lightFeatures = result.findFeatures(textQuery: 'light');
      
      // All returned features should have OBJNAM containing 'light'
      for (final feature in lightFeatures) {
        final objnam = feature.attributes['OBJNAM']?.toString();
        expect(objnam, isNotNull);
        expect(objnam!.toLowerCase(), contains('light'));
      }
      
      print('Found ${lightFeatures.length} features with "light" in OBJNAM');
    });

    test('should handle case variations correctly', () {
      final testData = _createTestDataWithOBJNAM();
      final result = S57Parser.parse(testData);
      
      // Test different cases should return same results
      final lowerCase = result.findFeatures(textQuery: 'test');
      final upperCase = result.findFeatures(textQuery: 'TEST');
      final mixedCase = result.findFeatures(textQuery: 'Test');
      
      expect(lowerCase.length, equals(upperCase.length));
      expect(lowerCase.length, equals(mixedCase.length));
      
      print('Case variations all found ${lowerCase.length} features');
    });

    test('should return empty list for non-matching text', () {
      final testData = _createTestDataWithOBJNAM();
      final result = S57Parser.parse(testData);
      
      final noMatches = result.findFeatures(textQuery: 'NONEXISTENT');
      expect(noMatches, isEmpty);
    });

    test('should handle empty or null text query', () {
      final testData = _createTestDataWithOBJNAM();
      final result = S57Parser.parse(testData);
      
      // Empty string should return all features
      final emptyQuery = result.findFeatures(textQuery: '');
      final allFeatures = result.findFeatures();
      expect(emptyQuery.length, equals(allFeatures.length));
      
      // Null query should return all features
      final nullQuery = result.findFeatures(textQuery: null);
      expect(nullQuery.length, equals(allFeatures.length));
    });

    test('should handle features without OBJNAM attribute', () {
      final testData = _createTestDataWithoutOBJNAM();
      final result = S57Parser.parse(testData);
      
      // Search should not crash on features without OBJNAM
      final searchResults = result.findFeatures(textQuery: 'anything');
      
      // Should return empty or only features that have OBJNAM
      for (final feature in searchResults) {
        final objnam = feature.attributes['OBJNAM']?.toString();
        if (objnam != null) {
          expect(objnam.toLowerCase(), contains('anything'));
        }
      }
      
      print('Search handled ${result.features.length} features, found ${searchResults.length} matches');
    });

    test('should find partial matches within OBJNAM', () {
      final testData = _createTestDataWithOBJNAM();
      final result = S57Parser.parse(testData);
      
      // Test partial substring matching
      final partialMatches = result.findFeatures(textQuery: 'Lig');
      
      for (final feature in partialMatches) {
        final objnam = feature.attributes['OBJNAM']?.toString();
        expect(objnam, isNotNull);
        expect(objnam!.toLowerCase(), contains('lig'));
      }
      
      print('Partial match "Lig" found ${partialMatches.length} features');
    });
  });
}

/// Create test data with OBJNAM attributes
List<int> _createTestDataWithOBJNAM() {
  // Create basic S-57 structure that will generate test features
  // The synthetic features created by the parser include OBJNAM attributes
  const ddrHeader = [
    0x30, 0x30, 0x31, 0x32, 0x30, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x1e,
  ];
  
  final data = List<int>.from(ddrHeader);
  // Pad to minimum size to trigger synthetic feature generation
  while (data.length < 120) {
    data.add(0x20);
  }
  
  return data;
}

/// Create test data without OBJNAM attributes
List<int> _createTestDataWithoutOBJNAM() {
  // Use minimal test data that creates features without OBJNAM
  return [
    0x30, 0x30, 0x30, 0x32, 0x34, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x1e,
  ];
}