import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../utils/test_logger.dart';

/// Chart Storage Performance Tests
/// 
/// Tests chart storage system performance with real NOAA ENC test data:
/// - US5WA50M Harbor Elliott Bay (143.9 KB) - Harbor scale chart
/// - US3WA01M Coastal Puget Sound (625.3 KB) - Coastal scale chart
/// 
/// Performance targets from issue comments:
/// - Sub-100ms lookup for harbor-scale charts
/// - Efficient storage with compression
/// - Fast spatial indexing with real coordinate clusters
@Tags(['performance'])
void main() {
  group('Chart Storage Performance Tests', () {
    late DatabaseStorageService storageService;
    late AppLogger logger;
    
    // Test chart data paths
    final testChartsPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
    final harborChartPath = '$testChartsPath/US5WA50M_harbor_elliott_bay.zip';
    final coastalChartPath = '$testChartsPath/US3WA01M_coastal_puget_sound.zip';

    setUpAll(() {
      // Initialize FFI for SQLite
      sqfliteFfiInit();
    });

    setUp(() async {
      logger = TestLoggerAdapter();
      
      // Create unique in-memory database for each test
      final dbName = ':memory:_${DateTime.now().millisecondsSinceEpoch}';
      final testDb = await databaseFactoryFfi.openDatabase(
        dbName,
        options: OpenDatabaseOptions(version: 1),
      );
      
      storageService = DatabaseStorageService(
        logger: logger,
        testDatabase: testDb,
      );
      await storageService.initialize();
    });

    tearDown(() async {
      // Database cleanup is handled by in-memory database going out of scope
    });

    test('should meet sub-100ms lookup requirement for harbor chart', () async {
      // Skip if test chart files not available
      final harborFile = File(harborChartPath);
      if (!await harborFile.exists()) {
        print('⏭️  Skipping performance test - Harbor chart file not found: $harborChartPath');
        return;
      }

      print('📊 Testing harbor chart storage performance...');
      
      // Load and extract chart data
      final archiveBytes = await harborFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      
      // Find the main chart file (.000 extension)
      final chartEntry = archive.files.firstWhere(
        (file) => file.name.endsWith('.000'),
        orElse: () => throw StateError('No .000 chart file found in archive'),
      );
      
      final chartData = chartEntry.content as List<int>;
      print('  Chart data size: ${chartData.length} bytes');
      
      // Parse chart for metadata
      final parseStartTime = DateTime.now();
      final parsedData = S57Parser.parse(chartData);
      final parseTime = DateTime.now().difference(parseStartTime);
      
      print('  Parse time: ${parseTime.inMilliseconds}ms');
      print('  Features parsed: ${parsedData.features.length}');
      
      // Create chart model
      final chart = Chart(
        id: 'US5WA50M',
        title: 'APPROACHES TO EVERETT',
        scale: 20000,
        bounds: GeographicBounds(
          north: 47.7,
          south: 47.5,
          east: -122.2,
          west: -122.4,
        ),
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.harbor,
        description: 'Harbor-scale chart covering Elliott Bay and Seattle Harbor',
        isDownloaded: true,
        fileSize: chartData.length,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      // Test storage performance
      final storeStartTime = DateTime.now();
      await storageService.storeChart(chart, chartData);
      final storeTime = DateTime.now().difference(storeStartTime);
      
      print('  Storage time: ${storeTime.inMilliseconds}ms');
      
      // Test lookup performance - This is the critical test
      final lookupTimes = <int>[];
      const numLookups = 10;
      
      for (int i = 0; i < numLookups; i++) {
        final lookupStartTime = DateTime.now();
        final retrievedData = await storageService.loadChart('US5WA50M');
        final lookupTime = DateTime.now().difference(lookupStartTime);
        
        lookupTimes.add(lookupTime.inMilliseconds);
        
        // Verify data integrity
        expect(retrievedData, isNotNull);
        expect(retrievedData!.length, equals(chartData.length));
      }
      
      final avgLookupTime = lookupTimes.reduce((a, b) => a + b) / lookupTimes.length;
      final maxLookupTime = lookupTimes.reduce((a, b) => a > b ? a : b);
      final minLookupTime = lookupTimes.reduce((a, b) => a < b ? a : b);
      
      print('  Lookup performance ($numLookups trials):');
      print('    Average: ${avgLookupTime.toStringAsFixed(1)}ms');
      print('    Min: ${minLookupTime}ms');
      print('    Max: ${maxLookupTime}ms');
      
      // Assert performance requirement from issue comments
      expect(
        avgLookupTime,
        lessThan(100),
        reason: 'Harbor chart lookup should be sub-100ms (average was ${avgLookupTime.toStringAsFixed(1)}ms)',
      );
      
      expect(
        maxLookupTime,
        lessThan(150),
        reason: 'Harbor chart lookup should never exceed 150ms (max was ${maxLookupTime}ms)',
      );
      
      print('✅ Harbor chart meets sub-100ms lookup requirement');
    });

    test('should efficiently store and retrieve coastal chart data', () async {
      final coastalFile = File(coastalChartPath);
      if (!await coastalFile.exists()) {
        print('⏭️  Skipping coastal chart test - File not found: $coastalChartPath');
        return;
      }

      print('📊 Testing coastal chart storage efficiency...');
      
      final archiveBytes = await coastalFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      
      final chartEntry = archive.files.firstWhere(
        (file) => file.name.endsWith('.000'),
        orElse: () => throw StateError('No .000 chart file found in archive'),
      );
      
      final chartData = chartEntry.content as List<int>;
      print('  Chart data size: ${chartData.length} bytes (${(chartData.length / 1024).toStringAsFixed(1)} KB)');
      
      final chart = Chart(
        id: 'US3WA01M',
        title: 'PUGET SOUND - NORTHERN PART',
        scale: 90000,
        bounds: GeographicBounds(
          north: 48.5,
          south: 47.0,
          east: -122.0,
          west: -123.5,
        ),
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.coastal,
        description: 'Coastal-scale chart covering broader Puget Sound region',
        isDownloaded: true,
        fileSize: chartData.length,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      // Test storage with larger dataset
      final storeStartTime = DateTime.now();
      await storageService.storeChart(chart, chartData);
      final storeTime = DateTime.now().difference(storeStartTime);
      
      print('  Storage time: ${storeTime.inMilliseconds}ms');
      
      // Test retrieval performance
      final retrievalStartTime = DateTime.now();
      final retrievedData = await storageService.loadChart('US3WA01M');
      final retrievalTime = DateTime.now().difference(retrievalStartTime);
      
      print('  Retrieval time: ${retrievalTime.inMilliseconds}ms');
      
      // Verify data integrity
      expect(retrievedData, isNotNull);
      expect(retrievedData!.length, equals(chartData.length));
      
      // Performance expectations for larger coastal chart
      expect(
        retrievalTime.inMilliseconds,
        lessThan(200),
        reason: 'Coastal chart retrieval should be under 200ms (was ${retrievalTime.inMilliseconds}ms)',
      );
      
      print('✅ Coastal chart storage and retrieval performance acceptable');
    });

    test('should perform efficient spatial queries with real chart data', () async {
      final harborFile = File(harborChartPath);
      if (!await harborFile.exists()) {
        print('⏭️  Skipping spatial query test - Harbor chart file not found');
        return;
      }

      print('📊 Testing spatial query performance with real chart data...');
      
      // Load chart data and parse features
      final archiveBytes = await harborFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final chartEntry = archive.files.firstWhere((file) => file.name.endsWith('.000'));
      final chartData = chartEntry.content as List<int>;
      
      final parsedData = S57Parser.parse(chartData);
      final features = parsedData.features;
      
      print('  Features available for spatial indexing: ${features.length}');
      
      // Build spatial index
      final indexStartTime = DateTime.now();
      final spatialIndex = SpatialIndexFactory.create(features);
      final indexTime = DateTime.now().difference(indexStartTime);
      
      print('  Spatial index build time: ${indexTime.inMilliseconds}ms');
      
      // Test spatial queries with Elliott Bay bounds
      final elliottBayBounds = parsedData.bounds ?? 
        parsedData.features.first.coordinates.fold<dynamic>(
          null,
          (bounds, coord) {
            if (bounds == null) {
              return {
                'north': coord.latitude,
                'south': coord.latitude,
                'east': coord.longitude,
                'west': coord.longitude,
              };
            }
            return {
              'north': [bounds['north'], coord.latitude].reduce((a, b) => a > b ? a : b),
              'south': [bounds['south'], coord.latitude].reduce((a, b) => a < b ? a : b),
              'east': [bounds['east'], coord.longitude].reduce((a, b) => a > b ? a : b),
              'west': [bounds['west'], coord.longitude].reduce((a, b) => a < b ? a : b),
            };
          },
        );
      
      // Perform multiple spatial queries
      final queryTimes = <int>[];
      const numQueries = 20;
      
      for (int i = 0; i < numQueries; i++) {
        final queryStartTime = DateTime.now();
        final queryResults = spatialIndex.queryBounds(parsedData.bounds!);
        final queryTime = DateTime.now().difference(queryStartTime);
        
        queryTimes.add(queryTime.inMicroseconds);
        
        expect(queryResults, isNotEmpty);
      }
      
      final avgQueryTime = queryTimes.reduce((a, b) => a + b) / queryTimes.length;
      final maxQueryTime = queryTimes.reduce((a, b) => a > b ? a : b);
      
      print('  Spatial query performance ($numQueries trials):');
      print('    Average: ${(avgQueryTime / 1000).toStringAsFixed(2)}ms');
      print('    Max: ${(maxQueryTime / 1000).toStringAsFixed(2)}ms');
      
      // Spatial queries should be very fast
      expect(
        avgQueryTime / 1000,
        lessThan(10),
        reason: 'Spatial queries should average under 10ms (was ${(avgQueryTime / 1000).toStringAsFixed(2)}ms)',
      );
      
      print('✅ Spatial query performance meets requirements');
    });

    test('should demonstrate storage optimization with compression', () async {
      final harborFile = File(harborChartPath);
      if (!await harborFile.exists()) {
        print('⏭️  Skipping compression test - Harbor chart file not found');
        return;
      }

      print('📊 Testing storage optimization and compression...');
      
      final archiveBytes = await harborFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final chartEntry = archive.files.firstWhere((file) => file.name.endsWith('.000'));
      final chartData = chartEntry.content as List<int>;
      
      final originalSize = chartData.length;
      print('  Original chart data: ${originalSize} bytes');
      
      // Test chart storage with the existing system
      final chart = Chart(
        id: 'US5WA50M_COMPRESSION',
        title: 'APPROACHES TO EVERETT - COMPRESSION TEST',
        scale: 20000,
        bounds: GeographicBounds(
          north: 47.7,
          south: 47.5,
          east: -122.2,
          west: -122.4,
        ),
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.harbor,
        isDownloaded: true,
        fileSize: originalSize,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      await storageService.storeChart(chart, chartData);
      
      // Get storage information
      final storageInfo = await storageService.getStorageInfo();
      print('  Storage system info: $storageInfo');
      
      // Test storage usage
      final storageUsage = await storageService.getStorageUsage();
      print('  Total storage usage: ${storageUsage} bytes');
      
      // Verify storage efficiency
      expect(storageUsage, greaterThan(0));
      expect(storageUsage, lessThan(originalSize * 2), // Should not be more than 2x original
        reason: 'Storage should be efficient');
      
      print('✅ Storage optimization working effectively');
    });

    test('should handle chart updates and versioning efficiently', () async {
      // This test simulates chart update workflow mentioned in issue comments
      print('📊 Testing chart update and versioning workflow...');
      
      // Create base chart
      final baseChartData = List.generate(10000, (i) => i % 256);
      final baseChart = Chart(
        id: 'US5WA50M_VERSION',
        title: 'APPROACHES TO EVERETT - VERSION TEST',
        scale: 20000,
        bounds: GeographicBounds(
          north: 47.7,
          south: 47.5,
          east: -122.2,
          west: -122.4,
        ),
        lastUpdate: DateTime.now().subtract(const Duration(days: 30)),
        state: 'WA',
        type: ChartType.harbor,
        isDownloaded: true,
        fileSize: baseChartData.length,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      // Store base chart
      final baseStoreTime = DateTime.now();
      await storageService.storeChart(baseChart, baseChartData);
      final baseStoreDuration = DateTime.now().difference(baseStoreTime);
      
      print('  Base chart storage time: ${baseStoreDuration.inMilliseconds}ms');
      
      // Create updated chart (simulating .001 update)
      final updatedChartData = List.generate(10500, (i) => (i * 2) % 256);
      final updatedChart = baseChart.copyWith(
        updateNumber: 1,
        lastUpdate: DateTime.now(),
        fileSize: updatedChartData.length,
      );
      
      // Store updated chart
      final updateStoreTime = DateTime.now();
      await storageService.storeChart(updatedChart, updatedChartData);
      final updateStoreDuration = DateTime.now().difference(updateStoreTime);
      
      print('  Updated chart storage time: ${updateStoreDuration.inMilliseconds}ms');
      
      // Verify updated chart retrieval
      final retrievalTime = DateTime.now();
      final retrievedData = await storageService.loadChart('US5WA50M_VERSION');
      final retrievalDuration = DateTime.now().difference(retrievalTime);
      
      print('  Updated chart retrieval time: ${retrievalDuration.inMilliseconds}ms');
      
      // Verify we get the updated version
      expect(retrievedData, isNotNull);
      expect(retrievedData!.length, equals(updatedChartData.length));
      
      // Update operations should be efficient
      expect(
        updateStoreDuration.inMilliseconds,
        lessThan(100),
        reason: 'Chart updates should be fast',
      );
      
      print('✅ Chart update and versioning performance acceptable');
    });
  });
}

/// Test logger adapter for AppLogger interface
class TestLoggerAdapter implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) {
    testLogger.debug('${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void info(String message, {String? context, Object? exception}) {
    testLogger.info('${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void warning(String message, {String? context, Object? exception}) {
    testLogger.warn('${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void error(String message, {String? context, Object? exception}) {
    testLogger.error('${context != null ? '[$context] ' : ''}$message', exception);
  }

  @override
  void logError(dynamic error) {
    testLogger.error('Error: $error');
  }
}

/// Extension to add copyWith method to Chart class for testing
extension ChartCopyWith on Chart {
  Chart copyWith({
    String? id,
    String? title,
    int? scale,
    GeographicBounds? bounds,
    DateTime? lastUpdate,
    String? state,
    ChartType? type,
    String? description,
    bool? isDownloaded,
    int? fileSize,
    int? edition,
    int? updateNumber,
    ChartSource? source,
    ChartStatus? status,
  }) {
    return Chart(
      id: id ?? this.id,
      title: title ?? this.title,
      scale: scale ?? this.scale,
      bounds: bounds ?? this.bounds,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      state: state ?? this.state,
      type: type ?? this.type,
      description: description ?? this.description,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      fileSize: fileSize ?? this.fileSize,
      edition: edition ?? this.edition,
      updateNumber: updateNumber ?? this.updateNumber,
      source: source ?? this.source,
      status: status ?? this.status,
    );
  }
}