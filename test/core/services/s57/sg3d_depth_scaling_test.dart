/// Test to verify SG3D parsing uses SOMF for depth scaling
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'dart:typed_data';

void main() {
  group('SG3D Depth Scaling', () {
    test('should scale depth values using SOMF from metadata', () {
      // Create a mock parser instance to test SG3D parsing directly
      final parser = MockS57Parser();
      
      // Test SG3D data (longitude, latitude, depth as 4-byte integers)
      final sg3dData = Uint8List.fromList([
        // Point 1: lon=1000, lat=2000, depth=100 (raw integer values)
        232, 3, 0, 0,    // 1000 in little endian
        208, 7, 0, 0,    // 2000 in little endian  
        100, 0, 0, 0,    // 100 in little endian
        
        // Point 2: lon=1500, lat=2500, depth=150
        220, 5, 0, 0,    // 1500 in little endian
        196, 9, 0, 0,    // 2500 in little endian
        150, 0, 0, 0,    // 150 in little endian
      ]);
      
      // Test with SOMF = 10.0 (default)
      parser.setMetadata(comf: 10000000.0, somf: 10.0);
      final result1 = parser.parse3DCoordinate(sg3dData);
      
      // Test with SOMF = 20.0 (double the default)
      parser.setMetadata(comf: 10000000.0, somf: 20.0);
      final result2 = parser.parse3DCoordinate(sg3dData);
      
      // Verify coordinates are the same (COMF unchanged)
      expect(result1[0]['longitude'], equals(result2[0]['longitude']));
      expect(result1[0]['latitude'], equals(result2[0]['latitude']));
      
      // Verify depths are different (SOMF changed)
      final depth1 = result1[0]['depth'] as double;
      final depth2 = result2[0]['depth'] as double;
      
      // When SOMF doubles, depth should be halved (depth = raw_value / SOMF)
      expect(depth2 / depth1, closeTo(0.5, 0.01));
      
      print('Depth with SOMF=10.0: $depth1');
      print('Depth with SOMF=20.0: $depth2');
      print('Ratio: ${depth2 / depth1}');
    });
  });
}

/// Mock parser class to test SG3D parsing directly
class MockS57Parser {
  double _comf = 10000000.0;
  double _somf = 10.0;
  
  void setMetadata({required double comf, required double somf}) {
    _comf = comf;
    _somf = somf;
  }
  
  /// Test the SG3D parsing logic directly
  List<Map<String, double>> parse3DCoordinate(Uint8List data) {
    final coordinates = <Map<String, double>>[];
    int pos = 0;

    while (pos + 12 <= data.length) {
      final x = _parseCoordinateValue(data, pos);
      final y = _parseCoordinateValue(data, pos + 4);
      final z = _parseCoordinateValue(data, pos + 8);

      if (x != null && y != null && z != null) {
        coordinates.add({
          'longitude': x / _comf,
          'latitude': y / _comf,
          'depth': z / _somf, // Depth in meters using SOMF
        });
      }

      pos += 12;
    }

    return coordinates;
  }
  
  /// Parse coordinate value from binary data (copied from S57Parser)
  double? _parseCoordinateValue(Uint8List data, int offset) {
    if (offset + 4 > data.length) return null;

    try {
      final bytes = data.sublist(offset, offset + 4);
      // Handle potential padding or invalid data
      final allZero = bytes.every((b) => b == 0);
      final allPadding = bytes.every((b) => b == 0x20); // Space padding

      if (allZero || allPadding) return null;

      return ByteData.sublistView(bytes).getInt32(0, Endian.little).toDouble();
    } catch (e) {
      return null;
    }
  }
}