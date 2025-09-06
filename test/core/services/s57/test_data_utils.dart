/// Shared test utilities for S57 testing
/// 
/// Provides common test data creation functions for Issue 20.8 tests

import 'dart:typed_data';

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