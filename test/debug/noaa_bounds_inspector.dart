@Skip('Excluded from CI: exploratory debug analysis test')
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  // Just inspect NOAA raw data without app dependencies
  await inspectNoaaChartBounds();
}

Future<void> inspectNoaaChartBounds() async {
  print('\n=== NOAA Chart Bounds Inspector ===\n');
  
  final client = HttpClient();
  
  try {
    final url = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query?where=1%3D1&outFields=*&f=json&returnGeometry=true&resultRecordCount=1000';
    
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', 'NavTool/1.0.0 (Marine Navigation App)');
    
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode == 200) {
      final data = json.decode(responseBody);
      final features = data['features'] as List<dynamic>;
      
      print('Total charts fetched: ${features.length}');
      print('First 5 charts:\n');
      
      for (int i = 0; i < 5 && i < features.length; i++) {
        final feature = features[i];
        final attributes = feature['attributes'];
        final geometry = feature['geometry'];
        
        final chartName = attributes['CELL_NAME'] ?? 'Unknown';
        final title = attributes['TITLE'] ?? 'No Title';
        
        print('Chart #${i + 1}: $chartName');
        print('  Title: $title');
        
        if (geometry != null) {
          final rings = geometry['rings'] as List<dynamic>?;
          if (rings != null && rings.isNotEmpty) {
            final firstRing = rings[0] as List<dynamic>;
            if (firstRing.isNotEmpty) {
              print('  Geometry type: Polygon with ${rings.length} ring(s)');
              print('  First ring has ${firstRing.length} points');
              
              // Extract bounds from first ring
              double minLon = double.infinity;
              double maxLon = double.negativeInfinity;
              double minLat = double.infinity;
              double maxLat = double.negativeInfinity;
              
              for (final point in firstRing) {
                if (point is List && point.length >= 2) {
                  final lon = (point[0] as num).toDouble();
                  final lat = (point[1] as num).toDouble();
                  
                  minLon = minLon > lon ? lon : minLon;
                  maxLon = maxLon < lon ? lon : maxLon;
                  minLat = minLat > lat ? lat : minLat;
                  maxLat = maxLat < lat ? lat : maxLat;
                }
              }
              
              print('  Calculated bounds: ($minLon, $minLat) to ($maxLon, $maxLat)');
              
              // Check if bounds are valid
              if (minLon == 0.0 && maxLon == 0.0 && minLat == 0.0 && maxLat == 0.0) {
                print('  ⚠️  INVALID BOUNDS: All zeros!');
              } else if (minLon == maxLon && minLat == maxLat) {
                print('  ⚠️  INVALID BOUNDS: Point instead of area!');
              } else {
                print('  ✅ Valid bounds');
              }
              
              // Check if Washington area
              final washingtonMinLon = -124.8;
              final washingtonMaxLon = -116.9;
              final washingtonMinLat = 45.5;
              final washingtonMaxLat = 49.0;
              
              if (maxLon >= washingtonMinLon && minLon <= washingtonMaxLon &&
                  maxLat >= washingtonMinLat && minLat <= washingtonMaxLat) {
                print('  🌲 Potentially covers Washington state');
              }
            }
          } else {
            print('  ⚠️  No rings in geometry');
          }
        } else {
          print('  ⚠️  No geometry data');
        }
        
        print('');
      }
      
      // Count charts by region
      int validBounds = 0;
      int invalidBounds = 0;
      int washingtonCharts = 0;
      
      for (final feature in features) {
        final geometry = feature['geometry'];
        if (geometry != null) {
          final rings = geometry['rings'] as List<dynamic>?;
          if (rings != null && rings.isNotEmpty) {
            final firstRing = rings[0] as List<dynamic>;
            
            double minLon = double.infinity;
            double maxLon = double.negativeInfinity;
            double minLat = double.infinity;
            double maxLat = double.negativeInfinity;
            
            for (final point in firstRing) {
              if (point is List && point.length >= 2) {
                final lon = (point[0] as num).toDouble();
                final lat = (point[1] as num).toDouble();
                
                minLon = minLon > lon ? lon : minLon;
                maxLon = maxLon < lon ? lon : maxLon;
                minLat = minLat > lat ? lat : minLat;
                maxLat = maxLat < lat ? lat : maxLat;
              }
            }
            
            if (minLon == 0.0 && maxLon == 0.0 && minLat == 0.0 && maxLat == 0.0) {
              invalidBounds++;
            } else if (minLon == maxLon && minLat == maxLat) {
              invalidBounds++;
            } else {
              validBounds++;
              
              // Check Washington overlap
              final washingtonMinLon = -124.8;
              final washingtonMaxLon = -116.9;
              final washingtonMinLat = 45.5;
              final washingtonMaxLat = 49.0;
              
              if (maxLon >= washingtonMinLon && minLon <= washingtonMaxLon &&
                  maxLat >= washingtonMinLat && minLat <= washingtonMaxLat) {
                washingtonCharts++;
              }
            }
          }
        }
      }
      
      print('Summary:');
      print('  Valid bounds: $validBounds');
      print('  Invalid bounds: $invalidBounds');
      print('  Charts potentially covering Washington: $washingtonCharts');
      
    } else {
      print('HTTP Error: ${response.statusCode}');
    }
    
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
