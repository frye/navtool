/// Binary test fixture generator for ISO 8211 records
/// 
/// Creates a binary test file containing:
/// 1. DDR (Directory Definition Record) with DSID and DSPM tags
/// 2. Data Record A with FOID and FT01 fields
/// 3. Data Record B with FT02 field
/// 4. Malformed Record (invalid base address) for recovery testing

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final fixture = _createSampleEncFixture();
  
  // Write to test fixtures directory
  final file = File('test/fixtures/iso8211/sample_enc.bin');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(fixture);
  
  print('Generated ISO 8211 test fixture: ${file.path}');
  print('Total size: ${fixture.length} bytes');
  
  // Verify the fixture by showing record structure
  _analyzeFixture(fixture);
}

/// Create the binary test fixture with specified record structure
List<int> _createSampleEncFixture() {
  final buffer = BytesBuilder();
  
  // Record 1: DDR (Directory Definition Record)
  buffer.add(_createDDRRecord());
  
  // Record 2: Data Record A
  buffer.add(_createDataRecordA());
  
  // Record 3: Data Record B
  buffer.add(_createDataRecordB());
  
  // Record 4: Malformed Record
  buffer.add(_createMalformedRecord());
  
  return buffer.toBytes();
}

/// Create DDR with DSID and DSPM fields
List<int> _createDDRRecord() {
  // Field data
  final dsidData = ascii.encode('US5WA50M'); // Chart ID
  final dspmData = ascii.encode('20241201'); // Date
  
  // Directory entries (tag=4, length=5, position=5)
  final directory = BytesBuilder();
  directory.add(ascii.encode('DSID')); // tag
  directory.add(ascii.encode('00008')); // length (8 bytes + terminator)
  directory.add(ascii.encode('00000')); // position from field area start
  
  directory.add(ascii.encode('DSPM')); // tag
  directory.add(ascii.encode('00008')); // length (8 bytes + terminator)
  directory.add(ascii.encode('00009')); // position (after DSID + terminator)
  
  directory.add([0x1e]); // directory terminator
  
  // Field area
  final fieldArea = BytesBuilder();
  fieldArea.add(dsidData);
  fieldArea.add([0x1e]); // field terminator
  fieldArea.add(dspmData);
  fieldArea.add([0x1e]); // field terminator
  
  // Calculate addresses
  final directoryBytes = directory.toBytes();
  final fieldAreaBytes = fieldArea.toBytes();
  final baseAddress = 24 + directoryBytes.length; // After leader + directory
  final recordLength = baseAddress + fieldAreaBytes.length + 1; // +1 for record terminator
  
  // Leader (24 bytes)
  final leader = BytesBuilder();
  leader.add(ascii.encode(recordLength.toString().padLeft(5, '0'))); // positions 0-4
  leader.add(ascii.encode('3')); // interchange level (position 5)
  leader.add(ascii.encode('L')); // leader identifier - DDR (position 6)
  leader.add(ascii.encode('0')); // field control length (position 7)
  leader.add(ascii.encode(baseAddress.toString().padLeft(5, '0'))); // base address (positions 8-12)
  leader.add(ascii.encode('   ')); // extended character set (positions 13-15)
  leader.add(ascii.encode('5')); // size of field length (position 16)
  leader.add(ascii.encode('5')); // size of field position (position 17)
  leader.add(ascii.encode(' ')); // reserved (position 18)
  leader.add(ascii.encode('4')); // size of field tag (position 19)
  leader.add(ascii.encode('    ')); // remaining reserved (positions 20-23)
  
  // Assemble complete record
  final record = BytesBuilder();
  record.add(leader.toBytes());
  record.add(directoryBytes);
  record.add(fieldAreaBytes);
  record.add([0x1d]); // record terminator
  
  return record.toBytes();
}

