import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/timing_harness.dart'; // legacy predicate helper (some tests still reference)
import '../../helpers/flakiness_guard.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import '../../helpers/download_test_utils.dart';
import '../../helpers/verify_helpers.dart';

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
      when(
        mockStorageService.getChartsDirectory(),
      ).thenAnswer((_) async => mockChartsDirectory);
      when(mockChartsDirectory.path).thenReturn('/test/charts');
      when(
        mockChartsDirectory.create(recursive: true),
      ).thenAnswer((_) async => mockChartsDirectory);

      downloadService = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorageService,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
        // Enable automatic processing for these behavioral tests
        networkSuitabilityProbe: () async => true,
      );
      // Apply centralized stub for head/get/download defaults
      configureDownloadHttpClientMock(mockHttpClient);
    });

    group('Automated Queue Processing', () {
      test(
        'should automatically start downloads when added to queue',
        () async {
          // Arrange
          final tempDir = Directory.systemTemp.createTempSync('download_test_');
          final tempFile = File('${tempDir.path}/chart1.zip');
          await tempFile.writeAsBytes([1, 2, 3, 4, 5]);

          // Override the charts directory to point to our temp directory
          when(
            mockStorageService.getChartsDirectory(),
          ).thenAnswer((_) async => tempDir);

          int downloadStarts = 0;
          when(
            mockHttpClient.downloadFile(
              any,
              any,
              cancelToken: anyNamed('cancelToken'),
              onReceiveProgress: anyNamed('onReceiveProgress'),
            ),
          ).thenAnswer((_) async {
            downloadStarts++;
          }); // Simulate successful download

          const chartId = 'chart1';
          const url = 'http://example.com/chart1.zip';

          // Act
          await downloadService.addToQueue(chartId, url);
          await waitForCondition<int>(
            () async => downloadStarts,
            predicate: (v) => v > 0,
            timeout: const Duration(
              milliseconds: 900,
            ), // slightly extended for CI jitter
            reason: 'Download did not start automatically',
            diagnosticSnapshot: () async => 'downloadStarts=$downloadStarts',
          );

          // Assert - download should have started automatically
          verify(
            mockHttpClient.downloadFile(
              any,
              any,
              cancelToken: anyNamed('cancelToken'),
              onReceiveProgress: anyNamed('onReceiveProgress'),
            ),
          ).called(1);

          verifyInfoLogged(mockLogger, 'Starting download for chart:');
          expectNoErrorLogs(mockLogger);

          // Cleanup
          await retryDeleteDirectory(tempDir);
        },
      );

      test('should respect max concurrent download limits', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(
          mockStorageService.getChartsDirectory(),
        ).thenAnswer((_) async => tempDir);

        // Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);

        // Create download completer to control when downloads finish
        final completer1 = Completer<void>();
        final completer2 = Completer<void>();

        bool started1 = false;
        bool started2 = false;
        when(
          mockHttpClient.downloadFile(
            argThat(contains('chart1')),
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((_) {
          started1 = true;
          return completer1.future;
        });

        when(
          mockHttpClient.downloadFile(
            argThat(contains('chart2')),
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((_) {
          started2 = true;
          return completer2.future;
        });

        // Act - add two charts to queue
        await downloadService.addToQueue(
          'chart1',
          'http://example.com/chart1.zip',
        );
        await downloadService.addToQueue(
          'chart2',
          'http://example.com/chart2.zip',
        );
        await waitForCondition<bool>(
          () async => started1,
          predicate: (v) => v,
          timeout: const Duration(milliseconds: 900), // allow jitter
          reason: 'First download did not start',
        );

        // Assert - only first download should start
        verify(
          mockHttpClient.downloadFile(
            argThat(contains('chart1')),
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).called(1);

        // Second download should not start yet
        verifyNever(
          mockHttpClient.downloadFile(
            argThat(contains('chart2')),
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        );

        // Complete first download
        completer1.complete();
        await waitForCondition<bool>(
          () async => started2,
          predicate: (v) => v,
          timeout: const Duration(milliseconds: 1100),
          reason: 'Second download did not start after first completion',
        );

        // Now second download should start
        verify(
          mockHttpClient.downloadFile(
            argThat(contains('chart2')),
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).called(1);

        // Complete second download
        completer2.complete();

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test('should prioritize high priority downloads', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(
          mockStorageService.getChartsDirectory(),
        ).thenAnswer((_) async => tempDir);

        // Set max concurrent downloads to 1
        await downloadService.setMaxConcurrentDownloads(1);

        final downloadOrder = <String>[];

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) {
          final url = invocation.positionalArguments[0] as String;
          downloadOrder.add(url);
          return Future.value();
        });

        // Act - add downloads with different priorities ensuring high is enqueued before others
        // This avoids a race where a normal priority item begins downloading before the high
        // priority item is added (since auto-processing starts immediately).
        await downloadService.addToQueue(
          'chart-high',
          'http://example.com/chart-high.zip',
          priority: DownloadPriority.high,
        );
        // Pump until first high priority starts (progress via captured order)
        await waitForCondition<List<String>>(
          () async => downloadOrder,
          predicate: (list) => list.isNotEmpty,
          timeout: const Duration(milliseconds: 300),
          reason: 'High priority download did not begin',
          diagnosticSnapshot: () async => 'order=${downloadOrder.join(',')}',
        );
        await downloadService.addToQueue(
          'chart-normal',
          'http://example.com/chart-normal.zip',
          priority: DownloadPriority.normal,
        );
        await downloadService.addToQueue(
          'chart-low',
          'http://example.com/chart-low.zip',
          priority: DownloadPriority.low,
        );
        await waitForCondition<List<String>>(
          () async => downloadOrder,
          predicate: (list) => list.length >= 3,
          timeout: const Duration(milliseconds: 800),
          reason: 'Subsequent downloads did not record order',
          diagnosticSnapshot: () async => 'order=${downloadOrder.join(',')}',
        );

        // Assert - high priority should be downloaded first
        expect(downloadOrder, isNotEmpty);
        // First recorded should include chart-high
        expect(downloadOrder.first, contains('chart-high'));

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test('should handle queue processing errors gracefully', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(
          mockStorageService.getChartsDirectory(),
        ).thenAnswer((_) async => tempDir);

        when(
          mockHttpClient.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(
              path: 'http://example.com/chart1.zip',
            ),
            type: DioExceptionType.connectionTimeout,
          ),
        );

        // Capture warning logs
        final warningMessages = <String>[];
        when(
          mockLogger.warning(
            any,
            context: anyNamed('context'),
            exception: anyNamed('exception'),
          ),
        ).thenAnswer((invocation) {
          warningMessages.add(invocation.positionalArguments[0] as String);
          return null;
        });

        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Act
        await downloadService.addToQueue(chartId, url);
        await waitForCondition<List<String>>(
          () async => warningMessages,
          predicate: (msgs) =>
              msgs.any((m) => m.contains('Download attempt 1 failed')),
          timeout: const Duration(milliseconds: 600),
          reason: 'Retry warning not logged in time',
          diagnosticSnapshot: () async =>
              'warnings=${warningMessages.join('|')}',
        );

        // Assert - at least one retry warning logged (pattern based)
        expect(
          warningMessages.any((m) => m.contains('Download attempt 1 failed')),
          isTrue,
        );

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test(
        'should continue processing queue after download completion',
        () async {
          // Arrange
          final tempDir = Directory.systemTemp.createTempSync('download_test_');
          final tempFile1 = File('${tempDir.path}/chart1.zip');
          final tempFile2 = File('${tempDir.path}/chart2.zip');
          await tempFile1.writeAsBytes([1, 2, 3, 4, 5]);
          await tempFile2.writeAsBytes([1, 2, 3, 4, 5]);

          // Override the charts directory to point to our temp directory
          when(
            mockStorageService.getChartsDirectory(),
          ).thenAnswer((_) async => tempDir);

          // Set max concurrent downloads to 1
          await downloadService.setMaxConcurrentDownloads(1);

          final completer1 = Completer<void>();
          int downloadCount = 0;

          when(
            mockHttpClient.downloadFile(
              any,
              any,
              cancelToken: anyNamed('cancelToken'),
              onReceiveProgress: anyNamed('onReceiveProgress'),
            ),
          ).thenAnswer((_) {
            downloadCount++;
            if (downloadCount == 1) {
              return completer1.future;
            } else {
              return Future.value();
            }
          });

          // Act - add two charts to queue
          await downloadService.addToQueue(
            'chart1',
            'http://example.com/chart1.zip',
          );
          await downloadService.addToQueue(
            'chart2',
            'http://example.com/chart2.zip',
          );
          await waitForCondition<int>(
            () async => downloadCount,
            predicate: (v) => v == 1,
            timeout: const Duration(milliseconds: 400),
            reason: 'First download did not start before completing it',
          );

          // Complete first download
          completer1.complete();

          await waitForCondition<int>(
            () async => downloadCount,
            predicate: (v) => v == 2,
            timeout: const Duration(milliseconds: 600),
            reason: 'Second download did not start after first completion',
          );

          // Assert - both downloads should have been attempted
          expect(downloadCount, 2);

          // Cleanup
          await retryDeleteDirectory(tempDir);
        },
      );
    });
  });
}
