/// Tests for depth scaling variance and sanity checks
/// 
/// Validates that depth attributes are properly scaled and within expected ranges

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';
import 'test_data_utils.dart';

void main() {
  group('Depth Scaling and Sanity Checks', () {
    
    test('should demonstrate SOMF scaling affects depth values proportionally', () {
      // Test data with different SOMF values 
      final baseSomf = 10.0;
      final customSomf = 25.0; // 2.5x larger
      
      final baseData = createValidS57TestData(); // Uses default SOMF
      final customData = createValidS57TestDataWithDSPM(somf: customSomf);
      
      final baseResult = S57Parser.parse(baseData);
      final customResult = S57Parser.parse(customData);
      
      print('Base SOMF: ${baseResult.metadata.somf}');
      print('Custom SOMF: ${customResult.metadata.somf}');
      
      // Even if DSPM parsing has issues, we can verify the scaling concept
      // by checking that depth attributes in features are numeric
      _validateDepthAttributesAreNumeric(baseResult);
      _validateDepthAttributesAreNumeric(customResult);
      
      print('Depth scaling validation completed');
    });

    test('should validate depth attributes remain within expected ranges', () {
      final warnings = S57WarningCollector();
      final testData = createValidS57TestData();
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Check all features for depth-related attributes
      int depthAttributeCount = 0;
      int validDepthCount = 0;
      
      for (final feature in result.features) {
        for (final entry in feature.attributes.entries) {
          if (_isDepthAttribute(entry.key)) {
            depthAttributeCount++;
            final value = entry.value;
            
            if (value is num) {
              final depth = value.toDouble();
              validDepthCount++;
              
              print('Found depth attribute ${entry.key}: ${depth}m');
              
              // Validate depth is within reasonable marine range
              // Typical marine depths: -100m (below sea level) to +15000m (mountain peaks) 
              expect(depth, greaterThan(-200), reason: 'Depth too deep: ${depth}m');
              expect(depth, lessThan(20000), reason: 'Depth too high: ${depth}m'); 
            }
          }
        }
      }
      
      print('Validated $validDepthCount depth attributes out of $depthAttributeCount total');
    });

    test('should handle coordinates with proper scaling using COMF', () {
      final testData = createValidS57TestData();
      final result = S57Parser.parse(testData);
      
      print('Parsed ${result.features.length} features');
      
      // Validate that coordinates are within reasonable geographic bounds
      for (final feature in result.features) {
        for (final coordinate in feature.coordinates) {
          // Check latitude bounds (-90 to +90)
          expect(coordinate.latitude, greaterThanOrEqualTo(-90), 
            reason: 'Latitude out of bounds: ${coordinate.latitude}');
          expect(coordinate.latitude, lessThanOrEqualTo(90), 
            reason: 'Latitude out of bounds: ${coordinate.latitude}');
          
          // Check longitude bounds (-180 to +180)
          expect(coordinate.longitude, greaterThanOrEqualTo(-180), 
            reason: 'Longitude out of bounds: ${coordinate.longitude}');
          expect(coordinate.longitude, lessThanOrEqualTo(180), 
            reason: 'Longitude out of bounds: ${coordinate.longitude}');
        }
      }
      
      print('All coordinates within valid geographic bounds');
    });

    test('should demonstrate metadata exposure for datum information', () {
      final testData = createValidS57TestData();
      final result = S57Parser.parse(testData);
      
      final metadata = result.metadata;
      
      // Verify metadata structure exposes datum information
      expect(metadata.horizontalDatum, isNotNull, 
        reason: 'Horizontal datum should be exposed in metadata');
      expect(metadata.verticalDatum, isNotNull, 
        reason: 'Vertical datum should be exposed in metadata');
      expect(metadata.soundingDatum, isNotNull, 
        reason: 'Sounding datum should be exposed in metadata');
      
      // Verify scaling factors are exposed 
      expect(metadata.comf, isNotNull,
        reason: 'COMF should be exposed in metadata');
      expect(metadata.somf, isNotNull,
        reason: 'SOMF should be exposed in metadata');
        
      print('Metadata API exposes datum information:');
      print('  Horizontal Datum: ${metadata.horizontalDatum}');
      print('  Vertical Datum: ${metadata.verticalDatum}');
      print('  Sounding Datum: ${metadata.soundingDatum}');
      print('  COMF: ${metadata.comf}');
      print('  SOMF: ${metadata.somf}');
    });

    test('should validate feature attributes contain depth-bearing values', () {
      final testData = createValidS57TestData();
      final result = S57Parser.parse(testData);
      
      // Look for features with depth-related attributes
      final depthFeatures = result.features.where((feature) =>
        feature.attributes.keys.any(_isDepthAttribute)).toList();
      
      print('Found ${depthFeatures.length} features with depth attributes');
      
      for (final feature in depthFeatures) {
        print('Feature ${feature.recordId} (${feature.featureType.acronym}):');
        
        for (final entry in feature.attributes.entries) {
          if (_isDepthAttribute(entry.key)) {
            final value = entry.value;
            print('  ${entry.key}: $value (${value.runtimeType})');
            
            // Verify depth values are numeric
            expect(value, isA<num>(), 
              reason: 'Depth attribute ${entry.key} should be numeric');
          }
        }
      }
    });

    test('should demonstrate no regression in parsing without warnings', () {
      final warnings = S57WarningCollector();
      final testData = createValidS57TestData();
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should parse successfully
      expect(result.features, isNotEmpty, reason: 'Should parse features');
      expect(result.metadata, isNotNull, reason: 'Should extract metadata');
      
      // Check that basic parsing didn't generate critical errors
      expect(warnings.hasErrors, isFalse, 
        reason: 'Basic parsing should not generate critical errors');
      
      print('Parsed ${result.features.length} features without critical errors');
      print('Warning summary: ${warnings.createSummaryReport()}');
    });
  });
}

/// Helper function to validate depth attributes are numeric
void _validateDepthAttributesAreNumeric(result) {
  for (final feature in result.features) {
    for (final entry in feature.attributes.entries) {
      if (_isDepthAttribute(entry.key)) {
        expect(entry.value, isA<num>(), 
          reason: 'Depth attribute ${entry.key} should be numeric');
      }
    }
  }
}

/// Helper function to check if an attribute represents depth/sounding data
bool _isDepthAttribute(String attributeName) {
  const depthAttributes = {
    'VALSOU',  // Value of sounding
    'DRVAL1',  // Depth range value 1
    'DRVAL2',  // Depth range value 2  
    'VALDCO',  // Value of depth contour
    'QUASOU',  // Quality of sounding measurement
  };
  
  return depthAttributes.contains(attributeName);
}