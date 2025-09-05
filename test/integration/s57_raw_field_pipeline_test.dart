import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/iso8211_reader.dart';
import 'package:navtool/core/services/s57/iso8211_models.dart';
import 'package:navtool/core/services/s57/iso8211_coercion.dart';

void main() {
  group('S57 Raw Field Pipeline Integration', () {
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

    test('should parse records and identify candidate feature-bearing fields', () {
      final records = reader.readAll().toList();
      expect(records.length, greaterThan(0));

      // Create temporary adapter to count feature-bearing fields
      final featureCandidateCount = _countFeatureCandidateFields(records);
      
      // Should find feature candidates in the test data
      expect(featureCandidateCount, greaterThan(0));
      
      // Specifically should find FT01 and FT02 fields which are feature fields
      final featureFieldCount = _countSpecificFeatureFields(records);
      expect(featureFieldCount, equals(2)); // FT01 and FT02
    });

    test('should successfully extract and process field data through pipeline', () {
      final records = reader.readAll().toList();
      
      // Process all records through the raw field pipeline
      final processedFields = _processRawFieldPipeline(records);
      
      expect(processedFields, isNotEmpty);
      
      // Verify we can extract meaningful data from each field
      for (final fieldData in processedFields) {
        expect(fieldData['tag'], isNotNull);
        expect(fieldData['data'], isNotNull);
        expect(fieldData['coercedValue'], isNotNull);
      }
    });

    test('should handle DDR fields for metadata extraction', () {
      final records = reader.readAll().toList();
      final ddr = records.first;
      
      // Extract metadata fields from DDR
      final metadataFields = _extractMetadataFields(ddr);
      
      expect(metadataFields, isNotEmpty);
      expect(metadataFields.containsKey('DSID'), isTrue);
      expect(metadataFields.containsKey('DSPM'), isTrue);
      
      // Verify metadata field values
      final dsidValue = metadataFields['DSID'];
      final dspmValue = metadataFields['DSPM'];
      
      expect(dsidValue, equals('US5WA50M'));
      expect(dspmValue, equals('20241201'));
    });

    test('should identify and process feature records correctly', () {
      final records = reader.readAll().toList();
      
      // Skip DDR and process data records
      final dataRecords = records.skip(1).toList();
      
      for (final record in dataRecords) {
        final featureData = _extractFeatureData(record);
        
        // Each data record should have at least one feature-related field
        expect(featureData, isNotEmpty);
        
        // Verify feature data structure
        for (final feature in featureData) {
          expect(feature.containsKey('fieldTag'), isTrue);
          expect(feature.containsKey('coercedData'), isTrue);
          expect(feature.containsKey('isFeatureField'), isTrue);
          
          if (feature['isFeatureField'] == true) {
            expect(feature['coercedData'], isNotNull);
          }
        }
      }
    });

    test('should handle subfield splitting in feature fields', () {
      final records = reader.readAll().toList();
      
      // Find FT01 field which has subfield delimiters
      final dataRecord = records[1]; // First data record
      final ft01Data = dataRecord.getFieldData('FT01');
      
      expect(ft01Data, isNotNull);
      
      // Process through coercion pipeline
      final coercedData = splitAndCoerce(ft01Data!);
      
      expect(coercedData, isA<List>());
      expect(coercedData.length, greaterThan(1)); // Should split on delimiters
      
      // First part should be object type
      expect(coercedData.first, equals('BCNCAR'));
      
      // Subsequent parts should be coerced to appropriate types
      for (int i = 1; i < coercedData.length; i++) {
        expect(coercedData[i], isNotNull);
      }
    });

    test('should maintain data integrity through full pipeline', () {
      final records = reader.readAll().toList();
      
      // Process all records and verify no data loss
      int totalFieldsIn = 0;
      int totalFieldsOut = 0;
      
      for (final record in records) {
        totalFieldsIn += record.fieldTags.length;
        
        final processedFields = _processRecordFields(record);
        totalFieldsOut += processedFields.length;
      }
      
      // Should not lose any fields in processing
      expect(totalFieldsOut, equals(totalFieldsIn));
      
      // Should have reasonable number of fields
      expect(totalFieldsIn, greaterThanOrEqualTo(5)); // DSID, DSPM, FOID, FT01, FT02
    });

    test('should handle error conditions gracefully in pipeline', () {
      // Create a record with problematic field data
      final records = reader.readAll().toList();
      final normalRecord = records.first;
      
      // Process should not throw even with edge cases
      expect(() => _processRawFieldPipeline([normalRecord]), returnsNormally);
      
      // Process empty field data
      final emptyFieldResult = coerceFieldValue([]);
      expect(emptyFieldResult, equals(''));
      
      // Process invalid subfield data
      final invalidSubfieldResult = splitAndCoerce([0xFF, 0xFE, 0xFD]);
      expect(invalidSubfieldResult, isA<List>());
    });
  });
}

