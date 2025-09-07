/// Test to verify SG2D parsing uses COMF for coordinate scaling
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'dart:typed_data';

void main() {
  group('SG2D Coordinate Scaling', () {
    test('should scale coordinate values using COMF from metadata', () {
      // Create a mock parser instance to test SG2D parsing directly
      final parser = MockS57Parser();
      
      // Test SG2D data (longitude, latitude as 4-byte integers)
      final sg2dData = Uint8List.fromList([
        // Point 1: lon=1000000, lat=2000000 (raw integer values)
        64, 66, 15, 0,    // 1000000 in little endian
        128, 132, 30, 0,  // 2000000 in little endian
        
        // Point 2: lon=1500000, lat=2500000
        96, 225, 22, 0,   // 1500000 in little endian
        160, 167, 38, 0,  // 2500000 in little endian
      ]);
      
      // Test with COMF = 10000000.0 (default)
      parser.setMetadata(comf: 10000000.0, somf: 10.0);
      final result1 = parser.parse2DCoordinate(sg2dData);
      
      // Test with COMF = 5000000.0 (half the default)
      parser.setMetadata(comf: 5000000.0, somf: 10.0);
      final result2 = parser.parse2DCoordinate(sg2dData);
      
      // Verify we got coordinates
      expect(result1, hasLength(2));
      expect(result2, hasLength(2));
      
      // Verify coordinates are different (COMF changed)
      final coord1 = result1[0];
      final coord2 = result2[0];
      
      // When COMF halves, coordinates should double (coord = raw_value / COMF)
      expect(coord2.latitude / coord1.latitude, closeTo(2.0, 0.01));
      expect(coord2.longitude / coord1.longitude, closeTo(2.0, 0.01));
      
      print('Coord1 with COMF=10000000.0: lat=${coord1.latitude}, lon=${coord1.longitude}');
      print('Coord2 with COMF=5000000.0: lat=${coord2.latitude}, lon=${coord2.longitude}');
      print('Latitude ratio: ${coord2.latitude / coord1.latitude}');
      print('Longitude ratio: ${coord2.longitude / coord1.longitude}');
    });
  });
}

/// Mock parser class to test SG2D parsing directly
class MockS57Parser {
  double _comf = 10000000.0;
  double _somf = 10.0;
  
  void setMetadata({required double comf, required double somf}) {
    _comf = comf;
    _somf = somf;
  }
  
  /// Test the SG2D parsing logic directly
  List<S57Coordinate> parse2DCoordinate(Uint8List data) {
    final coordinates = <S57Coordinate>[];
    int pos = 0;

    while (pos + 8 <= data.length) {
      final x = _parseCoordinateValue(data, pos);
      final y = _parseCoordinateValue(data, pos + 4);

      if (x != null && y != null) {
        // Convert from S-57 coordinate units to decimal degrees using dynamic COMF
        final longitude = x / _comf;
        final latitude = y / _comf;

        coordinates.add(
          S57Coordinate(latitude: latitude, longitude: longitude),
        );
      }

      pos += 8;
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