import 'dart:async';
import 'dart:io';
import 'dart:convert';
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

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  StorageService,
  AppLogger,
  ErrorHandler,
  Directory,
  File,
])
import 'download_persistence_test.mocks.dart';

void main() {
  group('Download Background Persistence Tests', () {
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

    group('Background Download State Persistence', () {
      test('should save download state to disk', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final stateFile = File('${tempDir.path}/.download_state.json');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';

        // Add item to queue
        await downloadService.addToQueue(chartId, url, 
          priority: DownloadPriority.high,
          expectedChecksum: 'test_checksum');

        // Act
        await downloadService.getPersistedDownloadState();

        // Assert
        expect(await stateFile.exists(), isTrue);

        final stateJson = await stateFile.readAsString();
        final state = jsonDecode(stateJson) as Map<String, dynamic>;

        expect(state.containsKey('queue'), isTrue);
        expect(state.containsKey('downloads'), isTrue);
        expect(state.containsKey('resumeData'), isTrue);

        final queue = state['queue'] as List<dynamic>;
        expect(queue.length, 1);
        expect(queue[0]['chartId'], chartId);
        expect(queue[0]['url'], url);
        expect(queue[0]['priority'], 'high');
        expect(queue[0]['expectedChecksum'], 'test_checksum');

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should load download state from disk', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final stateFile = File('${tempDir.path}/.download_state.json');

        // Create test state data
        final testState = {
          'downloads': {
            'chart1': {
              'chartId': 'chart1',
              'status': 'downloading',
              'progress': 0.5,
              'totalBytes': 1000,
              'downloadedBytes': 500,
              'lastUpdated': DateTime.now().toIso8601String(),
            }
          },
          'resumeData': {
            'chart1': {
              'chartId': 'chart1',
              'originalUrl': 'http://example.com/chart1.zip',
              'downloadedBytes': 500,
              'lastAttempt': DateTime.now().toIso8601String(),
              'checksum': 'test_checksum',
            }
          },
          'queue': [
            {
              'chartId': 'chart2',
              'url': 'http://example.com/chart2.zip',
              'priority': 'normal',
              'addedAt': DateTime.now().toIso8601String(),
              'expectedChecksum': null,
            }
          ],
        };

        await stateFile.writeAsString(jsonEncode(testState));

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Act
        await downloadService.recoverDownloads([]);

        // Assert
        verify(mockLogger.info(
          argThat(contains('Download state loaded from disk')),
          context: 'Download'
        )).called(1);

        // Verify queue is loaded
        final queue = await downloadService.getDetailedQueue();
        expect(queue.length, 1);
        expect(queue[0].chartId, 'chart2');
        expect(queue[0].url, 'http://example.com/chart2.zip');

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should handle missing state file gracefully', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory (no state file)
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Act
        await downloadService.recoverDownloads([]);

        // Assert
        verify(mockLogger.debug(
          argThat(contains('No persistent download state found')),
          context: 'Download'
        )).called(1);

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should handle corrupted state file gracefully', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final stateFile = File('${tempDir.path}/.download_state.json');

        // Write corrupted JSON
        await stateFile.writeAsString('invalid json content');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Act
        await downloadService.recoverDownloads([]);

        // Assert
        verify(mockLogger.warning(
          argThat(contains('Failed to load download state')),
          context: 'Download'
        )).called(1);

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });

    group('Resume Data Persistence', () {
      test('should save resume data with checksum information', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const checksum = 'test_checksum';

        // Simulate a download failure to trigger resume data saving
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act
        try {
          await downloadService.downloadChart(chartId, url, expectedChecksum: checksum);
        } catch (e) {
          // Expected to fail
        }

        // Wait for async persistence
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        final stateFile = File('${tempDir.path}/.download_state.json');
        expect(await stateFile.exists(), isTrue);

        final stateJson = await stateFile.readAsString();
        final state = jsonDecode(stateJson) as Map<String, dynamic>;

        expect(state.containsKey('resumeData'), isTrue);
        final resumeData = state['resumeData'] as Map<String, dynamic>;
        expect(resumeData.containsKey(chartId), isTrue);
        expect(resumeData[chartId]['checksum'], checksum);

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should restore resume data on recovery', () async {
        // Arrange
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        final stateFile = File('${tempDir.path}/.download_state.json');

        const chartId = 'chart1';
        const checksum = 'test_checksum';

        // Create test state with resume data
        final testState = {
          'downloads': {},
          'resumeData': {
            chartId: {
              'chartId': chartId,
              'originalUrl': 'http://example.com/chart1.zip',
              'downloadedBytes': 500,
              'lastAttempt': DateTime.now().toIso8601String(),
              'checksum': checksum,
            }
          },
          'queue': [],
        };

        await stateFile.writeAsString(jsonEncode(testState));

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // Act
        await downloadService.recoverDownloads([]);

        // Assert - verify resume data is available
        final resumeData = await downloadService.getResumeData(chartId);
        expect(resumeData, isNotNull);
        expect(resumeData!.chartId, chartId);
        expect(resumeData.checksum, checksum);

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });
  });
}