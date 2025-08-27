// Chart Bounds Data Inspector Test
//
// This test directly inspects the chart bounds data from NOAA API
// to identify invalid bounds that cause spatial intersection to fail

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http/http_client_service_impl.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/logging/app_logger_impl.dart';

void main() {
  group('Chart Bounds Data Inspector', () {
    late NoaaApiClientImpl apiClient;

    setUp(() {
      final httpClient = HttpClientServiceImpl();
      final rateLimiter = RateLimiter(requestsPerSecond: 5);
      final logger = AppLoggerImpl();
      apiClient = NoaaApiClientImpl(
        httpClient: httpClient,
        rateLimiter: rateLimiter,
        logger: logger,
      );
    });

    test('should inspect all chart bounds from NOAA API', () async {
      print('\n🔍 CHART BOUNDS DATA INSPECTOR');
      print('=============================');
      
      // Fetch charts from NOAA API
      print('📡 Fetching chart catalog from NOAA API...');
      final catalogJson = await apiClient.fetchChartCatalog();
      final catalogData = jsonDecode(catalogJson);
      
      print('✅ Fetched chart catalog from NOAA API');
      print('📊 Response structure: ${catalogData.keys}');
      
      // Check if features exist
      if (catalogData['features'] == null) {
        print('❌ No features found in catalog response');
        return;
      }
      
      final features = catalogData['features'] as List;
      print('📊 Found ${features.length} features in catalog');
      
      int validCharts = 0;
      int invalidCharts = 0;
      int zeroCharts = 0;
      int missingGeometry = 0;
      
      print('\n📊 ANALYZING CHART BOUNDS:');
      print('──────────────────────────');
      
      for (int i = 0; i < features.length; i++) {
        final feature = features[i];
        print('\n📋 Feature ${i + 1}:');
        
        // Check if it has properties/attributes
        final properties = feature['properties'] ?? feature['attributes'];
        if (properties == null) {
          print('   ❌ ERROR: No properties or attributes found');
          invalidCharts++;
          continue;
        }
        
        final chartId = properties['DSNM'] ?? properties['CELL_NAME'] ?? 'Unknown';
        final title = properties['TITLE'] ?? properties['INFORM'] ?? 'Unknown Title';
        print('   Chart ID: $chartId');
        print('   Title: $title');
        
        // Check geometry
        final geometry = feature['geometry'];
        if (geometry == null) {
          print('   ⚠️  WARNING: No geometry found');
          missingGeometry++;
          invalidCharts++;
          continue;
        }
        
        print('   Geometry Type: ${geometry['type']}');
        
        // Try to extract bounds from geometry
        try {
          if (geometry['type'] == 'Polygon' && geometry['coordinates'] != null) {
            final coordinates = geometry['coordinates'][0] as List;
            
            double minLat = double.infinity;
            double maxLat = double.negativeInfinity;
            double minLon = double.infinity;
            double maxLon = double.negativeInfinity;
            
            for (final coord in coordinates) {
              final lon = (coord[0] as num).toDouble();
              final lat = (coord[1] as num).toDouble();
              
              minLat = minLat < lat ? minLat : lat;
              maxLat = maxLat > lat ? maxLat : lat;
              minLon = minLon < lon ? minLon : lon;
              maxLon = maxLon > lon ? maxLon : lon;
            }
            
            print('   Raw Bounds: N:$maxLat S:$minLat E:$maxLon W:$minLon');
            
            // Check for zero/invalid bounds
            if (maxLat == 0 && minLat == 0 && maxLon == 0 && minLon == 0) {
              print('   🚨 WARNING: All coordinates are zero (invalid bounds)');
              zeroCharts++;
              invalidCharts++;
              continue;
            }
            
            // Check for invalid coordinate relationships
            if (maxLat < minLat) {
              print('   🚨 WARNING: North ($maxLat) < South ($minLat)');
              invalidCharts++;
              continue;
            }
            
            if (maxLon < minLon) {
              print('   🚨 WARNING: East ($maxLon) < West ($minLon)');
              invalidCharts++;
              continue;
            }
            
            // Check for reasonable coordinate ranges
            if (maxLat > 90 || minLat < -90 || maxLon > 180 || minLon < -180) {
              print('   🚨 WARNING: Coordinates outside valid ranges');
              invalidCharts++;
              continue;
            }
            
            // Try to create GeographicBounds object
            try {
              final geoBounds = GeographicBounds(
                north: maxLat,
                south: minLat,
                east: maxLon,
                west: minLon,
              );
              print('   ✅ Valid bounds - GeographicBounds created successfully');
              validCharts++;
              
              // Check if this chart might cover Washington
              if (_mightCoverWashington(geoBounds)) {
                print('   🗺️  POTENTIAL WASHINGTON CHART!');
              }
            } catch (e) {
              print('   ❌ ERROR: Failed to create GeographicBounds: $e');
              invalidCharts++;
            }
          } else {
            print('   ⚠️  WARNING: Unsupported geometry type or missing coordinates');
            invalidCharts++;
          }
        } catch (e) {
          print('   ❌ ERROR: Failed to process geometry: $e');
          invalidCharts++;
        }
      }
      
      print('\n🎯 BOUNDS ANALYSIS SUMMARY:');
      print('═══════════════════════════');
      print('📊 Total features: ${features.length}');
      print('✅ Valid charts: $validCharts');
      print('❌ Invalid charts: $invalidCharts');
      print('🚨 Zero bounds charts: $zeroCharts');
      print('🗺️  Missing geometry: $missingGeometry');
      print('📈 Valid percentage: ${(validCharts / features.length * 100).toStringAsFixed(1)}%');
      
      if (invalidCharts > 0) {
        print('\n⚠️  PROBLEM IDENTIFIED:');
        print('   $invalidCharts features have invalid bounds data');
        print('   This explains why spatial intersection finds 0 Washington charts');
        print('   Solution: Filter out charts with invalid bounds before spatial intersection');
      } else {
        print('\n✅ ALL BOUNDS VALID:');
        print('   No invalid bounds found - issue must be elsewhere');
      }
    });
  });
}

