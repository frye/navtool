import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/services/storage/noaa_storage_extensions.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';

import '../database_storage_service_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([AppLogger])
void main() {
  group('NOAA Storage Extensions Tests', () {
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
        version: 2, // Using version 2 for NOAA extensions
        onCreate: (db, version) async {
          // This will be implemented by the service
        },
        onUpgrade: (db, oldVersion, newVersion) async {
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

    group('Database Schema Version 2', () {
      test('should create NOAA-specific chart columns', () async {
        // Arrange & Act
        final columns = await database.rawQuery("PRAGMA table_info(charts)");

        // Assert
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('cell_name'));
        expect(columnNames, contains('usage_band'));
        expect(columnNames, contains('edition_number'));
        expect(columnNames, contains('update_number'));
        expect(columnNames, contains('compilation_scale'));
        expect(columnNames, contains('region'));
        expect(columnNames, contains('dt_pub'));
        expect(columnNames, contains('issue_date'));
        expect(columnNames, contains('source_date_string'));
        expect(columnNames, contains('edition_date'));
        expect(columnNames, contains('boundary_polygon'));
      });

      test('should create state_chart_mapping table', () async {
        // Arrange & Act
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );

        // Assert
        final tableNames = tables.map((t) => t['name'] as String).toList();
        expect(tableNames, contains('state_chart_mapping'));

        // Check table structure
        final columns = await database.rawQuery(
          "PRAGMA table_info(state_chart_mapping)",
        );
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('id'));
        expect(columnNames, contains('state_name'));
        expect(columnNames, contains('cell_name'));
        expect(columnNames, contains('coverage_percentage'));
        expect(columnNames, contains('created_at'));
        expect(columnNames, contains('updated_at'));
      });

      test('should create chart_catalog_cache table', () async {
        // Arrange & Act
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );

        // Assert
        final tableNames = tables.map((t) => t['name'] as String).toList();
        expect(tableNames, contains('chart_catalog_cache'));

        // Check table structure
        final columns = await database.rawQuery(
          "PRAGMA table_info(chart_catalog_cache)",
        );
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('id'));
        expect(columnNames, contains('catalog_type'));
        expect(columnNames, contains('catalog_data'));
        expect(columnNames, contains('catalog_hash'));
        expect(columnNames, contains('last_updated'));
        expect(columnNames, contains('etag'));
        expect(columnNames, contains('is_valid'));
        expect(columnNames, contains('expires_at'));
      });

      test('should create chart_update_history table', () async {
        // Arrange & Act
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );

        // Assert
        final tableNames = tables.map((t) => t['name'] as String).toList();
        expect(tableNames, contains('chart_update_history'));

        // Check table structure
        final columns = await database.rawQuery(
          "PRAGMA table_info(chart_update_history)",
        );
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('id'));
        expect(columnNames, contains('cell_name'));
        expect(columnNames, contains('old_edition'));
        expect(columnNames, contains('new_edition'));
        expect(columnNames, contains('old_update_number'));
        expect(columnNames, contains('new_update_number'));
        expect(columnNames, contains('update_detected_at'));
      });

      test('should create appropriate indexes for NOAA operations', () async {
        // Arrange & Act
        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index'",
        );

        // Assert
        final indexNames = indexes.map((i) => i['name'] as String).toList();
        expect(indexNames, contains('idx_charts_cell_name'));
        expect(indexNames, contains('idx_charts_usage_band'));
        expect(indexNames, contains('idx_charts_region'));
        expect(indexNames, contains('idx_charts_source'));
        expect(indexNames, contains('idx_state_chart_mapping_state'));
        expect(indexNames, contains('idx_state_chart_mapping_cell'));
        expect(indexNames, contains('idx_state_chart_mapping_coverage'));
        expect(indexNames, contains('idx_catalog_cache_type'));
        expect(indexNames, contains('idx_catalog_cache_valid'));
        expect(indexNames, contains('idx_catalog_cache_expires'));
        expect(indexNames, contains('idx_chart_history_cell'));
        expect(indexNames, contains('idx_chart_history_detected'));
      });
    });

    group('NOAA Chart Operations', () {
      test('should store NOAA chart with extended metadata', () async {
        // Arrange
        final chart = _createNoaaChart();
        final chartData = List<int>.generate(1000, (i) => i % 256);

        // Act
        await storageService.storeChart(chart, chartData);

        // Assert
        final result = await database.query(
          'charts',
          where: 'id = ?',
          whereArgs: [chart.id],
        );

        expect(result.length, equals(1));
        final storedChart = result.first;
        expect(storedChart['cell_name'], equals('US5TX22M'));
        expect(storedChart['usage_band'], equals('Overview'));
        expect(storedChart['edition_number'], equals(15));
        expect(storedChart['update_number'], equals(3));
        expect(storedChart['compilation_scale'], equals(80000));
        expect(storedChart['region'], equals('Region 5'));
        expect(storedChart['dt_pub'], equals('20231215'));
        expect(storedChart['issue_date'], equals('2023-12-15'));
        expect(storedChart['source_date_string'], equals('Various, see chart'));
        expect(storedChart['edition_date'], equals('2023-12-01'));
        expect(storedChart['boundary_polygon'], isNotNull);
      });

      test('should update NOAA chart with conflict resolution', () async {
        // Arrange
        final chart1 = _createNoaaChart(edition: 14, updateNumber: 1);
        final chart2 = _createNoaaChart(edition: 15, updateNumber: 3);
        final chartData = List<int>.generate(1000, (i) => i % 256);

        // Act
        await storageService.storeChart(chart1, chartData);
        await storageService.storeChart(chart2, chartData); // Should replace

        // Assert
        final result = await database.query(
          'charts',
          where: 'id = ?',
          whereArgs: [chart1.id],
        );

        expect(result.length, equals(1));
        final storedChart = result.first;
        expect(storedChart['edition_number'], equals(15));
        expect(storedChart['update_number'], equals(3));
      });

      test('should handle batch insert of NOAA charts efficiently', () async {
        // Arrange
        final charts = List.generate(
          50,
          (i) => _createNoaaChart(
            id: 'chart_$i',
            cellName: 'US5TX${(22 + i).toString().padLeft(2, '0')}M',
          ),
        );

        // Act
        final stopwatch = Stopwatch()..start();
        for (final chart in charts) {
          await storageService.storeChart(chart, List.generate(100, (i) => i));
        }
        stopwatch.stop();

        // Assert
        final result = await database.query('charts');
        expect(result.length, equals(50));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should be fast
      });

      test('should query charts by cell_name efficiently', () async {
        // Arrange
        final charts = [
          _createNoaaChart(id: 'chart1', cellName: 'US5TX22M'),
          _createNoaaChart(id: 'chart2', cellName: 'US5TX23M'),
          _createNoaaChart(id: 'chart3', cellName: 'US4FL01M'),
        ];

        for (final chart in charts) {
          await storageService.storeChart(chart, List.generate(100, (i) => i));
        }

        // Act
        final result = await database.query(
          'charts',
          where: 'cell_name = ?',
          whereArgs: ['US5TX22M'],
        );

        // Assert
        expect(result.length, equals(1));
        expect(result.first['id'], equals('chart1'));
      });
    });

    group('State-Chart Mapping Operations', () {
      test('should store state-chart mapping', () async {
        // Arrange
        const stateName = 'Texas';
        const cellNames = ['US5TX22M', 'US5TX23M', 'US5TX24M'];

        // Act
        await storageService.storeStateCellMapping(stateName, cellNames);

        // Assert
        final result = await database.query(
          'state_chart_mapping',
          where: 'state_name = ?',
          whereArgs: [stateName],
        );

        expect(result.length, equals(3));
        final storedCellNames = result
            .map((r) => r['cell_name'] as String)
            .toList();
        expect(storedCellNames, containsAll(cellNames));
      });

      test('should retrieve state-chart mapping', () async {
        // Arrange
        const stateName = 'Florida';
        const cellNames = ['US4FL01M', 'US4FL02M'];
        await storageService.storeStateCellMapping(stateName, cellNames);

        // Act
        final retrievedCellNames = await storageService.getStateCellMapping(
          stateName,
        );

        // Assert
        expect(retrievedCellNames, isNotNull);
        expect(retrievedCellNames, containsAll(cellNames));
        expect(retrievedCellNames!.length, equals(2));
      });

      test('should update existing state-chart mapping', () async {
        // Arrange
        const stateName = 'California';
        const initialCellNames = ['US1CA01M', 'US1CA02M'];
        const updatedCellNames = ['US1CA01M', 'US1CA03M', 'US1CA04M'];

        await storageService.storeStateCellMapping(stateName, initialCellNames);

        // Act
        await storageService.storeStateCellMapping(stateName, updatedCellNames);

        // Assert
        final result = await storageService.getStateCellMapping(stateName);
        expect(result, containsAll(updatedCellNames));
        expect(result!.length, equals(3));
        expect(result, isNot(contains('US1CA02M'))); // Should be removed
      });

      test('should clear all state-chart mappings', () async {
        // Arrange
        await storageService.storeStateCellMapping('Texas', ['US5TX22M']);
        await storageService.storeStateCellMapping('Florida', ['US4FL01M']);

        // Act
        await storageService.clearAllStateCellMappings();

        // Assert
        final result = await database.query('state_chart_mapping');
        expect(result.length, equals(0));
      });

      test('should return null for non-existent state mapping', () async {
        // Act
        final result = await storageService.getStateCellMapping(
          'NonExistentState',
        );

        // Assert
        expect(result, isNull);
      });
    });

    group('Chart Catalog Caching', () {
      test('should store catalog cache with metadata', () async {
        // Arrange
        const catalogData = '{"type":"FeatureCollection","features":[]}';
        const etag = '"abc123def456"';

        // Act
        await storageService.updateChartCatalog(catalogData, etag: etag);

        // Assert
        final result = await database.query('chart_catalog_cache');
        expect(result.length, equals(1));
        expect(result.first['catalog_data'], equals(catalogData));
        expect(result.first['etag'], equals(etag));
        expect(result.first['catalog_type'], equals('noaa'));
        expect(result.first['is_valid'], equals(1));
      });

      test('should retrieve valid cached catalog', () async {
        // Arrange
        const catalogData = '{"type":"FeatureCollection","features":[]}';
        await storageService.updateChartCatalog(catalogData);

        // Act
        final retrievedData = await storageService.getCachedCatalog();

        // Assert
        expect(retrievedData, equals(catalogData));
      });

      test('should invalidate expired cached catalog', () async {
        // Arrange
        const catalogData = '{"type":"FeatureCollection","features":[]}';
        await storageService.updateChartCatalog(catalogData);

        // Manually set expiration to past
        await database.update(
          'chart_catalog_cache',
          {
            'expires_at': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
          where: 'catalog_type = ?',
          whereArgs: ['noaa'],
        );

        // Act
        final retrievedData = await storageService.getCachedCatalog();

        // Assert
        expect(retrievedData, isNull);
      });

      test('should handle catalog cache cleanup', () async {
        // Arrange
        const catalogData = '{"type":"FeatureCollection","features":[]}';
        await storageService.updateChartCatalog(catalogData);

        // Add expired entry
        await database.insert('chart_catalog_cache', {
          'catalog_type': 'noaa',
          'catalog_data': '{"expired": true}',
          'catalog_hash': 'expired_hash',
          'last_updated': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
          'is_valid': 1,
          'expires_at': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
        });

        // Act
        await storageService.cleanupExpiredCache();

        // Assert
        final result = await database.query('chart_catalog_cache');
        expect(result.length, equals(1)); // Only non-expired should remain
        expect(result.first['catalog_data'], equals(catalogData));
      });
    });

    group('Chart Update Detection', () {
      test('should detect chart update availability', () async {
        // Arrange
        final chart = _createNoaaChart(edition: 14, updateNumber: 2);
        await storageService.storeChart(chart, List.generate(100, (i) => i));

        // Act
        final updateAvailable1 = await storageService.isChartUpdateAvailable(
          'US5TX22M',
          15,
          3,
        );
        final updateAvailable2 = await storageService.isChartUpdateAvailable(
          'US5TX22M',
          14,
          2,
        );
        final updateAvailable3 = await storageService.isChartUpdateAvailable(
          'US5TX22M',
          13,
          5,
        );

        // Assert
        expect(updateAvailable1, isTrue); // Higher edition
        expect(updateAvailable2, isFalse); // Same edition and update
        expect(updateAvailable3, isFalse); // Lower edition
      });

      test('should track chart update history', () async {
        // Arrange
        const cellName = 'US5TX22M';

        // Act
        await storageService.recordChartUpdate(cellName, 14, 15, 1, 3);

        // Assert
        final history = await storageService.getChartUpdateHistory(cellName);
        expect(history.length, equals(1));
        expect(history.first['cell_name'], equals(cellName));
        expect(history.first['old_edition'], equals(14));
        expect(history.first['new_edition'], equals(15));
        expect(history.first['old_update_number'], equals(1));
        expect(history.first['new_update_number'], equals(3));
      });
    });

    group('Geographic Bounds Operations', () {
      test('should retrieve charts within geographic bounds', () async {
        // Arrange
        final charts = [
          _createNoaaChart(
            id: 'chart1',
            bounds: GeographicBounds(
              north: 30.0,
              south: 29.0,
              east: -94.0,
              west: -95.0,
            ),
          ),
          _createNoaaChart(
            id: 'chart2',
            bounds: GeographicBounds(
              north: 31.0,
              south: 30.5,
              east: -93.0,
              west: -94.0,
            ),
          ),
          _createNoaaChart(
            id: 'chart3',
            bounds: GeographicBounds(
              north: 26.0,
              south: 25.0,
              east: -80.0,
              west: -81.0,
            ),
          ),
        ];

        for (final chart in charts) {
          await storageService.storeChart(chart, List.generate(100, (i) => i));
        }

        final searchBounds = GeographicBounds(
          north: 31.0,
          south: 29.0,
          east: -93.0,
          west: -95.0,
        );

        // Act
        final result = await storageService.getChartsInBounds(searchBounds);

        // Assert
        expect(result.length, equals(2));
        final resultIds = result.map((c) => c.id).toList();
        expect(resultIds, containsAll(['chart1', 'chart2']));
        expect(resultIds, isNot(contains('chart3')));
      });
    });

    group('Database Migration', () {
      test('should migrate from version 1 to version 2', () async {
        // This test will verify the migration process
        // The actual migration logic will be implemented in the service

        // Act
        final version = await storageService.getDatabaseVersion();

        // Assert
        expect(version, equals(2));
      });
    });
  });
}

