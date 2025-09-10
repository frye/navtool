/// Debug script to examine S-57 coordinate data
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  print('[Debug] Loading Elliott Bay chart for coordinate inspection...');
  
  try {
    // Load Elliott Bay harbor chart
    final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
    final List<int> chartBytes = byteData.buffer.asUint8List();
    
    print('[Debug] Loaded ${chartBytes.length} bytes');
    
    // Parse S-57 data
    final s57Data = S57Parser.parse(chartBytes);
    print('[Debug] Parsed ${s57Data.features.length} features');
    
    // Examine each feature's coordinates
    for (int i = 0; i < s57Data.features.length; i++) {
      final feature = s57Data.features[i];
      print('\n[Debug] Feature $i:');
      print('[Debug]   Type: ${feature.featureType.acronym}');
      print('[Debug]   Record ID: ${feature.recordId}');
      print('[Debug]   Coordinates count: ${feature.coordinates.length}');
      
      if (feature.coordinates.isNotEmpty) {
        final coord = feature.coordinates.first;
        print('[Debug]   First coordinate: lat=${coord.latitude}, lng=${coord.longitude}');
        
        // Test conversion
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures([feature]);
        if (maritimeFeatures.isNotEmpty) {
          final maritime = maritimeFeatures.first;
          print('[Debug]   Converted position: lat=${maritime.position.latitude}, lng=${maritime.position.longitude}');
        }
      } else {
        print('[Debug]   No coordinates available');
      }
      
      print('[Debug]   Attributes: ${feature.attributes.keys.join(', ')}');
    }
    
  } catch (e, stackTrace) {
    print('[Debug] Error: $e');
    print('[Debug] Stack trace: $stackTrace');
  }
}