import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/iso8211_coercion.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('Iso8211 Subfield Split and Coercion', () {
    test('should coerce basic string values to appropriate types', () {
      expect(coerceValue('123'), equals(123)); // Integer
      expect(coerceValue('123.45'), equals(123.45)); // Double
      expect(coerceValue('text'), equals('text')); // String
      expect(
        coerceValue('  whitespace  '),
        equals('whitespace'),
      ); // Trimmed string
      expect(coerceValue(''), equals('')); // Empty string
    });

    test('should handle edge cases in value coercion', () {
      expect(coerceValue('0'), equals(0)); // Zero integer
      expect(coerceValue('0.0'), equals(0.0)); // Zero double
      expect(coerceValue('-123'), equals(-123)); // Negative integer
      expect(coerceValue('-45.67'), equals(-45.67)); // Negative double
      expect(coerceValue('1.23e-4'), equals(1.23e-4)); // Scientific notation
    });

    test('should split and coerce subfield delimited data', () {
      // Create test data with subfield delimiters (0x1F)
      final testString = 'BCNCAR\u001f02\u001f150\u001f47.6789';
      final testBytes = ascii.encode(testString);

      final result = splitAndCoerce(testBytes);

      expect(result.length, equals(4));
      expect(result[0], equals('BCNCAR')); // String
      expect(result[1], equals(2)); // Integer
      expect(result[2], equals(150)); // Integer
      expect(result[3], equals(47.6789)); // Double
    });

    test('should handle single field without delimiters', () {
      final testBytes = ascii.encode('SOUNDG');
      final result = splitAndCoerce(testBytes);

      expect(result.length, equals(1));
      expect(result[0], equals('SOUNDG'));
    });

    test('should coerce field values without splitting', () {
      final textBytes = ascii.encode('US5WA50M');
      final numberBytes = ascii.encode('12345');
      final floatBytes = ascii.encode('123.456');

      expect(coerceFieldValue(textBytes), equals('US5WA50M'));
      expect(coerceFieldValue(numberBytes), equals(12345));
      expect(coerceFieldValue(floatBytes), equals(123.456));
      expect(coerceFieldValue([]), equals(''));
    });

    test('should extract structured values with field names', () {
      final testString = 'DEPARE\u001f5.2\u001f10.8\u001f15.0';
      final testBytes = ascii.encode(testString);
      final fieldNames = ['objectType', 'minDepth', 'maxDepth', 'safetyDepth'];

      final result = extractStructuredValues(testBytes, fieldNames);

      expect(result['objectType'], equals('DEPARE'));
      expect(result['minDepth'], equals(5.2));
      expect(result['maxDepth'], equals(10.8));
      expect(result['safetyDepth'], equals(15.0));
    });

    test('should handle mismatched field names and values', () {
      final testString = 'A\u001fB';
      final testBytes = ascii.encode(testString);
      final tooManyNames = ['field1', 'field2', 'field3', 'field4'];
      final tooFewNames = ['field1'];

      final resultTooMany = extractStructuredValues(testBytes, tooManyNames);
      expect(resultTooMany.length, equals(2)); // Only 2 values available
      expect(resultTooMany['field1'], equals('A'));
      expect(resultTooMany['field2'], equals('B'));
      expect(resultTooMany.containsKey('field3'), isFalse);

      final resultTooFew = extractStructuredValues(testBytes, tooFewNames);
      expect(resultTooFew.length, equals(1)); // Only 1 name provided
      expect(resultTooFew['field1'], equals('A'));
    });

    test('should handle empty and whitespace-only subfields', () {
      final testString = 'VALUE1\u001f\u001f  \u001fVALUE2';
      final testBytes = ascii.encode(testString);

      final result = splitAndCoerce(testBytes);

      expect(result.length, equals(4));
      expect(result[0], equals('VALUE1'));
      expect(result[1], equals('')); // Empty subfield
      expect(result[2], equals('')); // Whitespace-only becomes empty after trim
      expect(result[3], equals('VALUE2'));
    });
  });

  group('S57FieldCoercion Specialized Methods', () {
    test('should coerce coordinate values correctly', () {
      // Test coordinate as 32-bit signed integer scaled by 10^7
      final coordBytes = Uint8List(4);
      final byteData = ByteData.sublistView(coordBytes);
      byteData.setInt32(
        0,
        476789123,
        Endian.little,
      ); // Represents 47.6789123 degrees

      final result = S57FieldCoercion.coerceCoordinate(coordBytes.toList());
      expect(result, isNotNull);
      expect(result!, closeTo(47.6789123, 0.0000001));
    });

    test('should coerce depth values correctly', () {
      // Test depth as 32-bit signed integer in centimeters
      final depthBytes = Uint8List(4);
      final byteData = ByteData.sublistView(depthBytes);
      byteData.setInt32(0, 1523, Endian.little); // 15.23 meters

      final result = S57FieldCoercion.coerceDepth(depthBytes.toList());
      expect(result, isNotNull);
      expect(result!, equals(15.23));
    });

    test('should coerce record IDs correctly', () {
      // Test various record ID formats
      final id1Bytes = Uint8List(4);
      final byteData1 = ByteData.sublistView(id1Bytes);
      byteData1.setUint32(0, 12345, Endian.little);

      final id2Bytes = Uint8List(2);
      final byteData2 = ByteData.sublistView(id2Bytes);
      byteData2.setUint16(0, 999, Endian.little);

      final id3Bytes = [42]; // Single byte
      final id4Bytes = ascii.encode('789'); // String format

      expect(S57FieldCoercion.coerceRecordId(id1Bytes.toList()), equals(12345));
      expect(S57FieldCoercion.coerceRecordId(id2Bytes.toList()), equals(999));
      expect(S57FieldCoercion.coerceRecordId(id3Bytes), equals(42));
      expect(S57FieldCoercion.coerceRecordId(id4Bytes), equals(789));
      expect(S57FieldCoercion.coerceRecordId([]), isNull);
    });

    test('should coerce attribute values with appropriate handling', () {
      // Single byte value
      final singleByte = [5];
      expect(S57FieldCoercion.coerceAttributeValue(singleByte), equals(5));

      // 2-byte unsigned short
      final twoBytes = Uint8List(2);
      final byteData2 = ByteData.sublistView(twoBytes);
      byteData2.setUint16(0, 1000, Endian.little);
      expect(
        S57FieldCoercion.coerceAttributeValue(twoBytes.toList()),
        equals(1000),
      );

      // 4-byte signed integer
      final fourBytes = Uint8List(4);
      final byteData4 = ByteData.sublistView(fourBytes);
      byteData4.setInt32(0, -12345, Endian.little);
      expect(
        S57FieldCoercion.coerceAttributeValue(fourBytes.toList()),
        equals(-12345),
      );

      // Complex field with subfield delimiters
      final complexBytes = ascii.encode('ATTR1\u001f123\u001f45.6');
      final complexResult = S57FieldCoercion.coerceAttributeValue(complexBytes);
      expect(complexResult, isA<List>());
      final complexList = complexResult as List;
      expect(complexList.length, equals(3));
      expect(complexList[0], equals('ATTR1'));
      expect(complexList[1], equals(123));
      expect(complexList[2], equals(45.6));
    });

    test('should handle invalid or corrupted data gracefully', () {
      // Too short for coordinate
      expect(S57FieldCoercion.coerceCoordinate([1, 2]), isNull);

      // Too short for depth
      expect(S57FieldCoercion.coerceDepth([1]), isNull);

      // Empty data
      expect(S57FieldCoercion.coerceAttributeValue([]), equals(''));
    });

    test('should use correct scale factors', () {
      // Test custom scale for coordinate
      final coordBytes = Uint8List(4);
      final byteData = ByteData.sublistView(coordBytes);
      byteData.setInt32(0, 476789, Endian.little);

      final defaultScale = S57FieldCoercion.coerceCoordinate(
        coordBytes.toList(),
      );
      final customScale = S57FieldCoercion.coerceCoordinate(
        coordBytes.toList(),
        scale: 1000.0,
      );

      expect(
        defaultScale!,
        closeTo(0.0476789, 0.0000001),
      ); // Default scale 10^7
      expect(customScale!, closeTo(476.789, 0.001)); // Custom scale 10^3
    });
  });
}
