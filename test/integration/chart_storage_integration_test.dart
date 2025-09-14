import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/services/storage/chart_storage_analyzer.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';

/// Integration tests for chart storage system with real NOAA ENC data
/// 
/// Tests the complete workflow from S-57 parsing to storage optimization
/// using the available test charts:
/// - US5WA50M Harbor Elliott Bay (143.9 KB)
/// - US3WA01M Coastal Puget Sound (625.3 KB)
@Tags(['integration'])
void main() {
  group('Chart Storage Integration Tests', () {
    late DatabaseStorageService storageService;
    late ChartStorageAnalyzer analyzer;
    late AppLogger logger;

    // Test chart paths
    final testChartsPath = 'test/fixtures/charts/s57_data';
    final harborChartPath = '$testChartsPath/US5WA50M_harbor_elliott_bay.zip';
    final coastalChartPath = '$testChartsPath/US3WA01M_coastal_puget_sound.zip';

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      logger = TestLoggerAdapter();
      
      // Create fresh in-memory database for each test with unique name
      final uniqueDbName = ':memory:_${DateTime.now().microsecondsSinceEpoch}';
      final testDb = await databaseFactoryFfi.openDatabase(
        uniqueDbName,
        options: OpenDatabaseOptions(version: 1),
      );
      
      storageService = DatabaseStorageService(
        logger: logger,
        testDatabase: testDb,
      );
      await storageService.initialize();
      
      analyzer = ChartStorageAnalyzer(
        storageService: storageService,
        logger: logger,
      );
    });

    test('should integrate S-57 parsing with storage for harbor chart', () async {
      final harborFile = File(harborChartPath);
      if (!await harborFile.exists()) {
        print('⏭️  Skipping harbor chart integration - File not found: $harborChartPath');
        return;
      }

      print('🔗 Testing complete S-57 to storage integration for harbor chart...');

      final harborChart = Chart(
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
        fileSize: await harborFile.length(),
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );

      // Perform complete analysis
      final analysis = await analyzer.analyzeChart(harborChartPath, harborChart);
      
      print('Analysis Results:');
      print(analysis.toString());
      
      // Validate integration requirements
      expect(analysis.featureCount, greaterThan(0), reason: 'Should parse S-57 features');
      expect(analysis.retrievalTime.inMilliseconds, lessThan(100), 
        reason: 'Should meet sub-100ms lookup requirement');
      expect(analysis.compressionRatio, lessThanOrEqualTo(1.0), 
        reason: 'Should maintain or achieve compression');
      expect(analysis.efficiencyScore, greaterThan(70), 
        reason: 'Should achieve good efficiency score');

      // Generate optimization recommendations
      final recommendations = analyzer.generateOptimizationRecommendations(analysis);
      print('\nOptimization Recommendations:');
      recommendations.forEach((rec) => print('  • $rec'));

      print('✅ S-57 to storage integration successful for harbor chart');
    });

    test('should integrate S-57 parsing with storage for coastal chart', () async {
      final coastalFile = File(coastalChartPath);
      if (!await coastalFile.exists()) {
        print('⏭️  Skipping coastal chart integration - File not found: $coastalChartPath');
        return;
      }

      print('🔗 Testing complete S-57 to storage integration for coastal chart...');

      final coastalChart = Chart(
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
        fileSize: await coastalFile.length(),
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );

      final analysis = await analyzer.analyzeChart(coastalChartPath, coastalChart);
      
      print('Analysis Results:');
      print(analysis.toString());
      
      // Validate coastal chart requirements (different performance targets)
      expect(analysis.featureCount, greaterThan(0));
      expect(analysis.retrievalTime.inMilliseconds, lessThan(200), 
        reason: 'Coastal charts should retrieve under 200ms');
      expect(analysis.originalSize, greaterThan(600000), 
        reason: 'Should handle large coastal chart data (~625KB)');

      print('✅ S-57 to storage integration successful for coastal chart');
    });

    test('should perform batch analysis of all available charts', () async {
      print('📊 Testing batch chart storage analysis...');

      final chartFiles = <String, Chart>{};
      
      // Add harbor chart if available
      if (await File(harborChartPath).exists()) {
        chartFiles[harborChartPath] = Chart(
          id: 'US5WA50M_BATCH',
          title: 'APPROACHES TO EVERETT - BATCH TEST',
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
          fileSize: await File(harborChartPath).length(),
          edition: 1,
          updateNumber: 0,
          source: ChartSource.noaa,
          status: ChartStatus.current,
        );
      }
      
      // Add coastal chart if available
      if (await File(coastalChartPath).exists()) {
        chartFiles[coastalChartPath] = Chart(
          id: 'US3WA01M_BATCH',
          title: 'PUGET SOUND - NORTHERN PART - BATCH TEST',
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
          isDownloaded: true,
          fileSize: await File(coastalChartPath).length(),
          edition: 1,
          updateNumber: 0,
          source: ChartSource.noaa,
          status: ChartStatus.current,
        );
      }

      if (chartFiles.isEmpty) {
        print('⏭️  Skipping batch analysis - No chart files available');
        return;
      }

      print('Charts available for batch analysis: ${chartFiles.length}');

      final batchAnalysis = await analyzer.analyzeBatch(chartFiles);
      
      print('Batch Analysis Results:');
      print(batchAnalysis.toString());
      
      // Validate batch analysis
      expect(batchAnalysis.analyses, isNotEmpty);
      expect(batchAnalysis.summary['charts_analyzed'], equals(chartFiles.length));
      
      final summary = batchAnalysis.summary;
      expect(summary['performance_compliance_percent'], greaterThan(0));
      
      print('✅ Batch chart storage analysis completed successfully');
    });

    test('should validate spatial indexing integration with real coordinates', () async {
      final harborFile = File(harborChartPath);
      if (!await harborFile.exists()) {
        print('⏭️  Skipping spatial indexing test - Harbor chart not available');
        return;
      }

      print('🗺️  Testing spatial indexing with real Elliott Bay coordinates...');

      // Parse chart to get real coordinate data
      final archiveBytes = await harborFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(await harborFile.readAsBytes());
      final chartEntry = archive.files.firstWhere((f) => f.name.endsWith('.000'));
      final chartData = chartEntry.content as List<int>;
      
      final parsedData = S57Parser.parse(chartData);
      print('Features available for spatial indexing: ${parsedData.features.length}');
      
      // Store chart data
      final chart = Chart(
        id: 'US5WA50M_SPATIAL',
        title: 'APPROACHES TO EVERETT - SPATIAL TEST',
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
        fileSize: chartData.length,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      await storageService.storeChart(chart, chartData);
      
      // Test spatial queries with real Elliott Bay bounds
      final elliottBayBounds = GeographicBounds(
        north: 47.62,
        south: 47.58,
        east: -122.32,
        west: -122.36,
      );
      
      final spatialQueryStart = DateTime.now();
      final chartsInBounds = await storageService.getChartsInBounds(elliottBayBounds);
      final spatialQueryTime = DateTime.now().difference(spatialQueryStart);
      
      print('Spatial query results:');
      print('  Query time: ${spatialQueryTime.inMilliseconds}ms');
      print('  Charts found in bounds: ${chartsInBounds.length}');
      
      // Validate spatial query performance
      expect(spatialQueryTime.inMilliseconds, lessThan(50), 
        reason: 'Spatial queries should be very fast');
      expect(chartsInBounds.map((c) => c.id), contains(chart.id));
      
      print('✅ Spatial indexing integration validated with real coordinates');
    });

    test('should validate chart update workflow with versioning', () async {
      print('🔄 Testing chart update and versioning workflow...');
      
      // Create base chart version
      final baseChartData = List.generate(5000, (i) => i % 256);
      final baseChart = Chart(
        id: 'US5WA50M_UPDATE',
        title: 'APPROACHES TO EVERETT - UPDATE TEST',
        scale: 20000,
        bounds: GeographicBounds(
          north: 47.7,
          south: 47.5,
          east: -122.2,
          west: -122.4,
        ),
        lastUpdate: DateTime.now().subtract(const Duration(days: 7)),
        state: 'WA',
        type: ChartType.harbor,
        isDownloaded: true,
        fileSize: baseChartData.length,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      // Store base version
      await storageService.storeChart(baseChart, baseChartData);
      
      // Simulate chart update (.001 file)
      final updateData = List.generate(5200, (i) => (i * 3) % 256);
      final updatedChart = Chart(
        id: 'US5WA50M_UPDATE',
        title: 'APPROACHES TO EVERETT - UPDATE TEST',
        scale: 20000,
        bounds: baseChart.bounds,
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.harbor,
        isDownloaded: true,
        fileSize: updateData.length,
        edition: 1,
        updateNumber: 1, // Incremented update number
        source: ChartSource.noaa,
        status: ChartStatus.current,
      );
      
      // Apply update
      final updateStart = DateTime.now();
      await storageService.storeChart(updatedChart, updateData);
      final updateTime = DateTime.now().difference(updateStart);
      
      print('Chart update applied in: ${updateTime.inMilliseconds}ms');
      
      // Verify updated version is retrieved
      final retrievedData = await storageService.loadChart('US5WA50M_UPDATE');
      expect(retrievedData, isNotNull);
      expect(retrievedData!.length, equals(updateData.length));
      
      // Update should be efficient
      expect(updateTime.inMilliseconds, lessThan(100), 
        reason: 'Chart updates should be applied quickly');
      
      print('✅ Chart update and versioning workflow validated');
    });

    test('should validate storage cleanup and optimization', () async {
      print('🧹 Testing storage cleanup and optimization...');
      
      // Create multiple chart versions to test cleanup
      final charts = <Chart>[];
      for (int i = 0; i < 5; i++) {
        final chartData = List.generate(1000 + i * 100, (j) => (i * j) % 256);
        final chart = Chart(
          id: 'CLEANUP_TEST_$i',
          title: 'CLEANUP TEST CHART $i',
          scale: 20000 + i * 1000,
          bounds: GeographicBounds(
            north: 47.7 + i * 0.1,
            south: 47.5 + i * 0.1,
            east: -122.2 - i * 0.1,
            west: -122.4 - i * 0.1,
          ),
          lastUpdate: DateTime.now().subtract(Duration(days: i * 30)),
          state: 'WA',
          type: ChartType.harbor,
          isDownloaded: true,
          fileSize: chartData.length,
          edition: 1,
          updateNumber: 0,
          source: ChartSource.noaa,
          status: ChartStatus.current,
        );
        
        await storageService.storeChart(chart, chartData);
        charts.add(chart);
      }
      
      // Check initial storage usage
      final initialUsage = await storageService.getStorageUsage();
      print('Initial storage usage: ${initialUsage} bytes');
      
      // Test storage info
      final storageInfo = await storageService.getStorageInfo();
      print('Storage info: $storageInfo');
      
      // Test cleanup of old data
      final cleanupStart = DateTime.now();
      await storageService.cleanupOldData();
      final cleanupTime = DateTime.now().difference(cleanupStart);
      
      print('Cleanup completed in: ${cleanupTime.inMilliseconds}ms');
      
      // Verify cleanup was effective
      final finalUsage = await storageService.getStorageUsage();
      print('Final storage usage: ${finalUsage} bytes');
      
      // Cleanup should be efficient
      expect(cleanupTime.inMilliseconds, lessThan(1000), 
        reason: 'Storage cleanup should complete quickly');
      
      print('✅ Storage cleanup and optimization validated');
    });
  });
}

/// Test logger adapter for AppLogger interface
class TestLoggerAdapter implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) {
    print('DEBUG: ${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void info(String message, {String? context, Object? exception}) {
    print('INFO: ${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void warning(String message, {String? context, Object? exception}) {
    print('WARNING: ${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void error(String message, {String? context, Object? exception}) {
    print('ERROR: ${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}');
  }

  @override
  void logError(dynamic error) {
    print('ERROR: $error');
  }
}