/// Create Data Record A with FOID and FT01
List<int> _createDataRecordA() {
  // Field data
  final foidData = ascii.encode('001'); // Feature Object ID
  final ft01Data = ascii.encode('BCNCAR\u001f02\u001f01'); // Beacon Cardinal + attributes
  
  // Directory
  final directory = BytesBuilder();
  directory.add(ascii.encode('FOID')); // tag
  directory.add(ascii.encode('00003')); // length
  directory.add(ascii.encode('00000')); // position
  
  directory.add(ascii.encode('FT01')); // tag
  directory.add(ascii.encode('00010')); // length (including subfield delimiters)
  directory.add(ascii.encode('00004')); // position (after FOID + terminator)
  
  directory.add([0x1e]); // directory terminator
  
  // Field area
  final fieldArea = BytesBuilder();
  fieldArea.add(foidData);
  fieldArea.add([0x1e]); // field terminator
  fieldArea.add(ft01Data);
  fieldArea.add([0x1e]); // field terminator
  
  // Calculate addresses
  final directoryBytes = directory.toBytes();
  final fieldAreaBytes = fieldArea.toBytes();
  final baseAddress = 24 + directoryBytes.length;
  final recordLength = baseAddress + fieldAreaBytes.length + 1;
  
  // Leader
  final leader = BytesBuilder();
  leader.add(ascii.encode(recordLength.toString().padLeft(5, '0')));
  leader.add(ascii.encode('3'));
  leader.add(ascii.encode('D')); // Data record
  leader.add(ascii.encode('0'));
  leader.add(ascii.encode(baseAddress.toString().padLeft(5, '0')));
  leader.add(ascii.encode('   '));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode(' '));
  leader.add(ascii.encode('4'));
  leader.add(ascii.encode('    '));
  
  // Assemble record
  final record = BytesBuilder();
  record.add(leader.toBytes());
  record.add(directoryBytes);
  record.add(fieldAreaBytes);
  record.add([0x1d]);
  
  return record.toBytes();
}

/// Create Data Record B with FT02
List<int> _createDataRecordB() {
  // Field data
  final ft02Data = ascii.encode('SOUNDG\u001f150\u001f250'); // Sounding + depth values
  
  // Directory
  final directory = BytesBuilder();
  directory.add(ascii.encode('FT02')); // tag
  directory.add(ascii.encode('00013')); // length
  directory.add(ascii.encode('00000')); // position
  
  directory.add([0x1e]); // directory terminator
  
  // Field area
  final fieldArea = BytesBuilder();
  fieldArea.add(ft02Data);
  fieldArea.add([0x1e]); // field terminator
  
  // Calculate addresses
  final directoryBytes = directory.toBytes();
  final fieldAreaBytes = fieldArea.toBytes();
  final baseAddress = 24 + directoryBytes.length;
  final recordLength = baseAddress + fieldAreaBytes.length + 1;
  
  // Leader
  final leader = BytesBuilder();
  leader.add(ascii.encode(recordLength.toString().padLeft(5, '0')));
  leader.add(ascii.encode('3'));
  leader.add(ascii.encode('D')); // Data record
  leader.add(ascii.encode('0'));
  leader.add(ascii.encode(baseAddress.toString().padLeft(5, '0')));
  leader.add(ascii.encode('   '));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode(' '));
  leader.add(ascii.encode('4'));
  leader.add(ascii.encode('    '));
  
  // Assemble record
  final record = BytesBuilder();
  record.add(leader.toBytes());
  record.add(directoryBytes);
  record.add(fieldAreaBytes);
  record.add([0x1d]);
  
  return record.toBytes();
}

/// Create malformed record with invalid base address for testing error recovery
List<int> _createMalformedRecord() {
  // Intentionally malformed: base address smaller than leader size
  final leader = BytesBuilder();
  leader.add(ascii.encode('00050')); // record length
  leader.add(ascii.encode('3'));
  leader.add(ascii.encode('D'));
  leader.add(ascii.encode('0'));
  leader.add(ascii.encode('00010')); // invalid base address (< 24)
  leader.add(ascii.encode('   '));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode('5'));
  leader.add(ascii.encode(' '));
  leader.add(ascii.encode('4'));
  leader.add(ascii.encode('    '));
  
  // Pad to declared record length with dummy data
  final record = BytesBuilder();
  record.add(leader.toBytes()); // 24 bytes
  record.add(List.filled(25, 0x20)); // 25 bytes of padding
  record.add([0x1d]); // record terminator (1 byte) = 50 total
  
  return record.toBytes();
}

/// Analyze the generated fixture to verify structure
void _analyzeFixture(List<int> data) {
  print('\nFixture Analysis:');
  
  int offset = 0;
  int recordNum = 1;
  
  while (offset < data.length) {
    if (offset + 24 > data.length) break;
    
    // Read record length from leader
    final recordLengthStr = String.fromCharCodes(data.sublist(offset, offset + 5));
    final recordLength = int.tryParse(recordLengthStr);
    
    if (recordLength == null || recordLength <= 0) {
      print('Record $recordNum: Invalid record length at offset $offset');
      break;
    }
    
    final leaderIdentifier = String.fromCharCodes(data.sublist(offset + 6, offset + 7));
    final baseAddressStr = String.fromCharCodes(data.sublist(offset + 8, offset + 13));
    final baseAddress = int.tryParse(baseAddressStr) ?? 0;
    
    print('Record $recordNum: length=$recordLength, type=$leaderIdentifier, baseAddr=$baseAddress');
    
    offset += recordLength;
    recordNum++;
  }
}