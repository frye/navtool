/// Tests for S57ParsedData.findFeatures() combined filtering
/// 
/// Validates that multiple filters work together with AND logic
/// according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 FindFeatures Combined Filters', () {
    test('should combine type and bounds filters with AND logic', () {
      final testData = _createTestDataWithVariousFeatures();
      final result = S57Parser.parse(testData);
      
      // Define bounds and types
      final testBounds = S57Bounds(
        north: 47.65,
        south: 47.60,
        east: -122.30,
        west: -122.35,
      );
      final types = {'LIGHTS', 'DEPARE'};
      
      // Get results with combined filters
      final combinedResults = result.findFeatures(
        types: types,
        bounds: testBounds,
      );
      
      // Get individual filter results for comparison
      final typeResults = result.findFeatures(types: types);
      final boundsResults = result.findFeatures(bounds: testBounds);
      
      // Combined results should be subset of both individual results
      expect(combinedResults.length, lessThanOrEqualTo(typeResults.length));
      expect(combinedResults.length, lessThanOrEqualTo(boundsResults.length));
      
      // Verify all results match both criteria
      for (final feature in combinedResults) {
        // Must be one of the requested types
        expect(types, contains(feature.featureType.acronym));
        
        // Must have coordinates within bounds
        final hasCoordInBounds = feature.coordinates.any((coord) {
          return coord.latitude >= testBounds.south &&
                 coord.latitude <= testBounds.north &&
                 coord.longitude >= testBounds.west &&
                 coord.longitude <= testBounds.east;
        });
        expect(hasCoordInBounds, isTrue);
      }
      
      print('Type filter: ${typeResults.length} features');
      print('Bounds filter: ${boundsResults.length} features');
      print('Combined filter: ${combinedResults.length} features');
    });

    test('should combine type, bounds, and text filters', () {
      final testData = _createTestDataWithVariousFeatures();
      final result = S57Parser.parse(testData);
      
      final testBounds = S57Bounds(
        north: 47.65,
        south: 47.60,
        east: -122.30,
        west: -122.35,
      );
      
      // Get results with all three filters
      final tripleFiltered = result.findFeatures(
        types: {'LIGHTS'},
        bounds: testBounds,
        textQuery: 'light',
      );
      
      // Verify each feature matches all criteria
      for (final feature in tripleFiltered) {
        // Type check
        expect(feature.featureType.acronym, equals('LIGHTS'));
        
        // Bounds check
        final hasCoordInBounds = feature.coordinates.any((coord) {
          return coord.latitude >= testBounds.south &&
                 coord.latitude <= testBounds.north &&
                 coord.longitude >= testBounds.west &&
                 coord.longitude <= testBounds.east;
        });
        expect(hasCoordInBounds, isTrue);
        
        // Text check
        final objnam = feature.attributes['OBJNAM']?.toString();
        if (objnam != null) {
          expect(objnam.toLowerCase(), contains('light'));
        }
      }
      
      print('Triple filtered results: ${tripleFiltered.length} features');
    });

    test('should apply limit after all other filters', () {
      final testData = _createTestDataWithVariousFeatures();
      final result = S57Parser.parse(testData);
      
      // Get filtered results without limit
      final unlimitedResults = result.findFeatures(
        types: {'LIGHTS', 'DEPARE', 'BOYLAT'},
      );
      
      // Apply limit smaller than result set
      final limit = (unlimitedResults.length / 2).floor();
      if (limit > 0) {
        final limitedResults = result.findFeatures(
          types: {'LIGHTS', 'DEPARE', 'BOYLAT'},
          limit: limit,
        );
        
        expect(limitedResults.length, equals(limit));
        
        // All limited results should still match the filter criteria
        for (final feature in limitedResults) {
          expect(['LIGHTS', 'DEPARE', 'BOYLAT'], 
                 contains(feature.featureType.acronym));
        }
        
        print('Unlimited: ${unlimitedResults.length}, Limited to $limit: ${limitedResults.length}');
      }
    });

    test('should handle empty results from restrictive filters', () {
      final testData = _createTestDataWithVariousFeatures();
      final result = S57Parser.parse(testData);
      
      // Use very restrictive filters that should return empty set
      final emptyBounds = S57Bounds(
        north: 0.0,
        south: -1.0,
        east: 1.0,
        west: 0.0,
      );
      
      final emptyResults = result.findFeatures(
        types: {'NONEXISTENT'},
        bounds: emptyBounds,
        textQuery: 'IMPOSSIBLE_TO_MATCH',
      );
      
      expect(emptyResults, isEmpty);
    });

    test('should maintain filter order consistency', () {
      final testData = _createTestDataWithVariousFeatures();
      final result = S57Parser.parse(testData);
      
      // Run same filters multiple times
      final testBounds = S57Bounds(
        north: 47.65,
        south: 47.60,
        east: -122.30,
        west: -122.35,
      );
      
      final results1 = result.findFeatures(
        types: {'LIGHTS'},
        bounds: testBounds,
      );
      
      final results2 = result.findFeatures(
        types: {'LIGHTS'},
        bounds: testBounds,
      );
      
      // Results should be identical
      expect(results1.length, equals(results2.length));
      
      // Feature IDs should match (assuming deterministic ordering)
      for (int i = 0; i < results1.length; i++) {
        expect(results1[i].recordId, equals(results2[i].recordId));
      }
      
      print('Consistent results: ${results1.length} features');
    });
  });
}

/// Create test data with various features for comprehensive testing
List<int> _createTestDataWithVariousFeatures() {
  // Create S-57 structure that generates diverse feature set
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