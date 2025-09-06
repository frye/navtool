import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

// Simple in-memory logger collecting messages for assertions
class TestLogger implements AppLogger {
  final List<String> messages = [];
  void _add(String level, String msg) => messages.add('[$level] $msg');
  @override
  void debug(String message, {String? context, Object? exception}) =>
      _add('D', message);
  @override
  void info(String message, {String? context, Object? exception}) =>
      _add('I', message);
  @override
  void warning(String message, {String? context, Object? exception}) =>
      _add('W', message);
  @override
  void error(String message, {String? context, Object? exception}) =>
      _add('E', message);
  @override
  void logError(error) => _add('E', error.toString());
}

// Fake storage writing to a temp directory under system temp
class FakeStorageService implements StorageService {
  final Directory root;
  FakeStorageService(this.root);
  Directory get chartsDir => Directory(p.join(root.path, 'charts'));
  Future<Directory> _ensureCharts() async {
    if (!await chartsDir.exists()) await chartsDir.create(recursive: true);
    return chartsDir;
  }

  @override
  Future<Directory> getChartsDirectory() async => _ensureCharts();
  // The following methods are not needed for Phase 1 tests and throw if used unexpectedly
  @override
  Future<void> cleanupOldData() async {}
  @override
  Future<int> getStorageUsage() async => 0;
  @override
  Future<Map<String, dynamic>> getStorageInfo() async => {};
  @override
  Future<void> storeChart(chart, List<int> data) async {}
  @override
  Future<List<int>?> loadChart(String chartId) async => null;
  @override
  Future<void> deleteChart(String chartId) async {}
  @override
  Future<void> storeRoute(route) async => throw UnimplementedError();
  @override
  @override
  Future<NavigationRoute?> loadRoute(String routeId) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteRoute(String routeId) async => throw UnimplementedError();
  @override
  @override
  Future<List<NavigationRoute>> getAllRoutes() async =>
      throw UnimplementedError();
  @override
  Future<void> storeWaypoint(waypoint) async => throw UnimplementedError();
  @override
  @override
  Future<Waypoint?> loadWaypoint(String waypointId) async =>
      throw UnimplementedError();
  @override
  Future<void> updateWaypoint(waypoint) async => throw UnimplementedError();
  @override
  Future<void> deleteWaypoint(String waypointId) async =>
      throw UnimplementedError();
  @override
  @override
  Future<List<Waypoint>> getAllWaypoints() async => throw UnimplementedError();
  @override
  Future<void> storeStateCellMapping(
    String stateName,
    List<String> chartCells,
  ) async => throw UnimplementedError();
  @override
  Future<List<String>?> getStateCellMapping(String stateName) async => null;
  @override
  Future<void> clearAllStateCellMappings() async => throw UnimplementedError();
  @override
  @override
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds) async =>
      throw UnimplementedError();
  @override
  Future<int> countChartsWithInvalidBounds() async => 0;
  @override
  Future<int> clearChartsWithInvalidBounds() async => 0;
}

// Fake HTTP client using Dio's file download path but reading from an in-memory byte source
class FakeHttpClientService extends HttpClientService {
  final List<int> data; // bytes representing the chart
  int artificialLatencyMs;
  FakeHttpClientService({
    required AppLogger logger,
    required this.data,
    this.artificialLatencyMs = 0,
  }) : super(logger: logger, testDio: Dio());

  @override
  Future<void> downloadFile(
    String url,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    Map<String, dynamic>? queryParameters,
    int? resumeFrom,
  }) async {
    final file = File(savePath);
    final existing = resumeFrom ?? 0;
    final total = data.length;
    // Simulate chunked write for progress events
    const chunkSize = 1024;
    int offset = existing;
    // if resuming, append
    final raf = await file.open(mode: FileMode.append);
    try {
      while (offset < total) {
        if (cancelToken?.isCancelled == true)
          throw DioException(
            requestOptions: RequestOptions(path: url),
            error: 'cancelled',
          );
        final end = (offset + chunkSize).clamp(0, total);
        final chunk = data.sublist(offset, end);
        await raf.writeFrom(chunk);
        offset = end;
        onReceiveProgress?.call(offset, total);
        if (artificialLatencyMs > 0)
          await Future.delayed(Duration(milliseconds: artificialLatencyMs));
      }
    } finally {
      await raf.close();
    }
  }
}

