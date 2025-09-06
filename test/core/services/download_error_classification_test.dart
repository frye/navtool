import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/services/download_service.dart';

import 'download_phase2_features_test.mocks.dart';

void main() {
  group('DownloadService error code classification', () {
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorage;
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    late DownloadServiceImpl service;
    late Directory tempDir;

    setUp(() async {
      mockHttpClient = MockHttpClientService();
      mockStorage = MockStorageService();
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();
      tempDir = await Directory.systemTemp.createTemp('error_code_test');
      when(mockStorage.getChartsDirectory()).thenAnswer((_) async => tempDir);
      service = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorage,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
      );
    });

    tearDown(() async {
      service.dispose();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('classifies checksum mismatch', () async {
      const chartId = 'EC_CHKSUM';
      const url = 'https://example.com/chk.zip';
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
            'content-length': ['32'],
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
        final savePath = invocation.positionalArguments[1] as String;
        final f = File(savePath);
        await f.create(recursive: true);
        await f.writeAsBytes(
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
        final cb =
            invocation.namedArguments[#onReceiveProgress]
                as void Function(int, int)?;
        cb?.call(32, 32);
      });
      // Wrong checksum triggers mismatch
      try {
        await service.downloadChart(
          chartId,
          url,
          expectedChecksum:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        fail('Should throw AppError for checksum mismatch');
      } catch (_) {}
      final resume = await service.getResumeData(chartId);
      expect(resume, isNotNull);
      expect(resume!.lastErrorCode, equals(DownloadErrorCode.checksumMismatch));
    });

    test('classifies insufficient disk space preflight', () async {
      const chartId = 'EC_DISK';
      const url = 'https://example.com/big.zip';
      // HEAD returns huge size > heuristic threshold to trigger storage AppError
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
            'content-length': ['6442450944'],
          }),
        ),
      ); // 6GB
      try {
        await service.downloadChart(chartId, url);
        fail('Expected insufficient disk space error');
      } catch (_) {}
      final resume = await service.getResumeData(chartId);
      expect(resume, isNotNull);
      expect(
        resume!.lastErrorCode,
        equals(DownloadErrorCode.insufficientDiskSpace),
      );
    });

    test('classifies network timeout', () async {
      const chartId = 'EC_TIMEOUT';
      const url = 'https://example.com/timeout.zip';
      // HEAD small size success
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
            'content-length': ['16'],
          }),
        ),
      );
      // Force downloadFile to throw a timeout AppError
      when(
        mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).thenThrow(
        AppError.network(
          'Network timeout occurred. Please check your connection.',
        ),
      );
      try {
        await service.downloadChart(chartId, url);
        fail('Expected timeout error');
      } catch (_) {}
      final resume = await service.getResumeData(chartId);
      expect(resume, isNotNull);
      expect(resume!.lastErrorCode, equals(DownloadErrorCode.networkTimeout));
    });

    test('classifies generic network error', () async {
      const chartId = 'EC_NET';
      const url = 'https://example.com/net.zip';
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
            'content-length': ['10'],
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
      ).thenThrow(AppError.network('Some transient network failure'));
      try {
        await service.downloadChart(chartId, url);
        fail('expected network error');
      } catch (_) {}
      final resume = await service.getResumeData(chartId);
      expect(resume, isNotNull);
      expect(resume!.lastErrorCode, equals(DownloadErrorCode.network));
    });
  });
}
