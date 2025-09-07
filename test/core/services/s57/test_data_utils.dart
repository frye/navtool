/// Shared test utilities for S57 testing
/// 
/// Provides common test data creation functions for Issue 20.8 tests

import 'dart:typed_data';
import 'dart:convert';

/// Create valid S-57 test data that can be parsed successfully
List<int> createValidS57TestData() {
  // Create a minimal but valid S-57 ISO 8211 record structure
  final data = <int>[];

  // Record leader (24 bytes) - Enhanced for proper parsing
  data.addAll('01582'.codeUnits); // Record length (01582 bytes)
  data.addAll('3'.codeUnits); // Interchange level
  data.addAll('L'.codeUnits); // Leader identifier
  data.addAll('E'.codeUnits); // Inline code extension
  data.addAll('1'.codeUnits); // Version number
  data.addAll(' '.codeUnits); // Application indicator
  data.addAll('09'.codeUnits); // Field control length
  data.addAll('00201'.codeUnits); // Base address of data
  data.addAll(' ! '.codeUnits); // Extended character set
  data.addAll('4'.codeUnits); // Size of field length (4 bytes)
  data.addAll('4'.codeUnits); // Size of field position (4 bytes)
  data.addAll('0'.codeUnits); // Reserved
  data.addAll('4'.codeUnits); // Size of field tag (4 bytes)

  // Directory entries - Enhanced with proper S-57 fields
  data.addAll('DSID'.codeUnits); // Data Set Identification
  data.addAll('0165'.codeUnits); // Field length
  data.addAll('0000'.codeUnits); // Field position

  data.addAll('FRID'.codeUnits); // Feature Record Identifier
  data.addAll('0048'.codeUnits); // Field length
  data.addAll('0165'.codeUnits); // Field position

  data.addAll('FOID'.codeUnits); // Feature Object Identifier
  data.addAll('0024'.codeUnits); // Field length
  data.addAll('0213'.codeUnits); // Field position

  data.addAll('ATTF'.codeUnits); // Feature Attributes
  data.addAll('0036'.codeUnits); // Field length
  data.addAll('0237'.codeUnits); // Field position

  data.addAll('SG2D'.codeUnits); // 2D Coordinate
  data.addAll('0024'.codeUnits); // Field length
  data.addAll('0273'.codeUnits); // Field position

  // Field terminator
  data.add(0x1e);

  // Pad to reach base address (position 201)
  while (data.length < 201) {
    data.add(0x20); // Space padding
  }

  // DSID field data (Data Set Identification)
  data.addAll('NOAA'.codeUnits);
  data.addAll((' ' * (165 - 4)).codeUnits);

  // FRID field data (Feature Record Identifier) - Enhanced
  data.add(100); // RCNM (Record name) - Feature record
  addBinaryInt(data, 12345, 4); // RCID (Record ID)
  data.add(1); // PRIM (Primitive)
  data.add(1); // GRUP (Group)
  addBinaryInt(data, 58, 2); // OBJL (Object label) - BOYLAT code
  addBinaryInt(data, 1, 2); // RVER (Record version)
  data.add(1); // RUIN (Record update instruction)
  // Pad to exactly 48 bytes
  while (data.length < 201 + 165 + 48) {
    data.add(0x20);
  }

  // FOID field data (Feature Object Identifier) - Enhanced
  addBinaryInt(data, 550, 2); // AGEN (Agency code) - NOAA
  addBinaryInt(data, 98765, 4); // FIDN (Feature ID)
  addBinaryInt(data, 1, 2); // FIDS (Feature subdivision)
  // Pad to exactly 24 bytes
  while (data.length < 201 + 165 + 48 + 24) {
    data.add(0x20);
  }

  // ATTF field data (Attributes) - Enhanced with S-57 attributes
  addBinaryInt(data, 84, 2); // COLOUR attribute code
  addBinaryInt(data, 2, 4); // Red color
  addBinaryInt(data, 85, 2); // CATBOY attribute code
  addBinaryInt(data, 2, 4); // Port hand buoy
  addBinaryInt(data, 86, 2); // COLPAT attribute code
  addBinaryInt(data, 1, 4); // Horizontal stripes
  // Pad to exactly 36 bytes
  while (data.length < 201 + 165 + 48 + 24 + 36) {
    data.add(0x20);
  }

  // SG2D field data (2D Coordinates) - Enhanced with realistic Elliott Bay coords
  final lat = (47.64 * 10000000).round(); // Convert to S-57 coordinate units
  final lon = ((-122.34) * 10000000).round();
  addBinaryInt(data, lon, 4); // X coordinate (longitude)
  addBinaryInt(data, lat, 4); // Y coordinate (latitude)
  addBinaryInt(data, lon + 1000, 4); // Second point X
  addBinaryInt(data, lat + 1000, 4); // Second point Y
  addBinaryInt(data, lon + 2000, 4); // Third point X
  addBinaryInt(data, lat + 2000, 4); // Third point Y

  // Pad to declared record length
  while (data.length < 1582) {
    data.add(0x20);
  }

  return data;
}

