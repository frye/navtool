@Skip('Excluded from CI: exploratory debug analysis test')
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  // Inspect actual NOAA API response structure
  await inspectNoaaApiStructure();
}

Future<void> inspectNoaaApiStructure() async {
  print('\n=== NOAA API Response Structure Inspector ===\n');
  
  final client = HttpClient();
  
  try {
    final url = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query?where=1%3D1&outFields=*&f=json&returnGeometry=true&resultRecordCount=5';
    
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', 'NavTool/1.0.0 (Marine Navigation App)');
    
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode == 200) {
      final data = json.decode(responseBody);
      
      print('Response structure:');
      print('  Type: ${data.runtimeType}');
      print('  Top-level keys: ${data.keys.toList()}');
      
      if (data.containsKey('features')) {
        final features = data['features'] as List<dynamic>;
        print('  Features count: ${features.length}');
        
        if (features.isNotEmpty) {
          final firstFeature = features.first;
          print('  First feature structure:');
          print('    Keys: ${firstFeature.keys.toList()}');
          
          if (firstFeature.containsKey('attributes')) {
            final attributes = firstFeature['attributes'];
            print('    Attributes keys: ${attributes.keys.toList()}');
            print('    Sample attributes:');
            attributes.forEach((key, value) {
              print('      $key: $value (${value.runtimeType})');
            });
          }
          
          if (firstFeature.containsKey('properties')) {
            final properties = firstFeature['properties'];
            print('    Properties keys: ${properties.keys.toList()}');
          }
          
          if (firstFeature.containsKey('geometry')) {
            final geometry = firstFeature['geometry'];
            print('    Geometry type: ${geometry['type']}');
            if (geometry.containsKey('rings')) {
              final rings = geometry['rings'] as List;
              print('    Rings count: ${rings.length}');
              if (rings.isNotEmpty) {
                final firstRing = rings.first;
                print('    First ring points: ${firstRing.length}');
                if (firstRing.isNotEmpty) {
                  print('    First point: ${firstRing.first}');
                }
              }
            }
          }
        }
      }
      
    } else {
      print('HTTP Error: ${response.statusCode}');
    }
    
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
