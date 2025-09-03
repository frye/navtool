import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/services/download_metrics_collector.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/utils/network_resilience.dart';

class _TestLogger extends AppLogger {
  _TestLogger();
  @override
  void debug(String message, {String? context, Object? exception}) {}
  @override
  void info(String message, {String? context, Object? exception}) {}
  @override
  void warning(String message, {String? context, Object? exception}) {}
  @override
  void error(String message, {String? context, Object? exception}) {}
  @override
  void logError(AppError error) {}
}

class _MockHttpClient extends HttpClientService {
  _MockHttpClient() : super(logger: _TestLogger());
  int attempts = 0;
  @override
  Future<void> downloadFile(String url, String savePath, {CancelToken? cancelToken, ProgressCallback? onReceiveProgress, int? resumeFrom, Map<String, dynamic>? queryParameters}) async {
    attempts++;
    // simulate small file progress in two chunks
    onReceiveProgress?.call(50, 100);
    await Future.delayed(const Duration(milliseconds: 5));
    onReceiveProgress?.call(100, 100);
    final file = File(savePath);
    await file.writeAsBytes(List<int>.filled(10, 1));
  }
  @override
  Future<Response> head(String url, {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken}) async {
    return Response(
      requestOptions: RequestOptions(path: url),
      data: null,
      statusCode: 200,
      headers: Headers.fromMap({'content-length': ['100']}),
    );
  }
}

class _InMemoryStorage extends StorageService {
  final Directory dir;
  final Map<String, List<int>> _chartData = {};
  final Map<String, NavigationRoute> _routes = {};
  final Map<String, Waypoint> _waypoints = {};
  final Map<String, List<String>> _stateCells = {};
  _InMemoryStorage(this.dir);

  @override
  Future<void> storeChart(Chart chart, List<int> data) async {
    _chartData[chart.id] = data;
  }

  @override
  Future<List<int>?> loadChart(String chartId) async => _chartData[chartId];

  @override
  Future<void> deleteChart(String chartId) async { _chartData.remove(chartId); }

  @override
  Future<Map<String, dynamic>> getStorageInfo() async => {'charts': _chartData.length};

  @override
  Future<void> cleanupOldData() async {}

  @override
  Future<int> getStorageUsage() async => _chartData.values.fold<int>(0, (p, e) => p + e.length);

  @override
  Future<Directory> getChartsDirectory() async => dir;

  @override
  Future<void> storeRoute(NavigationRoute route) async { _routes[route.id] = route; }

  @override
  Future<NavigationRoute?> loadRoute(String routeId) async => _routes[routeId];

  @override
  Future<void> deleteRoute(String routeId) async { _routes.remove(routeId); }

  @override
  Future<List<NavigationRoute>> getAllRoutes() async => _routes.values.toList();

  @override
  Future<void> storeWaypoint(Waypoint waypoint) async { _waypoints[waypoint.id] = waypoint; }

  @override
  Future<Waypoint?> loadWaypoint(String waypointId) async => _waypoints[waypointId];

  @override
  Future<void> updateWaypoint(Waypoint waypoint) async { _waypoints[waypoint.id] = waypoint; }

  @override
  Future<void> deleteWaypoint(String waypointId) async { _waypoints.remove(waypointId); }

  @override
  Future<List<Waypoint>> getAllWaypoints() async => _waypoints.values.toList();

  @override
  Future<void> storeStateCellMapping(String stateName, List<String> chartCells) async { _stateCells[stateName] = chartCells; }

  @override
  Future<List<String>?> getStateCellMapping(String stateName) async => _stateCells[stateName];

  @override
  Future<void> clearAllStateCellMappings() async { _stateCells.clear(); }

  @override
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds) async => const [];

  @override
  Future<int> countChartsWithInvalidBounds() async => 0;

  @override
  Future<int> clearChartsWithInvalidBounds() async => 0;
}

void main() {
  group('Auto retry on network recovery', () {
    late Directory tempDir;
    late DownloadServiceImpl service;
    late NetworkResilience network;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dltest');
      network = NetworkResilience();
      service = DownloadServiceImpl(
        httpClient: _MockHttpClient(),
        storageService: _InMemoryStorage(tempDir),
        logger: _TestLogger(),
        errorHandler: ErrorHandler(logger: _TestLogger()),
        metrics: DownloadMetricsCollector(),
        networkResilience: network,
      );
    });

    tearDown(() async {
      service.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('requeues failed transient downloads when network recovers', () async {
      service.attachQueueNotifier(DownloadQueueNotifier(logger: _TestLogger(), errorHandler: ErrorHandler(logger: _TestLogger())));
      service.injectFailedDownload('CHT123', 'https://example.com/CHT123.zip', category: 'network');
      expect(service.debugProgressMap['CHT123']?.status, DownloadStatus.failed);
      service.simulateNetworkStatus(NetworkStatus.connected);
      // After network recovery, chart should be queued (removed from failed map or at least in queue ids)
      expect(service.debugQueueIds.contains('CHT123'), isTrue);
    });
  });
}