/// Helper to add binary integer to data list
void addBinaryInt(List<int> data, int value, int bytes) {
  final byteData = ByteData(8); // Use max size to avoid overflow

  switch (bytes) {
    case 1:
      byteData.setUint8(0, value & 0xFF);
      break;
    case 2:
      byteData.setUint16(0, value & 0xFFFF, Endian.little);
      break;
    case 4:
      byteData.setUint32(0, value & 0xFFFFFFFF, Endian.little);
      break;
    default:
      throw ArgumentError('Unsupported byte size: $bytes');
  }

  for (int i = 0; i < bytes; i++) {
    data.add(byteData.getUint8(i));
  }
}

/// Helper to add binary double to data list
void addBinaryDouble(List<int> data, double value) {
  final byteData = ByteData(4);
  byteData.setFloat32(0, value, Endian.little);
  
  for (int i = 0; i < 4; i++) {
    data.add(byteData.getUint8(i));
  }
}

/// Create valid S-57 test data with custom DSPM fields containing COMF/SOMF
List<int> createValidS57TestDataWithDSPM({double? comf, double? somf}) {
  // Create a minimal but valid S-57 ISO 8211 record structure
  final data = <int>[];

  // Record leader (24 bytes) - Enhanced for proper parsing
  data.addAll('01594'.codeUnits); // Record length (01594 bytes)
  data.addAll('3'.codeUnits); // Interchange level
  data.addAll('L'.codeUnits); // Leader identifier
  data.addAll('E'.codeUnits); // Inline code extension
  data.addAll('1'.codeUnits); // Version number
  data.addAll(' '.codeUnits); // Application indicator
  data.addAll('09'.codeUnits); // Field control length
  data.addAll('00245'.codeUnits); // Base address - calculated as leader(24) + directory + terminator
  data.addAll(' ! '.codeUnits); // Extended character set
  data.addAll('4'.codeUnits); // Size of field length (4 bytes)
  data.addAll('4'.codeUnits); // Size of field position (4 bytes)
  data.addAll('0'.codeUnits); // Reserved
  data.addAll('4'.codeUnits); // Size of field tag (4 bytes)

  // Directory entries - Enhanced with DSPM field
  data.addAll('DSID'.codeUnits); // Data Set Identification
  data.addAll('0165'.codeUnits); // Field length
  data.addAll('0000'.codeUnits); // Field position

  data.addAll('DSPM'.codeUnits); // Dataset Parameters - NEW!
  data.addAll('0040'.codeUnits); // Field length (40 bytes for DSPM data)
  data.addAll('0165'.codeUnits); // Field position (after DSID)

  data.addAll('FRID'.codeUnits); // Feature Record Identifier
  data.addAll('0048'.codeUnits); // Field length
  data.addAll('0205'.codeUnits); // Updated field position (165+40=205)

  data.addAll('FOID'.codeUnits); // Feature Object Identifier
  data.addAll('0024'.codeUnits); // Field length
  data.addAll('0253'.codeUnits); // Updated field position (205+48=253)

  data.addAll('ATTF'.codeUnits); // Feature Attributes
  data.addAll('0036'.codeUnits); // Field length
  data.addAll('0277'.codeUnits); // Updated field position (253+24=277)

  data.addAll('SG2D'.codeUnits); // 2D Coordinate
  data.addAll('0024'.codeUnits); // Field length
  data.addAll('0313'.codeUnits); // Updated field position (277+36=313)

  // Field terminator
  data.add(0x1e);

  // Pad to reach base address (position 245)
  while (data.length < 245) {
    data.add(0x20); // Space padding
  }

  // DSID field data (Data Set Identification) - starts at 245+0=245
  data.addAll('NOAA'.codeUnits);
  // Pad DSID to exactly 165 bytes
  while (data.length < 245 + 165) {
    data.add(0x20);
  }

  // DSPM field data (Dataset Parameters) - starts at position 245+165=410
  final dspmStartLength = data.length;
  
  data.add(10); // RCNM (Record name) - Dataset parameter record (1 byte)
  addBinaryInt(data, 1, 4); // RCID (Record ID) (4 bytes)
  
  // Add HDAT (Horizontal Datum) - exactly 4 bytes
  final hdatBytes = ascii.encode('WGS8'); // Use 4-byte representation 
  data.addAll(hdatBytes);
  
  // Add VDAT (Vertical Datum) - exactly 4 bytes  
  final vdatBytes = ascii.encode('MLLW'); // Exactly 4 bytes
  data.addAll(vdatBytes);
  
  // Add SDAT (Sounding Datum) - exactly 4 bytes
  final sdatBytes = ascii.encode('MLLW'); // Exactly 4 bytes  
  data.addAll(sdatBytes);
  
  // Add CSCL (Compilation Scale) - 4 bytes
  addBinaryInt(data, 50000, 4); // Typical chart scale
  
  // Add COMF (Coordinate Multiplication Factor) - 4 bytes
  addBinaryDouble(data, comf ?? 10000000.0);
  
  // Add SOMF (Sounding Multiplication Factor) - 4 bytes
  addBinaryDouble(data, somf ?? 10.0);
  
  // Current DSPM data length should be: 1+4+4+4+4+4+4+4 = 29 bytes
  // Pad remaining bytes to reach exactly 40 bytes total
  final dspmCurrentLength = data.length - dspmStartLength;
  final dspmPaddingNeeded = 40 - dspmCurrentLength;
  for (int i = 0; i < dspmPaddingNeeded; i++) {
    data.add(0x20); // Space padding
  }

  // FRID field data (Feature Record Identifier) - starts at 245+205=450
  data.add(100); // RCNM (Record name) - Feature record
  addBinaryInt(data, 12345, 4); // RCID (Record ID)
  data.add(1); // PRIM (Primitive)
  data.add(1); // GRUP (Group)
  addBinaryInt(data, 58, 2); // OBJL (Object label) - BOYLAT code
  addBinaryInt(data, 1, 2); // RVER (Record version)
  data.add(1); // RUIN (Record update instruction)
  // Pad to exactly 48 bytes
  while (data.length < 245 + 165 + 40 + 48) {
    data.add(0x20);
  }

  // FOID field data (Feature Object Identifier) - starts at 245+253=498
  addBinaryInt(data, 550, 2); // AGEN (Agency code) - NOAA
  addBinaryInt(data, 98765, 4); // FIDN (Feature ID)
  addBinaryInt(data, 1, 2); // FIDS (Feature subdivision)
  // Pad to exactly 24 bytes
  while (data.length < 245 + 165 + 40 + 48 + 24) {
    data.add(0x20);
  }

  // ATTF field data (Attributes) - starts at 245+277=522
  addBinaryInt(data, 84, 2); // COLOUR attribute code
  addBinaryInt(data, 2, 4); // Red color
  addBinaryInt(data, 85, 2); // CATBOY attribute code
  addBinaryInt(data, 2, 4); // Port hand buoy
  addBinaryInt(data, 86, 2); // COLPAT attribute code
  addBinaryInt(data, 1, 4); // Horizontal stripes
  // Pad to exactly 36 bytes
  while (data.length < 245 + 165 + 40 + 48 + 24 + 36) {
    data.add(0x20);
  }

  // SG2D field data (2D Coordinates) - starts at 245+313=558
  final customComf = comf ?? 10000000.0;
  final lat = (47.64 * customComf).round(); // Convert to S-57 coordinate units using custom COMF
  final lon = ((-122.34) * customComf).round();
  addBinaryInt(data, lon, 4); // X coordinate (longitude)
  addBinaryInt(data, lat, 4); // Y coordinate (latitude)
  addBinaryInt(data, lon + (1000 * customComf / 10000000).round(), 4); // Second point X
  addBinaryInt(data, lat + (1000 * customComf / 10000000).round(), 4); // Second point Y
  addBinaryInt(data, lon + (2000 * customComf / 10000000).round(), 4); // Third point X
  addBinaryInt(data, lat + (2000 * customComf / 10000000).round(), 4); // Third point Y

  // Pad to declared record length (1594 = 245 base + 1349 data)
  while (data.length < 1594) {
    data.add(0x20);
  }

  return data;
}