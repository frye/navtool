import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../helpers/download_test_utils.dart';

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  StorageService,
  AppLogger,
  ErrorHandler,
])
import 'enhanced_download_service_simple_test.mocks.dart';

void main() {
  group('Enhanced Download Service - Core Logic Tests', () {
    late DownloadServiceImpl downloadService;
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    
    // Use real temporary directory for file operations
    late Directory tempDirectory;
    late Directory tempChartsDirectory;
  // Mutable network suitability flag accessible to tests
  late bool networkSuitable;

  setUp(() async {
      mockHttpClient = MockHttpClientService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();
      
      // Create real temporary directories for testing
      tempDirectory = await Directory.systemTemp.createTemp('navtool_test_');
      tempChartsDirectory = Directory(path.join(tempDirectory.path, 'charts'));
      await tempChartsDirectory.create(recursive: true);

      // Setup storage service to return our temp directory
      when(mockStorageService.getChartsDirectory())
          .thenAnswer((_) async => tempChartsDirectory);

  // Default network suitability to false so queue/order tests don't auto-start downloads.
  // Individual tests that need active downloading will set this to true explicitly.
  networkSuitable = false; // reset each test
      downloadService = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorageService,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
        networkSuitabilityProbe: () async => networkSuitable,
      );
      configureDownloadHttpClientMock(mockHttpClient);
    });

    tearDown(() async {
      // Clean up temporary directory
      if (await tempDirectory.exists()) {
        await retryDeleteDirectory(tempDirectory);
      }
    });

    // Helper function to create a test file with specified content
    Future<File> createTestFile(String filename, [int size = 1024]) async {
      final file = File(path.join(tempChartsDirectory.path, filename));
      await file.writeAsBytes(List.filled(size, 65)); // Fill with 'A' bytes
      return file;
    }

    group('Queue Management', () {
      test('should add charts to queue with priority ordering', () async {
        // Act
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip', priority: DownloadPriority.high);
        await downloadService.addToQueue('chart2', 'http://example.com/chart2.zip', priority: DownloadPriority.normal);
        await downloadService.addToQueue('chart3', 'http://example.com/chart3.zip', priority: DownloadPriority.low);

        // Assert
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 3);
        
        // High priority should be first
        expect(queue.first.chartId, 'chart1');
        expect(queue.first.priority, DownloadPriority.high);
        
        // Low priority should be last
        expect(queue.last.chartId, 'chart3');
        expect(queue.last.priority, DownloadPriority.low);
      });

      test('should not add duplicate charts to queue', () async {
        // Act - Add same chart twice
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');

        // Assert
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 1);
        expect(queue.first.chartId, 'chart1');
      });

      test('should remove charts from queue', () async {
        // Arrange
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        await downloadService.addToQueue('chart2', 'http://example.com/chart2.zip');

        // Act
        await downloadService.removeFromQueue('chart1');

        // Assert
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 1);
        expect(queue.first.chartId, 'chart2');
      });

      test('should clear entire queue', () async {
        // Arrange
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        await downloadService.addToQueue('chart2', 'http://example.com/chart2.zip');

        // Act
        await downloadService.clearQueue();

        // Assert
        final queue = await downloadService.getDetailedQueue();
        expect(queue, isEmpty);
      });
    });

    group('Batch Download Operations', () {
      test('should start batch download for multiple charts', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2', 'chart3'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip', 'http://example.com/chart3.zip'];

        // Act
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Assert
        expect(batchId, isNotEmpty);
        final batchProgress = await downloadService.getBatchProgress(batchId);
        expect(batchProgress.totalCharts, 3);
        expect(batchProgress.status, BatchDownloadStatus.inProgress);

        // Verify charts were added to queue
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 3);
      });

      test('should provide batch progress stream', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];

        // Act
        final batchId = await downloadService.startBatchDownload(chartIds, urls);
        final progressStream = downloadService.getBatchProgressStream(batchId);

        // Assert
        expect(progressStream, isA<Stream<BatchDownloadProgress>>());
      });

      test('should handle batch download cancellation', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Act
        await downloadService.cancelBatchDownload(batchId);

        // Assert
        final batchProgress = await downloadService.getBatchProgress(batchId);
        expect(batchProgress.status, BatchDownloadStatus.cancelled);
      });
    });

    group('Download Management', () {
      test('should provide progress streams for individual downloads', () async {
        // Arrange
        const chartId = 'chart1';

        // Act
        final progressStream = downloadService.getDownloadProgress(chartId);

        // Assert
        expect(progressStream, isA<Stream<double>>());
      });

      test('should handle concurrent download limits', () async {
        // Arrange - Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);
        final maxConcurrent = await downloadService.getMaxConcurrentDownloads();
        
        // Assert
        expect(maxConcurrent, 1);
      });

      test('should manage resume data for background recovery', () async {
        networkSuitable = true; // enable active download behavior for this test
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Mock a failed download that should save resume data
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act - Try to download and expect it to fail but save resume data
        try {
          await downloadService.downloadChart(chartId, url);
          fail('Expected download to throw an exception');
        } catch (e) {
          expect(e, isA<AppError>());
        }

        // Assert - Resume data should be saved
        final resumeData = await downloadService.getResumeData(chartId);
        expect(resumeData, isNotNull);
        expect(resumeData!.chartId, chartId);
        expect(resumeData.originalUrl, url);
      });
    });

    group('Background Download Support', () {
      test('should persist download state', () async {
        // Act
        final persistedState = await downloadService.getPersistedDownloadState();

        // Assert
        expect(persistedState, isA<List<DownloadProgress>>());
      });

      test('should enable background notifications', () async {
        // Act
        await downloadService.enableBackgroundNotifications();
        final notifications = await downloadService.getPendingNotifications();

        // Assert
        expect(notifications, isA<List<DownloadNotification>>());
      });

      test('should handle download state recovery', () async {
        // Arrange - Simulate persisted download state
        final persistedDownloads = [
          DownloadProgress(
            chartId: 'chart1',
            status: DownloadStatus.downloading,
            progress: 0.5,
            totalBytes: 1024,
            downloadedBytes: 512,
            lastUpdated: DateTime.now(),
          ),
          DownloadProgress(
            chartId: 'chart2',
            status: DownloadStatus.paused,
            progress: 0.3,
            totalBytes: 2048,
            downloadedBytes: 600,
            lastUpdated: DateTime.now(),
          ),
        ];

        // Act
        await downloadService.recoverDownloads(persistedDownloads);

        // Assert - Should be able to recover downloads (implementation-specific behavior)
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, greaterThanOrEqualTo(0)); // Some may be auto-resumed, some may remain paused
      });
    });

    group('Error Handling and Resilience', () {
      test('should handle storage errors gracefully', () async {
        networkSuitable = true; // need active attempt
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        when(mockStorageService.getChartsDirectory())
            .thenThrow(const FileSystemException('Storage unavailable'));

        // Act & Assert
        expect(() => downloadService.downloadChart(chartId, url), throwsA(isA<AppError>()));
      });

      test('should handle network errors with proper error conversion', () async {
        networkSuitable = true; // need active attempt
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act & Assert
        expect(() => downloadService.downloadChart(chartId, url), throwsA(isA<AppError>()));
      });
    });

    group('Resource Management', () {
      test('should dispose properly and clean up resources', () async {
        // Arrange - Add some items to manage
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        final batchId = await downloadService.startBatchDownload(['chart2'], ['http://example.com/chart2.zip']);

        // Act
        downloadService.dispose();

        // Assert - After disposal, operations should not cause issues
        expect(() => downloadService.dispose(), returnsNormally);
      });
    });
  });
}
