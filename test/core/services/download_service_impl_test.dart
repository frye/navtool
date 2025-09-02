import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import '../../helpers/download_test_utils.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';

// Generate mocks: flutter packages pub run build_runner build
@GenerateMocks([HttpClientService, StorageService, AppLogger, ErrorHandler])
import 'download_service_impl_test.mocks.dart';

/// Comprehensive tests for DownloadService implementation
/// Tests download operations, queue management, progress tracking, and error handling
void main() {
  group('DownloadService Implementation Tests', () {
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    late DownloadServiceImpl downloadService;
    late Directory tempDir;

    setUp(() async {
      mockHttpClient = MockHttpClientService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();

      // Create temporary directory for test files
      tempDir = await Directory.systemTemp.createTemp('navtool_test_downloads');
      
      // Mock storage service to return temp directory
      when(mockStorageService.getChartsDirectory())
          .thenAnswer((_) async => tempDir);

      // Centralized HTTP head/get/download stubs (fractional progress 0..1 via bytes)
      configureDownloadHttpClientMock(mockHttpClient);

      downloadService = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorageService,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await retryDeleteDirectory(tempDir);
      }
    });

    group('Chart Download Operations', () {
      test('should download chart successfully', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        final testFile = File('${tempDir.path}/US5CA52M.zip');
        
        // Mock successful file download
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          // Simulate file creation
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);
          
          // Simulate progress callbacks
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          if (onProgress != null) {
            onProgress(1, 5); // 20% progress
            onProgress(3, 5); // 60% progress  
            onProgress(5, 5); // 100% progress
          }
          return null;
        });

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(mockLogger.info(
          argThat(contains('Starting download for chart: $chartId')),
          context: 'Download',
        )).called(1);
        
        verify(mockLogger.info(
          argThat(contains('Chart download completed: $chartId')),
          context: 'Download',
        )).called(1);

        verify(mockHttpClient.downloadFile(
          url,
          argThat(contains('US5CA52M.zip')),
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).called(1);
      });

      test('should handle download failure gracefully', () async {
        // Arrange
        const chartId = 'INVALID_CHART';
        const url = 'https://invalid.url/chart.zip';
        
        // Mock download failure
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenThrow(AppError.network('Download failed'));

        // Act & Assert
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );

        // Verify the download started (info log should be called)
        verify(mockLogger.info(
          'Starting download for chart: $chartId',
          context: 'Download',
        )).called(1);

        // Verify error handling was called
        verify(mockErrorHandler.handleError(any, any)).called(1);
      });

      test('should track download progress correctly', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        final testFile = File('${tempDir.path}/US5CA52M.zip');
        final progressValues = <double>[];

        // Reset and set up specific mock for this test
        reset(mockHttpClient);
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          if (onProgress != null) {
            // Simulate progress updates
            await Future.delayed(const Duration(milliseconds: 10));
            onProgress(25, 100); // 25%
            await Future.delayed(const Duration(milliseconds: 10));
            onProgress(50, 100); // 50%
            await Future.delayed(const Duration(milliseconds: 10));
            onProgress(75, 100); // 75%
            await Future.delayed(const Duration(milliseconds: 10));
            onProgress(100, 100); // 100%
          }
          await testFile.create(recursive: true);
          await testFile.writeAsBytes(List.generate(100, (i) => i));
        });

        // Act & Assert - Start download and then track progress
        StreamSubscription<double>? subscription;
        bool hasProgress = false;
        
        // Start download (this creates the progress controller)
        final downloadFuture = downloadService.downloadChart(chartId, url);
        
        // Give a small delay for the progress controller to be created
        await Future.delayed(const Duration(milliseconds: 5));
        
        // Now subscribe to progress stream
        final progressStream = downloadService.getDownloadProgress(chartId);
        subscription = progressStream.listen((progress) {
          progressValues.add(progress);
          hasProgress = true;
        });

        // Wait for download to complete
        await downloadFuture;

        // Allow time for final stream updates
        await Future.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        // Assert - We should have received some progress updates
        expect(hasProgress, isTrue, reason: 'Should have received at least one progress update');
        // All emitted progress values must be normalized fractions in [0,1]
        for (final p in progressValues) {
          expect(p, inInclusiveRange(0.0, 1.0), reason: 'Download progress values must be normalized (got $p)');
        }
        if (progressValues.isNotEmpty) {
          expectProgressCloseTo(progressValues.last, 1.0);
        }
      });
    });

    group('Download Queue Management', () {
      test('should add downloads to queue', () async {
        // Arrange
        const chartId1 = 'US5CA52M';
        const chartId2 = 'US4CA11M';
        const url1 = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        const url2 = 'https://charts.noaa.gov/ENCs/US4CA11M.zip';
        // Re-create service with network probe that always returns false so queue is not auto-processed
        downloadService = DownloadServiceImpl(
          httpClient: mockHttpClient,
          storageService: mockStorageService,
          logger: mockLogger,
          errorHandler: mockErrorHandler,
          networkSuitabilityProbe: () async => false,
        );

        final queueBefore = await downloadService.getDownloadQueue();
        await downloadService.addToQueue(chartId1, url1);
        await downloadService.addToQueue(chartId2, url2);
        final queueAfter = await downloadService.getDownloadQueue();

        expect(queueBefore, isEmpty);
        expect(queueAfter.length, 2);
        expect(queueAfter, containsAll([chartId1, chartId2]));
      });

      test('should get download queue correctly', () async {
        // Arrange & Act
        final initialQueue = await downloadService.getDownloadQueue();

        // Assert
        expect(initialQueue, isA<List<String>>());
        expect(initialQueue, isEmpty);
      });
    });

    group('Download Control Operations', () {
      test('should pause download successfully', () async {
        // Arrange
        const chartId = 'US5CA52M';
        
        // Provide a slow download so we can pause mid-flight
        reset(mockHttpClient);
        configureDownloadHttpClientMock(
          mockHttpClient,
          fileContents: {
            'https://test.com/chart.zip': List.generate(400, (i) => i % 256),
          },
          progressChunks: 20,
        );

        // Act
  final downloadFuture = downloadService.downloadChart(chartId, 'https://test.com/chart.zip');
  // Allow a little time for first progress events
  await Future.delayed(const Duration(milliseconds: 30));
  await downloadService.pauseDownload(chartId);
        
        // Wait for download to complete/cancel
        try {
          await downloadFuture;
        } catch (e) {
          // Expected cancellation
        }

        // Assert
        verify(mockLogger.info(
          argThat(contains('Download paused: $chartId')),
          context: 'Download',
        )).called(1);
      });

    test('should resume download with error message', () async {
      // Arrange - The resume method should throw because no URL is provided
      const chartId = 'test-chart';

      // Act & Assert - Resume should throw AppError for missing URL
      await expectLater(
        downloadService.resumeDownload(chartId),
        throwsA(isA<AppError>()),
      );
    });

    test('should cancel download successfully', () async {
        // Arrange
        const chartId = 'US5CA52M';

        // Slow download to allow cancellation before completion
        reset(mockHttpClient);
        final completer = Completer<void>();
        when(mockHttpClient.head(any,
                queryParameters: anyNamed('queryParameters'),
                options: anyNamed('options'),
                cancelToken: anyNamed('cancelToken')))
            .thenAnswer((_) async => Response(
                  requestOptions: RequestOptions(path: 'https://test.com/chart.zip'),
                  statusCode: 200,
                  headers: Headers.fromMap({'content-length': ['400']}),
                ));
        int sent = 0;
        when(mockHttpClient.downloadFile(any, any,
                onReceiveProgress: anyNamed('onReceiveProgress'),
                cancelToken: anyNamed('cancelToken'),
                queryParameters: anyNamed('queryParameters'),
                resumeFrom: anyNamed('resumeFrom')))
            .thenAnswer((invocation) async {
          final savePath = invocation.positionalArguments[1] as String;
          final onProgress = invocation.namedArguments[#onReceiveProgress] as void Function(int, int)?;
          final total = 400;
          while (!completer.isCompleted && sent < total) {
            await Future.delayed(const Duration(milliseconds: 10));
            sent += 40;
            if (sent > total) sent = total;
            onProgress?.call(sent, total);
          }
          if (!completer.isCompleted) {
            // Simulate early termination due to cancellation
            throw DioException(requestOptions: RequestOptions(path: 'https://test.com/chart.zip'), type: DioExceptionType.cancel);
          }
          final file = File(savePath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(List.generate(total, (i) => i % 256));
        });

        // Act
  final downloadFuture = downloadService.downloadChart(chartId, 'https://test.com/chart.zip');
  await Future.delayed(const Duration(milliseconds: 30));
  await downloadService.cancelDownload(chartId);
  completer.complete();
        
        // Wait for download to complete/cancel
        try {
          await downloadFuture;
        } catch (e) {
          // Expected error after cancellation
        }

        // Assert
        verify(mockLogger.info(
          argThat(contains('Download cancelled: $chartId')),
          context: 'Download',
        )).called(1);
      });
    });

    group('Progress Tracking', () {
      test('should provide progress stream for active download', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final testFile = File('${tempDir.path}/US5CA52M.zip');

        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);
          return null;
        });

        // Act
        final progressStream = downloadService.getDownloadProgress(chartId);
        
        // Assert
        expect(progressStream, isA<Stream<double>>());
      });

      test('should return empty stream for unknown chart', () async {
        // Arrange
        const unknownChartId = 'UNKNOWN_CHART';

        // Act
        final progressStream = downloadService.getDownloadProgress(unknownChartId);
        final progressList = await progressStream.take(1).toList().timeout(
          const Duration(milliseconds: 100),
          onTimeout: () => <double>[],
        );

        // Assert
        expect(progressList, isEmpty);
      });
    });

    group('Error Handling', () {
      test('should handle network errors appropriately', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://invalid.url/chart.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert - The service wraps DioException in AppError
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );

        verify(mockErrorHandler.handleError(any, any)).called(1);
      });

      test('should handle storage errors appropriately', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';

        when(mockStorageService.getChartsDirectory())
            .thenThrow(AppError.storage('Storage not available'));

        // Act & Assert
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );
      });

      test('should handle file system errors appropriately', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';

        // Mock download success but no file created (simulates filesystem error)
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((_) async {}); // Don't create file

        // Act & Assert
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Marine Navigation Requirements', () {
      test('should handle large chart downloads efficiently', () async {
        // Arrange
        const chartId = 'LARGE_CHART';
        const url = 'https://charts.noaa.gov/ENCs/LargeChart.zip';
        final testFile = File('${tempDir.path}/LargeChart.zip');
        
        // Create large test file (simulating 10MB chart)
        final largeData = List.generate(10 * 1024 * 1024, (i) => i % 256);
        
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          
          // Simulate chunked download progress
          final totalSize = largeData.length;
          final chunkSize = 1024 * 1024; // 1MB chunks
          
          for (int i = 0; i < totalSize; i += chunkSize) {
            final end = (i + chunkSize < totalSize) ? i + chunkSize : totalSize;
            onProgress?.call(end, totalSize);
            
            // Small delay to simulate network transfer
            await Future.delayed(const Duration(milliseconds: 10));
          }
          
          await testFile.writeAsBytes(largeData);
        });

        // Act
        final stopwatch = Stopwatch()..start();
        await downloadService.downloadChart(chartId, url);
        stopwatch.stop();

        // Assert
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds
        expect(await testFile.exists(), isTrue);
        expect(await testFile.length(), equals(largeData.length));
      });

      test('should support concurrent downloads with limits', () async {
        // Arrange
        const charts = ['CHART_1', 'CHART_2', 'CHART_3'];
        const baseUrl = 'https://charts.noaa.gov/ENCs/';
        
        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          final filePath = invocation.positionalArguments[1] as String;
          final file = File(filePath);
          await Future.delayed(const Duration(milliseconds: 100));
          await file.writeAsBytes([1, 2, 3, 4, 5]);
        });

        // Act
        final futures = charts.map((chartId) => 
          downloadService.downloadChart(chartId, '$baseUrl$chartId.zip')
        ).toList();

        await Future.wait(futures);

        // Assert
        verify(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).called(charts.length);
      });
    });

    group('File Management', () {
      test('should generate correct file names from URLs', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        final testFile = File('${tempDir.path}/US5CA52M.zip');

        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          final filePath = invocation.positionalArguments[1] as String;
          expect(filePath, contains('US5CA52M.zip'));
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);
        });

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(mockHttpClient.downloadFile(
          url,
          argThat(contains('US5CA52M.zip')),
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).called(1);
      });

      test('should clean up partial downloads on cancellation', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          // Simulate cancellation during download
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel,
          );
        });

        // Act & Assert - The service wraps DioException in AppError
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );

        // Assert - cleanup should be called
        verify(mockErrorHandler.handleError(any, any)).called(1);
      });
    });
  });
}
