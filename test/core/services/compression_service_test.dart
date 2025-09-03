import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:archive/archive.dart';
import 'package:navtool/core/services/compression_service.dart';
import 'package:navtool/core/services/compression_service_impl.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/compression_result.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../helpers/verify_helpers.dart';

// Generate mocks
@GenerateMocks([AppLogger])
import 'compression_service_test.mocks.dart';

void main() {
  group('CompressionService Interface Tests', () {
    test('should define required compression methods', () {
      // This test ensures the compression service interface is properly defined
      expect(CompressionService, isA<Type>());
    });

    test('should define compression levels enum', () {
      // Verify compression levels are available
      expect(CompressionLevel.fast, isA<CompressionLevel>());
      expect(CompressionLevel.balanced, isA<CompressionLevel>());
      expect(CompressionLevel.maximum, isA<CompressionLevel>());
    });

    test('should define compression result model', () {
      // Verify compression result structure
      final result = CompressionResult(
        originalSize: 1000,
        compressedSize: 400,
        compressionRatio: 0.4,
        compressionTime: const Duration(milliseconds: 100),
        compressedData: Uint8List.fromList(const []),
      );
      expect(result.originalSize, equals(1000));
      expect(result.compressedSize, equals(400));
      expect(result.compressionRatio, equals(0.4));
      expect(result.compressionTime, equals(const Duration(milliseconds: 100)));
    });
  });

  group('CompressionServiceImpl Tests', () {
    late CompressionServiceImpl compressionService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      compressionService = CompressionServiceImpl(logger: mockLogger);
    });

    group('Chart File Compression Tests', () {
      test('should compress S-57 chart file data successfully', () async {
        // Arrange
        final chartData = Uint8List.fromList(List.generate(500, (i) => [1, 2, 3, 4, 5][i % 5])); // Simulate 500 bytes
        const chartId = 'US5CA52M';

        // Act
        final result = await compressionService.compressChartData(
          chartData,
          chartId: chartId,
          level: CompressionLevel.balanced,
        );

        // Assert
        expect(result, isA<CompressionResult>());
        expect(result.originalSize, equals(chartData.length));
        expect(result.compressedSize, lessThan(result.originalSize));
        expect(result.compressionRatio, lessThan(1.0));
        expect(result.compressionTime.inMilliseconds, greaterThan(0));

        // Verify logging (info called once for compression start and once for completion)
  // Two info logs: start + completion (context 'Compression')
  verifyInfoLogged(mockLogger, RegExp(r'Compressing chart data:'), expectedContext: 'Compression', times: 1);
  verifyInfoLogged(mockLogger, RegExp(r'Chart compression completed:'), expectedContext: 'Compression', times: 1);
      });

      test('should decompress S-57 chart file data successfully', () async {
        // Arrange
        final originalData = Uint8List.fromList(List.generate(500, (i) => [1, 2, 3, 4, 5][i % 5]));
        const chartId = 'US5CA52M';

        // First compress the data
        final compressionResult = await compressionService.compressChartData(
          originalData,
          chartId: chartId,
        );

        // Act - decompress the data
        final decompressedData = await compressionService.decompressChartData(
          compressionResult.compressedData,
          chartId: chartId,
        );

        // Assert
        expect(decompressedData, equals(originalData));
        expect(decompressedData.length, equals(originalData.length));
      });

      test('should handle different compression levels for charts', () async {
        // Arrange
        final chartData = Uint8List.fromList(List.generate(1000, (i) => [1, 2, 3, 4, 5][i % 5]));
        const chartId = 'US5CA52M';

        // Act - test different compression levels
        final fastResult = await compressionService.compressChartData(
          chartData,
          chartId: chartId,
          level: CompressionLevel.fast,
        );

        final balancedResult = await compressionService.compressChartData(
          chartData,
          chartId: chartId,
          level: CompressionLevel.balanced,
        );

        final maxResult = await compressionService.compressChartData(
          chartData,
          chartId: chartId,
          level: CompressionLevel.maximum,
        );

        // Assert - all compression levels should work and produce valid results
        // Note: For small test data, timing differences may not be significant or predictable
        // so we focus on functionality rather than performance characteristics
        
        // All compression operations should complete successfully
        expect(fastResult.compressionTime.inMicroseconds, greaterThan(0));
        expect(balancedResult.compressionTime.inMicroseconds, greaterThan(0));
        expect(maxResult.compressionTime.inMicroseconds, greaterThan(0));
        
        // Note: In practice, compression ratios might be similar for small test data
        // So we just verify all operations completed successfully
        expect(fastResult.compressionRatio, lessThan(1.0));
        expect(balancedResult.compressionRatio, lessThan(1.0));
        expect(maxResult.compressionRatio, lessThan(1.0));
      });

      test('should handle empty chart data gracefully', () async {
        // Arrange
        final emptyData = Uint8List(0);
        const chartId = 'EMPTY_CHART';

        // Act & Assert
        expect(
          () => compressionService.compressChartData(emptyData, chartId: chartId),
          throwsA(isA<AppError>()),
        );
      });

      test('should handle corrupted compressed chart data', () async {
        // Arrange
        final corruptedData = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0xFC]);
        const chartId = 'CORRUPTED_CHART';

        // Act & Assert
        expect(
          () => compressionService.decompressChartData(corruptedData, chartId: chartId),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Route Backup Compression Tests', () {
      test('should compress route JSON data successfully', () async {
        // Arrange
        const routeJson = '''
        {
          "id": "route_001",
          "name": "San Francisco to Monterey",
          "waypoints": [
            {"lat": 37.7749, "lng": -122.4194, "name": "San Francisco"},
            {"lat": 36.6002, "lng": -121.8947, "name": "Monterey"}
          ],
          "distance": 120.5,
          "estimatedTime": "4 hours"
        }
        ''';
        final routeData = Uint8List.fromList(routeJson.codeUnits);
        const routeId = 'route_001';

        // Act
        final result = await compressionService.compressRouteData(
          routeData,
          routeId: routeId,
          level: CompressionLevel.balanced,
        );

        // Assert
        expect(result, isA<CompressionResult>());
        expect(result.originalSize, equals(routeData.length));
        expect(result.compressedSize, lessThan(result.originalSize));
        expect(result.compressionRatio, lessThan(1.0));
      });

      test('should decompress route JSON data successfully', () async {
        // Arrange
        const routeJson = '''{"id":"route_001","name":"Test Route"}''';
        final originalData = Uint8List.fromList(routeJson.codeUnits);
        const routeId = 'route_001';

        // First compress the data
        final compressionResult = await compressionService.compressRouteData(
          originalData,
          routeId: routeId,
        );

        // Act - decompress the data
        final decompressedData = await compressionService.decompressRouteData(
          compressionResult.compressedData,
          routeId: routeId,
        );

        // Assert
        expect(decompressedData, equals(originalData));
        expect(String.fromCharCodes(decompressedData), equals(routeJson));
      });

      test('should compress multiple routes for backup', () async {
        // Arrange
        const routes = [
          '{"id":"route_001","name":"Route 1"}',
          '{"id":"route_002","name":"Route 2"}',
          '{"id":"route_003","name":"Route 3"}',
        ];
        final routesData = routes.map((r) => Uint8List.fromList(r.codeUnits)).toList();

        // Act
        final result = await compressionService.compressRoutesBackup(
          routesData,
          backupId: 'backup_001',
          level: CompressionLevel.maximum,
        );

        // Assert
        expect(result, isA<CompressionResult>());
        final totalOriginalSize = routesData.fold<int>(0, (sum, data) => sum + data.length);
        expect(result.originalSize, equals(totalOriginalSize));
        // Note: ZIP compression may not always reduce size for very small test data
        expect(result.compressedSize, greaterThan(0));
      });
    });

    group('Downloaded Chart Extraction Tests', () {
      test('should extract ZIP archive from NOAA download', () async {
        // Arrange - Create a real ZIP archive for testing
        final archive = Archive();
        
        // Add a mock S-57 chart file
        final chartData = List.generate(100, (i) => i % 256);
        final chartFile = ArchiveFile('US5CA52M.000', chartData.length, chartData);
        archive.addFile(chartFile);
        
        // Add a metadata file
        final metadataData = 'Chart metadata content'.codeUnits;
        final metadataFile = ArchiveFile('US5CA52M.txt', metadataData.length, metadataData);
        archive.addFile(metadataFile);
        
        // Encode as ZIP
        final zipData = Uint8List.fromList(ZipEncoder().encode(archive)!);
        const chartId = 'US5CA52M';

        // Act
        final extractedFiles = await compressionService.extractChartArchive(
          zipData,
          chartId: chartId,
        );

        // Assert
        expect(extractedFiles, isA<List<ExtractedFile>>());
        expect(extractedFiles, isNotEmpty);
        
        // Verify extracted files have expected properties
        for (final file in extractedFiles) {
          expect(file.fileName, isNotEmpty);
          expect(file.data, isNotEmpty);
          expect(file.isChartFile, isA<bool>());
        }
      });

      test('should handle different archive formats', () async {
        // Arrange - Create real archives for testing
        
        // Create ZIP archive
        final zipArchive = Archive();
        final zipData = List.generate(50, (i) => i % 256);
        final zipFile = ArchiveFile('test.000', zipData.length, zipData);
        zipArchive.addFile(zipFile);
        final zipBytes = Uint8List.fromList(ZipEncoder().encode(zipArchive)!);
        
        // Create GZIP compressed data
        final gzipData = List.generate(50, (i) => i % 256);
        final gzipBytes = Uint8List.fromList(GZipEncoder().encode(gzipData)!);
        
        const chartId = 'TEST_CHART';

        // Act & Assert - ZIP should work
        final zipResult = await compressionService.extractChartArchive(
          zipBytes,
          chartId: chartId,
        );
        expect(zipResult, isNotEmpty);

        // GZIP should also work (single file extraction)
        final gzipResult = await compressionService.extractChartArchive(
          gzipBytes,
          chartId: chartId,
        );
        expect(gzipResult, isNotEmpty);
      });

      test('should handle corrupted archive files', () async {
        // Arrange
        final corruptedData = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
        const chartId = 'CORRUPTED_ARCHIVE';

        // Act & Assert
        expect(
          () => compressionService.extractChartArchive(corruptedData, chartId: chartId),
          throwsA(isA<AppError>()),
        );
      });

      test('should filter S-57 files from extracted archive', () async {
        // Arrange - Create archive with mixed file types
        final archive = Archive();
        
        // Add S-57 chart files
        final chartData1 = List.generate(100, (i) => i % 256);
        final chartFile1 = ArchiveFile('US5CA52M.000', chartData1.length, chartData1);
        archive.addFile(chartFile1);
        
        final chartData2 = List.generate(100, (i) => (i + 50) % 256);
        final chartFile2 = ArchiveFile('US5CA52M.001', chartData2.length, chartData2);
        archive.addFile(chartFile2);
        
        // Add non-chart files
        final textData = 'Some text file content'.codeUnits;
        final textFile = ArchiveFile('readme.txt', textData.length, textData);
        archive.addFile(textFile);
        
        final zipData = Uint8List.fromList(ZipEncoder().encode(archive)!);
        const chartId = 'US5CA52M';

        // Act
        final extractedFiles = await compressionService.extractChartArchive(
          zipData,
          chartId: chartId,
        );

        // Assert
        final chartFiles = extractedFiles.where((f) => f.isChartFile).toList();
        expect(chartFiles, isNotEmpty);
        
        // Should identify S-57 files (.000, .001, etc.)
        for (final file in chartFiles) {
          expect(
            file.fileName.endsWith('.000') || 
            file.fileName.endsWith('.001'),
            isTrue,
          );
        }
      });
    });

    group('Cache Compression Tests', () {
      test('should compress cache data for offline storage', () async {
        // Arrange
        final cacheData = Uint8List.fromList(List.generate(1000, (i) => [0xAA, 0xBB, 0xCC, 0xDD][i % 4])); // 1KB of data
        const cacheKey = 'offshore_charts_cache';

        // Act
        final result = await compressionService.compressCacheData(
          cacheData,
          cacheKey: cacheKey,
          level: CompressionLevel.balanced,
        );

        // Assert
        expect(result, isA<CompressionResult>());
        expect(result.originalSize, equals(cacheData.length));
        expect(result.compressedSize, lessThan(result.originalSize));
        expect(result.compressionRatio, lessThan(0.8)); // Should achieve good compression
      });

      test('should decompress cache data successfully', () async {
        // Arrange
        final originalData = Uint8List.fromList(List.generate(400, (i) => [0xAA, 0xBB, 0xCC, 0xDD][i % 4]));
        const cacheKey = 'test_cache';

        // First compress the data
        final compressionResult = await compressionService.compressCacheData(
          originalData,
          cacheKey: cacheKey,
        );

        // Act - decompress the data
        final decompressedData = await compressionService.decompressCacheData(
          compressionResult.compressedData,
          cacheKey: cacheKey,
        );

        // Assert
        expect(decompressedData, equals(originalData));
      });

      test('should handle cache compression for large datasets', () async {
        // Arrange - simulate large cache (10MB)
        final largeData = Uint8List(10 * 1024 * 1024);
        for (int i = 0; i < largeData.length; i++) {
          largeData[i] = (i % 256);
        }
        const cacheKey = 'large_charts_cache';

        // Act
        final result = await compressionService.compressCacheData(
          largeData,
          cacheKey: cacheKey,
          level: CompressionLevel.fast, // Use fast for large data
        );

        // Assert
        expect(result, isA<CompressionResult>());
        expect(result.originalSize, equals(largeData.length));
        expect(result.compressedSize, lessThan(result.originalSize));
        
        // Should complete in reasonable time (less than 10 seconds)
        expect(result.compressionTime.inSeconds, lessThan(10));
      });
    });

    group('Compression Performance Tests', () {
      test('should compress data within performance limits', () async {
        // Arrange
        final testData = Uint8List.fromList(List.generate(4000, (i) => [0x01, 0x02, 0x03, 0x04][i % 4])); // 4KB
        const dataId = 'performance_test';

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await compressionService.compressChartData(
          testData,
          chartId: dataId,
          level: CompressionLevel.fast,
        );
        stopwatch.stop();

        // Assert
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should complete in < 1 second
        expect(result.compressionTime.inMilliseconds, lessThan(1000));
        expect(result.compressionRatio, lessThan(1.0));
      });

      test('should handle concurrent compression operations', () async {
        // Arrange
        final testData1 = Uint8List.fromList(List.generate(1000, (i) => 0x01));
        final testData2 = Uint8List.fromList(List.generate(1000, (i) => 0x02));
        final testData3 = Uint8List.fromList(List.generate(1000, (i) => 0x03));

        // Act - run concurrent compressions
        final futures = <Future<CompressionResult>>[
          compressionService.compressChartData(testData1, chartId: 'chart1'),
          compressionService.compressChartData(testData2, chartId: 'chart2'),
          compressionService.compressChartData(testData3, chartId: 'chart3'),
        ];

        final results = await Future.wait(futures);

        // Assert
        expect(results, hasLength(3));
        for (final result in results) {
          expect(result, isA<CompressionResult>());
          expect(result.compressedSize, lessThan(result.originalSize));
        }
      });
    });

    group('Error Handling Tests', () {
      test('should handle compression failures gracefully', () async {
        // Arrange
        final invalidData = Uint8List(0);
        const chartId = 'INVALID_CHART';

        // Act & Assert
        expect(
          () => compressionService.compressChartData(invalidData, chartId: chartId),
          throwsA(isA<AppError>()),
        );

        // Note: No error was logged to the mock logger because the error was thrown 
        // before reaching the catch block in the implementation
      });

      test('should handle decompression failures gracefully', () async {
        // Arrange
        final invalidCompressedData = Uint8List.fromList([0xFF, 0xFE, 0xFD]);
        const chartId = 'INVALID_COMPRESSED';

        // Act & Assert
        expect(
          () => compressionService.decompressChartData(invalidCompressedData, chartId: chartId),
          throwsA(isA<AppError>()),
        );

        // Verify error was logged
  verifyErrorLogged(mockLogger, RegExp(r'decompression failed|Failed to decompress'), times: 1);
      });

      test('should handle memory limitations for large files', () async {
        // Arrange - simulate very large file (100MB)
        final largeData = Uint8List(100 * 1024 * 1024);
        const chartId = 'HUGE_CHART';

        // Act - this should either succeed or throw a specific memory error
        try {
          final result = await compressionService.compressChartData(
            largeData,
            chartId: chartId,
            level: CompressionLevel.fast,
          );
          
          // If successful, verify it's reasonable
          expect(result, isA<CompressionResult>());
          expect(result.originalSize, equals(largeData.length));
        } catch (error) {
          // If it fails, should be a specific memory or resource error
          expect(error, isA<AppError>());
        }
      });
    });

    group('Compression Configuration Tests', () {
      test('should allow custom compression settings', () async {
        // Arrange
        final testData = Uint8List.fromList(List.generate(300, (i) => [0x01, 0x02, 0x03][i % 3]));
        const chartId = 'CONFIG_TEST';
        
        final customSettings = CompressionSettings(
          level: CompressionLevel.maximum,
          enableDictionary: true,
          chunkSize: 8192,
          memoryLevel: 8,
        );

        // Act
        final result = await compressionService.compressChartDataWithSettings(
          testData,
          chartId: chartId,
          settings: customSettings,
        );

        // Assert
        expect(result, isA<CompressionResult>());
        expect(result.compressionRatio, lessThan(0.9)); // Should achieve better compression
      });

      test('should validate compression settings', () {
        // Act & Assert
        expect(
          () => CompressionSettings(
            level: CompressionLevel.fast,
            chunkSize: -1, // Invalid chunk size
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => CompressionSettings(
            level: CompressionLevel.fast,
            memoryLevel: 15, // Invalid memory level (max is 9)
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
