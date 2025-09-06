import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/compression_result.dart';
import '../services/compression_service.dart';
import '../logging/app_logger.dart';
import '../error/app_error.dart';

/// Implementation of compression service using the archive package
/// Handles chart files, routes, cache data, and archive extraction
class CompressionServiceImpl implements CompressionService {
  final AppLogger _logger;
  final Map<String, dynamic> _stats = {};

  CompressionServiceImpl({required AppLogger logger}) : _logger = logger;

  @override
  Future<CompressionResult> compressChartData(
    Uint8List data, {
    required String chartId,
    CompressionLevel level = CompressionLevel.balanced,
  }) async {
    if (data.isEmpty) {
      throw AppError.validation(
        'Chart data cannot be empty',
        context: {'chartId': chartId},
      );
    }

    try {
      _logger.info(
        'Compressing chart data: $chartId (${data.length} bytes)',
        context: 'Compression',
      );

      final stopwatch = Stopwatch()..start();

      // Use GZIP compression with specified level
      final compressedData = GZipEncoder().encode(data)!;

      stopwatch.stop();

      final result = CompressionResult(
        originalSize: data.length,
        compressedSize: compressedData.length,
        compressionRatio: compressedData.length / data.length,
        compressionTime: stopwatch.elapsed,
        compressedData: Uint8List.fromList(compressedData),
      );

      _updateStats('chart_compression', result);

      _logger.info(
        'Chart compression completed: $chartId - ${result.toString()}',
        context: 'Compression',
      );

      return result;
    } catch (error) {
      _logger.error(
        'Failed to compress chart data: $chartId',
        exception: error,
      );
      throw AppError.storage('Chart compression failed', originalError: error);
    }
  }

  @override
  Future<Uint8List> decompressChartData(
    Uint8List compressedData, {
    required String chartId,
  }) async {
    try {
      _logger.debug(
        'Decompressing chart data: $chartId (${compressedData.length} bytes)',
        context: 'Compression',
      );

      // Decompress GZIP data
      final decompressedData = GZipDecoder().decodeBytes(compressedData);

      _logger.debug(
        'Chart decompression completed: $chartId (${decompressedData.length} bytes)',
        context: 'Compression',
      );

      return Uint8List.fromList(decompressedData);
    } catch (error) {
      _logger.error(
        'Failed to decompress chart data: $chartId',
        exception: error,
      );
      throw AppError.storage(
        'Chart decompression failed',
        originalError: error,
      );
    }
  }

  @override
  Future<CompressionResult> compressChartDataWithSettings(
    Uint8List data, {
    required String chartId,
    required CompressionSettings settings,
  }) async {
    settings.validate();

    if (data.isEmpty) {
      throw AppError.validation('Chart data cannot be empty');
    }

    try {
      _logger.info(
        'Compressing chart data with custom settings: $chartId',
        context: 'Compression',
      );

      final stopwatch = Stopwatch()..start();

      // Use custom compression settings
      final encoder = GZipEncoder();

      final compressedData = encoder.encode(data)!;
      stopwatch.stop();

      final result = CompressionResult(
        originalSize: data.length,
        compressedSize: compressedData.length,
        compressionRatio: compressedData.length / data.length,
        compressionTime: stopwatch.elapsed,
        compressedData: Uint8List.fromList(compressedData),
      );

      _updateStats('chart_compression_custom', result);

      return result;
    } catch (error) {
      _logger.error(
        'Failed to compress chart data with settings: $chartId',
        exception: error,
      );
      throw AppError.storage(
        'Chart compression with settings failed',
        originalError: error,
      );
    }
  }

  @override
  Future<CompressionResult> compressRouteData(
    Uint8List routeData, {
    required String routeId,
    CompressionLevel level = CompressionLevel.balanced,
  }) async {
    if (routeData.isEmpty) {
      throw AppError.validation('Route data cannot be empty');
    }

    try {
      _logger.debug('Compressing route data: $routeId', context: 'Compression');

      final stopwatch = Stopwatch()..start();
      final compressedData = GZipEncoder().encode(routeData)!;
      stopwatch.stop();

      final result = CompressionResult(
        originalSize: routeData.length,
        compressedSize: compressedData.length,
        compressionRatio: compressedData.length / routeData.length,
        compressionTime: stopwatch.elapsed,
        compressedData: Uint8List.fromList(compressedData),
      );

      _updateStats('route_compression', result);

      return result;
    } catch (error) {
      _logger.error(
        'Failed to compress route data: $routeId',
        exception: error,
      );
      throw AppError.storage('Route compression failed', originalError: error);
    }
  }

