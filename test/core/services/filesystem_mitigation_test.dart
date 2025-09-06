import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import '../../helpers/download_test_utils.dart';

// Reuse existing generated mocks from another test suite to avoid rebuild.
import 'download_service_impl_test.mocks.dart';

/// Focused tests for filesystem mitigation helpers invoked indirectly via downloadChart.
void main() {
  group('Filesystem Mitigation', () {
    late MockHttpClientService http;
    late MockStorageService storage;
    late MockAppLogger logger;
    late MockErrorHandler errors;
    late DownloadServiceImpl service;
    late Directory chartsDir;

    setUp(() async {
      http = MockHttpClientService();
      storage = MockStorageService();
      logger = MockAppLogger();
      errors = MockErrorHandler();
      chartsDir = await Directory.systemTemp.createTemp('fs_mitig_');
      when(storage.getChartsDirectory()).thenAnswer((_) async => chartsDir);
      service = DownloadServiceImpl(
        httpClient: http,
        storageService: storage,
        logger: logger,
        errorHandler: errors,
      );
      configureDownloadHttpClientMock(http);
    });

    tearDown(() async {
      if (await chartsDir.exists()) {
        await chartsDir.delete(recursive: true);
      }
    });

    test(
      'should overwrite existing file at final path via safe rename',
      () async {
        const chartId = 'X1';
        const url = 'http://example.com/X1.zip';
        final existing = File('${chartsDir.path}/X1.zip');
        await existing.writeAsBytes([9, 9, 9]);

        // Simulate a temp file outcome by letting download write through our stub
        when(
          http.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          final targetTempPath =
              invocation.positionalArguments[1] as String; // ends with .part
          final tempFile = File(targetTempPath);
          await tempFile.writeAsBytes([1, 2, 3, 4]);
        });

        await service.downloadChart(chartId, url);
        final finalFile = File('${chartsDir.path}/X1.zip');
        expect(
          await finalFile.exists(),
          isTrue,
          reason: 'Final file should exist after rename',
        );
        final bytes = await finalFile.readAsBytes();
        expect(bytes.length, 4);
      },
    );

    test(
      'should remove directory occupying final file path before rename',
      () async {
        const chartId = 'Y1';
        const url = 'http://example.com/Y1.zip';
        final blockingDir = Directory('${chartsDir.path}/Y1.zip');
        await blockingDir.create(); // same path where file must go

        when(
          http.downloadFile(
            any,
            any,
            cancelToken: anyNamed('cancelToken'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenAnswer((invocation) async {
          final targetTempPath =
              invocation.positionalArguments[1] as String; // .part
          await File(targetTempPath).writeAsBytes([5, 6, 7]);
        });

        await service.downloadChart(chartId, url);
        final finalFile = File('${chartsDir.path}/Y1.zip');
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.length(), 3);
      },
    );
  });
}
