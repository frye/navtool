import 'package:http/http.dart' as http;

void main() async {
  print('Testing network connectivity to NOAA API endpoints...');
  
  // Test basic connectivity
  final catalogUrl = 'https://gis.charttools.noaa.gov/arcgis/rest/services/MCS/ENCOnline/MapServer/exts/MaritimeChartService/WMSServer?request=GetCapabilities&service=WMS';
  
  try {
    print('Testing catalog endpoint: $catalogUrl');
    final response = await http.get(Uri.parse(catalogUrl));
    print('Response status: ${response.statusCode}');
    print('Response headers: ${response.headers}');
    if (response.statusCode == 200) {
      print('✓ Catalog endpoint is accessible');
      print('Response length: ${response.body.length} characters');
    } else {
      print('✗ Catalog endpoint returned status: ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Error accessing catalog endpoint: $e');
  }
  
  print('\n');
  
  // Test chart download endpoint
  final downloadUrl = 'https://charts.noaa.gov/ENCs/';
  
  try {
    print('Testing download endpoint: $downloadUrl');
    final response = await http.head(Uri.parse(downloadUrl));
    print('Response status: ${response.statusCode}');
    print('Response headers: ${response.headers}');
    if (response.statusCode == 200 || response.statusCode == 403) {
      print('✓ Download endpoint is accessible');
    } else {
      print('✗ Download endpoint returned status: ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Error accessing download endpoint: $e');
  }
}
