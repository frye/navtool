/// Malformed S-57 record fixture builder for Issue 20.x
///
/// Creates targeted S-57 ISO 8211 record corruptions for testing parser
/// resilience. Each method generates specific failure classes to validate
/// error handling and warning generation.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

/// Builder for creating malformed S-57 ISO 8211 records for testing
///
/// Provides methods to generate specific corruption patterns that exercise
/// different parser error paths and warning generation logic.
class MalformedFixtureBuilder {
  static const int _leaderSize = 24;
  static const int _fieldTerminator = 0x1e;
  static const int _recordTerminator = 0x1d;
  static const int _subfieldDelimiter = 0x1f;

  /// Create truncated leader (failure class 1)
  /// 
  /// Generates a record with leader shorter than required 24 bytes
  static List<int> createTruncatedLeader({int truncateAt = 15}) {
    if (truncateAt >= _leaderSize) {
      throw ArgumentError('truncateAt must be less than $_leaderSize');
    }
    
    // Start with a valid leader structure
    final leader = BytesBuilder();
    leader.add(ascii.encode('00100')); // record length (5 bytes)
    leader.add(ascii.encode('3'));     // interchange level (1 byte)  
    leader.add(ascii.encode('D'));     // data record (1 byte)
    leader.add(ascii.encode('0'));     // field control length (1 byte)
    leader.add(ascii.encode('00030')); // base address (5 bytes)
    leader.add(ascii.encode('   '));   // extended char set (3 bytes)
    leader.add(ascii.encode('4'));     // size of field length (1 byte)
    leader.add(ascii.encode('3'));     // size of field position (1 byte)
    leader.add(ascii.encode(' '));     // reserved (1 byte)
    leader.add(ascii.encode('4'));     // size of field tag (1 byte)
    leader.add(ascii.encode('    '));  // remaining reserved (4 bytes)
    
    // Truncate at specified position
    final leaderBytes = leader.toBytes();
    return leaderBytes.sublist(0, math.min(truncateAt, leaderBytes.length));
  }

  /// Create directory entry length mismatch (failure class 2)
  ///
  /// Generates a record where directory entry declares different field length
  /// than actual field data provides
  static List<int> createDirectoryLengthMismatch() {
    final buffer = BytesBuilder();
    
    // Create leader that points to directory
    final leader = _createValidLeader(
      recordLength: 100,
      baseAddress: 35, // After 24-byte leader + 11-byte directory
    );
    buffer.add(leader);
    
    // Directory with deliberately wrong field length
    buffer.add(ascii.encode('DSID')); // Field tag (4 bytes)
    buffer.add(ascii.encode('0020')); // Wrong length: claims 20 bytes (4 bytes)  
    buffer.add(ascii.encode('000')); // Position (3 bytes)
    buffer.add([_fieldTerminator]); // Directory terminator (1 byte)
    
    // Actual field data is only 10 bytes, not 20 as declared
    buffer.add(ascii.encode('NOAA12345')); // 10 bytes actual data
    buffer.add([_fieldTerminator]); // Field terminator
    
    // Pad to declared record length
    while (buffer.length < 99) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create missing field terminator (failure class 3)
  ///
  /// Generates a record missing 0x1E field terminator before record terminator
  static List<int> createMissingFieldTerminator() {
    final buffer = BytesBuilder();
    
    // Create valid leader
    final leader = _createValidLeader(
      recordLength: 60,
      baseAddress: 35,
    );
    buffer.add(leader);
    
    // Directory
    buffer.add(ascii.encode('DSID')); // Field tag
    buffer.add(ascii.encode('0010')); // Field length  
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]); // Directory terminator
    
    // Field data WITHOUT field terminator
    buffer.add(ascii.encode('NOAATEST12')); // 10 bytes
    // Deliberately omit field terminator here
    
