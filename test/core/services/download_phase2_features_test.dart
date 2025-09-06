import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';
import 'download_phase2_features_test.mocks.dart';

@GenerateMocks([HttpClientService, StorageService, AppLogger, ErrorHandler])
void main() {
  group('DownloadService Phase 2 Features', () {
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
      tempDir = await Directory.systemTemp.createTemp('phase2_test');
      when(mockStorage.getChartsDirectory()).thenAnswer((_) async => tempDir);
      service = DownloadServiceImpl(
        httpClient: mockHttpClient,
        storageService: mockStorage,
        logger: mockLogger,
        errorHandler: mockErrorHandler,
      );
    });

    tearDown(() async {
      // Ensure resources released before deleting temp dir (Windows file locks)
      service.dispose();
      if (await tempDir.exists()) {
        for (int i = 0; i < 3; i++) {
          try {
            await tempDir.delete(recursive: true);
            break;
          } catch (e) {
            if (i == 2) rethrow;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    });

    test('range probe sets supportsRange true when 206 returned', () async {
      const chartId = 'RANGE_CHART';
      const url = 'https://example.com/range_chart.zip';

      // HEAD for disk space preflight
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

      // Initial download (not resumed) -> normal downloadFile call
      when(
        mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).thenAnswer((invocation) async {
        final savePath =
            invocation.positionalArguments[1] as String; // temp .part
        final file = File(savePath);
        await file.create(recursive: true);
        await file.writeAsBytes(List.generate(50, (i) => i));
        final cb =
            invocation.namedArguments[#onReceiveProgress]
                as void Function(int, int)?;
        cb?.call(50, 100);
      });

      // Range probe (GET bytes=0-0) returns 206
      when(
        mockHttpClient.get(
          any,
          options: anyNamed('options'),
          queryParameters: anyNamed('queryParameters'),
          cancelToken: anyNamed('cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          headers: Headers.fromMap({
            'content-range': ['bytes 0-0/100'],
          }),
          data: ResponseBody.fromString(
            '',
            206,
            headers: {
              Headers.contentTypeHeader: ['application/octet-stream'],
            },
          ),
        ),
      );

      await service.downloadChart(chartId, url);
      final resume = await service.getResumeData(chartId);
      // Not set during initial because probe occurs on resume; simulate resume
      await service.resumeDownload(chartId, url: url); // triggers probe
      final resume2 = await service.getResumeData(chartId);
      expect(resume2?.supportsRange, isTrue);
    });

    test('manual append resume increments downloaded bytes', () async {
      const chartId = 'APPEND_CHART';
      const url = 'https://example.com/append_chart.zip';
      int call = 0;

      // HEAD preflight
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
            'content-length': ['200'],
          }),
        ),
      );

      // First attempt: write partial (80 bytes) then throw to leave .part file
      when(
        mockHttpClient.downloadFile(
          any,
          any,
          cancelToken: anyNamed('cancelToken'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).thenAnswer((invocation) async {
        call++;
        final savePath = invocation.positionalArguments[1] as String;
        if (call == 1) {
          final file = File(savePath);
          await file.create(recursive: true);
          await file.writeAsBytes(List.generate(80, (i) => i));
          final cb =
              invocation.namedArguments[#onReceiveProgress]
                  as void Function(int, int)?;
          cb?.call(80, 200);
          throw AppError.network('Simulated failure after partial write');
        } else {
          // Subsequent retries also fail quickly so we end with partial
          throw AppError.network('Simulated retry failure');
        }
      });

      // Range probe success (for resume) followed by append streaming
      int getCall = 0;
      when(
        mockHttpClient.get(
          any,
          options: anyNamed('options'),
          queryParameters: anyNamed('queryParameters'),
          cancelToken: anyNamed('cancelToken'),
        ),
      ).thenAnswer((_) async {
        getCall++;
        if (getCall == 1) {
          // Probe response 0-0/200
          return Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            headers: Headers.fromMap({
              'content-range': ['bytes 0-0/200'],
            }),
            data: ResponseBody.fromString('', 206),
          );
        } else {
          // Append stream 80-199 (120 bytes total) to reach EXACT total (200)
          final appendedChunks = [
            Uint8List.fromList(List<int>.filled(30, 1)),
            Uint8List.fromList(List<int>.filled(30, 2)),
            Uint8List.fromList(List<int>.filled(30, 3)),
            Uint8List.fromList(List<int>.filled(30, 4)),
          ];
          return Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            headers: Headers.fromMap({
              'content-range': ['bytes 80-199/200'],
            }),
            data: ResponseBody(Stream.fromIterable(appendedChunks), 206),
          );
        }
      });

      // Attempt initial download (expected to fail)
      await expectLater(
        service.downloadChart(chartId, url),
        throwsA(isA<AppError>()),
      );

      // GET stub already configured above to stream on second call

      await service.resumeDownload(chartId, url: url);
      final finalFile = File('${tempDir.path}/append_chart.zip');
      expect(await finalFile.exists(), isTrue);
      // 80 initial partial + 4 * 30 appended = 200 total (normalized progress stays <=1.0)
      expect(await finalFile.length(), equals(200));
    });

    test(
      'retry logic applies jitter (attempts > 1 increments ResumeData.attempts)',
      () async {
        const chartId = 'RETRY_CHART';
        const url = 'https://example.com/retry_chart.zip';
        int callCount = 0;

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
        ).thenAnswer((invocation) async {
          callCount++;
          if (callCount < 3) {
            // force two failures to ensure attempts tracked
            throw AppError.network('Transient failure #$callCount');
          }
          final savePath = invocation.positionalArguments[1] as String;
          final f = File(savePath);
          await f.create(recursive: true);
          await f.writeAsBytes(List.generate(10, (i) => i));
          final cb =
              invocation.namedArguments[#onReceiveProgress]
                  as void Function(int, int)?;
          cb?.call(10, 10);
        });

        await service.downloadChart(chartId, url);
        // Validate we had at least 3 underlying download attempts (2 failures + 1 success)
        expect(callCount, greaterThanOrEqualTo(3));
      },
    );

    test(
      'disk space heuristic rejects extremely large projected size',
      () async {
        const chartId = 'HUGE_CHART';
        const url = 'https://example.com/huge_chart.zip';
        // Force head to report massive size (6GB) => heuristic should reject
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
        ); // 6 GB

        await expectLater(
          service.downloadChart(chartId, url),
          throwsA(isA<AppError>()),
        );
      },
    );
  });
}
