import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import '../../helpers/timing_harness.dart';
import '../../helpers/download_test_utils.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../helpers/progress_matchers.dart';
import '../../helpers/verify_helpers.dart';

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
      when(
        mockStorageService.getChartsDirectory(),
      ).thenAnswer((_) async => tempDir);

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
        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          // Simulate file creation
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);

          // Simulate progress callbacks
          final onProgress =
              invocation.namedArguments[#onReceiveProgress]
                  as Function(int, int)?;
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
        verifyInfoLogged(
          mockLogger,
          'Starting download for chart: $chartId',
          expectedContext: 'Download',
        );
        verifyInfoLogged(
          mockLogger,
          'Chart download completed: $chartId',
          expectedContext: 'Download',
        );

        verify(
          mockHttpClient.downloadFile(
            url,
            argThat(contains('US5CA52M.zip')),
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).called(1);
      });

      test('should handle download failure gracefully', () async {
        // Arrange
        const chartId = 'INVALID_CHART';
        const url = 'https://invalid.url/chart.zip';

        // Mock download failure
        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenThrow(AppError.network('Download failed'));

        // Act & Assert
        await expectLater(
          downloadService.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );

        // Verify the download started (info log should be called)
        verifyInfoLogged(
          mockLogger,
          'Starting download for chart: $chartId',
          expectedContext: 'Download',
        );

        // Verify error handling was called
        verify(mockErrorHandler.handleError(any, any)).called(1);
      });

      test('should track download progress correctly', () async {
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        final testFile = File('${tempDir.path}/US5CA52M.zip');

        reset(mockHttpClient);
        when(
          mockHttpClient.head(
            any,
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
            cancelToken: anyNamed('cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 200,
            headers: Headers.fromMap({
              'content-length': ['100'],
            }),
          ),
        );
        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          final onProgress =
              invocation.namedArguments[#onReceiveProgress]
                  as void Function(int, int)?;
          onProgress?.call(25, 100);
          onProgress?.call(75, 100);
          onProgress?.call(100, 100);
          await testFile.create(recursive: true);
          await testFile.writeAsBytes(List.generate(100, (i) => i));
        });

        await downloadService.downloadChart(chartId, url);
        final snapshot = await downloadService
            .getDownloadProgress(chartId)
            .first;
        expect(snapshot, inInclusiveRange(0.0, 1.0));
        expectProgressCloseTo(snapshot, 1.0);
        expect(await testFile.exists(), isTrue);
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
        final downloadFuture = downloadService.downloadChart(
          chartId,
          'https://test.com/chart.zip',
        );
        await Future.delayed(const Duration(milliseconds: 30));
        await downloadService.pauseDownload(chartId);

        // Wait for download to complete/cancel
        try {
          await downloadFuture;
        } catch (_) {
          // Expected cancellation
        }

        // Assert
        verifyInfoLogged(
          mockLogger,
          'Download paused: $chartId',
          expectedContext: 'Download',
        );
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
        configureDownloadHttpClientMock(
          mockHttpClient,
          fileContents: {
            'https://test.com/chart.zip': List.generate(400, (i) => i % 256),
          },
          progressChunks: 20,
        );

        // Act
        final downloadFuture = downloadService.downloadChart(
          chartId,
          'https://test.com/chart.zip',
        );
        await Future.delayed(const Duration(milliseconds: 30));
        await downloadService.cancelDownload(chartId);

        try {
          await downloadFuture;
        } catch (_) {
          // Expected cancellation error
        }

        // Assert
        verifyInfoLogged(
          mockLogger,
          'Download cancelled: $chartId',
          expectedContext: 'Download',
        );
      });
    });

    group('Progress Tracking', () {
      test('should provide progress stream for active download', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final testFile = File('${tempDir.path}/US5CA52M.zip');

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);
          return null;
        });

        // Act
        final progressStream = downloadService.getDownloadProgress(chartId);

        // Assert
        expect(progressStream, isA<Stream<double>>());
      });

      test(
        'should emit initial 0.0 for unknown chart (lazy stream seed)',
        () async {
          // Arrange
          const unknownChartId = 'UNKNOWN_CHART';

          // Act
          final progressStream = downloadService.getDownloadProgress(
            unknownChartId,
          );
          final first = await progressStream.first.timeout(
            const Duration(milliseconds: 200),
          );

          // Assert
          expect(first, 0.0);
        },
      );
    });

    group('Error Handling', () {
      test('should handle network errors appropriately', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://invalid.url/chart.zip';

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.connectionError,
          ),
        );

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

        when(
          mockStorageService.getChartsDirectory(),
        ).thenThrow(AppError.storage('Storage not available'));

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
        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((_) async {}); // Don't create file

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

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          final onProgress =
              invocation.namedArguments[#onReceiveProgress]
                  as Function(int, int)?;

          // Simulate chunked download progress
          final totalSize = largeData.length;
          final chunkSize = 1024 * 1024; // 1MB chunks

          for (int i = 0; i < totalSize; i += chunkSize) {
            final end = (i + chunkSize < totalSize) ? i + chunkSize : totalSize;
            onProgress?.call(end, totalSize);
            // Yield to event loop without real time delay
            await Future(() {});
          }

          await testFile.writeAsBytes(largeData);
        });

        // Act
        final stopwatch = Stopwatch()..start();
        await downloadService.downloadChart(chartId, url);
        stopwatch.stop();

        // Assert
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(5000),
        ); // Should complete within 5 seconds
        expect(await testFile.exists(), isTrue);
        expect(await testFile.length(), equals(largeData.length));
      });
    });

    group('File Management', () {
      test('should generate correct file names from URLs', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        final testFile = File('${tempDir.path}/US5CA52M.zip');

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          final filePath = invocation.positionalArguments[1] as String;
          expect(filePath, contains('US5CA52M.zip'));
          await testFile.writeAsBytes([1, 2, 3, 4, 5]);
        });

        // Act
        await downloadService.downloadChart(chartId, url);

        // Assert
        verify(
          mockHttpClient.downloadFile(
            url,
            argThat(contains('US5CA52M.zip')),
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).called(1);
      });

      test('should clean up partial downloads on cancellation', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const url = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
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