    // Pad and add record terminator  
    while (buffer.length < 59) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create unexpected subfield delimiter placement (failure class 4)
  ///
  /// Generates a record with 0x1F subfield delimiter at start or doubled
  static List<int> createUnexpectedSubfieldDelimiter({bool atStart = true}) {
    final buffer = BytesBuilder();
    
    final leader = _createValidLeader(
      recordLength: 70,
      baseAddress: 35,
    );
    buffer.add(leader);
    
    // Directory
    buffer.add(ascii.encode('FRID')); // Feature record identifier field
    buffer.add(ascii.encode('0015')); // Field length
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]);
    
    // Field data with malformed subfield delimiters
    if (atStart) {
      // Start with unexpected subfield delimiter
      buffer.add([_subfieldDelimiter]); // Unexpected at start
      buffer.add([100]); // RCNM 
      buffer.add(ascii.encode('12345')); // RCID
      buffer.add([1]); // PRIM
    } else {
      // Double subfield delimiter  
      buffer.add([100]); // RCNM
      buffer.add([_subfieldDelimiter, _subfieldDelimiter]); // Double delimiter
      buffer.add(ascii.encode('12345')); // RCID
      buffer.add([1]); // PRIM
    }
    
    buffer.add([_fieldTerminator]);
    
    // Pad to declared length
    while (buffer.length < 69) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create dangling FSPT pointer (failure class 5)
  ///
  /// Generates a record with FSPT pointing to non-existent VRID
  static List<int> createDanglingFSPTPointer() {
    final buffer = BytesBuilder();
    
    final leader = _createValidLeader(
      recordLength: 80,
      baseAddress: 35,
    );
    buffer.add(leader);
    
    // Directory for FSPT field
    buffer.add(ascii.encode('FSPT')); // Feature to spatial pointer
    buffer.add(ascii.encode('0020')); // Field length
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]);
    
    // FSPT field data pointing to non-existent record
    buffer.add([110]); // RCNM - Spatial record name
    _addBinaryInt(buffer, 99999, 4); // RCID - Non-existent record ID
    buffer.add([1]); // ORNT - Orientation  
    buffer.add([1]); // USAG - Usage
    buffer.add([255]); // MASK - All bits set (invalid pattern)
    
    buffer.add([_fieldTerminator]);
    
    // Pad to declared length
    while (buffer.length < 79) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create VRPT count inconsistent with coordinate data (failure class 6)
  ///
  /// Generates a record where VRPT claims N coordinates but provides different count
  static List<int> createInconsistentVRPTCount() {
    final buffer = BytesBuilder();
    
    final leader = _createValidLeader(
      recordLength: 100,
      baseAddress: 35,
    );
    buffer.add(leader);
    
    // Directory for VRPT field
    buffer.add(ascii.encode('VRPT')); // Vector record to point
    buffer.add(ascii.encode('0030')); // Field length
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]);
    
    // VRPT claims 5 coordinate pairs but only provides 3
    _addBinaryInt(buffer, 5, 2); // Claims 5 coordinate pairs
    
    // But only provide 3 pairs (6 coordinates total)
    _addBinaryInt(buffer, 1000, 4); // X1
    _addBinaryInt(buffer, 2000, 4); // Y1
    _addBinaryInt(buffer, 1100, 4); // X2  
    _addBinaryInt(buffer, 2100, 4); // Y2
    _addBinaryInt(buffer, 1200, 4); // X3
    _addBinaryInt(buffer, 2200, 4); // Y3
    // Missing X4,Y4 and X5,Y5
    
    buffer.add([_fieldTerminator]);
    
    // Pad to declared length
    while (buffer.length < 99) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create empty DSPM/DSID fields (failure class 7)
  ///
  /// Generates a record with zero-length required field data
  static List<int> createEmptyRequiredFields({bool emptyDSID = true}) {
    final buffer = BytesBuilder();
    
    final leader = _createValidLeader(
      recordLength: 40,
      baseAddress: 24 + 12, // leader + directory
    );
    buffer.add(leader);
    
    // Directory
    final fieldTag = emptyDSID ? 'DSID' : 'DSPM';
    buffer.add(ascii.encode(fieldTag));
    buffer.add(ascii.encode('0001')); // Length of 1 for just the field terminator
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]);
    
    // Field data is just the field terminator (effectively empty)
    buffer.add([_fieldTerminator]);
    
    // Pad to declared length
    while (buffer.length < 39) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create invalid RUIN operation (failure class 8)
  ///
  /// Generates a record with unsupported RUIN (Record Update Instruction) code
  static List<int> createInvalidRUINOperation() {
    final buffer = BytesBuilder();
    
    final leader = _createValidLeader(
      recordLength: 70,
      baseAddress: 35,
    );
    buffer.add(leader);
    
    // Directory for FRID field (Feature Record Identifier)
    buffer.add(ascii.encode('FRID'));
    buffer.add(ascii.encode('0015')); // Field length
    buffer.add(ascii.encode('000')); // Position
    buffer.add([_fieldTerminator]);
    
    // FRID with invalid RUIN
    buffer.add([100]); // RCNM - Record name
    _addBinaryInt(buffer, 12345, 4); // RCID - Record ID
    buffer.add([1]); // PRIM - Primitive
    buffer.add([1]); // GRUP - Group
    _addBinaryInt(buffer, 58, 2); // OBJL - Object label
    _addBinaryInt(buffer, 1, 2); // RVER - Record version
    buffer.add([99]); // RUIN - Invalid operation code (valid are 1=insert, 2=delete, 3=modify)
    
    buffer.add([_fieldTerminator]);
    
    // Pad to declared length
    while (buffer.length < 69) {
      buffer.add([0x20]);
    }
    buffer.add([_recordTerminator]);
    
    return buffer.toBytes();
  }

  /// Create a valid leader for test records
  static List<int> _createValidLeader({
    required int recordLength,
    required int baseAddress,
  }) {
    final leader = BytesBuilder();
    leader.add(ascii.encode(recordLength.toString().padLeft(5, '0')));
    leader.add(ascii.encode('3')); // Interchange level
    leader.add(ascii.encode('D')); // Data record  
    leader.add(ascii.encode('0')); // Field control length
    leader.add(ascii.encode(baseAddress.toString().padLeft(5, '0')));
    leader.add(ascii.encode('   ')); // Extended character set
    leader.add(ascii.encode('4')); // Size of field length
    leader.add(ascii.encode('3')); // Size of field position
    leader.add(ascii.encode(' ')); // Reserved
    leader.add(ascii.encode('4')); // Size of field tag
    leader.add(ascii.encode('    ')); // Remaining reserved
    
    return leader.toBytes();
  }

  /// Add binary integer to buffer in little-endian format
  static void _addBinaryInt(BytesBuilder buffer, int value, int bytes) {
    final data = ByteData(bytes);
    switch (bytes) {
      case 1:
        data.setUint8(0, value);
        break;
      case 2:
        data.setUint16(0, value, Endian.little);
        break;
      case 4:
        data.setUint32(0, value, Endian.little);
        break;
      default:
        throw ArgumentError('Unsupported byte count: $bytes');
    }
    buffer.add(data.buffer.asUint8List());
  }

  /// Generate random corruption for fuzz testing
  ///
  /// Applies random corruption patterns to a base valid record
  static List<int> createRandomCorruption(List<int> baseRecord, {int? seed}) {
    final random = math.Random(seed);
    final corrupted = List<int>.from(baseRecord);
    
    if (corrupted.length < _leaderSize) {
      return corrupted; // Already corrupted
    }
    
    // Pick random corruption type
    final corruptionType = random.nextInt(6);
    
    switch (corruptionType) {
      case 0:
        // Corrupt random byte in leader
        final pos = random.nextInt(_leaderSize);
        corrupted[pos] = random.nextInt(256);
        break;
      case 1:
        // Truncate at random position
        final truncateAt = _leaderSize + random.nextInt(corrupted.length - _leaderSize);
        return corrupted.sublist(0, truncateAt);
      case 2:
        // Insert random subfield delimiter
        final pos = _leaderSize + random.nextInt(corrupted.length - _leaderSize);
        corrupted.insert(pos, _subfieldDelimiter);
        break;
      case 3:
        // Remove random field terminator
        for (int i = _leaderSize; i < corrupted.length; i++) {
          if (corrupted[i] == _fieldTerminator && random.nextBool()) {
            corrupted.removeAt(i);
            break;
          }
        }
        break;
      case 4:
        // Corrupt record length in leader
        final newLength = random.nextInt(99999).toString().padLeft(5, '0');
        for (int i = 0; i < 5; i++) {
          corrupted[i] = newLength.codeUnitAt(i);
        }
        break;
      case 5:
        // Corrupt base address in leader
        final newBaseAddr = random.nextInt(99999).toString().padLeft(5, '0');
        for (int i = 8; i < 13; i++) {
          corrupted[i] = newBaseAddr.codeUnitAt(i - 8);
        }
        break;
    }
    
    return corrupted;
  }
}