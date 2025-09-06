/// Synthetic S-57 Update File Generator
///
/// Creates test fixtures for sequential update file processing tests
/// Generates binary S-57 files with RUIN operations

import 'dart:io';
import 'dart:typed_data';

import '../../../lib/core/services/s57/s57_models.dart';
import '../../../lib/core/services/s57/s57_update_models.dart';

/// Generator for synthetic S-57 update test fixtures
class S57UpdateFixtureGenerator {
  /// Generate base file (SAMPLE.000) with initial features
  static Future<void> generateBaseFile(String directory) async {
    final data = _createBaseENCData();
    final file = File('$directory/SAMPLE.000');
    await file.writeAsBytes(data);
  }

  /// Generate update file .001 - Delete F2 (sounding)
  static Future<void> generateUpdate001(String directory) async {
    final data = _createUpdateData001();
    final file = File('$directory/SAMPLE.001');
    await file.writeAsBytes(data);
  }

  /// Generate update file .002 - Modify F1 (change DRVAL1)
  static Future<void> generateUpdate002(String directory) async {
    final data = _createUpdateData002();
    final file = File('$directory/SAMPLE.002');
    await file.writeAsBytes(data);
  }

  /// Generate update file .003 - Insert F4 (new obstruction)
  static Future<void> generateUpdate003(String directory) async {
    final data = _createUpdateData003();
    final file = File('$directory/SAMPLE.003');
    await file.writeAsBytes(data);
  }

  /// Generate gap test file (same as .003 but used when .002 is missing)
  static Future<void> generateGapTest003(String directory) async {
    final data = _createUpdateData003();
    final file = File('$directory/SAMPLE_GAP.003');
    await file.writeAsBytes(data);
  }

  /// Generate all test fixtures
  static Future<void> generateAllFixtures(String directory) async {
    await Directory(directory).create(recursive: true);

    await generateBaseFile(directory);
    await generateUpdate001(directory);
    await generateUpdate002(directory);
    await generateUpdate003(directory);
    await generateGapTest003(directory);
  }

  /// Create base ENC data with 3 features: F1(DEPARE), F2(SOUNDG), F3(LIGHTS)
  static List<int> _createBaseENCData() {
    final data = <int>[];

    // Create minimal ISO 8211 structure for base file
    // Record leader (24 bytes) - must be valid
    data.addAll(
      '00256 D     '.codeUnits,
    ); // Record length: 256, interchange level: D
    data.addAll('L'.codeUnits); // Leader identifier
    data.addAll(' '.codeUnits); // Inline code extension
    data.addAll('1'.codeUnits); // Version number
    data.addAll(' '.codeUnits); // Application indicator
    data.addAll('09'.codeUnits); // Field control length
    data.addAll('00024'.codeUnits); // Base address: 24 (start after leader)
    data.addAll('   '.codeUnits); // Extended character set
    data.addAll('4'.codeUnits); // Size of field length indicator
    data.addAll('4'.codeUnits); // Size of field position indicator
    data.addAll(' '.codeUnits); // Reserved
    data.addAll('4'.codeUnits); // Size of field tag

    // Keep it simple - no directory, just data area starts at byte 24
    // Pad to base address (24 bytes total for leader)
    while (data.length < 24) {
      data.add(0x20);
    }

    // Simple data area with just chart name
    data.addAll('SAMPLE'.codeUnits);
    data.add(0x1e); // Field terminator

    // Pad to record length (256)
    while (data.length < 256) {
      data.add(0x20);
    }

    return data;
  }

  /// Create update data for .001 (delete F2)
  static List<int> _createUpdateData001() {
    final data = <int>[];

    // Simplified update record with RUIN delete operation
    data.addAll('00200 D00000'.codeUnits); // Record header
    data.addAll('000000'.codeUnits);
    data.addAll('0025000'.codeUnits);
    data.addAll(' !'.codeUnits);

    // Directory
    data.addAll('FRID00060000'.codeUnits); // Feature Record ID
    data.addAll('FOID00080006'.codeUnits); // Feature Object ID
    data.addAll('0001'.codeUnits);

    // Pad to base address
    while (data.length < 25) {
      data.add(0x20);
    }

    // FRID - Feature Record Identifier
    data.add(100); // RCNM
    _addBinaryInt(data, 2, 4); // RCID (F2)
    data.add(1); // PRIM
    data.add(1); // GRUP
    _addBinaryInt(data, 127, 2); // OBJL (SOUNDG)
    _addBinaryInt(data, 1, 2); // RVER
    data.add(2); // RUIN = Delete
    data.add(0x1e); // Field terminator

    // FOID - Feature Object Identifier
    _addBinaryInt(data, 550, 2); // AGEN
    _addBinaryInt(data, 2, 4); // FIDN (F2)
    _addBinaryInt(data, 1, 2); // FIDS
    data.add(0x1e); // Field terminator

    // Pad to total length
    while (data.length < 200) {
      data.add(0x20);
    }

    return data;
  }