/// Check if bounds might cover Washington state
bool _mightCoverWashington(GeographicBounds bounds) {
  final washingtonBounds = GeographicBounds(
    north: 49.0,
    south: 45.5,
    east: -116.9,
    west: -124.8,
  );
  
  // Simple bounding box overlap check
  return !(bounds.east < washingtonBounds.west ||
           bounds.west > washingtonBounds.east ||
           bounds.north < washingtonBounds.south ||
           bounds.south > washingtonBounds.north);
}

    test('should inspect all chart bounds from NOAA API', () async {
      print('\n🔍 CHART BOUNDS DATA INSPECTOR');
      print('=============================');
      
      // Fetch charts from NOAA API
      print('📡 Fetching chart catalog from NOAA API...');
      final charts = await apiClient.fetchChartCatalog();
      print('✅ Fetched ${charts.length} charts from NOAA API');
      
      int validCharts = 0;
      int invalidCharts = 0;
      int zeroCharts = 0;
      
      print('\n📊 ANALYZING CHART BOUNDS:');
      print('──────────────────────────');
      
      for (int i = 0; i < charts.length; i++) {
        final chart = charts[i];
        print('\n📋 Chart ${i + 1}: ${chart.cellName}');
        print('   Title: ${chart.title}');
        
        // Check if bounds exist
        if (chart.bounds == null) {
          print('   ❌ ERROR: No bounds data');
          invalidCharts++;
          continue;
        }
        
        final bounds = chart.bounds!;
        print('   Bounds: N:${bounds.north} S:${bounds.south} E:${bounds.east} W:${bounds.west}');
        
        // Check for zero/invalid bounds
        if (bounds.north == 0 && bounds.south == 0 && 
            bounds.east == 0 && bounds.west == 0) {
          print('   🚨 WARNING: All coordinates are zero (invalid bounds)');
          zeroCharts++;
          invalidCharts++;
          continue;
        }
        
        // Check for invalid coordinate relationships
        if (bounds.north < bounds.south) {
          print('   🚨 WARNING: North (${bounds.north}) < South (${bounds.south})');
          invalidCharts++;
          continue;
        }
        
        if (bounds.east < bounds.west) {
          print('   🚨 WARNING: East (${bounds.east}) < West (${bounds.west})');
          invalidCharts++;
          continue;
        }
        
        // Check for reasonable coordinate ranges
        if (bounds.north > 90 || bounds.south < -90 ||
            bounds.east > 180 || bounds.west < -180) {
          print('   🚨 WARNING: Coordinates outside valid ranges');
          invalidCharts++;
          continue;
        }
        
        // Try to create GeographicBounds object
        try {
          final geoBounds = GeographicBounds(
            north: bounds.north,
            south: bounds.south,
            east: bounds.east,
            west: bounds.west,
          );
          print('   ✅ Valid bounds - GeographicBounds created successfully');
          validCharts++;
        } catch (e) {
          print('   ❌ ERROR: Failed to create GeographicBounds: $e');
          invalidCharts++;
        }
      }
      
      print('\n🎯 BOUNDS ANALYSIS SUMMARY:');
      print('═══════════════════════════');
      print('📊 Total charts: ${charts.length}');
      print('✅ Valid charts: $validCharts');
      print('❌ Invalid charts: $invalidCharts');
      print('🚨 Zero bounds charts: $zeroCharts');
      print('📈 Valid percentage: ${(validCharts / charts.length * 100).toStringAsFixed(1)}%');
      
      if (invalidCharts > 0) {
        print('\n⚠️  PROBLEM IDENTIFIED:');
        print('   ${invalidCharts} charts have invalid bounds data');
        print('   This explains why spatial intersection finds 0 Washington charts');
        print('   Solution: Filter out charts with invalid bounds before spatial intersection');
      } else {
        print('\n✅ ALL BOUNDS VALID:');
        print('   No invalid bounds found - issue must be elsewhere');
      }
    });

    test('should test Washington state specific charts', () async {
      print('\n🔍 WASHINGTON STATE CHART ANALYSIS');
      print('===================================');
      
      // Fetch charts
      final charts = await apiClient.fetchChartCatalog();
      
      // Look for charts that might cover Washington state
      print('🔎 Searching for charts that might cover Washington state...');
      print('   Washington bounds: N:49.0 S:45.5 E:-116.9 W:-124.8');
      
      final washingtonBounds = GeographicBounds(
        north: 49.0,
        south: 45.5,
        east: -116.9,
        west: -124.8,
      );
      
      int potentialWashingtonCharts = 0;
      
      for (final chart in charts) {
        if (chart.bounds == null) continue;
        
        final bounds = chart.bounds!;
        
        // Skip invalid bounds
        if (bounds.north == 0 && bounds.south == 0 && 
            bounds.east == 0 && bounds.west == 0) {
          continue;
        }
        
        if (bounds.north < bounds.south || bounds.east < bounds.west) {
          continue;
        }
        
        try {
          final chartBounds = GeographicBounds(
            north: bounds.north,
            south: bounds.south,
            east: bounds.east,
            west: bounds.west,
          );
          
          // Check if chart might intersect Washington
          // Simple bounding box overlap check
          bool mightIntersect = !(
            chartBounds.east < washingtonBounds.west ||
            chartBounds.west > washingtonBounds.east ||
            chartBounds.north < washingtonBounds.south ||
            chartBounds.south > washingtonBounds.north
          );
          
          if (mightIntersect) {
            potentialWashingtonCharts++;
            print('\n📋 Potential Washington Chart: ${chart.cellName}');
            print('   Title: ${chart.title}');
            print('   Bounds: N:${bounds.north} S:${bounds.south} E:${bounds.east} W:${bounds.west}');
            print('   ✅ Bounding box overlaps Washington');
          }
        } catch (e) {
          // Skip charts that can't create valid GeographicBounds
          continue;
        }
      }
      
      print('\n🎯 WASHINGTON ANALYSIS SUMMARY:');
      print('═══════════════════════════════');
      print('📊 Potential Washington charts: $potentialWashingtonCharts');
      
      if (potentialWashingtonCharts == 0) {
        print('⚠️  NO WASHINGTON CHARTS FOUND:');
        print('   No charts have bounds that overlap with Washington state');
        print('   This confirms the spatial intersection issue');
      } else {
        print('✅ FOUND POTENTIAL WASHINGTON CHARTS:');
        print('   $potentialWashingtonCharts charts might cover Washington');
        print('   Issue may be in spatial intersection implementation');
      }
    });
  });
}
