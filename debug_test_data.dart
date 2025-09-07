/// Debug utility to analyze test data byte layout
import 'dart:typed_data';
import 'test/core/services/s57/test_data_utils.dart';

void main() {
  print('Analyzing test data generation...');
  
  final testData = createValidS57TestDataWithDSPM(comf: 5000000.0, somf: 25.0);
  
  print('Total data length: ${testData.length}');
  
  // Find DSPM in directory
  for (int i = 0; i < testData.length - 4; i++) {
    if (testData[i] == 68 && testData[i+1] == 83 && testData[i+2] == 80 && testData[i+3] == 77) { // "DSPM"
      print('Found DSPM at offset $i');
      // Check the following bytes (length and position)
      final lengthBytes = testData.sublist(i+4, i+8);
      final positionBytes = testData.sublist(i+8, i+12);
      print('Length field: ${String.fromCharCodes(lengthBytes)}');
      print('Position field: ${String.fromCharCodes(positionBytes)}');
      
      // Try to parse as integers
      final position = int.tryParse(String.fromCharCodes(positionBytes)) ?? 0;
      final length = int.tryParse(String.fromCharCodes(lengthBytes)) ?? 0;
      print('Parsed position: $position, length: $length');
      
      print('\\nChecking different absolute positions:');
      
      // Check what parser calculates (dataStart=317, position=165 -> fieldStart=482)
      final parserPosition = 317 + position;
      print('Parser position (317 + $position = $parserPosition):');
      if (parserPosition >= 0 && parserPosition + length <= testData.length) {
        final parserData = testData.sublist(parserPosition, parserPosition + length);
        print('  Hex: ${parserData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('  ASCII: ${parserData.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join('')}');
      }
      
      // Check what I calculated (base=241, position=165 -> absolute=406)
      final myPosition = 241 + position;
      print('\\nMy position (241 + $position = $myPosition):');
      if (myPosition >= 0 && myPosition + length <= testData.length) {
        final myData = testData.sublist(myPosition, myPosition + length);
        print('  Hex: ${myData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        print('  ASCII: ${myData.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join('')}');
      }
      break;
    }
  }
}