/// Count fields that are candidates for containing feature data
int _countFeatureCandidateFields(List<Iso8211Record> records) {
  int count = 0;
  
  for (final record in records) {
    for (final tag in record.fieldTags) {
      // Feature candidate fields typically start with 'F' or contain object codes
      if (tag.startsWith('F') || tag.startsWith('ATTR') || tag.startsWith('FOID')) {
        count++;
      }
    }
  }
  
  return count;
}

/// Count specific feature fields (FT01, FT02) that represent actual features
int _countSpecificFeatureFields(List<Iso8211Record> records) {
  int count = 0;
  
  for (final record in records) {
    if (record.hasField('FT01')) count++;
    if (record.hasField('FT02')) count++;
  }
  
  return count;
}

/// Process records through raw field pipeline
List<Map<String, dynamic>> _processRawFieldPipeline(List<Iso8211Record> records) {
  final processedFields = <Map<String, dynamic>>[];
  
  for (final record in records) {
    for (final tag in record.fieldTags) {
      final fieldData = record.getFieldData(tag);
      if (fieldData != null) {
        final coercedValue = coerceFieldValue(fieldData);
        
        processedFields.add({
          'tag': tag,
          'data': fieldData,
          'coercedValue': coercedValue,
          'recordLength': record.recordLength,
        });
      }
    }
  }
  
  return processedFields;
}

/// Extract metadata fields from DDR
Map<String, dynamic> _extractMetadataFields(Iso8211Record ddr) {
  final metadata = <String, dynamic>{};
  
  // Common S-57 metadata field tags
  final metadataFields = ['DSID', 'DSPM', 'DSSI', 'DSAC'];
  
  for (final tag in metadataFields) {
    if (ddr.hasField(tag)) {
      final fieldData = ddr.getFieldData(tag)!;
      metadata[tag] = coerceFieldValue(fieldData);
    }
  }
  
  return metadata;
}

/// Extract feature data from a record
List<Map<String, dynamic>> _extractFeatureData(Iso8211Record record) {
  final featureData = <Map<String, dynamic>>[];
  
  for (final tag in record.fieldTags) {
    final fieldData = record.getFieldData(tag)!;
    final coercedData = splitAndCoerce(fieldData);
    
    // Determine if this is likely a feature field
    final isFeatureField = tag.startsWith('F') && tag != 'FOID';
    
    featureData.add({
      'fieldTag': tag,
      'coercedData': coercedData,
      'isFeatureField': isFeatureField,
      'dataLength': fieldData.length,
    });
  }
  
  return featureData;
}

/// Process all fields in a record
List<Map<String, dynamic>> _processRecordFields(Iso8211Record record) {
  final processedFields = <Map<String, dynamic>>[];
  
  for (final tag in record.fieldTags) {
    final fieldData = record.getFieldData(tag);
    if (fieldData != null) {
      processedFields.add({
        'tag': tag,
        'length': fieldData.length,
        'processed': true,
      });
    }
  }
  
  return processedFields;
}