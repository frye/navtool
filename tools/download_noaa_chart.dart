// Simple standalone script to download a NOAA ENC chart using the existing
// DownloadService implementation.
//
// Usage:
//   dart run tools/download_noaa_chart.dart [CHART_ID]
// Example:
//   dart run tools/download_noaa_chart.dart US5WA11M
//
// The script tries multiple known NOAA distribution URL patterns and picks the
// first that responds with HTTP 200 to a HEAD request, then runs the normal
// download pipeline (with retries, checksum support if later added, etc.).
// The resulting .zip (or chart file) is stored in the charts directory used by
// the app (same directory as the SQLite database path on this platform).

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

Future<void> main(List<String> args) async {
  // Initialize FFI for desktop DB usage (same as main.dart does on Windows/Linux)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final chartId = (args.isNotEmpty ? args[0] : 'US5WA11M').trim();
  if (chartId.isEmpty) {
    stderr.writeln('Chart ID cannot be empty');
    exit(64); // EX_USAGE
  }

  final container = ProviderContainer();
  final logger = container.read(loggerProvider);
  final httpClient = container.read(httpClientServiceProvider);
  final downloadService = container.read(downloadServiceProvider);
  final storageService = container.read(storageServiceProvider);

  logger.info('Preparing to download NOAA ENC chart: $chartId');

  // Candidate URL patterns (first successful HEAD wins)
  final candidates = <String>[
    'https://charts.noaa.gov/ENCs/$chartId.zip',
    'https://distribution.charts.noaa.gov/encs/$chartId/$chartId.zip',
    'https://distribution.charts.noaa.gov/ENC_ROOT/$chartId/$chartId.zip',
    // Fallback to raw S-57 cell if zip not present (some legacy cells)
    'https://distribution.charts.noaa.gov/encs/$chartId/$chartId.000',
    'https://distribution.charts.noaa.gov/ENC_ROOT/$chartId/$chartId.000',
  ];

  String? selectedUrl;
  for (final url in candidates) {
    try {
      final resp = await httpClient.head(url);
      final code = resp.statusCode ?? resp.statusCode; // Dio Response compatibility
      if (code != null && code >= 200 && code < 300) {
        selectedUrl = url;
        logger.info('Selected download URL: $selectedUrl (HTTP $code)');
        break;
      } else {
        logger.debug('HEAD $url -> $code');
      }
    } catch (e) {
      logger.debug('HEAD failed for $url: $e');
    }
  }

  if (selectedUrl == null) {
    stderr.writeln('Could not locate a valid download URL for $chartId');
    exit(1);
  }

  // Subscribe to progress BEFORE starting download to avoid missing early events.
  final progressStream = downloadService.getDownloadProgress(chartId);
  double lastProgress = 0.0;
  final progressSub = progressStream.listen((p) {
    lastProgress = p;
    final pct = (p * 100).clamp(0, 100).toStringAsFixed(1);
    stdout.write('\rProgress: $pct%   ');
  });

  int exitCode = 0;
  final stopwatch = Stopwatch()..start();
  try {
    await downloadService.downloadChart(chartId, selectedUrl);
  } catch (e, st) {
    stderr.writeln('\nDownload failed: $e');
    logger.error('Download script failure for $chartId', exception: e, stackTrace: st);
    exitCode = 2;
  } finally {
    await progressSub.cancel();
  }

  if (exitCode == 0 && lastProgress >= 0.999) {
    stdout.writeln('\nDownload completed successfully in ${stopwatch.elapsed.inSeconds}s');
    // Determine final file path (DownloadService derives final name from URL)
    final chartsDir = await storageService.getChartsDirectory();
    final fileName = p.basename(Uri.parse(selectedUrl).path); // e.g., US5WA11M.zip or .000
    final finalPath = p.join(chartsDir.path, fileName);
    if (await File(finalPath).exists()) {
      final size = await File(finalPath).length();
      stdout.writeln('Stored at: $finalPath (${_formatBytes(size)})');
    } else {
      stdout.writeln('Expected file not found at: $finalPath (may have been renamed internally)');
    }
  }

  await _gracefulShutdown(container);
  exit(exitCode);
}

Future<void> _gracefulShutdown(ProviderContainer container) async {
  // Give any async logging a tick
  await Future.delayed(const Duration(milliseconds: 100));
  container.dispose();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
