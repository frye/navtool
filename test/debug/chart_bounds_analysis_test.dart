@Skip('Excluded from CI: exploratory debug analysis test')
import 'package:flutter_test/flutter_test.dart';
/// Test to check what chart bounds are actually being cached from NOAA API
void main() {
  group('Chart Bounds Analysis', () {
    test('should analyze typical chart bounds patterns', () {
      print('\\n🔍 CHART BOUNDS ANALYSIS');
      print('=========================');
      
      // Patterns we've seen in the application logs for West Coast charts
      final charts = [
        {'id': 'US1WC01M.000', 'name': 'West Coast Chart 1'},
        {'id': 'US1WC04M.000', 'name': 'West Coast Chart 4'},
        {'id': 'US1WC07M.000', 'name': 'West Coast Chart 7'},
        {'id': 'US1AK90M.000', 'name': 'Alaska Chart'},
        {'id': 'US1PO02M.000', 'name': 'Pacific Ocean Chart'},
      ];
      
      print('📋 Charts found in application logs:');
      for (final chart in charts) {
        print('  - ${chart['id']}: ${chart['name']}');
      }
      
      // Test common scenarios for invalid bounds
      print('\\n🚨 INVALID BOUNDS SCENARIOS:');
      
      // Scenario 1: All zeros
      print('1. All zeros (0,0,0,0):');
      try {
        final bounds1 = GeographicBounds(north: 0, south: 0, east: 0, west: 0);
        print('   ✅ Created: N:${bounds1.north} S:${bounds1.south} E:${bounds1.east} W:${bounds1.west}');
        print('   📐 Area: ${_calculateArea(bounds1)}');
      } catch (e) {
        print('   ❌ Error: $e');
      }
      
      // Scenario 2: Invalid ordering (north < south, etc.)
      print('\\n2. Invalid ordering (north < south):');
      try {
        final bounds2 = GeographicBounds(north: 45.0, south: 49.0, east: -120.0, west: -125.0);
        print('   ❌ This should fail validation');
      } catch (e) {
        print('   ✅ Correctly rejected: $e');
      }
      
      // Scenario 3: Point coordinates (no area)
      print('\\n3. Point coordinates (same lat/lng):');
      try {
        final bounds3 = GeographicBounds(north: 47.6062, south: 47.6062, east: -122.3321, west: -122.3321);
        print('   ✅ Created: N:${bounds3.north} S:${bounds3.south} E:${bounds3.east} W:${bounds3.west}');
        print('   📐 Area: ${_calculateArea(bounds3)}');
      } catch (e) {
        print('   ❌ Error: $e');
      }
      
      // Valid Washington area bounds for comparison
      print('\\n✅ VALID BOUNDS FOR COMPARISON:');
      final washingtonBounds = GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8);
      print('Washington state: N:${washingtonBounds.north} S:${washingtonBounds.south} E:${washingtonBounds.east} W:${washingtonBounds.west}');
      print('Area: ${_calculateArea(washingtonBounds)}');
      
      // Typical chart bounds in Washington waters
      final pugetsoundBounds = GeographicBounds(north: 48.5, south: 47.0, east: -122.0, west: -123.5);
      print('Puget Sound area: N:${pugetsoundBounds.north} S:${pugetsoundBounds.south} E:${pugetsoundBounds.east} W:${pugetsoundBounds.west}');
      print('Area: ${_calculateArea(pugetsoundBounds)}');
      
      print('\\n🎯 CONCLUSION:');
      print('Charts with invalid bounds (0,0,0,0) or point coordinates will not intersect with state polygons.');
      print('This explains why 18 charts are cached but 0 charts are found for Washington spatial intersection.');
      print('The issue is likely that NOAA API is returning charts with placeholder/invalid geometry data.');
    });
    
    test('should demonstrate the spatial intersection threshold', () {
      print('\\n🔍 SPATIAL INTERSECTION THRESHOLD ANALYSIS');
      print('==========================================');
      
      final washingtonBounds = GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8);
      
      // Different chart sizes to test coverage thresholds
      final charts = [
        {
          'name': 'Tiny chart (should fail)',
          'bounds': GeographicBounds(north: 47.1, south: 47.0, east: -122.1, west: -122.2),
        },
        {
          'name': 'Small chart (might pass)',
          'bounds': GeographicBounds(north: 48.0, south: 47.0, east: -122.0, west: -123.0),
        },
        {
          'name': 'Large chart (should pass)',
          'bounds': GeographicBounds(north: 50.0, south: 45.0, east: -120.0, west: -125.0),
        },
      ];
      
      print('Testing coverage threshold of 1% (0.01):');
      for (final chart in charts) {
        final chartBounds = chart['bounds'] as GeographicBounds;
        final coverage = _calculateCoverageEstimate(washingtonBounds, chartBounds);
        final passesThreshold = coverage > 0.01;
        
        print('\\n📋 ${chart['name']}:');
        print('   Bounds: N:${chartBounds.north} S:${chartBounds.south} E:${chartBounds.east} W:${chartBounds.west}');
        print('   Estimated coverage: ${(coverage * 100).toStringAsFixed(2)}%');
        print('   Passes threshold: $passesThreshold');
      }
      
      print('\\n💡 INSIGHT:');
  print("Even valid charts might fail if they're too small relative to the state area.");
      print('Consider lowering the threshold for detailed harbor/approach charts.');
    });
  });
}

/// Calculate rough area of geographic bounds (not precise, just for comparison)
double _calculateArea(GeographicBounds bounds) {
  final latDiff = bounds.north - bounds.south;
  final lonDiff = bounds.east - bounds.west;
  return (latDiff * lonDiff).abs(); // Simple rectangular area
}

/// Estimate coverage percentage (simplified calculation)
double _calculateCoverageEstimate(GeographicBounds stateBounds, GeographicBounds chartBounds) {
  // Simple rectangular intersection calculation
  final intersectionNorth = [stateBounds.north, chartBounds.north].reduce((a, b) => a < b ? a : b);
  final intersectionSouth = [stateBounds.south, chartBounds.south].reduce((a, b) => a > b ? a : b);
  final intersectionEast = [stateBounds.east, chartBounds.east].reduce((a, b) => a < b ? a : b);
  final intersectionWest = [stateBounds.west, chartBounds.west].reduce((a, b) => a > b ? a : b);
  
  if (intersectionNorth <= intersectionSouth || intersectionEast <= intersectionWest) {
    return 0.0; // No intersection
  }
  
  final intersectionArea = (intersectionNorth - intersectionSouth) * (intersectionEast - intersectionWest);
  final stateArea = _calculateArea(stateBounds);
  
  return intersectionArea / stateArea;
}
