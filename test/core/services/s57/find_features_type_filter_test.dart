/// Tests for S57ParsedData.findFeatures() type filtering
/// 
/// Validates that type filtering returns only requested feature types
/// according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 FindFeatures Type Filter', () {
    test('should return only requested feature types', () {
      // Create test data and parse it
      final testData = _createTestDataWithMultipleFeatureTypes();
      final result = S57Parser.parse(testData);
      
      // Test filtering by single type - use a type that actually exists
      final depthFeatures = result.findFeatures(types: {'BOYLAT'});
      expect(depthFeatures, isNotEmpty);
      
      // All returned features should be the requested type
      for (final feature in depthFeatures) {
        expect(feature.featureType.acronym, equals('BOYLAT'));
      }
      
      print('Found ${depthFeatures.length} BOYLAT features');
    });

    test('should return multiple types when requested', () {
      final testData = _createTestDataWithMultipleFeatureTypes();
      final result = S57Parser.parse(testData);
      
      // Test filtering by multiple types
      final navFeatures = result.findFeatures(types: {'LIGHTS', 'BOYLAT'});
      
      // All returned features should be one of the requested types
      for (final feature in navFeatures) {
        expect(['LIGHTS', 'BOYLAT'], contains(feature.featureType.acronym));
      }
      
      print('Found ${navFeatures.length} navigation aid features');
    });

    test('should return empty list for non-existent types', () {
      final testData = _createTestDataWithMultipleFeatureTypes();
      final result = S57Parser.parse(testData);
      
      // Test filtering by non-existent type
      final nonExistentFeatures = result.findFeatures(types: {'NONEXISTENT'});
      expect(nonExistentFeatures, isEmpty);
    });

    test('should return all features when no type filter specified', () {
      final testData = _createTestDataWithMultipleFeatureTypes();
      final result = S57Parser.parse(testData);
      
      // Test without type filter
      final allFeatures = result.findFeatures();
      expect(allFeatures.length, equals(result.features.length));
      
      // Should include all feature types
      final types = allFeatures.map((f) => f.featureType.acronym).toSet();
      expect(types, isNotEmpty);
      
      print('Total features: ${allFeatures.length}');
      print('Feature types: $types');
    });

    test('should handle empty type set', () {
      final testData = _createTestDataWithMultipleFeatureTypes();
      final result = S57Parser.parse(testData);
      
      // Test with empty type set - should return all features (no filtering)
      final allFeatures = result.findFeatures(types: <String>{});
      final expectedAllFeatures = result.findFeatures(); // No filter
      expect(allFeatures.length, equals(expectedAllFeatures.length));
    });
  });
}

/// Create test data with multiple feature types for testing
List<int> _createTestDataWithMultipleFeatureTypes() {
  return createValidS57TestData();
}