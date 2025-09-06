import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/iso8211_reader.dart';
import 'package:navtool/core/services/s57/iso8211_models.dart';

void main() {
  group('Iso8211Reader Valid Records', () {
    late List<int> testData;
    late Iso8211Reader reader;

    setUpAll(() async {
      // Load the binary test fixture
      final file = File('test/fixtures/iso8211/sample_enc.bin');
      testData = await file.readAsBytes();
    });

    setUp(() {
      reader = Iso8211Reader(testData);
    });

    test('should parse all valid records from fixture', () {
      final records = reader.readAll().toList();

      // Should get 3 valid records (DDR + 2 data records), malformed record skipped
      expect(records.length, equals(3));
      expect(
        reader.warnings.length,
        equals(1),
      ); // One warning for malformed record
    });

    test('should parse DDR record correctly', () {
      final records = reader.readAll().toList();
      final ddr = records.first;

      expect(ddr.recordLength, equals(72));
      expect(ddr.baseAddress, equals(53));
      expect(ddr.fieldTags, containsAll(['DSID', 'DSPM']));

      // Verify DSID field contains chart ID
      final dsidData = ddr.getFieldData('DSID');
      expect(dsidData, isNotNull);
      expect(String.fromCharCodes(dsidData!), equals('US5WA50M'));

      // Verify DSPM field contains date
      final dspmData = ddr.getFieldData('DSPM');
      expect(dspmData, isNotNull);
      expect(String.fromCharCodes(dspmData!), equals('20241201'));
    });

    test('should parse first data record correctly', () {
      final records = reader.readAll().toList();
      final dataRecordA = records[1];

      expect(dataRecordA.recordLength, equals(71));
      expect(dataRecordA.fieldTags, containsAll(['FOID', 'FT01']));

      // Verify FOID field
      final foidData = dataRecordA.getFieldData('FOID');
      expect(foidData, isNotNull);
      expect(String.fromCharCodes(foidData!), equals('001'));

      // Verify FT01 field with subfield delimiters
      final ft01Data = dataRecordA.getFieldData('FT01');
      expect(ft01Data, isNotNull);
      final ft01String = String.fromCharCodes(ft01Data!);
      expect(ft01String, contains('BCNCAR'));
      expect(ft01String, contains('\u001f')); // subfield delimiter
    });

    test('should parse second data record correctly', () {
      final records = reader.readAll().toList();
      final dataRecordB = records[2];

      expect(dataRecordB.recordLength, equals(55));
      expect(dataRecordB.fieldTags, contains('FT02'));

      // Verify FT02 field
      final ft02Data = dataRecordB.getFieldData('FT02');
      expect(ft02Data, isNotNull);
      final ft02String = String.fromCharCodes(ft02Data!);
      expect(ft02String, contains('SOUNDG'));
      expect(ft02String, contains('150'));
      expect(ft02String, contains('250'));
    });

    test('should provide directory entry information', () {
      final records = reader.readAll().toList();
      final ddr = records.first;

      expect(ddr.directory.length, equals(2));

      final dsidEntry = ddr.directory.firstWhere((e) => e.tag == 'DSID');
      expect(dsidEntry.length, equals(8));
      expect(dsidEntry.position, equals(0));

      final dspmEntry = ddr.directory.firstWhere((e) => e.tag == 'DSPM');
      expect(dspmEntry.length, equals(8));
      expect(dspmEntry.position, equals(9)); // After DSID + terminator
    });

    test('should handle hasField and getFieldData methods correctly', () {
      final records = reader.readAll().toList();
      final ddr = records.first;

      expect(ddr.hasField('DSID'), isTrue);
      expect(ddr.hasField('DSPM'), isTrue);
      expect(ddr.hasField('NONEXISTENT'), isFalse);

      expect(ddr.getFieldData('DSID'), isNotNull);
      expect(ddr.getFieldData('NONEXISTENT'), isNull);
    });
  });
}
