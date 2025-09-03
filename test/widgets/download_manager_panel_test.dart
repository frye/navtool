import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/features/charts/widgets/download_manager_panel.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';

/// A fake DownloadService to drive the widget state without real network IO.
class FakeDownloadService implements DownloadService {
  final Map<String, ResumeData> _resume = {};
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> addToQueue(String chartId, String url, {DownloadPriority priority = DownloadPriority.normal, String? expectedChecksum}) async {}
  @override
  Future<void> pauseDownload(String chartId) async {}
  @override
  Future<void> resumeDownload(String chartId, {String? url}) async {}
  @override
  Future<void> cancelDownload(String chartId) async {}
  @override
  Future<List<String>> getDownloadQueue() async => [];
  @override
  Stream<double> getDownloadProgress(String chartId) async* {}
  @override
  Future<void> pauseAllDownloads() async {}
  @override
  Future<void> resumeAllDownloads() async {}
  @override
  Future<String> exportDiagnostics() async => '{}';
  @override
  Future<ResumeData?> getResumeData(String chartId) async => _resume[chartId];
  @override
  void dispose() {}
  @override
  Future<void> downloadChart(String chartId, String url, {String? expectedChecksum}) async {}
  @override
  Future<void> removeFromQueue(String chartId) async {}
  @override
  Future<void> clearQueue() async {}
  @override
  Future<List<QueueItem>> getDetailedQueue() async => [];
  @override
  Future<String> startBatchDownload(List<String> chartIds, List<String> urls, {DownloadPriority priority = DownloadPriority.normal}) async => 'batch';
  @override
  Future<BatchDownloadProgress> getBatchProgress(String batchId) async => BatchDownloadProgress(batchId: batchId, status: BatchDownloadStatus.completed, totalCharts: 0, completedCharts: 0, failedCharts: 0, overallProgress: 0, lastUpdated: DateTime.now(), failedChartIds: const []);
  @override
  Stream<BatchDownloadProgress> getBatchProgressStream(String batchId) async* {}
  @override
  Future<void> pauseBatchDownload(String batchId) async {}
  @override
  Future<void> resumeBatchDownload(String batchId) async {}
  @override
  Future<void> cancelBatchDownload(String batchId) async {}
  @override
  Future<List<DownloadProgress>> getPersistedDownloadState() async => [];
  @override
  Future<void> recoverDownloads(List<DownloadProgress> persistedDownloads) async {}
  @override
  Future<void> enableBackgroundNotifications() async {}
  @override
  Future<List<DownloadNotification>> getPendingNotifications() async => [];
  @override
  Future<int> getMaxConcurrentDownloads() async => 3;
  @override
  Future<void> setMaxConcurrentDownloads(int maxConcurrent) async {}
}

class TestDownloadQueueNotifier extends DownloadQueueNotifier {
  TestDownloadQueueNotifier({
    required AppLogger logger,
    required ErrorHandler errorHandler,
    required DownloadQueueState initial,
  }) : super(logger: logger, errorHandler: errorHandler) {
    state = initial;
  }
}

void main() {
  testWidgets('DownloadManagerPanel empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        downloadServiceProvider.overrideWithValue(FakeDownloadService()),
        // Provide empty queue state
        downloadQueueProvider.overrideWith((ref) => TestDownloadQueueNotifier(
              logger: ref.read(loggerProvider),
              errorHandler: ref.read(errorHandlerProvider),
              initial: const DownloadQueueState(),
            )),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 400, child: DownloadManagerPanel()),
        ),
      ),
    ));

    expect(find.text('Download Manager'), findsOneWidget);
    expect(find.text('No downloads yet.'), findsOneWidget);
  });

  testWidgets('DownloadManagerPanel renders sections and queue position', (tester) async {
    final now = DateTime.now();
    DownloadProgress build({required String id, required DownloadStatus status, double prog = 0, String? errMsg, String? errCat, double? bps, int? eta}) => DownloadProgress(
          chartId: id,
          status: status,
          progress: prog,
          errorMessage: errMsg,
          errorCategory: errCat,
          bytesPerSecond: bps,
          etaSeconds: eta,
          lastUpdated: now,
        );
    final active = [build(id: 'A123', status: DownloadStatus.downloading, prog: 0.42, bps: 120000, eta: 30)];
    final queued = [build(id: 'B456', status: DownloadStatus.queued), build(id: 'C789', status: DownloadStatus.queued)];
    final completed = [build(id: 'D000', status: DownloadStatus.completed, prog: 1.0)];
    final failed = [build(id: 'E999', status: DownloadStatus.failed, prog: 0.77, errMsg: 'Timeout', errCat: 'network')];

    final downloads = <String, DownloadProgress>{
      for (final d in [...active, ...queued, ...completed, ...failed]) d.chartId: d,
    };

    final queueState = DownloadQueueState(
      downloads: downloads,
      queue: queued.map((e) => e.chartId).toList(),
      maxConcurrentDownloads: 2,
      isPaused: false,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        downloadServiceProvider.overrideWithValue(FakeDownloadService()),
        downloadQueueProvider.overrideWith((ref) => TestDownloadQueueNotifier(
              logger: ref.read(loggerProvider),
              errorHandler: ref.read(errorHandlerProvider),
              initial: queueState,
            )),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: DownloadManagerPanel()),
        ),
      ),
    ));

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
  // 'Completed' appears in section header and possibly in list tile subtitle
  expect(find.text('Completed'), findsWidgets);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('B456  (#1 in queue)'), findsOneWidget);
    expect(find.textContaining('C789  (#2 in queue)'), findsOneWidget);
    expect(find.textContaining('[network]'), findsOneWidget);
    expect(find.textContaining('42.0%'), findsOneWidget);
  });
}