/// Helper function to create a test NOAA chart
Chart _createNoaaChart({
  String id = 'test_chart_noaa',
  String title = 'Galveston Bay',
  int scale = 80000,
  GeographicBounds? bounds,
  String state = 'Texas',
  String cellName = 'US5TX22M',
  String usageBand = 'Overview',
  int edition = 15,
  int updateNumber = 3,
  int compilationScale = 80000,
  String region = 'Region 5',
  String dtPub = '20231215',
  String issueDate = '2023-12-15',
  String sourceDateString = 'Various, see chart',
  String editionDate = '2023-12-01',
  String boundaryPolygon =
      '{"type":"Polygon","coordinates":[[[-95.5,29.0],[-94.5,29.0],[-94.5,30.0],[-95.5,30.0],[-95.5,29.0]]]}',
}) {
  return Chart(
    id: id,
    title: title,
    scale: scale,
    bounds:
        bounds ??
        GeographicBounds(north: 30.0, south: 29.0, east: -94.5, west: -95.5),
    lastUpdate: DateTime.now(),
    state: state,
    type: ChartType.coastal,
    source: ChartSource.noaa,
    status: ChartStatus.current,
    edition: edition,
    updateNumber: updateNumber,
    metadata: {
      'cell_name': cellName,
      'usage_band': usageBand,
      'compilation_scale': compilationScale,
      'region': region,
      'dt_pub': dtPub,
      'issue_date': issueDate,
      'source_date_string': sourceDateString,
      'edition_date': editionDate,
      'boundary_polygon': boundaryPolygon,
    },
  );
}