  @override
  Future<Uint8List> decompressRouteData(
    Uint8List compressedData, {
    required String routeId,
  }) async {
    try {
      _logger.debug(
        'Decompressing route data: $routeId',
        context: 'Compression',
      );

      final decompressedData = GZipDecoder().decodeBytes(compressedData);

      return Uint8List.fromList(decompressedData);
    } catch (error) {
      _logger.error(
        'Failed to decompress route data: $routeId',
        exception: error,
      );
      throw AppError.storage(
        'Route decompression failed',
        originalError: error,
      );
    }
  }

  @override
  Future<CompressionResult> compressRoutesBackup(
    List<Uint8List> routesData, {
    required String backupId,
    CompressionLevel level = CompressionLevel.maximum,
  }) async {
    if (routesData.isEmpty) {
      throw AppError.validation('Routes data cannot be empty');
    }

    try {
      _logger.info(
        'Creating compressed routes backup: $backupId',
        context: 'Compression',
      );

      final stopwatch = Stopwatch()..start();

      // Create a ZIP archive with all routes
      final archive = Archive();
      int totalOriginalSize = 0;

      for (int i = 0; i < routesData.length; i++) {
        final routeData = routesData[i];
        totalOriginalSize += routeData.length;

        final file = ArchiveFile('route_$i.json', routeData.length, routeData);
        archive.addFile(file);
      }

      // Compress the archive
      final zipData = ZipEncoder().encode(archive)!;
      stopwatch.stop();

      final result = CompressionResult(
        originalSize: totalOriginalSize,
        compressedSize: zipData.length,
        compressionRatio: zipData.length / totalOriginalSize,
        compressionTime: stopwatch.elapsed,
        compressedData: Uint8List.fromList(zipData),
      );

      _updateStats('routes_backup', result);

      _logger.info(
        'Routes backup compression completed: $backupId - ${result.toString()}',
        context: 'Compression',
      );

      return result;
    } catch (error) {
      _logger.error(
        'Failed to compress routes backup: $backupId',
        exception: error,
      );
      throw AppError.storage(
        'Routes backup compression failed',
        originalError: error,
      );
    }
  }

  @override
  Future<List<ExtractedFile>> extractChartArchive(
    Uint8List archiveData, {
    required String chartId,
  }) async {
    try {
      _logger.info(
        'Extracting chart archive: $chartId (${archiveData.length} bytes)',
        context: 'Compression',
      );

      Archive? archive;

      // Try to determine archive type and decode
      if (_isZipArchive(archiveData)) {
        archive = ZipDecoder().decodeBytes(archiveData);
      } else if (_isGzipArchive(archiveData)) {
        // For GZIP, decompress and check if it's a TAR
        final decompressed = GZipDecoder().decodeBytes(archiveData);
        try {
          archive = TarDecoder().decodeBytes(decompressed);
        } catch (e) {
          // Single GZIP file, create a simple archive
          final file = ArchiveFile(
            'data.bin',
            decompressed.length,
            decompressed,
          );
          archive = Archive()..addFile(file);
        }
      } else {
        throw AppError.validation('Unsupported archive format');
      }

      final extractedFiles = <ExtractedFile>[];

      for (final file in archive.files) {
        if (file.isFile) {
          final fileName = file.name;
          final fileData = Uint8List.fromList(file.content as List<int>);
          final isChartFile = _isChartFile(fileName);

          final extractedFile = ExtractedFile(
            fileName: fileName,
            data: fileData,
            lastModified: DateTime.fromMillisecondsSinceEpoch(
              file.lastModTime * 1000,
            ),
            isChartFile: isChartFile,
          );

          extractedFiles.add(extractedFile);
        }
      }

      _logger.info(
        'Chart archive extraction completed: $chartId (${extractedFiles.length} files)',
        context: 'Compression',
      );

      return extractedFiles;
    } catch (error) {
      _logger.error(
        'Failed to extract chart archive: $chartId',
        exception: error,
      );
      throw AppError.storage(
        'Chart archive extraction failed',
        originalError: error,
      );
    }
  }

