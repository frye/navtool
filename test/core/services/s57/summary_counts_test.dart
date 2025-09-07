/// Tests for S57ParsedData.summary() feature counting
/// 
/// Validates summary statistics according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 Summary Counts', () {
    test('should return correct feature counts by acronym', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final summary = result.summary();
      final totalFeatures = result.features.length;
      
      // Sum of counts should equal total features
      final sumOfCounts = summary.values.fold(0, (sum, count) => sum + count);
      expect(sumOfCounts, equals(totalFeatures));
      
      print('Total features: $totalFeatures');
      print('Summary counts: $summary');
      print('Sum of counts: $sumOfCounts');
    });

    test('should count each feature type correctly', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final summary = result.summary();
      
      // Manually count each type for verification
      final manualCounts = <String, int>{};
      for (final feature in result.features) {
        final acronym = feature.featureType.acronym;
        manualCounts[acronym] = (manualCounts[acronym] ?? 0) + 1;
      }
      
      // Summary should match manual counts
      expect(summary.length, equals(manualCounts.length));
      
      for (final entry in manualCounts.entries) {
        expect(summary[entry.key], equals(entry.value));
      }
      
      print('Manual counts: $manualCounts');
      print('Summary counts: $summary');
    });

    test('should handle empty feature collection', () {
      // Create data that results in no features by using minimal structure
      final testData = _createMinimalTestData();
      final result = S57Parser.parse(testData);
      
      // Remove all features for this test
      final emptyResult = S57ParsedData(
        metadata: result.metadata,
        features: [],
        bounds: result.bounds,
        spatialIndex: result.spatialIndex,
      );
      
      final summary = emptyResult.summary();
      expect(summary, isEmpty);
    });

    test('should include all unique feature types', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final summary = result.summary();
      final uniqueTypes = result.features
          .map((f) => f.featureType.acronym)
          .toSet();
      
      // Summary should have an entry for each unique type
      expect(summary.keys.toSet(), equals(uniqueTypes));
      
      // All counts should be positive
      for (final count in summary.values) {
        expect(count, greaterThan(0));
      }
      
      print('Unique types: $uniqueTypes');
      print('Summary keys: ${summary.keys.toSet()}');
    });

    test('should provide consistent results on multiple calls', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final summary1 = result.summary();
      final summary2 = result.summary();
      
      // Should be identical
      expect(summary1.length, equals(summary2.length));
      
      for (final key in summary1.keys) {
        expect(summary2[key], equals(summary1[key]));
      }
    });

    test('should handle single feature type correctly', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      // Filter to get only one type of feature
      final lightsOnly = result.findFeatures(types: {'LIGHTS'});
      
      if (lightsOnly.isNotEmpty) {
        // Create filtered result for testing
        final filteredResult = S57ParsedData(
          metadata: result.metadata,
          features: lightsOnly,
          bounds: result.bounds,
          spatialIndex: result.spatialIndex,
        );
        
        final summary = filteredResult.summary();
        
        // Should only have one entry
        expect(summary.length, equals(1));
        expect(summary['LIGHTS'], equals(lightsOnly.length));
        
        print('Single type summary: $summary');
      }
    });

    test('should handle multiple instances of same type', () {
      final testData = _createTestDataWithFeatures();
      final result = S57Parser.parse(testData);
      
      final summary = result.summary();
      
      // Check if any type has multiple instances
      final multipleInstanceTypes = summary.entries
          .where((entry) => entry.value > 1)
          .toList();
      
      if (multipleInstanceTypes.isNotEmpty) {
        for (final entry in multipleInstanceTypes) {
          print('Type ${entry.key} has ${entry.value} instances');
          
          // Verify by manual count
          final actualCount = result.features
              .where((f) => f.featureType.acronym == entry.key)
              .length;
          expect(entry.value, equals(actualCount));
        }
      } else {
        print('All feature types have single instances');
      }
    });
  });
}

/// Create test data that generates multiple features for counting
List<int> _createTestDataWithFeatures() {
  return createValidS57TestData();
}

/// Create minimal test data that generates few/no features
List<int> _createMinimalTestData() {
  return createValidS57TestData();
}