import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';

import 'database_storage_service_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([AppLogger])
void main() {
  group('DatabaseStorageService Tests', () {
    late DatabaseStorageService storageService;
    late MockAppLogger mockLogger;
    late Database database;

    setUpAll(() {
      // SQLite FFI is now initialized globally in flutter_test_config.dart
    });

    setUp(() async {
      mockLogger = MockAppLogger();
      
      // Create in-memory database for testing
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // This will be implemented by the service
        },
      );
      
      storageService = DatabaseStorageService(
        logger: mockLogger,
        testDatabase: database,
      );
      
      await storageService.initialize();
    });

    tearDown(() async {
      await database.close();
    });

    group('Database Initialization', () {
      test('should initialize database with correct schema', () async {
        // Arrange & Act
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        
        final views = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='view'",
        );
        
        // Assert
        final tableNames = tables.map((t) => t['name'] as String).toList();
        final viewNames = views.map((v) => v['name'] as String).toList();
        
        expect(tableNames, contains('charts'));
        expect(tableNames, contains('routes'));
        expect(tableNames, contains('waypoints'));
        expect(tableNames, contains('download_queue'));
        expect(viewNames, contains('chart_metadata'));
      });

      test('should create proper indexes for performance', () async {
        // Arrange & Act
        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index'",
        );
        
        // Assert
        final indexNames = indexes.map((i) => i['name'] as String).toList();
        expect(indexNames, contains('idx_charts_bounds'));
        expect(indexNames, contains('idx_charts_scale'));
        expect(indexNames, contains('idx_waypoints_route_id'));
        expect(indexNames, contains('idx_download_queue_status'));
      });

      test('should handle database migrations', () async {
        // Test will verify migration system works
        expect(await storageService.getDatabaseVersion(), equals(1));
      });
    });

    group('Chart Storage Operations', () {
      test('should store chart with metadata', () async {
        // Arrange
        final chart = _createTestChart();
        final chartData = List<int>.generate(1000, (i) => i % 256);

        // Act
        await storageService.storeChart(chart, chartData);

        // Assert
        final storedData = await storageService.loadChart(chart.id);
        expect(storedData, isNotNull);
        expect(storedData!.length, equals(chartData.length));
        expect(storedData, equals(chartData));
      });

      test('should retrieve chart metadata', () async {
        // Arrange
        final chart = _createTestChart();
        final chartData = List<int>.generate(500, (i) => i % 256);
        await storageService.storeChart(chart, chartData);

        // Act
        final retrievedChart = await storageService.getChartMetadata(chart.id);

        // Assert
        expect(retrievedChart, isNotNull);
        expect(retrievedChart!.id, equals(chart.id));
        expect(retrievedChart.title, equals(chart.title));
        expect(retrievedChart.scale, equals(chart.scale));
        expect(retrievedChart.bounds.north, equals(chart.bounds.north));
      });

      test('should update chart metadata', () async {
        // Arrange
        final chart = _createTestChart();
        final chartData = List<int>.generate(500, (i) => i % 256);
        await storageService.storeChart(chart, chartData);

        final updatedChart = chart.copyWith(
          title: 'Updated Chart Title',
          lastUpdate: DateTime.now(),
        );

        // Act
        await storageService.updateChartMetadata(updatedChart);

        // Assert
        final retrievedChart = await storageService.getChartMetadata(chart.id);
        expect(retrievedChart!.title, equals('Updated Chart Title'));
      });

      test('should delete chart and its data', () async {
        // Arrange
        final chart = _createTestChart();
        final chartData = List<int>.generate(500, (i) => i % 256);
        await storageService.storeChart(chart, chartData);

        // Act
        await storageService.deleteChart(chart.id);

        // Assert
        final storedData = await storageService.loadChart(chart.id);
        expect(storedData, isNull);
        
        final chartMetadata = await storageService.getChartMetadata(chart.id);
        expect(chartMetadata, isNull);
      });

      test('should query charts by geographic bounds', () async {
        // Arrange
        final chart1 = _createTestChart(id: 'chart1', bounds: GeographicBounds(
          north: 38.0, south: 37.0, east: -122.0, west: -123.0,
        ));
        final chart2 = _createTestChart(id: 'chart2', bounds: GeographicBounds(
          north: 39.0, south: 38.0, east: -121.0, west: -122.0,
        ));
        
        await storageService.storeChart(chart1, [1, 2, 3]);
        await storageService.storeChart(chart2, [4, 5, 6]);

        // Act
        final chartsInBounds = await storageService.getChartsInBounds(
          GeographicBounds(north: 38.5, south: 37.5, east: -121.5, west: -122.5),
        );

        // Assert
        expect(chartsInBounds.length, equals(2));
        expect(chartsInBounds.any((c) => c.id == 'chart1'), isTrue);
        expect(chartsInBounds.any((c) => c.id == 'chart2'), isTrue);
      });

      test('should demonstrate cache invalidation needed for Washington charts', () async {
        // Arrange - Simulate the real issue: OLD cached charts with wrong bounds
        // These represent charts that were cached BEFORE geometry extraction was implemented
        
        // OLD cached West Coast chart with wrong default bounds
        final oldCachedChart = _createTestChart(
          id: 'US1WC07M', 
          bounds: GeographicBounds(
            north: 0.0, south: 0.0, east: 0.0, west: 0.0, // Wrong default bounds from old API
          )
        );
        
        await storageService.storeChart(oldCachedChart, [1]);

        // Act - Query for Washington (this should find 0 charts due to old cache)
        final washingtonBounds = GeographicBounds(
          north: 49.0, south: 45.5, east: -116.9, west: -124.8
        );
        final chartsInWashington = await storageService.getChartsInBounds(washingtonBounds);
        
        print('DEBUG: Found ${chartsInWashington.length} charts with old cached bounds');

        // Assert - Demonstrates the cache invalidation problem
        expect(chartsInWashington.length, equals(0), 
               reason: 'Old cached charts with wrong bounds (0,0,0,0) don\'t intersect Washington');
               
        // Now test what SHOULD happen with correct bounds
        final correctedChart = _createTestChart(
          id: 'US1WC07M', 
          bounds: GeographicBounds(
            north: 49.0, south: 32.0, east: -117.0, west: -125.0, // Correct West Coast bounds
          )
        );
        
        // Update the chart with correct bounds (simulating re-fetch with geometry)
        await storageService.storeChart(correctedChart, [1]);
        
        final chartsAfterUpdate = await storageService.getChartsInBounds(washingtonBounds);
        print('DEBUG: Found ${chartsAfterUpdate.length} charts after bounds correction');
        
        expect(chartsAfterUpdate.length, equals(1), 
               reason: 'After bounds correction, West Coast chart should be found for Washington');
        expect(chartsAfterUpdate.first.id, equals('US1WC07M'));
      });

      test('should detect and count charts with invalid bounds', () async {
        // Arrange - Create charts with various bound scenarios
        final validChart = Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );
        
        final invalidChart1 = Chart(
          id: 'US1WC01M',
          title: 'Columbia River Chart',
          scale: 80000,
          bounds: GeographicBounds(north: 0, south: 0, east: 0, west: 0), // Invalid: all zeros
          lastUpdate: DateTime(2024, 1, 15),
          state: 'Washington',
          type: ChartType.general,
        );
        
        final invalidChart2 = Chart(
          id: 'US1WC04M',
          title: 'Puget Sound Chart',
          scale: 25000,
          bounds: GeographicBounds(north: 0, south: 0, east: 0, west: 0), // Invalid: all zeros
          lastUpdate: DateTime(2024, 1, 15),
          state: 'Washington',
          type: ChartType.harbor,
        );
        
        await storageService.storeChart(validChart, [1]);
        await storageService.storeChart(invalidChart1, [1]);
        await storageService.storeChart(invalidChart2, [1]);
        
        // Act - Count charts with invalid bounds
        final invalidBoundsCount = await storageService.countChartsWithInvalidBounds();
        
        // Assert
        expect(invalidBoundsCount, equals(2), reason: 'Should find exactly 2 charts with invalid bounds (0,0,0,0)');
      });

      test('should provide cache invalidation for charts with invalid bounds', () async {
        // Arrange - Create charts that simulate the Washington chart discovery issue
        final washingtonChart1 = Chart(
          id: 'US1WC01M',
          title: 'Columbia River to Destruction I.',
          scale: 80000,
          bounds: GeographicBounds(north: 0, south: 0, east: 0, west: 0), // Old cached bounds
          lastUpdate: DateTime(2024, 1, 15),
          state: 'Washington',
          type: ChartType.general,
        );
        
        final washingtonChart2 = Chart(
          id: 'US1WC04M',
          title: 'Cape Disappointment to Lincoln City',
          scale: 80000,
          bounds: GeographicBounds(north: 0, south: 0, east: 0, west: 0), // Old cached bounds
          lastUpdate: DateTime(2024, 1, 15),
          state: 'Washington',
          type: ChartType.general,
        );
        
        await storageService.storeChart(washingtonChart1, [1]);
        await storageService.storeChart(washingtonChart2, [1]);
        
        // Verify the problem exists
        final invalidCountBefore = await storageService.countChartsWithInvalidBounds();
        expect(invalidCountBefore, equals(2), reason: 'Should have 2 charts with invalid bounds initially');
        
        // Act - Clear charts with invalid bounds (cache invalidation)
        final clearedCount = await storageService.clearChartsWithInvalidBounds();
        
        // Assert - Verify cache invalidation worked
        expect(clearedCount, equals(2), reason: 'Should clear exactly 2 charts with invalid bounds');
        
        final invalidCountAfter = await storageService.countChartsWithInvalidBounds();
        expect(invalidCountAfter, equals(0), reason: 'Should have 0 charts with invalid bounds after clearing');
        
        // Verify the charts are actually gone
        final remainingCharts = await storageService.getChartsInBounds(
          GeographicBounds(north: 90, south: -90, east: 180, west: -180)
        );
        expect(remainingCharts.length, equals(0), reason: 'All charts with invalid bounds should be removed');
      });

      test('should handle edge case charts that just touch boundaries', () async {
        // Arrange - Chart that just barely touches the query area
        final edgeChart = _createTestChart(
          id: 'EDGE01M',
          bounds: GeographicBounds(
            north: 45.5, south: 45.0, east: -116.0, west: -117.0, // Just touches Washington's south-east corner
          )
        );
        
        await storageService.storeChart(edgeChart, [1]);

        // Act - Query for Washington state bounds
        final washingtonBounds = GeographicBounds(
          north: 49.0, south: 45.5, east: -116.9, west: -124.8
        );
        final chartsInWashington = await storageService.getChartsInBounds(washingtonBounds);

        // Assert - Should find chart that touches the boundary
        expect(chartsInWashington.length, equals(1));
        expect(chartsInWashington.first.id, equals('EDGE01M'));
      });

      test('should handle charts that partially overlap query bounds', () async {
        // Arrange - Chart that overlaps but extends in all directions
        final overlapChart = _createTestChart(
          id: 'OVERLAP01M',
          bounds: GeographicBounds(
            north: 50.0, south: 44.0, east: -115.0, west: -126.0, // Larger than Washington
          )
        );
        
        await storageService.storeChart(overlapChart, [1]);

        // Act - Query for Washington state bounds  
        final washingtonBounds = GeographicBounds(
          north: 49.0, south: 45.5, east: -116.9, west: -124.8
        );
        final chartsInWashington = await storageService.getChartsInBounds(washingtonBounds);

        // Assert - Should find overlapping chart
        expect(chartsInWashington.length, equals(1));
        expect(chartsInWashington.first.id, equals('OVERLAP01M'));
      });

      test('should query charts by scale range', () async {
        // Arrange
        final smallScale = _createTestChart(id: 'small', scale: 10000);
        final mediumScale = _createTestChart(id: 'medium', scale: 50000);
        final largeScale = _createTestChart(id: 'large', scale: 100000);
        
        await storageService.storeChart(smallScale, [1]);
        await storageService.storeChart(mediumScale, [2]);
        await storageService.storeChart(largeScale, [3]);

        // Act
        final chartsInRange = await storageService.getChartsByScaleRange(25000, 75000);

        // Assert
        expect(chartsInRange.length, equals(1));
        expect(chartsInRange.first.id, equals('medium'));
      });
    });

    group('Route Storage Operations', () {
      test('should store route with waypoints', () async {
        // Arrange
        final route = _createTestRoute();

        // Act
        await storageService.storeRoute(route);

        // Assert
        final storedRoute = await storageService.getRoute(route.id);
        expect(storedRoute, isNotNull);
        expect(storedRoute!.id, equals(route.id));
        expect(storedRoute.name, equals(route.name));
        expect(storedRoute.waypoints.length, equals(route.waypoints.length));
      });

      test('should update route', () async {
        // Arrange
        final route = _createTestRoute();
        await storageService.storeRoute(route);

        final updatedRoute = route.copyWith(
          name: 'Updated Route Name',
          description: 'Updated description',
          updatedAt: DateTime.now(),
        );

        // Act
        await storageService.updateRoute(updatedRoute);

        // Assert
        final storedRoute = await storageService.getRoute(route.id);
        expect(storedRoute!.name, equals('Updated Route Name'));
        expect(storedRoute.description, equals('Updated description'));
      });

      test('should delete route and its waypoints', () async {
        // Arrange
        final route = _createTestRoute();
        await storageService.storeRoute(route);

        // Act
        await storageService.deleteRoute(route.id);

        // Assert
        final storedRoute = await storageService.getRoute(route.id);
        expect(storedRoute, isNull);
      });

      test('should get all routes', () async {
        // Arrange
        final route1 = _createTestRoute(id: 'route1');
        final route2 = _createTestRoute(id: 'route2');
        await storageService.storeRoute(route1);
        await storageService.storeRoute(route2);

        // Act
        final allRoutes = await storageService.getAllRoutes();

        // Assert
        expect(allRoutes.length, equals(2));
        expect(allRoutes.any((r) => r.id == 'route1'), isTrue);
        expect(allRoutes.any((r) => r.id == 'route2'), isTrue);
      });
    });

    group('Waypoint Storage Operations', () {
      test('should store standalone waypoints', () async {
        // Arrange
        final waypoint = _createTestWaypoint();

        // Act
        await storageService.storeWaypoint(waypoint);

        // Assert
        final storedWaypoint = await storageService.getWaypoint(waypoint.id);
        expect(storedWaypoint, isNotNull);
        expect(storedWaypoint!.id, equals(waypoint.id));
        expect(storedWaypoint.name, equals(waypoint.name));
        expect(storedWaypoint.latitude, equals(waypoint.latitude));
        expect(storedWaypoint.longitude, equals(waypoint.longitude));
      });

      test('should update waypoint', () async {
        // Arrange
        final waypoint = _createTestWaypoint();
        await storageService.storeWaypoint(waypoint);

        final updatedWaypoint = waypoint.copyWith(
          name: 'Updated Waypoint',
          description: 'Updated description',
        );

        // Act
        await storageService.updateWaypoint(updatedWaypoint);

        // Assert
        final storedWaypoint = await storageService.getWaypoint(waypoint.id);
        expect(storedWaypoint!.name, equals('Updated Waypoint'));
        expect(storedWaypoint.description, equals('Updated description'));
      });

      test('should delete waypoint', () async {
        // Arrange
        final waypoint = _createTestWaypoint();
        await storageService.storeWaypoint(waypoint);

        // Act
        await storageService.deleteWaypoint(waypoint.id);

        // Assert
        final storedWaypoint = await storageService.getWaypoint(waypoint.id);
        expect(storedWaypoint, isNull);
      });

      test('should get waypoints in area', () async {
        // Arrange
        final waypoint1 = _createTestWaypoint(
          id: 'wp1',
          latitude: 37.7749,
          longitude: -122.4194,
        );
        final waypoint2 = _createTestWaypoint(
          id: 'wp2',
          latitude: 37.7849,
          longitude: -122.4094,
        );
        final waypoint3 = _createTestWaypoint(
          id: 'wp3',
          latitude: 38.0000,
          longitude: -121.0000,
        );

        await storageService.storeWaypoint(waypoint1);
        await storageService.storeWaypoint(waypoint2);
        await storageService.storeWaypoint(waypoint3);

        // Act
        final waypointsInArea = await storageService.getWaypointsInArea(
          GeographicBounds(
            north: 37.8,
            south: 37.7,
            east: -122.3,
            west: -122.5,
          ),
        );

        // Assert
        expect(waypointsInArea.length, equals(2));
        expect(waypointsInArea.any((w) => w.id == 'wp1'), isTrue);
        expect(waypointsInArea.any((w) => w.id == 'wp2'), isTrue);
        expect(waypointsInArea.any((w) => w.id == 'wp3'), isFalse);
      });
    });

    group('Download Queue Management', () {
      test('should add chart to download queue', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const downloadUrl = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';

        // Act
        await storageService.addToDownloadQueue(chartId, downloadUrl);

        // Assert
        final queueItem = await storageService.getDownloadQueueItem(chartId);
        expect(queueItem, isNotNull);
        expect(queueItem!['chart_id'], equals(chartId));
        expect(queueItem['download_url'], equals(downloadUrl));
        expect(queueItem['status'], equals('pending'));
      });

      test('should update download queue item status', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const downloadUrl = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        await storageService.addToDownloadQueue(chartId, downloadUrl);

        // Act
        await storageService.updateDownloadQueueStatus(chartId, 'downloading', 0.5);

        // Assert
        final queueItem = await storageService.getDownloadQueueItem(chartId);
        expect(queueItem!['status'], equals('downloading'));
        expect(queueItem['progress'], equals(0.5));
      });

      test('should remove completed downloads from queue', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const downloadUrl = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        await storageService.addToDownloadQueue(chartId, downloadUrl);
        await storageService.updateDownloadQueueStatus(chartId, 'completed', 1.0);

        // Act
        await storageService.removeFromDownloadQueue(chartId);

        // Assert
        final queueItem = await storageService.getDownloadQueueItem(chartId);
        expect(queueItem, isNull);
      });

      test('should get pending downloads', () async {
        // Arrange
        await storageService.addToDownloadQueue('chart1', 'url1');
        await storageService.addToDownloadQueue('chart2', 'url2');
        await storageService.addToDownloadQueue('chart3', 'url3');
        
        await storageService.updateDownloadQueueStatus('chart2', 'downloading', 0.3);
        await storageService.updateDownloadQueueStatus('chart3', 'completed', 1.0);

        // Act
        final pendingDownloads = await storageService.getPendingDownloads();

        // Assert
        expect(pendingDownloads.length, equals(2)); // pending and downloading
        expect(pendingDownloads.any((d) => d['chart_id'] == 'chart1'), isTrue);
        expect(pendingDownloads.any((d) => d['chart_id'] == 'chart2'), isTrue);
        expect(pendingDownloads.any((d) => d['chart_id'] == 'chart3'), isFalse);
      });
    });

    group('Storage Utilities', () {
      test('should get storage information', () async {
        // Arrange
        final chart = _createTestChart();
        await storageService.storeChart(chart, List.generate(1000, (i) => i % 256));

        // Act
        final storageInfo = await storageService.getStorageInfo();

        // Assert
        expect(storageInfo, containsPair('total_charts', 1));
        expect(storageInfo, containsPair('total_routes', 0));
        expect(storageInfo, containsPair('total_waypoints', 0));
        expect(storageInfo, containsPair('total_downloads_pending', 0));
        expect(storageInfo, contains('database_size_bytes'));
      });

      test('should get storage usage in bytes', () async {
        // Arrange
        final chart = _createTestChart();
        await storageService.storeChart(chart, List.generate(2000, (i) => i % 256));

        // Act
        final usage = await storageService.getStorageUsage();

        // Assert
        expect(usage, isA<int>());
        expect(usage, greaterThan(0));
      });

      test('should cleanup old data', () async {
        // Arrange
        final oldChart = _createTestChart(
          id: 'old_chart',
          lastUpdate: DateTime.now().subtract(const Duration(days: 365)),
        );
        final newChart = _createTestChart(
          id: 'new_chart',
          lastUpdate: DateTime.now(),
        );
        
        await storageService.storeChart(oldChart, [1, 2, 3]);
        await storageService.storeChart(newChart, [4, 5, 6]);

        // Act
        final cleanedCount = await storageService.cleanupOldDataWithAge(maxAge: const Duration(days: 30));

        // Assert
        expect(cleanedCount, equals(1));
        expect(await storageService.getChartMetadata('old_chart'), isNull);
        expect(await storageService.getChartMetadata('new_chart'), isNotNull);
      });
    });

    group('Error Handling', () {
      test('should handle database connection errors', () async {
        // Arrange
        await database.close();

        // Act & Assert
        expect(
          () async => await storageService.storeChart(_createTestChart(), [1, 2, 3]),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle invalid chart data', () async {
        // Act & Assert
        expect(
          () async => await storageService.storeChart(_createTestChart(), []),
          throwsArgumentError,
        );
      });

      test('should handle duplicate chart IDs by replacing', () async {
        // Arrange
        final chart = _createTestChart();
        await storageService.storeChart(chart, [1, 2, 3]);

        // Act - Should replace the existing chart
        await storageService.storeChart(chart, [4, 5, 6]);

        // Assert - Should have the new data
        final loadedData = await storageService.loadChart(chart.id);
        expect(loadedData, equals([4, 5, 6]));
      });

      test('should handle non-existent chart deletion', () async {
        // Act & Assert
        expect(
          () async => await storageService.deleteChart('non_existent_chart'),
          returnsNormally,
        );
      });
    });

    group('Migration Tests', () {
      test('should handle database version upgrades', () async {
        // This test would verify migration from version 1 to 2
        expect(await storageService.getDatabaseVersion(), equals(1));
        
        // Future migration testing would go here
      });

      test('should preserve data during migrations', () async {
        // Arrange
        final chart = _createTestChart();
        await storageService.storeChart(chart, [1, 2, 3]);

        // Simulate migration (would be tested with actual version upgrade)
        // Act - migration would happen here

        // Assert
        final preservedChart = await storageService.getChartMetadata(chart.id);
        expect(preservedChart, isNotNull);
      });
    });
  });
}

