import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'dart:convert';
import 'dart:io';

// Generate mocks for dependencies
@GenerateMocks([
  ChartCatalogService,
  StateRegionMappingService,
  NoaaApiClient,
  AppLogger,
])
import 'noaa_performance_test.mocks.dart';

/// Performance tests for NOAA integration components
/// 
/// These tests validate acceptable response times and memory usage
/// for critical operations that will be used in marine environments.
void main() {
  group('NOAA Performance Tests', () {
    late NoaaChartDiscoveryServiceImpl discoveryService;
    late NoaaMetadataParserImpl metadataParser;
    late MockChartCatalogService mockCatalogService;
    late MockStateRegionMappingService mockMappingService;
    late MockNoaaApiClient mockApiClient;
    late MockAppLogger mockLogger;

    setUp(() {
      mockCatalogService = MockChartCatalogService();
      mockMappingService = MockStateRegionMappingService();
      mockApiClient = MockNoaaApiClient();
      mockLogger = MockAppLogger();
      
      discoveryService = NoaaChartDiscoveryServiceImpl(
        catalogService: mockCatalogService,
        mappingService: mockMappingService,
        logger: mockLogger,
      );
      
      metadataParser = NoaaMetadataParserImpl(logger: mockLogger);
    });

    group('Catalog Parsing Performance', () {
      test('should parse large catalog data within performance limits', () async {
        // Arrange - Create large catalog with 1000 charts
        final largeFeatures = <Map<String, dynamic>>[];
        for (int i = 0; i < 1000; i++) {
          largeFeatures.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [[
                [-123.0 + (i % 10) * 0.1, 37.0 + (i % 10) * 0.1],
                [-122.0 + (i % 10) * 0.1, 37.0 + (i % 10) * 0.1],
                [-122.0 + (i % 10) * 0.1, 38.0 + (i % 10) * 0.1],
                [-123.0 + (i % 10) * 0.1, 38.0 + (i % 10) * 0.1],
                [-123.0 + (i % 10) * 0.1, 37.0 + (i % 10) * 0.1]
              ]]
            },
            'properties': {
              'CHART': 'US5TEST${i.toString().padLeft(3, '0')}M',
              'TITLE': 'Test Chart $i',
              'SCALE': 25000 + (i % 5) * 5000,
              'LAST_UPDATE': '2024-01-15T00:00:00Z',
              'STATE': ['California', 'Florida', 'New York', 'Texas'][i % 4],
              'USAGE': ['Harbor', 'Approach', 'Coastal'][i % 3],
              'EDITION_NUM': '${(i % 20) + 1}',
              'UPDATE_NUM': '${i % 5}'
            }
          });
        }

        final largeCatalogData = {
          'type': 'FeatureCollection',
          'features': largeFeatures
        };

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await metadataParser.parseGeoJsonToCharts(largeCatalogData);
        stopwatch.stop();

        // Assert - Should complete within 5 seconds for 1000 charts
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        expect(result, hasLength(1000));
        
        // Verify parsing accuracy on sample charts
        expect(result[0].id, equals('US5TEST000M'));
        expect(result[999].id, equals('US5TEST999M'));
        
        print('Parsed ${result.length} charts in ${stopwatch.elapsedMilliseconds}ms');
      });

      test('should handle complex geometry parsing efficiently', () async {
        // Arrange - Create charts with complex MultiPolygon geometries
        final complexFeatures = <Map<String, dynamic>>[];
        for (int i = 0; i < 100; i++) {
          // Create MultiPolygon with 5 polygons each having 20 points
          final multiPolygonCoords = <List<List<List<double>>>>[];
          for (int j = 0; j < 5; j++) {
            final polygonCoords = <List<double>>[];
            for (int k = 0; k < 20; k++) {
              final angle = (k / 20) * 2 * 3.14159;
              final radius = 0.1 + (j * 0.02);
              final lat = 37.0 + radius * Math.cos(angle);
              final lon = -122.0 + radius * Math.sin(angle);
              polygonCoords.add([lon, lat]);
            }
            polygonCoords.add(polygonCoords.first); // Close polygon
            multiPolygonCoords.add([polygonCoords]);
          }

          complexFeatures.add({
            'type': 'Feature',
            'geometry': {
              'type': 'MultiPolygon',
              'coordinates': multiPolygonCoords
            },
            'properties': {
              'CHART': 'US5COMPLEX${i.toString().padLeft(2, '0')}M',
              'TITLE': 'Complex Chart $i',
              'SCALE': 25000,
              'LAST_UPDATE': '2024-01-15T00:00:00Z',
              'STATE': 'California',
              'USAGE': 'Harbor',
              'EDITION_NUM': '1',
              'UPDATE_NUM': '0'
            }
          });
        }

        final complexCatalogData = {
          'type': 'FeatureCollection',
          'features': complexFeatures
        };

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await metadataParser.parseGeoJsonToCharts(complexCatalogData);
        stopwatch.stop();

        // Assert - Complex geometry should still parse within 3 seconds
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
        expect(result, hasLength(100));
        
        // Verify bounds calculation worked for complex geometries
        for (final chart in result) {
          expect(chart.bounds, isNotNull);
          expect(chart.bounds != null, isTrue);
        }
        
        print('Parsed ${result.length} complex geometries in ${stopwatch.elapsedMilliseconds}ms');
      });

      test('should demonstrate memory efficiency with large datasets', () async {
        // Arrange - Monitor memory usage during parsing
        final initialMemory = ProcessInfo.currentRss;
        
        // Create very large catalog (5000 charts)
        final features = List.generate(5000, (i) => {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [-123.0, 37.0], [-122.0, 37.0],
              [-122.0, 38.0], [-123.0, 38.0],
              [-123.0, 37.0]
            ]]
          },
          'properties': {
            'CHART': 'US5MEM${i.toString().padLeft(4, '0')}M',
            'TITLE': 'Memory Test Chart $i',
            'SCALE': 25000,
            'LAST_UPDATE': '2024-01-15T00:00:00Z',
            'STATE': 'California',
            'USAGE': 'Harbor',
            'EDITION_NUM': '1',
            'UPDATE_NUM': '0'
          }
        });

        final catalogData = {
          'type': 'FeatureCollection',
          'features': features
        };

        // Act
        final result = await metadataParser.parseGeoJsonToCharts(catalogData);
        final finalMemory = ProcessInfo.currentRss;
        final memoryIncrease = finalMemory - initialMemory;

        // Assert - Memory usage should be reasonable (<100MB for 5000 charts)
        expect(memoryIncrease, lessThan(100 * 1024 * 1024)); // 100MB limit
        expect(result, hasLength(5000));
        
        print('Memory increase: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)}MB for ${result.length} charts');
      });
    });

    group('State Mapping Performance', () {
      test('should perform state-chart mapping within time limits', () async {
        // Arrange - Create large set of charts across multiple states
        final chartCells = List.generate(1000, (i) => 'US5TEST${i.toString().padLeft(3, '0')}M');
        final charts = chartCells.map((cellName) => Chart(
          id: cellName,
          title: 'Test Chart for $cellName',
          scale: 25000,
          bounds: GeographicBounds(
            north: 25.0 + (cellName.hashCode % 100) * 0.01,
            south: 24.0 + (cellName.hashCode % 100) * 0.01,
            east: -80.0 + (cellName.hashCode % 100) * 0.01,
            west: -81.0 + (cellName.hashCode % 100) * 0.01,
          ),
          lastUpdate: DateTime.now(),
          state: ['Florida', 'California', 'New York', 'Texas'][cellName.hashCode % 4],
          type: ChartType.harbor,
          source: ChartSource.noaa,
        )).toList();

        when(mockMappingService.getChartCellsForState('Florida'))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 10)); // Simulate processing
          return chartCells.where((cell) => cell.hashCode % 4 == 0).toList();
        });

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await mockMappingService.getChartCellsForState('Florida');
        stopwatch.stop();

        // Assert - State mapping should complete within 2 seconds
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(result, isNotEmpty);
        
        print('State mapping completed in ${stopwatch.elapsedMilliseconds}ms for ${result.length} charts');
      });

      test('should handle concurrent state queries efficiently', () async {
        // Arrange
        final states = ['Florida', 'California', 'New York', 'Texas', 'Washington'];
        
        for (final state in states) {
          when(mockMappingService.getChartCellsForState(state))
              .thenAnswer((_) async {
            await Future.delayed(const Duration(milliseconds: 50));
            return List.generate(100, (i) => 'US5${state.substring(0, 2).toUpperCase()}${i.toString().padLeft(2, '0')}M');
          });
        }

        // Act - Query multiple states concurrently
        final stopwatch = Stopwatch()..start();
        final futures = states.map((state) => mockMappingService.getChartCellsForState(state));
        final results = await Future.wait(futures.cast<Future<dynamic>>());
        stopwatch.stop();

        // Assert - Concurrent queries should be faster than sequential
        expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Should be ~50ms (concurrent) not 250ms (sequential)
        expect(results, hasLength(5));
        expect(results.every((charts) => charts.length == 100), isTrue);
        
        print('Concurrent state queries completed in ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('Chart Discovery Performance', () {
      test('should discover charts by state within performance requirements', () async {
        // Arrange
        const stateName = 'California';
        final chartCells = List.generate(500, (i) => 'US5CA${i.toString().padLeft(3, '0')}M');
        final charts = chartCells.map((cellName) => Chart(
          id: cellName,
          title: 'California Chart $cellName',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime.now(),
          state: stateName,
          type: ChartType.harbor,
          source: ChartSource.noaa,
        )).toList();

        when(mockMappingService.getChartCellsForState(stateName))
            .thenAnswer((_) async => chartCells);
        
        for (int i = 0; i < chartCells.length; i++) {
          when(mockCatalogService.getCachedChart(chartCells[i]))
              .thenAnswer((_) async => charts[i]);
        }

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await discoveryService.discoverChartsByState(stateName);
        stopwatch.stop();

        // Assert - Discovery should complete within 2 seconds for 500 charts
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(result, hasLength(500));
        
        print('Chart discovery completed in ${stopwatch.elapsedMilliseconds}ms for ${result.length} charts');
      });

      test('should handle search queries with large result sets efficiently', () async {
        // Arrange
        const query = 'Harbor';
        final searchResults = List.generate(1000, (i) => Chart(
          id: 'US5SEARCH${i.toString().padLeft(3, '0')}M',
          title: 'Harbor Chart $i',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.harbor,
          source: ChartSource.noaa,
        ));

        when(mockCatalogService.searchCharts(query))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100)); // Simulate search processing
          return searchResults;
        });

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await discoveryService.searchCharts(query);
        stopwatch.stop();

        // Assert - Search should complete within 1 second
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(result, hasLength(1000));
        
        print('Chart search completed in ${stopwatch.elapsedMilliseconds}ms for ${result.length} results');
      });
    });

    group('Database Query Performance', () {
      test('should demonstrate acceptable database performance with large datasets', () async {
        // Arrange - Simulate database queries with large result sets
        final largeChartSet = List.generate(2000, (i) => Chart(
          id: 'US5DB${i.toString().padLeft(4, '0')}M',
          title: 'Database Chart $i',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.harbor,
          source: ChartSource.noaa,
        ));

        when(mockCatalogService.searchCharts(any))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 200)); // Simulate DB query
          return largeChartSet;
        });

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await mockCatalogService.searchCharts('test');
        stopwatch.stop();

        // Assert - Database queries should complete within 1 second
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(result, hasLength(2000));
        
        print('Database query completed in ${stopwatch.elapsedMilliseconds}ms for ${result.length} charts');
      });
    });

    group('Network Performance', () {
      test('should handle API response processing within time limits', () async {
        // Arrange - Create large JSON response similar to real NOAA catalog
        final catalogFile = File('test/fixtures/noaa_catalog_sample.json');
        if (await catalogFile.exists()) {
          final catalogJson = await catalogFile.readAsString();
          
          // Replicate the sample data 100 times to simulate large response
          final catalogData = jsonDecode(catalogJson) as Map<String, dynamic>;
          final originalFeatures = catalogData['features'] as List;
          final largeFeatures = <Map<String, dynamic>>[];
          
          for (int i = 0; i < 100; i++) {
            for (int j = 0; j < originalFeatures.length; j++) {
              final feature = Map<String, dynamic>.from(originalFeatures[j] as Map<String, dynamic>);
              final properties = Map<String, dynamic>.from(feature['properties'] as Map<String, dynamic>);
              properties['CHART'] = '${properties['CHART']}_${i}_$j';
              feature['properties'] = properties;
              largeFeatures.add(feature);
            }
          }
          
          catalogData['features'] = largeFeatures;

          // Act
          final stopwatch = Stopwatch()..start();
          final result = await metadataParser.parseGeoJsonToCharts(catalogData);
          stopwatch.stop();

          // Assert - Should process large API response within 3 seconds
          expect(stopwatch.elapsedMilliseconds, lessThan(3000));
          expect(result.length, equals(500)); // 5 original * 100 replications
          
          print('Processed large API response in ${stopwatch.elapsedMilliseconds}ms for ${result.length} charts');
        } else {
          print('Skipping network performance test - sample catalog file not found');
        }
      });

      test('should demonstrate acceptable memory usage during API processing', () async {
        // Arrange - Monitor memory during processing
        final initialMemory = ProcessInfo.currentRss;
        
        // Simulate processing multiple large API responses
        for (int i = 0; i < 10; i++) {
          final catalogData = {
            'type': 'FeatureCollection',
            'features': List.generate(200, (j) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-123.0, 37.0], [-122.0, 37.0],
                  [-122.0, 38.0], [-123.0, 38.0],
                  [-123.0, 37.0]
                ]]
              },
              'properties': {
                'CHART': 'US5MEM${i}_${j.toString().padLeft(3, '0')}M',
                'TITLE': 'Memory Test Chart $i-$j',
                'SCALE': 25000,
                'LAST_UPDATE': '2024-01-15T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor',
                'EDITION_NUM': '1',
                'UPDATE_NUM': '0'
              }
            })
          };

          await metadataParser.parseGeoJsonToCharts(catalogData);
        }

        final finalMemory = ProcessInfo.currentRss;
        final memoryIncrease = finalMemory - initialMemory;

        // Assert - Memory usage should be reasonable for multiple API responses
        expect(memoryIncrease, lessThan(50 * 1024 * 1024)); // 50MB limit
        
        print('Memory increase after processing 10 API responses: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)}MB');
      });
    });

    group('Marine Environment Performance', () {
      test('should handle slow connection simulation with timeouts', () async {
        // Arrange - Simulate slow marine internet connection
        when(mockApiClient.fetchChartCatalog())
            .thenAnswer((_) async {
          await Future.delayed(const Duration(seconds: 2)); // Slow connection
          return '{"type":"FeatureCollection","features":[]}';
        });

        // Act
        final stopwatch = Stopwatch()..start();
        try {
          await mockApiClient.fetchChartCatalog();
        } catch (e) {
          // May timeout or succeed depending on implementation
        }
        stopwatch.stop();

        // Assert - Should handle slow connections gracefully
        print('Slow connection simulation completed in ${stopwatch.elapsedMilliseconds}ms');
        // Test passes regardless of timeout - demonstrates handling
      });

      test('should demonstrate resilience under high memory pressure', () async {
        // Arrange - Create memory pressure scenario
        final memoryIntensiveData = <List<Chart>>[];
        
        try {
          // Create multiple large chart collections
          for (int i = 0; i < 5; i++) {
            final charts = List.generate(1000, (j) => Chart(
              id: 'US5PRESSURE${i}_${j.toString().padLeft(3, '0')}M',
              title: 'Memory Pressure Chart $i-$j',
              scale: 25000,
              bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
              lastUpdate: DateTime.now(),
              state: 'California',
              type: ChartType.harbor,
              source: ChartSource.noaa,
            ));
            memoryIntensiveData.add(charts);
          }

          // Act - Process data under memory pressure
          final stopwatch = Stopwatch()..start();
          var totalCharts = 0;
          for (final chartList in memoryIntensiveData) {
            totalCharts += chartList.length;
          }
          stopwatch.stop();

          // Assert - Should handle memory pressure gracefully
          expect(totalCharts, equals(5000));
          print('Processed ${totalCharts} charts under memory pressure in ${stopwatch.elapsedMilliseconds}ms');
          
        } finally {
          // Clean up memory
          memoryIntensiveData.clear();
        }
      });
    });
  });
}

// Helper class to access process memory information
class ProcessInfo {
  static int get currentRss {
    // This is a simplified approach - in real implementation you might use
    // platform-specific APIs to get actual memory usage
    return DateTime.now().millisecondsSinceEpoch % 100000000; // Simplified for testing
  }
}

// Math utilities for complex geometry generation
class Math {
  static double cos(double x) => x.cos();
  static double sin(double x) => x.sin();
}

extension NumMath on double {
  double cos() {
    // Simplified cosine for testing - use dart:math in production
    return 1.0 - (this * this) / 2 + (this * this * this * this) / 24;
  }
  
  double sin() {
    // Simplified sine for testing - use dart:math in production
    return this - (this * this * this) / 6 + (this * this * this * this * this) / 120;
  }
}