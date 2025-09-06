import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';

// Reuse generated mocks from existing Phase 2 feature test
import 'download_phase2_features_test.mocks.dart';

void main() {
  group('DownloadService checksum mismatch handling', () {
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
      tempDir = await Directory.systemTemp.createTemp('checksum_test');
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

    test('mismatch deletes temp file and throws AppError', () async {
      const chartId = 'CHK1';
      const url = 'https://example.com/sample_chart.zip';

      // HEAD preflight (size 64 bytes)
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
            'content-length': ['64'],
          }),
        ),
      );

      // Successful download producing deterministic 64 bytes
      when(
        mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          resumeFrom: anyNamed('resumeFrom'),
        ),
      ).thenAnswer((invocation) async {
        final savePath =
            invocation.positionalArguments[1] as String; // temp .part
        final file = File(savePath);
        await file.create(recursive: true);
        final data = Uint8List.fromList(List<int>.generate(64, (i) => i));
        await file.writeAsBytes(data);
        final cb =
            invocation.namedArguments[#onReceiveProgress]
                as void Function(int, int)?;
        cb?.call(64, 64);
      });

      // Provide an intentionally incorrect checksum (actual will be different)
      const wrongChecksum =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      AppError? thrown;
      try {
        await service.downloadChart(
          chartId,
          url,
          expectedChecksum: wrongChecksum,
        );
        fail('Expected checksum mismatch to throw');
      } catch (e) {
        expect(e, isA<AppError>());
        thrown = e as AppError;
        expect(thrown.message.toLowerCase(), contains('checksum'));
      }

      // Ensure temp and final files are not present
      final fileName = 'sample_chart.zip';
      final finalFile = File('${tempDir.path}/$fileName');
      final tempFile = File('${tempDir.path}/$fileName.part');
      expect(
        await finalFile.exists(),
        isFalse,
        reason: 'Final file must not remain on mismatch',
      );
      expect(
        await tempFile.exists(),
        isFalse,
        reason: 'Temp file should be deleted after mismatch',
      );

      // Resume data should exist but show 0 downloaded bytes (temp was deleted before catch captured size)
      final resume = await service.getResumeData(chartId);
      expect(resume, isNotNull);
      expect(
        resume!.downloadedBytes,
        0,
        reason: 'Partial bytes recorded as 0 after deletion',
      );
    });
  });
}
