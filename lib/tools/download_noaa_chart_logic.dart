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

Future<void> runDownload(String chartId) async {
  // Initialize FFI for desktop DB usage (same as main.dart does on Windows/Linux)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final container = ProviderContainer();
  final logger = container.read(loggerProvider);
  final httpClient = container.read(httpClientServiceProvider);
  final downloadService = container.read(downloadServiceProvider);
  final storageService = container.read(storageServiceProvider);

  logger.info('Preparing to download NOAA ENC chart: $chartId');

  final candidates = <String>[
    'https://charts.noaa.gov/ENCs/$chartId.zip',
    'https://distribution.charts.noaa.gov/encs/$chartId/$chartId.zip',
    'https://distribution.charts.noaa.gov/ENC_ROOT/$chartId/$chartId.zip',
    'https://distribution.charts.noaa.gov/encs/$chartId/$chartId.000',
    'https://distribution.charts.noaa.gov/ENC_ROOT/$chartId/$chartId.000',
  ];
  String? selectedUrl;
  for (final url in candidates) {
    try {
      final resp = await httpClient.head(url);
      final code = resp.statusCode;
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
    container.dispose();
    return;
  }
  final progressStream = downloadService.getDownloadProgress(chartId);
  double lastProgress = 0.0;
  final progressSub = progressStream.listen((p) {
    lastProgress = p;
    final pct = (p * 100).clamp(0, 100).toStringAsFixed(1);
    stdout.write('\rProgress: $pct%   ');
  });
  final sw = Stopwatch()..start();
  try {
    await downloadService.downloadChart(chartId, selectedUrl);
  } catch (e, st) {
    stderr.writeln('\nDownload failed: $e');
    logger.error('Download script failure for $chartId', exception: e);
    logger.debug(st.toString());
  } finally {
    await progressSub.cancel();
  }
  if (lastProgress >= 0.999) {
    stdout.writeln(
      '\nDownload completed successfully in ${sw.elapsed.inSeconds}s',
    );
    final chartsDir = await storageService.getChartsDirectory();
    final fileName = p.basename(Uri.parse(selectedUrl).path);
    final finalPath = p.join(chartsDir.path, fileName);
    if (await File(finalPath).exists()) {
      final size = await File(finalPath).length();
      stdout.writeln('Stored at: $finalPath (${_formatBytes(size)})');
    } else {
      stdout.writeln('Expected file not found at: $finalPath');
    }
  }
  await Future.delayed(const Duration(milliseconds: 150));
  container.dispose();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
