import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/logging/app_logger.dart';

import '../../utils/test_mocks.dart';

void main() {
  group('NOAA Chart Bounds Debug Tests', () {
    late NoaaChartDiscoveryServiceImpl discoveryService;
    late ChartCatalogService mockCatalogService;
    late StateRegionMappingService mockMappingService;  
    late StorageService mockStorageService;
    late AppLogger mockLogger;

    setUp(() {
      mockCatalogService = createMockChartCatalogService();
      mockMappingService = createMockStateRegionMappingService();
      mockStorageService = createMockStorageService();
      mockLogger = createMockAppLogger();
      
      discoveryService = NoaaChartDiscoveryServiceImpl(
        catalogService: mockCatalogService,
        mappingService: mockMappingService, 
        storageService: mockStorageService,
        logger: mockLogger,
      );
    });

    test('should fetch real NOAA chart catalog and analyze bounds for Washington coverage', () async {
      // Act - Fetch real NOAA data
      final charts = await apiClient.fetchChartCatalog();
      
      print('=== NOAA CHART BOUNDS DEBUG ===');
      print('Total charts fetched: ${charts.length}');
      print('');
      
      // Washington state bounds for reference
      final washingtonBounds = GeographicBounds(
        north: 49.0, south: 45.5, east: -116.9, west: -124.8
      );
      
      print('Washington State Bounds:');
      print('  North: ${washingtonBounds.north}, South: ${washingtonBounds.south}');
      print('  East: ${washingtonBounds.east}, West: ${washingtonBounds.west}');
      print('');
      
      // Analyze each chart
      var washingtonCharts = <String>[];
      var westCoastCharts = <String>[];
      var chartsWithInvalidBounds = <String>[];
      
      for (final chart in charts) {
        print('Chart: ${chart.id} - ${chart.title}');
        print('  Bounds: N=${chart.bounds.north}, S=${chart.bounds.south}, E=${chart.bounds.east}, W=${chart.bounds.west}');
        print('  State: ${chart.state}, Type: ${chart.type}, Scale: ${chart.scale}');
        
        // Check for invalid bounds
        if (chart.bounds.north == 0 && chart.bounds.south == 0 && 
            chart.bounds.east == 0 && chart.bounds.west == 0) {
          chartsWithInvalidBounds.add(chart.id);
          print('  ❌ INVALID BOUNDS (0,0,0,0)');
        }
        
        // Check if it intersects with Washington
        final intersectsWashington = _boundsIntersect(chart.bounds, washingtonBounds);
        if (intersectsWashington) {
          washingtonCharts.add(chart.id);
          print('  ✅ INTERSECTS WASHINGTON');
        }
        
        // Check if it's a West Coast chart
        if (chart.id.contains('WC') || chart.title.toLowerCase().contains('washington') || 
            chart.title.toLowerCase().contains('puget') || chart.title.toLowerCase().contains('columbia')) {
          westCoastCharts.add(chart.id);
          print('  🌊 WEST COAST CHART');
        }
        
        print('');
      }
      
      print('=== SUMMARY ===');
      print('Charts with invalid bounds (0,0,0,0): ${chartsWithInvalidBounds.length}');
      chartsWithInvalidBounds.forEach((id) => print('  - $id'));
      print('');
      
      print('Charts intersecting Washington: ${washingtonCharts.length}');
      washingtonCharts.forEach((id) => print('  - $id'));
      print('');
      
      print('Potential West Coast charts: ${westCoastCharts.length}');
      westCoastCharts.forEach((id) => print('  - $id'));
      print('');
      
      // Test specific charts that should cover Washington
      final targetCharts = ['US1WC01M', 'US1WC04M', 'US1WC07M'];
      for (final chartId in targetCharts) {
        final chart = charts.firstWhere((c) => c.id == chartId, orElse: () => throw Exception('Chart $chartId not found'));
        print('Target Chart Analysis: $chartId');
        print('  Title: ${chart.title}');
        print('  Bounds: N=${chart.bounds.north}, S=${chart.bounds.south}, E=${chart.bounds.east}, W=${chart.bounds.west}');
        print('  Should cover Washington coordinates (47.6062, -122.3321): ${_pointInBounds(47.6062, -122.3321, chart.bounds)}');
        print('  Intersects Washington state: ${_boundsIntersect(chart.bounds, washingtonBounds)}');
        print('');
      }
      
      // Assert that we understand the data
      expect(charts.length, greaterThan(0), reason: 'Should fetch some charts from NOAA');
      expect(chartsWithInvalidBounds.length, equals(0), reason: 'Current NOAA data should have valid bounds');
      
      // This test documents what we found - might fail if NOAA data doesn't cover Washington
      print('🔍 DIAGNOSTIC COMPLETE - Check output above for Washington chart coverage analysis');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

// Helper function to check if two geographic bounds intersect
bool _boundsIntersect(GeographicBounds bounds1, GeographicBounds bounds2) {
  return !(bounds1.east < bounds2.west || 
           bounds1.west > bounds2.east || 
           bounds1.north < bounds2.south || 
           bounds1.south > bounds2.north);
}

// Helper function to check if a point is within bounds
bool _pointInBounds(double lat, double lon, GeographicBounds bounds) {
  return lat >= bounds.south && lat <= bounds.north && 
         lon >= bounds.west && lon <= bounds.east;
}