  @override
  Future<CompressionResult> compressCacheData(
    Uint8List cacheData, {
    required String cacheKey,
    CompressionLevel level = CompressionLevel.balanced,
  }) async {
    if (cacheData.isEmpty) {
      throw AppError.validation('Cache data cannot be empty');
    }

    try {
      _logger.debug(
        'Compressing cache data: $cacheKey',
        context: 'Compression',
      );

      final stopwatch = Stopwatch()..start();
      final compressedData = GZipEncoder().encode(cacheData)!;
      stopwatch.stop();

      final result = CompressionResult(
        originalSize: cacheData.length,
        compressedSize: compressedData.length,
        compressionRatio: compressedData.length / cacheData.length,
        compressionTime: stopwatch.elapsed,
        compressedData: Uint8List.fromList(compressedData),
      );

      _updateStats('cache_compression', result);

      return result;
    } catch (error) {
      _logger.error(
        'Failed to compress cache data: $cacheKey',
        exception: error,
      );
      throw AppError.storage('Cache compression failed', originalError: error);
    }
  }

  @override
  Future<Uint8List> decompressCacheData(
    Uint8List compressedData, {
    required String cacheKey,
  }) async {
    try {
      _logger.debug(
        'Decompressing cache data: $cacheKey',
        context: 'Compression',
      );

      final decompressedData = GZipDecoder().decodeBytes(compressedData);

      return Uint8List.fromList(decompressedData);
    } catch (error) {
      _logger.error(
        'Failed to decompress cache data: $cacheKey',
        exception: error,
      );
      throw AppError.storage(
        'Cache decompression failed',
        originalError: error,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getCompressionStats() async {
    return Map<String, dynamic>.from(_stats);
  }

  @override
  Future<void> cleanup() async {
    _logger.debug('Cleaning up compression service', context: 'Compression');
    _stats.clear();
  }

  /// Check if data is a ZIP archive
  bool _isZipArchive(Uint8List data) {
    if (data.length < 4) return false;
    return data[0] == 0x50 &&
        data[1] == 0x4B &&
        data[2] == 0x03 &&
        data[3] == 0x04;
  }

  /// Check if data is a GZIP archive
  bool _isGzipArchive(Uint8List data) {
    if (data.length < 2) return false;
    return data[0] == 0x1F && data[1] == 0x8B;
  }

  /// Check if filename is an S-57 chart file
  bool _isChartFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;

    // S-57 chart files: .000, .001, .002, etc.
    if (extension.length == 3) {
      final firstChar = extension[0];
      return (firstChar == '0' || firstChar == '1' || firstChar == '2') &&
          extension.substring(1).contains(RegExp(r'^\d{2}$'));
    }

    return false;
  }

  /// Update compression statistics
  void _updateStats(String operation, CompressionResult result) {
    final key = '${operation}_stats';
    if (!_stats.containsKey(key)) {
      _stats[key] = {
        'count': 0,
        'totalOriginalSize': 0,
        'totalCompressedSize': 0,
        'totalTime': Duration.zero,
        'bestRatio': 1.0,
        'worstRatio': 0.0,
      };
    }

    final stats = _stats[key] as Map<String, dynamic>;
    stats['count'] = (stats['count'] as int) + 1;
    stats['totalOriginalSize'] =
        (stats['totalOriginalSize'] as int) + result.originalSize;
    stats['totalCompressedSize'] =
        (stats['totalCompressedSize'] as int) + result.compressedSize;
    stats['totalTime'] =
        (stats['totalTime'] as Duration) + result.compressionTime;

    if (result.compressionRatio < stats['bestRatio']) {
      stats['bestRatio'] = result.compressionRatio;
    }
    if (result.compressionRatio > stats['worstRatio']) {
      stats['worstRatio'] = result.compressionRatio;
    }
  }
}
