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

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  StorageService,
  AppLogger,
  ErrorHandler,
  Directory,
  File,
])
import 'download_queue_processing_test.mocks.dart';

void main() {
  group('Download Queue Processing Tests', () {
    late DownloadService downloadService;
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    late MockDirectory mockChartsDirectory;

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();
      mockChartsDirectory = MockDirectory();

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

    group('Automated Queue Processing', () {
      test('should automatically start downloads when added to queue', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final tempFile = File('${tempDir.path}/chart1.zip');
        await tempFile.writeAsBytes([1, 2, 3, 4, 5]);

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) async {}); // Simulate successful download

        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Act
        await downloadService.addToQueue(chartId, url);

        // Give time for async processing
        await Future.delayed(Duration(milliseconds: 100));

        // Assert - download should have started automatically
        verify(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .called(1);

        verify(mockLogger.info(
          argThat(contains('Starting download for chart: $chartId')),
          context: 'Download'
        )).called(1);

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should respect max concurrent download limits', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);

        // Create download completer to control when downloads finish
        final completer1 = Completer<void>();
        final completer2 = Completer<void>();

        when(mockHttpClient.downloadFile(
          argThat(contains('chart1')), any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) => completer1.future);

        when(mockHttpClient.downloadFile(
          argThat(contains('chart2')), any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) => completer2.future);

        // Act - add two charts to queue
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        await downloadService.addToQueue('chart2', 'http://example.com/chart2.zip');

        // Give time for processing
        await Future.delayed(Duration(milliseconds: 100));

        // Assert - only first download should start
        verify(mockHttpClient.downloadFile(
          argThat(contains('chart1')), any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .called(1);

        // Second download should not start yet
        verifyNever(mockHttpClient.downloadFile(
          argThat(contains('chart2')), any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')));

        // Complete first download
        completer1.complete();
        await Future.delayed(Duration(milliseconds: 100));

        // Now second download should start
        verify(mockHttpClient.downloadFile(
          argThat(contains('chart2')), any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .called(1);

        // Complete second download
        completer2.complete();

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should prioritize high priority downloads', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);

        final downloadOrder = <String>[];
        
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((invocation) {
              final url = invocation.positionalArguments[0] as String;
              downloadOrder.add(url);
              return Future.value();
            });

        // Act - add downloads with different priorities
        await downloadService.addToQueue('chart-normal', 'http://example.com/chart-normal.zip', 
          priority: DownloadPriority.normal);
        await downloadService.addToQueue('chart-high', 'http://example.com/chart-high.zip', 
          priority: DownloadPriority.high);
        await downloadService.addToQueue('chart-low', 'http://example.com/chart-low.zip', 
          priority: DownloadPriority.low);

        // Give time for processing
        await Future.delayed(Duration(milliseconds: 200));

        // Assert - high priority should be downloaded first
        expect(downloadOrder.length, greaterThanOrEqualTo(1));
        expect(downloadOrder[0], contains('chart-high'));

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should handle queue processing errors gracefully', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: 'http://example.com/chart1.zip'),
              type: DioExceptionType.connectionTimeout,
            ));

        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Act
        await downloadService.addToQueue(chartId, url);

        // Give time for processing and error handling
        await Future.delayed(Duration(milliseconds: 200));

        // Assert - error should be logged
        verify(mockLogger.error(
          argThat(contains('Chart download failed: $chartId')),
          exception: anyNamed('exception'),
          context: 'Download'
        )).called(1);

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should continue processing queue after download completion', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final tempFile1 = File('${tempDir.path}/chart1.zip');
        final tempFile2 = File('${tempDir.path}/chart2.zip');
        await tempFile1.writeAsBytes([1, 2, 3, 4, 5]);
        await tempFile2.writeAsBytes([1, 2, 3, 4, 5]);

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);

        final completer1 = Completer<void>();
        int downloadCount = 0;

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenAnswer((_) {
              downloadCount++;
              if (downloadCount == 1) {
                return completer1.future;
              } else {
                return Future.value();
              }
            });

        // Act - add two charts to queue
        await downloadService.addToQueue('chart1', 'http://example.com/chart1.zip');
        await downloadService.addToQueue('chart2', 'http://example.com/chart2.zip');

        // Give time for first download to start
        await Future.delayed(Duration(milliseconds: 100));

        // Complete first download
        completer1.complete();

        // Give time for second download to start
        await Future.delayed(Duration(milliseconds: 100));

        // Assert - both downloads should have been attempted
        expect(downloadCount, 2);

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });
  });
}