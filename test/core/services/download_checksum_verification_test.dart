import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import '../../helpers/verify_helpers.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';
import '../../helpers/download_test_utils.dart';

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  StorageService,
  AppLogger,
  ErrorHandler,
  Directory,
  File,
])
import 'download_checksum_verification_test.mocks.dart';

void main() {
  group('Download Checksum Verification Tests', () {
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
      configureDownloadHttpClientMock(mockHttpClient);
    });

    group('File Integrity Verification', () {
      test('should verify checksum successfully when checksums match', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const testData = 'test file content';
        final testBytes = utf8.encode(testData);
        final expectedChecksum = sha256.convert(testBytes).toString();

        // Create a real temporary file for this test
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        // Centralized mock will create the file; we pre-stage expected bytes via override
        // Override downloadFile to write .part then rename path logic will move to final
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom'))).thenAnswer((invocation) async {
            final savePath = invocation.positionalArguments[1] as String; // tempFilePath (.part)
            final tempFile = File(savePath);
            await tempFile.parent.create(recursive: true);
            await tempFile.writeAsBytes(testBytes, flush: true);
            // Also create the final file path in case service branch skips rename
            if (savePath.endsWith('.part')) {
              final finalPath = savePath.substring(0, savePath.length - 5);
              final finalFile = File(finalPath);
              await finalFile.writeAsBytes(testBytes, flush: true);
            }
            final onProgress = invocation.namedArguments[#onReceiveProgress] as void Function(int,int)?;
            onProgress?.call(testBytes.length, testBytes.length);
          });

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // (Removed redundant stub that overrode file-writing behavior)

        // Act
        await downloadService.downloadChart(chartId, url, expectedChecksum: expectedChecksum);

        // Assert
        verifyInfoLogged(mockLogger, 'Checksum verification passed', expectedContext: 'Download');
        verifyInfoLogged(mockLogger, 'Chart download completed', expectedContext: 'Download');

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test('should fail verification when checksums do not match', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const testData = 'test file content';
        final testBytes = utf8.encode(testData);
        const wrongChecksum = 'wrong_checksum_value';

        // Create a real temporary file for this test
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom'))).thenAnswer((invocation) async {
            final savePath = invocation.positionalArguments[1] as String;
            final tempFile = File(savePath);
            await tempFile.parent.create(recursive: true);
            await tempFile.writeAsBytes(testBytes, flush: true);
            if (savePath.endsWith('.part')) {
              final finalPath = savePath.substring(0, savePath.length - 5);
              final finalFile = File(finalPath);
              await finalFile.writeAsBytes(testBytes, flush: true);
            }
            final onProgress = invocation.namedArguments[#onReceiveProgress] as void Function(int,int)?;
            onProgress?.call(testBytes.length, testBytes.length);
          });

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // (Removed redundant stub that overrode file-writing behavior)

        // Act & Assert
        await expectLater(
          downloadService.downloadChart(chartId, url, expectedChecksum: wrongChecksum),
          throwsA(isA<AppError>().having((e) => e.message, 'message', contains('checksum verification'))),
        );

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test('should handle checksum calculation errors gracefully', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const expectedChecksum = 'abc123def456';

        // Create a temporary directory but no file (to simulate missing file)
        final tempDir = Directory.systemTemp.createTempSync('download_test_');

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress')))
            .thenThrow(Exception('Download failed'));

        // Act & Assert
        expect(
          () => downloadService.downloadChart(chartId, url, expectedChecksum: expectedChecksum),
          throwsException,
        );

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });

      test('should skip verification when no checksum is provided', () async {
        // Arrange
        const chartId = 'chart1';
        const url = 'http://example.com/chart1.zip';
        const testData = 'test file content';
        final testBytes = utf8.encode(testData);

        // Create a real temporary file for this test
        final tempDir = Directory.systemTemp.createTempSync('download_test_');
        when(mockHttpClient.downloadFile(any, any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom'))).thenAnswer((invocation) async {
            final savePath = invocation.positionalArguments[1] as String;
            final tempFile = File(savePath);
            await tempFile.parent.create(recursive: true);
            await tempFile.writeAsBytes(testBytes, flush: true);
            if (savePath.endsWith('.part')) {
              final finalPath = savePath.substring(0, savePath.length - 5);
              final finalFile = File(finalPath);
              await finalFile.writeAsBytes(testBytes, flush: true);
            }
            final onProgress = invocation.namedArguments[#onReceiveProgress] as void Function(int,int)?;
            onProgress?.call(testBytes.length, testBytes.length);
          });

        // Override the charts directory to point to our temp directory
        when(mockStorageService.getChartsDirectory())
            .thenAnswer((_) async => tempDir);

        // (Removed redundant stub that overrode file-writing behavior)

        // Act
        await downloadService.downloadChart(chartId, url); // No checksum provided

        // Assert - should complete without verification
        verifyInfoLogged(mockLogger, 'Chart download completed', expectedContext: 'Download');
        // Should NOT call checksum verification (keep explicit negative verify for clarity)
        verifyNever(mockLogger.info(argThat(contains('Checksum verification passed')), context: anyNamed('context')));

        // Cleanup
        await retryDeleteDirectory(tempDir);
      });
    });
  });
}