import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/services/http_client_service.dart';

/// Helper to configure a mock [HttpClientService] for download-related tests
/// with deterministic behavior: successful HEAD/GET, simulated download
/// progress, and optional checksum mismatch scenarios.
///
/// Progress Normalization (Section C):
///   All progress values in the codebase are expressed as normalized
///   fractional values in the inclusive range [0.0, 1.0]. Tests must not
///   assume or tolerate percentage-style (0-100) progress emissions. Any
///   future producer emitting >1.0 would trigger a warning from the service
///   and be clamped. This utility therefore always invokes callbacks with
///   byte counts that translate to normalized fractions inside the service.
///
/// [fileContents] maps URL -> byte content to be written on download.
/// If omitted, a small default payload is used.
void configureDownloadHttpClientMock(
  dynamic mockHttpClient, {
  Map<String, List<int>>? fileContents,
  AppLogger? mockLogger,
  int totalSize = 1024,
  int progressChunks = 4,
}) {
  fileContents ??= {
    'http://example.com/chart1.zip': utf8.encode('chart1-data'),
    'http://example.com/chart2.zip': utf8.encode('chart2-data'),
    'https://test.com/chart.zip': utf8.encode('test-chart-data'),
  };

  // HEAD requests: return a 200 with content-length header.
  when(mockHttpClient.head(any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
          cancelToken: anyNamed('cancelToken')))
      .thenAnswer((invocation) async => Response(
            requestOptions: RequestOptions(path: invocation.positionalArguments.first as String),
            statusCode: 200,
            headers: Headers.fromMap({
              'content-length': [totalSize.toString()],
            }),
          ));

  // GET requests (range probes etc.): respond with subset or full bytes.
  when(mockHttpClient.get(any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
          cancelToken: anyNamed('cancelToken')))
      .thenAnswer((invocation) async {
    final url = invocation.positionalArguments.first as String;
    final data = fileContents![url] ?? utf8.encode('generic');
    return Response(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      data: data,
    );
  });

  // downloadFile simulation: writes bytes and invokes progress callback.
  when(mockHttpClient.downloadFile(any, any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
          resumeFrom: anyNamed('resumeFrom')))
      .thenAnswer((invocation) async {
    final url = invocation.positionalArguments[0] as String;
    final savePath = invocation.positionalArguments[1] as String;
    final onProgress =
        invocation.namedArguments[const Symbol('onReceiveProgress')] as void Function(int, int)?;

    final data = fileContents![url] ?? utf8.encode('generic');
    final chunkSize = (data.length / progressChunks).ceil();
    int sent = 0;
    for (int i = 0; i < progressChunks; i++) {
      await Future.delayed(const Duration(milliseconds: 5));
      sent = (i == progressChunks - 1) ? data.length : (i + 1) * chunkSize;
      if (sent > data.length) sent = data.length;
      onProgress?.call(sent, data.length);
    }

    final file = File(savePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
  });
}

/// Introduce a checksum mismatch by altering bytes after initial write.
Future<void> corruptDownloadedFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return;
  bytes[0] = bytes[0] ^ 0xFF; // invert first byte
  await file.writeAsBytes(bytes, flush: true);
}

/// Retry deletion of a directory to mitigate Windows file locking issues.
Future<void> retryDeleteDirectory(Directory dir,
    {int attempts = 5, Duration backoff = const Duration(milliseconds: 80)}) async {
  for (int i = 0; i < attempts; i++) {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    } catch (e) {
      if (i == attempts - 1) rethrow;
      await Future.delayed(backoff * (i + 1));
    }
  }
}

// NOTE: Progress expectation helper moved to progress_matchers.dart (alias
// expectProgressCloseTo / expectNormalizedProgress). This legacy helper was
// removed to centralize normalization logic (Issue #139 C3).