// Helper functions for creating test data
Chart _createTestChart({
  String? id,
  String? title,
  GeographicBounds? bounds,
  int? scale,
  DateTime? lastUpdate,
}) {
  return Chart(
    id: id ?? 'US5CA52M',
    title: title ?? 'San Francisco Bay',
    scale: scale ?? 25000,
    bounds: bounds ?? GeographicBounds(
      north: 37.8267,
      south: 37.7849,
      east: -122.3994,
      west: -122.5194,
    ),
    lastUpdate: lastUpdate ?? DateTime.now().subtract(const Duration(days: 1)),
    state: 'California',
    type: ChartType.harbor,
  );
}

NavigationRoute _createTestRoute({String? id, String? name}) {
  final routeId = id ?? 'test_route_001';
  return NavigationRoute(
    id: routeId,
    name: name ?? 'Test Navigation Route',
    waypoints: [
      _createTestWaypoint(id: '${routeId}_wp1', name: 'Start Point'),
      _createTestWaypoint(id: '${routeId}_wp2', name: 'End Point', latitude: 37.8000),
    ],
    description: 'Test route for navigation',
  );
}

Waypoint _createTestWaypoint({
  String? id,
  String? name,
  double? latitude,
  double? longitude,
}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return Waypoint(
    id: id ?? 'test_waypoint_$timestamp',
    name: name ?? 'Test Waypoint',
    latitude: latitude ?? 37.7749,
    longitude: longitude ?? -122.4194,
    type: WaypointType.destination,
    description: 'Test waypoint for navigation',
  );
}
