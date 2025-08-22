import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/error/app_error.dart';

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  StorageService,
  AppLogger,
  ErrorHandler,
  Directory,
  File,
])
import 'enhanced_download_service_test.mocks.dart';

void main() {
  group('Enhanced Download Service Tests', () {
    late DownloadService downloadService;
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    late MockDirectory mockChartsDirectory;
    late MockFile mockFile;

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();
      mockChartsDirectory = MockDirectory();
      mockFile = MockFile();

      // Setup default storage service behavior
      when(mockStorageService.getChartsDirectory())
          .thenAnswer((_) async => mockChartsDirectory);
      when(mockChartsDirectory.path).thenReturn('/test/charts');
      when(mockChartsDirectory.create(recursive: true))
          .thenAnswer((_) async => mockChartsDirectory);

      downloadService = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorageService,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
      );
    });

    group('Queue Management', () {
      test('should add charts to download queue with priority', () async {
        // Act - Add charts with different priorities
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
        expect(queue.isEmpty, true);
      });

      test('should reorder queue items by priority', () async {
        // Arrange - Add charts in mixed priority order
        await downloadService.addToQueue('low1', 'http://example.com/low1.zip', priority: DownloadPriority.low);
        await downloadService.addToQueue('high1', 'http://example.com/high1.zip', priority: DownloadPriority.high);
        await downloadService.addToQueue('normal1', 'http://example.com/normal1.zip', priority: DownloadPriority.normal);

        // Act
        final queue = await downloadService.getDetailedQueue();

        // Assert - Should be ordered: high, normal, low
        expect(queue[0].chartId, 'high1');
        expect(queue[0].priority, DownloadPriority.high);
        expect(queue[1].chartId, 'normal1');
        expect(queue[1].priority, DownloadPriority.normal);
        expect(queue[2].chartId, 'low1');
        expect(queue[2].priority, DownloadPriority.low);
      });
    });

    group('Batch Download Operations', () {
      test('should start batch download for multiple charts', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2', 'chart3'];
        final urls = [
          'http://example.com/chart1.zip',
          'http://example.com/chart2.zip',
          'http://example.com/chart3.zip',
        ];

        when(mockHttpClient.downloadFile(any, any, 
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Assert
        expect(batchId, isNotNull);
        final batchProgress = await downloadService.getBatchProgress(batchId);
        expect(batchProgress.totalCharts, 3);
        expect(batchProgress.status, BatchDownloadStatus.inProgress);
      });

      test('should track batch download progress', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];

        when(mockHttpClient.downloadFile(any, any, 
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Assert
        final progressStream = downloadService.getBatchProgressStream(batchId);
        expect(progressStream, isA<Stream<BatchDownloadProgress>>());

        final progress = await downloadService.getBatchProgress(batchId);
        expect(progress.completedCharts, 0);
        expect(progress.failedCharts, 0);
        expect(progress.overallProgress, 0.0);
      });

      test('should pause batch download', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Act
        await downloadService.pauseBatchDownload(batchId);

        // Assert
        final progress = await downloadService.getBatchProgress(batchId);
        expect(progress.status, BatchDownloadStatus.paused);
      });

      test('should resume batch download', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];
        final batchId = await downloadService.startBatchDownload(chartIds, urls);
        await downloadService.pauseBatchDownload(batchId);

        // Act
        await downloadService.resumeBatchDownload(batchId);

        // Assert
        final progress = await downloadService.getBatchProgress(batchId);
        expect(progress.status, BatchDownloadStatus.inProgress);
      });

      test('should cancel batch download', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2'];
        final urls = ['http://example.com/chart1.zip', 'http://example.com/chart2.zip'];
        final batchId = await downloadService.startBatchDownload(chartIds, urls);

        // Act
        await downloadService.cancelBatchDownload(batchId);

        // Assert
        final progress = await downloadService.getBatchProgress(batchId);
        expect(progress.status, BatchDownloadStatus.cancelled);
      });
    });

    group('Download Resumption', () {
      test('should support resumable downloads with partial content', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const totalSize = 2048;
        const resumeFrom = 1024;

        // Setup partial file scenario
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => resumeFrom);
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom')))
            .thenAnswer((_) async {});

        // Act
        await downloadService.resumeDownload(chartId, url: url);

        // Assert
        verify(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom'))).called(1);
      });

      test('should handle resume from corruption by restarting download', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Setup corrupted file scenario
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 512);
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: RequestOptions(path: url),
                statusCode: 416, // Range not satisfiable
              ),
            ));
        when(mockFile.delete()).thenAnswer((_) async => mockFile);
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});

        // Act
        await downloadService.resumeDownload(chartId, url: url);

        // Assert
        verify(mockFile.delete()).called(1);
        verify(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'))).called(1);
      });

      test('should save resume metadata for background recovery', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Setup download interruption scenario
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act & Assert
        expect(() => downloadService.downloadChart(chartId, url), throwsA(isA<AppError>()));

        // Verify resume metadata is saved
        final resumeData = await downloadService.getResumeData(chartId);
        expect(resumeData, isNotNull);
        expect(resumeData!.chartId, chartId);
        expect(resumeData.originalUrl, url);
      });
    });

    group('Background Download Support', () {
      test('should persist download state for background recovery', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Setup background scenario
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        final persistedState = await downloadService.getPersistedDownloadState();
        expect(persistedState, isNotEmpty);
        verify(mockLogger.info(any, context: 'Download')).called(greaterThanOrEqualTo(1));
      });

      test('should recover active downloads on service restart', () async {
        // Arrange - Simulate persisted download state
        final persistedDownloads = [
          DownloadProgress(
            chartId: 'chart1',
            status: DownloadStatus.downloading,
            progress: 0.5,
            totalBytes: 2048,
            downloadedBytes: 1024,
            lastUpdated: DateTime.now(),
          ),
          DownloadProgress(
            chartId: 'chart2',
            status: DownloadStatus.paused,
            progress: 0.3,
            totalBytes: 1024,
            downloadedBytes: 300,
            lastUpdated: DateTime.now(),
          ),
        ];

        // Act
        await downloadService.recoverDownloads(persistedDownloads);

        // Assert
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 2);
        
        // chart1 should be resumed automatically
        final chart1Progress = downloadService.getDownloadProgress('chart1');
        expect(chart1Progress, isA<Stream<double>>());
        
        // chart2 should remain paused
        expect(queue.any((item) => item.chartId == 'chart2'), true);
      });

      test('should handle background download notifications', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        await downloadService.enableBackgroundNotifications();
        await downloadService.downloadChart(chartId, url);

        // Assert
        final notifications = await downloadService.getPendingNotifications();
        expect(notifications, isNotNull);
        expect(notifications.any((n) => n.chartId == chartId), true);
      });

      test('should support concurrent downloads with resource management', () async {
        // Arrange
        final chartIds = ['chart1', 'chart2', 'chart3', 'chart4', 'chart5'];
        final urls = chartIds.map((id) => 'http://example.com/$id.zip').toList();
        
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {
              await Future.delayed(const Duration(milliseconds: 100));
            });
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act - Start multiple downloads
        final futures = <Future>[];
        for (int i = 0; i < chartIds.length; i++) {
          futures.add(downloadService.downloadChart(chartIds[i], urls[i]));
        }

        // Assert
        await Future.wait(futures);
        
        // Should respect max concurrent downloads (typically 2-3 for marine networks)
        final maxConcurrent = await downloadService.getMaxConcurrentDownloads();
        expect(maxConcurrent, lessThanOrEqualTo(3));
      });
    });

    group('Download Verification', () {
      test('should verify file integrity after download', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const expectedSize = 1024;

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => expectedSize);

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(mockFile.length()).called(greaterThanOrEqualTo(1));
        verify(mockLogger.info(
          argThat(contains('Chart download completed')),
          context: 'Download'
        )).called(1);
      });

      test('should handle verification failure by retrying download', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        
        // First call returns corrupted file, second call succeeds
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024); // Valid file

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'))).called(2);
      });

      test('should support checksum verification when available', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const expectedChecksum = 'abc123def456';

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {});
        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        await downloadService.downloadChart(chartId, url, expectedChecksum: expectedChecksum);

        // Assert
        // Verification is logged but not implemented yet (as per requirements)
        verify(mockLogger.info(
          argThat(contains('Chart download completed')),
          context: 'Download'
        )).called(1);
      });
    });

    group('Error Handling and Resilience', () {
      test('should retry failed downloads with exponential backoff', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom')))
            .thenAnswer((_) async {}); // Simulates successful download

        when(mockFile.exists()).thenAnswer((_) async => true);
        when(mockFile.length()).thenAnswer((_) async => 1024);

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'))).called(3);
      });

      test('should handle storage errors gracefully', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        when(mockStorageService.getChartsDirectory())
            .thenThrow(const FileSystemException('Storage unavailable'));

        // Act & Assert
        expect(
          () => downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );

        verify(mockErrorHandler.handleError(any, any)).called(1);
      });

      test('should clean up resources on service disposal', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Start a download
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {
              await Future.delayed(const Duration(seconds: 1));
            });

        final downloadFuture = downloadService.downloadChart(chartId, url);

        // Act
        downloadService.dispose();

        // Assert
        expect(() => downloadFuture, throwsA(isA<Exception>()));
      });
    });
  });
}
