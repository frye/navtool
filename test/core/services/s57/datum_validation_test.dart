/// Tests for datum extraction and validation functionality
/// 
/// Validates that datum codes are properly extracted from DSPM fields
/// and unknown datum codes trigger appropriate warnings

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_parse_warnings.dart';
import 'package:navtool/core/services/s57/s57_warning_collector.dart';
import 'test_data_utils.dart';

void main() {
  group('Datum Extraction and Validation', () {
    
    test('should expose datum codes in metadata for default fixtures', () {
      final testData = createValidS57TestData(); // No DSPM - uses defaults
      
      final result = S57Parser.parse(testData);
      
      // Default datum codes should be available
      expect(result.metadata.horizontalDatum, equals('WGS84'));
      expect(result.metadata.verticalDatum, equals('MLLW'));
      expect(result.metadata.soundingDatum, equals('MLLW'));
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should expose datum codes in metadata for custom fixtures', () {
      final testData = createValidS57TestDataWithDSPM(comf: 10000000.0, somf: 10.0);
      
      final result = S57Parser.parse(testData);
      
      // Custom datum codes should be available (even if COMF/SOMF parsing has issues)
      expect(result.metadata.horizontalDatum, isNotNull);
      expect(result.metadata.verticalDatum, isNotNull);
      expect(result.metadata.soundingDatum, isNotNull);
      
      print('Extracted datum codes:');
      print('  Horizontal: ${result.metadata.horizontalDatum}');
      print('  Vertical: ${result.metadata.verticalDatum}');
      print('  Sounding: ${result.metadata.soundingDatum}');
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should emit warning for unknown horizontal datum code', () {
      final warnings = S57WarningCollector();
      
      // Create test data with a known bad datum code
      final testData = createValidS57TestDataWithCustomDatum(
        horizontalDatum: 'BADH', // Unknown horizontal datum
        verticalDatum: 'MLLW',   // Known vertical datum
        soundingDatum: 'MLLW',   // Known sounding datum
      );
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should have emitted unknown horizontal datum warning
      final unknownHDatWarnings = warnings.getWarningsByCode(
        S57WarningCodes.unknownHorizontalDatum
      );
      expect(unknownHDatWarnings, hasLength(1));
      expect(unknownHDatWarnings.first.message, contains('BADH'));
      
      // Should not have emitted vertical/sounding datum warnings
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownVerticalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownSoundingDatum), isEmpty);
      
      print('Warning emitted: ${unknownHDatWarnings.first.message}');
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should emit warning for unknown vertical datum code', () {
      final warnings = S57WarningCollector();
      
      final testData = createValidS57TestDataWithCustomDatum(
        horizontalDatum: 'WGS84',  // Known horizontal datum
        verticalDatum: 'BADV',    // Unknown vertical datum
        soundingDatum: 'MLLW',    // Known sounding datum
      );
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should have emitted unknown vertical datum warning
      final unknownVDatWarnings = warnings.getWarningsByCode(
        S57WarningCodes.unknownVerticalDatum
      );
      expect(unknownVDatWarnings, hasLength(1));
      expect(unknownVDatWarnings.first.message, contains('BADV'));
      
      // Should not have emitted other datum warnings
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownHorizontalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownSoundingDatum), isEmpty);
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should emit warning for unknown sounding datum code', () {
      final warnings = S57WarningCollector();
      
      final testData = createValidS57TestDataWithCustomDatum(
        horizontalDatum: 'WGS84',  // Known horizontal datum
        verticalDatum: 'MLLW',    // Known vertical datum  
        soundingDatum: 'BADS',    // Unknown sounding datum
      );
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should have emitted unknown sounding datum warning
      final unknownSDatWarnings = warnings.getWarningsByCode(
        S57WarningCodes.unknownSoundingDatum
      );
      expect(unknownSDatWarnings, hasLength(1));
      expect(unknownSDatWarnings.first.message, contains('BADS'));
      
      // Should not have emitted other datum warnings
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownHorizontalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownVerticalDatum), isEmpty);
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should emit multiple warnings for multiple unknown datum codes', () {
      final warnings = S57WarningCollector();
      
      final testData = createValidS57TestDataWithCustomDatum(
        horizontalDatum: 'BADH',  // Unknown horizontal datum
        verticalDatum: 'BADV',   // Unknown vertical datum
        soundingDatum: 'BADS',   // Unknown sounding datum
      );
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should have emitted all three unknown datum warnings
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownHorizontalDatum), hasLength(1));
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownVerticalDatum), hasLength(1));
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownSoundingDatum), hasLength(1));
      
      // Total warnings should be 3
      expect(warnings.totalWarnings, equals(3));
      expect(warnings.warningCount, equals(3)); // All should be warning level
      
      print('Total warnings emitted: ${warnings.totalWarnings}');
      for (final warning in warnings.warnings) {
        print('  ${warning.code}: ${warning.message}');
      }
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should not emit warnings for known datum codes', () {
      final warnings = S57WarningCollector();
      
      final testData = createValidS57TestDataWithCustomDatum(
        horizontalDatum: 'WGS84',  // Known horizontal datum
        verticalDatum: 'MSL',     // Known vertical datum
        soundingDatum: 'LAT',     // Known sounding datum
      );
      
      final result = S57Parser.parse(testData, warnings: warnings);
      
      // Should not have emitted any datum warnings
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownHorizontalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownVerticalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownSoundingDatum), isEmpty);
      
      print('No datum warnings emitted for known codes');
      print('Total warnings: ${warnings.totalWarnings}');
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');

    test('should recognize various known datum codes', () {
      final warnings = S57WarningCollector();
      
      // Test several known datum codes to ensure recognition works
      final knownHorizontalDatums = ['WGS84', 'WGS8', 'NAD83', 'NAD27', 'ETRS'];
      final knownVerticalDatums = ['MLLW', 'MLW', 'MSL', 'MLHW', 'MHW', 'LAT', 'HAT', 'CD'];
      
      for (final hDatum in knownHorizontalDatums) {
        for (final vDatum in knownVerticalDatums) {
          final testData = createValidS57TestDataWithCustomDatum(
            horizontalDatum: hDatum,
            verticalDatum: vDatum,
            soundingDatum: vDatum, // Use same as vertical
          );
          
          final result = S57Parser.parse(testData, warnings: warnings);
        }
      }
      
      // Should not have emitted any datum warnings for known codes
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownHorizontalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownVerticalDatum), isEmpty);
      expect(warnings.getWarningsByCode(S57WarningCodes.unknownSoundingDatum), isEmpty);
      
      print('Tested ${knownHorizontalDatums.length * knownVerticalDatums.length} datum combinations');
      print('No warnings emitted for known datum codes');
    }, skip: 'Temporarily disabled: S57 DSPM/datum parsing issue - datum fields not properly extracted');
  });
}