  /// Create update data for .002 (modify F1 DRVAL1)
  static List<int> _createUpdateData002() {
    final data = <int>[];

    // Update record with RUIN modify operation
    data.addAll('00250 D00000'.codeUnits);
    data.addAll('000000'.codeUnits);
    data.addAll('0025000'.codeUnits);
    data.addAll(' !'.codeUnits);

    // Directory
    data.addAll('FRID00060000'.codeUnits);
    data.addAll('FOID00080006'.codeUnits);
    data.addAll('ATTF00100014'.codeUnits); // Attributes
    data.addAll('0001'.codeUnits);

    // Pad to base address
    while (data.length < 25) {
      data.add(0x20);
    }

    // FRID - Feature Record Identifier
    data.add(100); // RCNM
    _addBinaryInt(data, 1, 4); // RCID (F1)
    data.add(1); // PRIM
    data.add(1); // GRUP
    _addBinaryInt(data, 120, 2); // OBJL (DEPARE)
    _addBinaryInt(data, 2, 2); // RVER
    data.add(3); // RUIN = Modify
    data.add(0x1e);

    // FOID
    _addBinaryInt(data, 550, 2); // AGEN
    _addBinaryInt(data, 1, 4); // FIDN (F1)
    _addBinaryInt(data, 1, 2); // FIDS
    data.add(0x1e);

    // ATTF - Modified attributes (change DRVAL1 from 10.0 to 5.0)
    _addBinaryInt(data, 55, 2); // DRVAL1 attribute code
    _addBinaryInt(data, 500, 4); // New value (5.0 * 100 for fixed point)
    data.add(0x1e);

    // Pad to total length
    while (data.length < 250) {
      data.add(0x20);
    }

    return data;
  }

  /// Create update data for .003 (insert F4 obstruction)
  static List<int> _createUpdateData003() {
    final data = <int>[];

    // Update record with RUIN insert operation
    data.addAll('00300 D00000'.codeUnits);
    data.addAll('000000'.codeUnits);
    data.addAll('0025000'.codeUnits);
    data.addAll(' !'.codeUnits);

    // Directory (more complex for insert with coordinates)
    data.addAll('FRID00060000'.codeUnits);
    data.addAll('FOID00080006'.codeUnits);
    data.addAll('ATTF00080014'.codeUnits);
    data.addAll('SG2D00080022'.codeUnits); // 2D coordinates
    data.addAll('0001'.codeUnits);

    // Pad to base address
    while (data.length < 25) {
      data.add(0x20);
    }

    // FRID - Feature Record Identifier
    data.add(100); // RCNM
    _addBinaryInt(data, 4, 4); // RCID (F4)
    data.add(1); // PRIM
    data.add(1); // GRUP
    _addBinaryInt(data, 104, 2); // OBJL (OBSTRN)
    _addBinaryInt(data, 3, 2); // RVER
    data.add(1); // RUIN = Insert
    data.add(0x1e);

    // FOID
    _addBinaryInt(data, 550, 2); // AGEN
    _addBinaryInt(data, 4, 4); // FIDN (F4)
    _addBinaryInt(data, 1, 2); // FIDS
    data.add(0x1e);

    // ATTF - Obstruction attributes
    _addBinaryInt(data, 86, 2); // CATOBS attribute
    _addBinaryInt(data, 1, 4); // Obstruction category
    data.add(0x1e);

    // SG2D - 2D coordinates (single point)
    _addBinaryInt(data, -1223400000, 4); // X (longitude * 10^7)
    _addBinaryInt(data, 476500000, 4); // Y (latitude * 10^7)
    data.add(0x1e);

    // Pad to total length
    while (data.length < 300) {
      data.add(0x20);
    }

    return data;
  }

  /// Helper to add binary integer in little-endian format
  static void _addBinaryInt(List<int> data, int value, int bytes) {
    final byteData = ByteData(bytes);
    switch (bytes) {
      case 1:
        byteData.setUint8(0, value);
        break;
      case 2:
        byteData.setUint16(0, value, Endian.little);
        break;
      case 4:
        byteData.setInt32(0, value, Endian.little);
        break;
    }
    data.addAll(byteData.buffer.asUint8List());
  }
}

/// Main function to generate test fixtures
void main() async {
  final directory = 'test/fixtures/updates';
  print('Generating S-57 update test fixtures in $directory...');

  await S57UpdateFixtureGenerator.generateAllFixtures(directory);

  print('Generated fixtures:');
  print('  - SAMPLE.000 (base file)');
  print('  - SAMPLE.001 (delete F2)');
  print('  - SAMPLE.002 (modify F1)');
  print('  - SAMPLE.003 (insert F4)');
  print('  - SAMPLE_GAP.003 (gap test)');
  print('Done!');
}
