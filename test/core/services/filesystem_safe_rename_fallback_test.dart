import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';

// Reuse mocks from existing generated file to avoid new build step.
import 'download_service_impl_test.mocks.dart';

/// Focused tests for _safeRename retry & fallback copy behavior via injected renameImpl hook.
void main() {
  group('Safe rename retry & fallback', () {
    late MockHttpClientService http;
    late MockStorageService storage;
    late MockAppLogger logger;
    late MockErrorHandler errors;
    late Directory chartsDir;
    late List<String> renameAttempts;

    setUp(() async {
      http = MockHttpClientService();
      storage = MockStorageService();
      logger = MockAppLogger();
      errors = MockErrorHandler();
      chartsDir = await Directory.systemTemp.createTemp('safe_rename_');
      when(storage.getChartsDirectory()).thenAnswer((_) async => chartsDir);
      renameAttempts = [];
    });

    tearDown(() async {
      if (await chartsDir.exists()) {
        await chartsDir.delete(recursive: true);
      }
    });

    test('retries rename before succeeding (no fallback copy)', () async {
      // Arrange: first two attempts throw, third succeeds by performing real rename.
      final injected = (File temp, String finalPath) async {
        renameAttempts.add(finalPath);
        if (renameAttempts.length < 3) {
          throw const FileSystemException('simulated transient rename failure');
        }
        // Perform actual rename on third try
        await temp.rename(finalPath);
      };

      final service = DownloadServiceImpl(
        httpClient: http,
        storageService: storage,
        logger: logger,
        errorHandler: errors,
        renameImpl: injected,
      );

      const chartId = 'R1';
      const url = 'http://example.com/R1.bin';

      when(http.head(any,
        queryParameters: anyNamed('queryParameters'),
        options: anyNamed('options'),
        cancelToken: anyNamed('cancelToken'))).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: url), statusCode: 200, headers: Headers.fromMap({'content-length': ['4']})));

      when(http.downloadFile(any, any,
        cancelToken: anyNamed('cancelToken'),
        onReceiveProgress: anyNamed('onReceiveProgress'),
        resumeFrom: anyNamed('resumeFrom'))).thenAnswer((invocation) async {
          final savePath = invocation.positionalArguments[1] as String;
          final f = File(savePath);
          await f.create(recursive: true);
          await f.writeAsBytes([1,2,3,4]);
        });

      // Act
      await service.downloadChart(chartId, url);

      // Assert
      expect(renameAttempts.length, 3, reason: 'Should attempt rename thrice before success');
      final finalFile = File('${chartsDir.path}/R1.bin');
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.length(), 4);
    });

    test('falls back to copy after repeated rename failures', () async {
      // Arrange: all attempts throw forcing copy fallback.
      final injected = (File temp, String finalPath) async {
        renameAttempts.add(finalPath);
        throw const FileSystemException('persistent rename failure');
      };

      final service = DownloadServiceImpl(
        httpClient: http,
        storageService: storage,
        logger: logger,
        errorHandler: errors,
        renameImpl: injected,
      );

      const chartId = 'R2';
      const url = 'http://example.com/R2.bin';

      when(http.head(any,
        queryParameters: anyNamed('queryParameters'),
        options: anyNamed('options'),
        cancelToken: anyNamed('cancelToken'))).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: url), statusCode: 200, headers: Headers.fromMap({'content-length': ['3']})));

      when(http.downloadFile(any, any,
        cancelToken: anyNamed('cancelToken'),
        onReceiveProgress: anyNamed('onReceiveProgress'),
        resumeFrom: anyNamed('resumeFrom'))).thenAnswer((invocation) async {
          final savePath = invocation.positionalArguments[1] as String;
          final f = File(savePath);
          await f.create(recursive: true);
          await f.writeAsBytes([7,8,9]);
        });

      // Act
      await service.downloadChart(chartId, url);

      // Assert
      expect(renameAttempts.length, 3, reason: 'Should attempt configured max attempts before fallback');
      final finalFile = File('${chartsDir.path}/R2.bin');
      expect(await finalFile.exists(), isTrue, reason: 'Copy fallback should produce final file');
      expect(await finalFile.length(), 3);
    });
  });
}
