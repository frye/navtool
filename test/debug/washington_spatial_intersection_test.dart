@Skip('Excluded from CI: exploratory debug analysis test')
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/utils/spatial_operations.dart';
import 'package:navtool/core/models/chart_models.dart';

/// Test to diagnose the Washington state spatial intersection issue
void main() {
  group('Washington State Spatial Intersection Diagnostic', () {
    test('should analyze why Washington charts are not found', () {
      // Washington state bounds from the application
      final washingtonBounds = GeographicBounds(
        north: 49.0, 
        south: 45.5, 
        east: -116.9, 
        west: -124.8
      );
      
      // Seattle coordinates used as fallback
      final seattleCoords = LatLng(47.6062, -122.3321);
      
      // Example West Coast chart bounds (US1WC01M.000 - these are the charts found in logs)
      final westCoastChart1 = GeographicBounds(
        north: 50.0,   // Hypothetical bounds - need to check actual data
        south: 40.0,
        east: -120.0,
        west: -130.0
      );
      
      final westCoastChart2 = GeographicBounds(
        north: 48.5,
        south: 46.0,
        east: -122.0,
        west: -125.0
      );
      
      print('🔍 WASHINGTON STATE SPATIAL INTERSECTION DIAGNOSTIC');
      print('=================================================');
      
      // Check if Seattle is in Washington bounds
      final seattlePolygon = [seattleCoords];
      final washingtonPolygon = SpatialOperations.boundsToPolygon(washingtonBounds);
      final isSeattleInWashington = SpatialOperations.isPointInPolygon(seattleCoords, washingtonPolygon);
      
      print('✅ Seattle coordinates: ${seattleCoords.latitude}, ${seattleCoords.longitude}');
      print('✅ Washington bounds: N:${washingtonBounds.north} S:${washingtonBounds.south} E:${washingtonBounds.east} W:${washingtonBounds.west}');
      print('✅ Seattle in Washington polygon: $isSeattleInWashington');
      
      // Test chart intersections
      print('\\n📊 CHART INTERSECTION ANALYSIS:');
      
      // Test West Coast Chart 1
      final chart1Polygon = SpatialOperations.boundsToPolygon(westCoastChart1);
      final chart1Intersects = SpatialOperations.doPolygonsIntersect(washingtonPolygon, chart1Polygon);
      final chart1Coverage = SpatialOperations.calculateCoveragePercentage(washingtonPolygon, chart1Polygon);
      
      print('📋 West Coast Chart 1:');
      print('  Bounds: N:${westCoastChart1.north} S:${westCoastChart1.south} E:${westCoastChart1.east} W:${westCoastChart1.west}');
      print('  Intersects Washington: $chart1Intersects');
      print('  Coverage: ${(chart1Coverage * 100).toStringAsFixed(2)}%');
      print('  Meets threshold (>1%): ${chart1Coverage > 0.01}');
      
      // Test West Coast Chart 2  
      final chart2Polygon = SpatialOperations.boundsToPolygon(westCoastChart2);
      final chart2Intersects = SpatialOperations.doPolygonsIntersect(washingtonPolygon, chart2Polygon);
      final chart2Coverage = SpatialOperations.calculateCoveragePercentage(washingtonPolygon, chart2Polygon);
      
      print('\\n📋 West Coast Chart 2 (Puget Sound area):');
      print('  Bounds: N:${westCoastChart2.north} S:${westCoastChart2.south} E:${westCoastChart2.east} W:${westCoastChart2.west}');
      print('  Intersects Washington: $chart2Intersects');
      print('  Coverage: ${(chart2Coverage * 100).toStringAsFixed(2)}%');
      print('  Meets threshold (>1%): ${chart2Coverage > 0.01}');
      
      // Test polygon conversion
      print('\\n🔧 POLYGON CONVERSION TEST:');
      print('Washington polygon vertices: ${washingtonPolygon.length}');
      for (int i = 0; i < washingtonPolygon.length; i++) {
        final vertex = washingtonPolygon[i];
        print('  Vertex $i: ${vertex.latitude}, ${vertex.longitude}');
      }
      
      // Check for degenerate polygons
      final isWashingtonDegenerate = washingtonPolygon.length < 3;
      final isChart1Degenerate = chart1Polygon.length < 3;
      final isChart2Degenerate = chart2Polygon.length < 3;
      
      print('\\n🚨 DEGENERATE POLYGON CHECK:');
      print('Washington polygon degenerate: $isWashingtonDegenerate');
      print('Chart 1 polygon degenerate: $isChart1Degenerate'); 
      print('Chart 2 polygon degenerate: $isChart2Degenerate');
      
      print('\\n🎯 DIAGNOSIS COMPLETE');
      print('If charts are not intersecting, possible causes:');
      print('1. Chart bounds data is (0,0,0,0) - invalid bounds');
      print('2. Spatial intersection algorithm issue');
      print('3. Coverage threshold too high (>1%)');
      print('4. Chart source filtering issue (only NOAA charts included)');
      
      // Basic assertions
      expect(isSeattleInWashington, isTrue, reason: 'Seattle should be in Washington');
      expect(washingtonPolygon.length, greaterThanOrEqualTo(3), reason: 'Washington polygon should have at least 3 vertices');
    });
    
    test('should test actual chart bounds extraction issue', () {
      print('\\n🔍 CHART BOUNDS EXTRACTION TEST');
      print('==============================');
      
      // Test common invalid bounds scenarios
      final invalidBounds1 = GeographicBounds(north: 0, south: 0, east: 0, west: 0);
      final invalidBounds2 = GeographicBounds(north: -1, south: 1, east: -1, west: 1); // Invalid (north < south)
      final validBounds = GeographicBounds(north: 48.0, south: 47.0, east: -122.0, west: -123.0);
      
      print('Testing invalid bounds (0,0,0,0):');
      try {
        final polygon1 = SpatialOperations.boundsToPolygon(invalidBounds1);
        print('  ✅ Polygon created: ${polygon1.length} vertices');
      } catch (e) {
        print('  ❌ Error creating polygon: $e');
      }
      
      print('\\nTesting invalid bounds (inverted):');
      try {
        final polygon2 = SpatialOperations.boundsToPolygon(invalidBounds2);
        print('  ✅ Polygon created: ${polygon2.length} vertices');
      } catch (e) {
        print('  ❌ Error creating polygon: $e');
      }
      
      print('\\nTesting valid bounds:');
      try {
        final polygon3 = SpatialOperations.boundsToPolygon(validBounds);
        print('  ✅ Polygon created: ${polygon3.length} vertices');
        for (int i = 0; i < polygon3.length; i++) {
          final vertex = polygon3[i];
          print('    Vertex $i: ${vertex.latitude}, ${vertex.longitude}');
        }
      } catch (e) {
        print('  ❌ Error creating polygon: $e');
      }
    });
  });
}