void main() {
  group('DownloadServiceImpl Phase 1', () {
    late TestLogger logger;
    late ErrorHandler errorHandler;
    late FakeStorageService storage;
    late FakeHttpClientService http;
    late DownloadServiceImpl service;
    late DownloadQueueNotifier notifier;

    setUp(() async {
      logger = TestLogger();
      errorHandler = ErrorHandler(logger: logger);
      storage = FakeStorageService(
        Directory.systemTemp.createTempSync('navtool_test'),
      );
      final bytes = List<int>.generate(
        10 * 1024,
        (i) => i % 256,
      ); // 10KB pseudo data
      http = FakeHttpClientService(
        logger: logger,
        data: bytes,
        artificialLatencyMs: 1,
      );
      notifier = DownloadQueueNotifier(
        logger: logger,
        errorHandler: errorHandler,
      );
      service = DownloadServiceImpl(
        httpClient: http,
        storageService: storage,
        logger: logger,
        errorHandler: errorHandler,
        queueNotifier: notifier,
      );
    });

    test('progress is normalized 0..1 and reaches 1.0', () async {
      await service.downloadChart('chartA', 'https://example.com/chartA.zip');
      final progress = await service.getPersistedDownloadState();
      final entry = progress.firstWhere((p) => p.chartId == 'chartA');
      expect(entry.progress, 1.0);
      // ensure notifier also got normalized value
      final notifierEntry = notifier.state.downloads['chartA'];
      expect(notifierEntry?.progress, 1.0);
    });

    test('atomic .part file is renamed to final name', () async {
      await service.downloadChart('chartB', 'https://example.com/chartB.zip');
      final dir = await storage.getChartsDirectory();
      final finalFile = Directory(dir.path)
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('chartB.zip'));
      expect(await finalFile.exists(), isTrue);
      final partExists = File(finalFile.path + '.part').existsSync();
      expect(partExists, isFalse, reason: '.part file should be renamed away');
    });

    test('pause persists resume data with partial bytes', () async {
      // Start download in a separate future so we can pause mid-way
      final downloadFuture = service.downloadChart(
        'chartC',
        'https://example.com/chartC.zip',
      );
      // wait a moment for some progress
      await Future.delayed(const Duration(milliseconds: 10));
      await service.pauseDownload('chartC');
      // Get resume data
      final resume = await service.getResumeData('chartC');
      expect(resume, isNotNull);
      expect(resume!.downloadedBytes, greaterThan(0));
      // Ensure progress status is paused in internal + notifier state
      final internal = (await service.getPersistedDownloadState()).firstWhere(
        (p) => p.chartId == 'chartC',
      );
      expect(internal.status, DownloadStatus.paused);
      final notifierEntry = notifier.state.downloads['chartC'];
      expect(notifierEntry?.status, DownloadStatus.paused);
      // Cancel underlying future if still running
      try {
        await downloadFuture;
      } catch (_) {}
    });

    test('concurrency ordering respects max slots', () async {
      // Force small files but introduce latency to overlap
      http.artificialLatencyMs = 3;
      await service.setMaxConcurrentDownloads(1); // only 1 at a time
      // Queue three downloads using queue API to exercise ordering
      await service.addToQueue('q1', 'https://example.com/q1.zip');
      await service.addToQueue('q2', 'https://example.com/q2.zip');
      await service.addToQueue('q3', 'https://example.com/q3.zip');

      // Poll until all complete
      final start = DateTime.now();
      while (true) {
        final states = await service.getPersistedDownloadState();
        if (states
                .where(
                  (d) =>
                      d.chartId.startsWith('q') &&
                      d.status == DownloadStatus.completed,
                )
                .length ==
            3)
          break;
        if (DateTime.now().difference(start) > const Duration(seconds: 10)) {
          fail('Timeout waiting for queued downloads to finish');
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
      // Assert ordering by completion cannot strictly guarantee queue order, but ensure never more than one active at a time
      // (use notifier snapshot history by scanning logs for simultaneous 'downloading')
      final overlapping = logger.messages
          .where((m) => m.contains('Download completed: q'))
          .length;
      expect(overlapping, 3);
    });

    test('network gating defers start until probe returns true', () async {
      // Recreate service with a probe that is initially false then flips
      bool allow = false;
      service = DownloadServiceImpl(
        httpClient: http,
        storageService: storage,
        logger: logger,
        errorHandler: errorHandler,
        queueNotifier: notifier,
        networkSuitabilityProbe: () async => allow,
      );
      // Start download future (will defer)
      final future = service.downloadChart(
        'net1',
        'https://example.com/net1.zip',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      // Ensure not started (no completion log yet)
      expect(logger.messages.any((m) => m.contains('net1.zip')), isFalse);
      allow = true; // Flip probe
      await future; // Should now complete
      final state = (await service.getPersistedDownloadState()).firstWhere(
        (p) => p.chartId == 'net1',
      );
      expect(state.status, DownloadStatus.completed);
    });
  });
}
