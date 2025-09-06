import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/iso8211_reader.dart';
import 'package:navtool/core/services/s57/iso8211_models.dart';

void main() {
  group('Iso8211Reader Malformed Records', () {
    late List<int> testData;
    late Iso8211Reader reader;

    setUpAll(() async {
      // Load the binary test fixture which contains a malformed record
      final file = File('test/fixtures/iso8211/sample_enc.bin');
      testData = await file.readAsBytes();
    });

    setUp(() {
      reader = Iso8211Reader(testData);
    });

    test('should skip malformed record and generate warning', () {
      final records = reader.readAll().toList();

      // Should parse 3 valid records and skip 1 malformed
      expect(records.length, equals(3));

      // Should have exactly one warning for the malformed record
      expect(reader.warnings.length, equals(1));
      final warning = reader.warnings.first;
      expect(warning.code, equals(Iso8211WarningCodes.badBaseAddress));
      expect(warning.message, contains('Invalid base address'));
    });

    test('should continue parsing after malformed record', () {
      final records = reader.readAll().toList();

      // All three valid records should be successfully parsed
      expect(records.length, equals(3));

      // First record is DDR
      expect(records[0].fieldTags, containsAll(['DSID', 'DSPM']));

      // Second record is first data record
      expect(records[1].fieldTags, containsAll(['FOID', 'FT01']));

      // Third record is second data record
      expect(records[2].fieldTags, contains('FT02'));
    });

    test('should handle empty data gracefully', () {
      final emptyReader = Iso8211Reader([]);
      final records = emptyReader.readAll().toList();

      expect(records, isEmpty);
      expect(emptyReader.warnings, isEmpty);
    });

    test('should handle truncated data gracefully', () {
      // Take only first 30 bytes (incomplete record)
      final truncatedData = testData.take(30).toList();
      final truncatedReader = Iso8211Reader(truncatedData);

      expect(
        () => truncatedReader.readAll().toList(),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle malformed leader gracefully for non-DDR records', () {
      // Create test data with valid DDR followed by malformed data
      final validDDR = testData.take(72).toList(); // First record only
      final malformedData = [
        ...validDDR,
        // Add completely invalid data that looks like a record start
        ...List.generate(50, (i) => 0xFF),
      ];

      final malformedReader = Iso8211Reader(malformedData);
      final records = malformedReader.readAll().toList();

      // Should parse the valid DDR and skip the malformed data
      expect(records.length, equals(1));
      expect(records.first.fieldTags, containsAll(['DSID', 'DSPM']));

      // Should have warnings about the malformed data
      expect(malformedReader.warnings, isNotEmpty);
    });

    test('should validate warning structure', () {
      reader.readAll().toList(); // Process all records

      final warnings = reader.warnings;
      expect(warnings.length, equals(1));

      final warning = warnings.first;
      expect(warning.code, isA<String>());
      expect(warning.message, isA<String>());
      expect(warning.code, isNotEmpty);
      expect(warning.message, isNotEmpty);
    });

    test('should use proper warning codes', () {
      reader.readAll().toList();

      final warning = reader.warnings.first;
      expect(warning.code, equals(Iso8211WarningCodes.badBaseAddress));

      // Verify warning codes are properly defined
      expect(
        Iso8211WarningCodes.leaderLengthMismatch,
        equals('LEADER_LEN_MISMATCH'),
      );
      expect(Iso8211WarningCodes.badBaseAddress, equals('BAD_BASE_ADDR'));
      expect(Iso8211WarningCodes.directoryTruncated, equals('DIR_TRUNCATED'));
      expect(Iso8211WarningCodes.fieldBounds, equals('FIELD_BOUNDS'));
      expect(Iso8211WarningCodes.subfieldParse, equals('SUBFIELD_PARSE'));
    });
  });
}
