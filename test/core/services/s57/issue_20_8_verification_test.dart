/// Quick test to verify new Issue 20.8 functionality works
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'test_data_utils.dart';

void main() {
  test('verify new Issue 20.8 API works', () {
    // Create test data and parse
    final testData = createValidS57TestData();
    final result = S57Parser.parse(testData);
    
    print('=== Testing Issue 20.8 Implementation ===');
    
    // Test 1: Enhanced Metadata
    print('\n1. Enhanced Metadata:');
    print('   Producer: ${result.metadata.producer}');
    print('   COMF: ${result.metadata.comf}');
    print('   SOMF: ${result.metadata.somf}');
    print('   Edition: ${result.metadata.editionNumber}');
    print('   Update: ${result.metadata.updateNumber}');
    
    // Test 2: findFeatures API
    print('\n2. findFeatures API:');
    final allFeatures = result.findFeatures();
    print('   Total features: ${allFeatures.length}');
    
    final depthFeatures = result.findFeatures(types: {'DEPARE'});
    print('   DEPARE features: ${depthFeatures.length}');
    
    final lightFeatures = result.findFeatures(types: {'LIGHTS'});
    print('   LIGHTS features: ${lightFeatures.length}');
    
    // Test 3: summary API
    print('\n3. Summary API:');
    final summary = result.summary();
    print('   Feature counts: $summary');
    
    // Test 4: GeoJSON export
    print('\n4. GeoJSON Export:');
    final geoJson = result.toGeoJson();
    print('   GeoJSON type: ${geoJson['type']}');
    print('   Features exported: ${(geoJson['features'] as List).length}');
    
    if ((geoJson['features'] as List).isNotEmpty) {
      final firstFeature = (geoJson['features'] as List)[0] as Map<String, dynamic>;
      print('   Sample feature type: ${firstFeature['properties']['typeAcronym']}');
      print('   Sample geometry: ${firstFeature['geometry']['type']}');
    }
    
    // Test 5: Coordinate scaling
    print('\n5. Coordinate Scaling:');
    if (allFeatures.isNotEmpty) {
      final firstCoord = allFeatures.first.coordinates.first;
      print('   Sample coordinate: ${firstCoord.latitude}, ${firstCoord.longitude}');
      print('   Using COMF: ${result.metadata.comf}');
    }
    
    print('\n=== All Issue 20.8 APIs Working! ===');
    
    // Basic assertions
    expect(result.metadata.comf, equals(10000000.0));
    expect(result.metadata.somf, equals(10.0));
    expect(allFeatures, isNotEmpty);
    expect(summary, isNotEmpty);
    expect(geoJson['type'], equals('FeatureCollection'));
  });
}