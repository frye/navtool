/// Tests for DSPM (Dataset Parameter) parsing functionality
/// 
/// Validates that DSPM fields are properly parsed and COMF/SOMF values
/// are correctly extracted according to Issue 20.8 requirements

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';

void main() {
  group('DSPM Parsing', () {
    test('should parse DSPM fields with custom COMF', () {
      final testData = createValidS57TestDataWithDSPM(comf: 5000000.0);
      
      final result = S57Parser.parse(testData);
      
      print('Parsed COMF: ${result.metadata.comf}');
      print('Parsed SOMF: ${result.metadata.somf}');
      
      // Should extract custom COMF from DSPM
      expect(result.metadata.comf, equals(5000000.0));
    });

    test('should parse DSPM fields with custom SOMF', () {
      final testData = createValidS57TestDataWithDSPM(somf: 25.0);
      
      final result = S57Parser.parse(testData);
      
      print('Parsed COMF: ${result.metadata.comf}');
      print('Parsed SOMF: ${result.metadata.somf}');
      
      // Should extract custom SOMF from DSPM
      expect(result.metadata.somf, equals(25.0));
    });

    test('should parse DSPM fields with both custom COMF and SOMF', () {
      final testData = createValidS57TestDataWithDSPM(comf: 8000000.0, somf: 15.0);
      
      final result = S57Parser.parse(testData);
      
      print('Parsed COMF: ${result.metadata.comf}');
      print('Parsed SOMF: ${result.metadata.somf}');
      
      // Should extract both custom values from DSPM
      expect(result.metadata.comf, equals(8000000.0));
      expect(result.metadata.somf, equals(15.0));
    });

    test('should use defaults when DSPM not present', () {
      final testData = createValidS57TestData(); // No DSPM
      
      final result = S57Parser.parse(testData);
      
      // Should use default values
      expect(result.metadata.comf, equals(10000000.0));
      expect(result.metadata.somf, equals(10.0));
    });
  });
}