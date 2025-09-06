/// Tests for S57ParsedData.findFeatures() bounds filtering
/// 
/// Validates that bounds filtering returns correct geographic subset
/// according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 FindFeatures Bounds Filter', () {
    test('should return features within specified bounds', () {
      final testData = _createTestDataWithKnownCoordinates();
      final result = S57Parser.parse(testData);
      
      // Define bounds that should include some features
      final testBounds = S57Bounds(
        north: 47.65,
        south: 47.60,
        east: -122.30,
        west: -122.35,
      );
      
      final boundedFeatures = result.findFeatures(bounds: testBounds);
      final allFeatures = result.findFeatures();
      
      // Bounded result should be subset of all features
      expect(boundedFeatures.length, lessThanOrEqualTo(allFeatures.length));
      
      // Manually verify bounds filtering is correct
      final manuallyFiltered = allFeatures.where((feature) {
        return feature.coordinates.any((coord) {
          return coord.latitude >= testBounds.south &&
                 coord.latitude <= testBounds.north &&
                 coord.longitude >= testBounds.west &&
                 coord.longitude <= testBounds.east;
        });
      }).toList();
      
      expect(boundedFeatures.length, equals(manuallyFiltered.length));
      
      print('Total features: ${allFeatures.length}');
      print('Features in bounds: ${boundedFeatures.length}');
      print('Manually filtered: ${manuallyFiltered.length}');
    });

    test('should return empty list for bounds with no features', () {
      final testData = _createTestDataWithKnownCoordinates();
      final result = S57Parser.parse(testData);
      
      // Define bounds that should not include any features
      final emptyBounds = S57Bounds(
        north: 0.0,
        south: -1.0,
        east: 1.0,
        west: 0.0,
      );
      
      final boundedFeatures = result.findFeatures(bounds: emptyBounds);
      expect(boundedFeatures, isEmpty);
    });

    test('should return all features for very large bounds', () {
      final testData = _createTestDataWithKnownCoordinates();
      final result = S57Parser.parse(testData);
      
      // Define very large bounds that should include all features
      final largeBounds = S57Bounds(
        north: 90.0,
        south: -90.0,
        east: 180.0,
        west: -180.0,
      );
      
      final boundedFeatures = result.findFeatures(bounds: largeBounds);
      final allFeatures = result.findFeatures();
      
      expect(boundedFeatures.length, equals(allFeatures.length));
    });

    test('should handle features with multiple coordinates correctly', () {
      final testData = _createTestDataWithKnownCoordinates();
      final result = S57Parser.parse(testData);
      
      // Test with bounds that intersect some but not all coordinates
      final partialBounds = S57Bounds(
        north: 47.62,
        south: 47.61,
        east: -122.32,
        west: -122.34,
      );
      
      final boundedFeatures = result.findFeatures(bounds: partialBounds);
      
      // Should include features where ANY coordinate is within bounds
      for (final feature in boundedFeatures) {
        final hasCoordInBounds = feature.coordinates.any((coord) {
          return coord.latitude >= partialBounds.south &&
                 coord.latitude <= partialBounds.north &&
                 coord.longitude >= partialBounds.west &&
                 coord.longitude <= partialBounds.east;
        });
        expect(hasCoordInBounds, isTrue);
      }
      
      print('Features with coordinates in partial bounds: ${boundedFeatures.length}');
    });
  });
}

/// Create test data with known coordinate patterns
List<int> _createTestDataWithKnownCoordinates() {
  // Create basic S-57 structure that will generate test features
  // The parser will create synthetic features with Elliott Bay coordinates
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