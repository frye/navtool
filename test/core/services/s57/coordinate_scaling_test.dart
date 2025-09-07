/// Tests for coordinate scaling using COMF/SOMF factors
/// 
/// Validates that coordinate scaling is not hard-coded and uses
/// metadata COMF/SOMF values according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 Coordinate Scaling', () {
    test('should use COMF from metadata for coordinate scaling', () {
      // Test that coordinate values use proper COMF handling
      // Create test data with different COMF values
      final testData1 = _createTestDataWithCOMF(10000000.0);
      final testData2 = _createTestDataWithCOMF(5000000.0); 
      
      final result1 = S57Parser.parse(testData1);
      final result2 = S57Parser.parse(testData2);

      // Both should have features with coordinates
      expect(result1.features, isNotEmpty);
      expect(result2.features, isNotEmpty);
      
      // Should use the actual COMF values from DSPM
      expect(result1.metadata.comf, equals(10000000.0));
      expect(result2.metadata.comf, equals(5000000.0));
      
      // Coordinates should be different due to different COMF scaling
      final coord1 = result1.features.first.coordinates.first;
      final coord2 = result2.features.first.coordinates.first;
      
      // The ratio of coordinates should match the ratio of COMF values
      // Since coordinate = raw_value / COMF, when COMF is halved, coordinate should double
      expect(coord2.latitude / coord1.latitude, closeTo(2.0, 0.01));
      expect(coord2.longitude / coord1.longitude, closeTo(2.0, 0.01));
      
      print('Result 1 COMF: ${result1.metadata.comf}');
      print('Result 2 COMF: ${result2.metadata.comf}');
      print('Feature 1 coords: ${result1.features.first.coordinates.first}');
      print('Feature 2 coords: ${result2.features.first.coordinates.first}');
    });

    test('should use SOMF from metadata for sounding scaling', () {
      // Test that SOMF is correctly extracted and stored
      final testData = _createTestDataWithSOMF(25.0);
      
      final result = S57Parser.parse(testData);
      
      // Should use the actual SOMF from DSPM
      expect(result.metadata.somf, equals(25.0));
      print('SOMF value: ${result.metadata.somf}');
    });

    test('should use default scaling when COMF/SOMF not present', () {
      // Test with minimal data that doesn't contain DSPM fields
      final testData = _createMinimalTestData();
      
      final result = S57Parser.parse(testData);
      
      // Should use default values
      expect(result.metadata.comf, equals(10000000.0));
      expect(result.metadata.somf, equals(10.0));
    });

    test('should confirm no hard-coded scaling remains', () {
      // This test confirms that the parser uses metadata values
      final customComf = 20000000.0;
      final testData = _createTestDataWithCOMF(customComf);
      
      final result = S57Parser.parse(testData);
      
      // The metadata should contain the actual COMF value from DSPM
      expect(result.metadata.comf, equals(customComf));
      
      // Verify that coordinates are present (indicating parsing succeeded)
      expect(result.features, isNotEmpty);
      expect(result.features.first.coordinates, isNotEmpty);
    });
  });
}

/// Create test data with specific COMF value
List<int> _createTestDataWithCOMF(double comf) {
  // Create test data with DSPM field containing specified COMF
  return createValidS57TestDataWithDSPM(comf: comf);
}

/// Create test data with specific SOMF value
List<int> _createTestDataWithSOMF(double somf) {
  // Create test data with DSPM field containing specified SOMF
  return createValidS57TestDataWithDSPM(somf: somf);
}

/// Create minimal test data without DSPM fields
List<int> _createMinimalTestData() {
  return createValidS57TestData();
}