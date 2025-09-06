@Skip('Excluded from CI: exploratory debug analysis test')
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Simple mock logger for testing
class TestLogger implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) =>
      print('[DEBUG] $message');

  @override
  void info(String message, {String? context, Object? exception}) =>
      print('[INFO] $message');

  @override
  void warning(String message, {String? context, Object? exception}) =>
      print('[WARNING] $message');

  @override
  void error(String message, {String? context, Object? exception}) =>
      print('[ERROR] $message ${exception ?? ''}');

  @override
  void logError(AppError error) => print('[ERROR] ${error.message}');
}

void main() {
  group('Washington Chart Coverage Analysis', () {
    late DatabaseStorageService storageService;
    late AppLogger logger;
    late Database database;

    setUpAll(() {
      // Initialize SQLite FFI for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      logger = TestLogger();

      // Create in-memory database for testing
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // This will be implemented by the service
        },
      );

      storageService = DatabaseStorageService(
        logger: logger,
        testDatabase: database,
      );

      await storageService.initialize();
    });

    tearDown(() async {
      await database.close();
    });

    test('should analyze why no charts cover Washington coordinates', () async {
      print('\n=== WASHINGTON CHART COVERAGE ANALYSIS ===');

      // Washington state bounds (from state_region_mapping_service.dart)
      final washingtonBounds = GeographicBounds(
        north: 49.0,
        south: 45.5,
        east: -116.9,
        west: -124.8,
      );

      print('Washington State Bounds:');
      print(
        '  North: ${washingtonBounds.north}°, South: ${washingtonBounds.south}°',
      );
      print(
        '  East: ${washingtonBounds.east}°, West: ${washingtonBounds.west}°',
      );
      print('');

      // Seattle coordinates (from app logs: 47.6062, -122.3321)
      const seattleLat = 47.6062;
      const seattleLon = -122.3321;
      print('Seattle Coordinates: $seattleLat°N, $seattleLon°W');
      print(
        'Seattle within Washington bounds: ${_pointInBounds(seattleLat, seattleLon, washingtonBounds)}',
      );
      print('');

      // Create test charts based on the NOAA API response pattern we see in logs
      final testCharts = [
        // Alaska charts
        Chart(
          id: 'US1AK90M',
          title: 'Alaska Test Chart',
          scale: 80000,
          bounds: GeographicBounds(
            north: 71.0,
            south: 54.0,
            east: -130.0,
            west: -170.0,
          ),
          lastUpdate: DateTime.now(),
          state: 'Alaska',
          type: ChartType.general,
        ),

        // Bering Sea charts
        Chart(
          id: 'US1BS01M',
          title: 'Bering Sea 1',
          scale: 100000,
          bounds: GeographicBounds(
            north: 66.0,
            south: 53.0,
            east: -158.0,
            west: -180.0,
          ),
          lastUpdate: DateTime.now(),
          state: 'Alaska',
          type: ChartType.general,
        ),

        // West Coast charts - These should potentially cover Washington
        Chart(
          id: 'US1WC01M',
          title: 'Columbia River to Destruction Island',
          scale: 80000,
          bounds: GeographicBounds(
            north: 48.5,
            south: 46.0,
            east: -123.5,
            west: -124.8,
          ), // Should cover WA coast
          lastUpdate: DateTime.now(),
          state: 'Washington',
          type: ChartType.general,
        ),

        Chart(
          id: 'US1WC04M',
          title: 'Cape Disappointment to Lincoln City',
          scale: 80000,
          bounds: GeographicBounds(
            north: 46.5,
            south: 44.5,
            east: -123.8,
            west: -124.5,
          ), // OR/WA border
          lastUpdate: DateTime.now(),
          state: 'Oregon',
          type: ChartType.general,
        ),

        Chart(
          id: 'US1WC07M',
          title: 'San Francisco to Point Arena',
          scale: 80000,
          bounds: GeographicBounds(
            north: 39.0,
            south: 37.0,
            east: -122.0,
            west: -123.8,
          ), // California
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.general,
        ),

        // Hawaii charts
        Chart(
          id: 'US1HA01M',
          title: 'Hawaiian Islands',
          scale: 500000,
          bounds: GeographicBounds(
            north: 22.5,
            south: 18.5,
            east: -154.0,
            west: -161.0,
          ),
          lastUpdate: DateTime.now(),
          state: 'Hawaii',
          type: ChartType.general,
        ),

        // Pacific Ocean chart
        Chart(
          id: 'US1PO02M',
          title: 'North Pacific Ocean',
          scale: 1000000,
          bounds: GeographicBounds(
            north: 60.0,
            south: 20.0,
            east: -120.0,
            west: -180.0,
          ),
          lastUpdate: DateTime.now(),
          state: 'Pacific',
          type: ChartType.overview,
        ),
      ];

      // Store all test charts
      for (final chart in testCharts) {
        await storageService.storeChart(chart, [1, 2, 3]); // Dummy chart data
      }

      print('=== STORED CHARTS ANALYSIS ===');
      print('Total charts stored: ${testCharts.length}');
      print('');

      // Analyze each chart's relation to Washington
      for (final chart in testCharts) {
        print('Chart: ${chart.id} - ${chart.title}');
        print(
          '  Bounds: N=${chart.bounds.north}°, S=${chart.bounds.south}°, E=${chart.bounds.east}°, W=${chart.bounds.west}°',
        );
        print('  State: ${chart.state}');

        final intersectsWA = _boundsIntersect(chart.bounds, washingtonBounds);
        print('  Intersects Washington: $intersectsWA');

        final coversSeattle = _pointInBounds(
          seattleLat,
          seattleLon,
          chart.bounds,
        );
        print('  Covers Seattle: $coversSeattle');

        if (intersectsWA || coversSeattle) {
          print('  ✅ SHOULD BE FOUND FOR WASHINGTON');
        } else {
          print('  ❌ Would not be found for Washington');
        }
        print('');
      }

      // Now test the spatial query
      print('=== SPATIAL QUERY RESULTS ===');
      final chartsInWashington = await storageService.getChartsInBounds(
        washingtonBounds,
      );
      print('Charts found for Washington bounds: ${chartsInWashington.length}');

      for (final chart in chartsInWashington) {
        print('  - ${chart.id}: ${chart.title}');
      }

      // Test specific coordinates
      final seattleBounds = GeographicBounds(
        north: seattleLat + 0.1,
        south: seattleLat - 0.1,
        east: seattleLon + 0.1,
        west: seattleLon - 0.1,
      );
      final chartsAroundSeattle = await storageService.getChartsInBounds(
        seattleBounds,
      );
      print('\\nCharts covering Seattle area: ${chartsAroundSeattle.length}');

      for (final chart in chartsAroundSeattle) {
        print('  - ${chart.id}: ${chart.title}');
      }

      print('\\n=== DIAGNOSIS ===');
      if (chartsInWashington.isEmpty) {
        print('❌ NO CHARTS FOUND for Washington state bounds');
        print(
          'This explains why the app shows 0 charts for Washington selection.',
        );

        // Check if any West Coast charts exist
        final westCoastCharts = testCharts
            .where((c) => c.id.contains('WC'))
            .toList();
        print('\\nWest Coast charts in test data: ${westCoastCharts.length}');
        for (final chart in westCoastCharts) {
          final shouldMatch = _boundsIntersect(chart.bounds, washingtonBounds);
          print('  - ${chart.id}: should match = $shouldMatch');
        }
      } else {
        print('✅ Found ${chartsInWashington.length} charts for Washington');
      }

      // Expected result: Should find at least US1WC01M for Washington
      expect(
        chartsInWashington.any((c) => c.id == 'US1WC01M'),
        isTrue,
        reason:
            'US1WC01M should cover Washington coast and be found by spatial query',
      );
    });
  });
}

// Helper functions
bool _boundsIntersect(GeographicBounds bounds1, GeographicBounds bounds2) {
  return !(bounds1.east < bounds2.west ||
      bounds1.west > bounds2.east ||
      bounds1.north < bounds2.south ||
      bounds1.south > bounds2.north);
}

bool _pointInBounds(double lat, double lon, GeographicBounds bounds) {
  return lat >= bounds.south &&
      lat <= bounds.north &&
      lon >= bounds.west &&
      lon <= bounds.east;
}
