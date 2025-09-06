import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/download_state.dart';
import '../../../core/state/providers.dart';
import '../../../core/services/download_service.dart';

/// Download Manager Panel (extracted for testability)
class DownloadManagerPanel extends ConsumerWidget {
  const DownloadManagerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDownloadsProvider);
    final queued = ref.watch(queuedDownloadsProvider);
    final completed = ref.watch(completedDownloadsProvider);
    final failed = ref.watch(failedDownloadsProvider);
    final overall = ref.watch(overallDownloadProgressProvider);
    final queueNotifier = ref.read(downloadQueueProvider.notifier);
    final downloadService = ref.read(downloadServiceProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_download),
              const SizedBox(width: 8),
              const Text(
                'Download Manager',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Tooltip(
                message: 'Pause All',
                child: IconButton(
                  icon: const Icon(Icons.pause_circle),
                  onPressed: () {
                    queueNotifier.pauseAll();
                    downloadService.pauseAllDownloads();
                  },
                ),
              ),
              Tooltip(
                message: 'Resume All',
                child: IconButton(
                  icon: const Icon(Icons.play_circle),
                  onPressed: () {
                    queueNotifier.resumeAll();
                    downloadService.resumeAllDownloads();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: overall == 0 ? null : overall),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (active.isNotEmpty) _section(context, ref, 'Active', active),
                if (queued.isNotEmpty) _section(context, ref, 'Queued', queued),
                if (completed.isNotEmpty)
                  _section(context, ref, 'Completed', completed),
                if (failed.isNotEmpty) _section(context, ref, 'Failed', failed),
                if (active.isEmpty &&
                    queued.isEmpty &&
                    completed.isEmpty &&
                    failed.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No downloads yet.')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<DownloadProgress> items,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...items.map((d) => _row(context, ref, d)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, DownloadProgress progress) {
    final pct = (progress.progress * 100).toStringAsFixed(1);
    String subtitle;
    if (progress.status == DownloadStatus.failed) {
      final cat = progress.errorCategory != null
          ? '[${progress.errorCategory}] '
          : '';
      subtitle = '$cat${progress.errorMessage ?? 'Failed'}';
    } else if (progress.status == DownloadStatus.completed) {
      subtitle = 'Completed';
    } else {
      final speed =
          progress.bytesPerSecond != null && progress.bytesPerSecond! > 0
          ? _formatSpeed(progress.bytesPerSecond!)
          : '';
      final eta = progress.etaSeconds != null && progress.etaSeconds! > 0
          ? ' • ETA ${_formatEta(progress.etaSeconds!)}'
          : '';
      subtitle =
          '${progress.status.name} • $pct%${speed.isNotEmpty ? ' • $speed' : ''}$eta';
    }
    final service = ref.read(downloadServiceProvider);
    final queueNotifier = ref.read(downloadQueueProvider.notifier);
    int? queuePos;
    if (progress.status == DownloadStatus.queued) {
      final queue = ref.read(downloadQueueProvider).queue;
      final idx = queue.indexOf(progress.chartId);
      if (idx >= 0) queuePos = idx + 1;
    }
    return ListTile(
      dense: true,
      title: Text(
        progress.chartId + (queuePos != null ? '  (#$queuePos in queue)' : ''),
      ),
      subtitle: Text(subtitle),
      trailing: SizedBox(
        width: 140,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: progress.status == DownloadStatus.completed
                    ? 1
                    : progress.progress == 0
                    ? null
                    : progress.progress,
              ),
            ),
            const SizedBox(width: 6),
            _actions(progress, service, queueNotifier),
          ],
        ),
      ),
    );
  }

  Widget _actions(
    DownloadProgress p,
    DownloadService service,
    DownloadQueueNotifier notifier,
  ) {
    if (p.status == DownloadStatus.completed) {
      return const SizedBox(width: 0);
    }
    if (p.status == DownloadStatus.downloading) {
      return IconButton(
        icon: const Icon(Icons.pause, size: 18),
        tooltip: 'Pause',
        onPressed: () {
          notifier.pauseDownload(p.chartId);
          service.pauseDownload(p.chartId);
        },
      );
    }
    if (p.status == DownloadStatus.paused) {
      return IconButton(
        icon: const Icon(Icons.play_arrow, size: 18),
        tooltip: 'Resume',
        onPressed: () {
          notifier.resumeDownload(p.chartId);
          service.resumeDownload(p.chartId);
        },
      );
    }
    if (p.status == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.refresh, size: 18),
        tooltip: 'Retry',
        onPressed: () {
          notifier.resumeDownload(p.chartId);
          service.getResumeData(p.chartId).then((data) {
            final url =
                data?.originalUrl ??
                'https://charts.noaa.gov/ENCs/${p.chartId}.zip';
            service.addToQueue(p.chartId, url);
          });
        },
      );
    }
    if (p.status == DownloadStatus.queued) {
      return IconButton(
        icon: const Icon(Icons.cancel, size: 18),
        tooltip: 'Cancel',
        onPressed: () {
          notifier.cancelDownload(p.chartId);
          service.cancelDownload(p.chartId);
        },
      );
    }
    return const SizedBox.shrink();
  }

  String _formatSpeed(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String _formatEta(int secs) {
    if (secs < 60) return '${secs}s';
    final m = secs ~/ 60;
    final s = secs % 60;
    if (m < 60) return '${m}m${s}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h${rm}m';
  }
}
