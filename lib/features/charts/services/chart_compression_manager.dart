import 'dart:typed_data';
import '../../../core/services/compression_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/compression_result.dart';

/// Manager for chart compression operations
/// Provides high-level interface for compressing and managing chart files
class ChartCompressionManager {
  final CompressionService _compressionService;
  final AppLogger _logger;

  ChartCompressionManager({
    required CompressionService compressionService,
    required AppLogger logger,
  }) : _compressionService = compressionService,
       _logger = logger;

  /// Compress a chart file for storage
  /// 
  /// Example usage:
  /// ```dart
  /// final manager = ChartCompressionManager(
  ///   compressionService: ref.read(compressionServiceProvider),
  ///   logger: ref.read(loggerProvider),
  /// );
  /// 
  /// final chartData = await loadChartData('chart001.000');
  /// final result = await manager.compressChart(
  ///   chartId: 'chart001',
  ///   data: chartData,
  ///   settings: CompressionSettings(level: CompressionLevel.balanced),
  /// );
  /// 
  /// if (result.isSuccess) {
  ///   print('Compressed ${result.originalSize} to ${result.compressedSize} bytes');
  ///   print('Compression ratio: ${result.compressionRatio.toStringAsFixed(2)}');
  /// }
  /// ```
  Future<CompressionResult> compressChart({
    required String chartId,
    required Uint8List data,
    CompressionSettings? settings,
  }) async {
    try {
      _logger.info('Starting compression for chart: $chartId');
      
      final result = await _compressionService.compressChart(
        chartId: chartId,
        data: data,
        settings: settings,
      );
      
      if (result.isSuccess) {
        _logger.info(
          'Chart $chartId compressed successfully: '
          '${result.originalSize} → ${result.compressedSize} bytes '
          '(${result.compressionRatio.toStringAsFixed(2)} ratio)',
        );
      } else {
        _logger.warning('Failed to compress chart $chartId: ${result.error}');
      }
      
      return result;
    } catch (error) {
      _logger.error('Error compressing chart $chartId', exception: error);
      return CompressionResult.failure(
        originalSize: data.length,
        error: 'Compression failed: $error',
      );
    }
  }

  /// Decompress a chart file for use
  /// 
  /// Example usage:
  /// ```dart
  /// final compressedData = await loadCompressedChart('chart001');
  /// final result = await manager.decompressChart(
  ///   chartId: 'chart001',
  ///   compressedData: compressedData,
  /// );
  /// 
  /// if (result.isSuccess && result.data != null) {
  ///   // Use the decompressed chart data
  ///   await processChartData(result.data!);
  /// }
  /// ```
  Future<CompressionResult> decompressChart({
    required String chartId,
    required Uint8List compressedData,
  }) async {
    try {
      _logger.info('Starting decompression for chart: $chartId');
      
      final result = await _compressionService.decompressChart(
        chartId: chartId,
        compressedData: compressedData,
      );
      
      if (result.isSuccess) {
        _logger.info(
          'Chart $chartId decompressed successfully: '
          '${result.compressedSize} → ${result.originalSize} bytes',
        );
      } else {
        _logger.warning('Failed to decompress chart $chartId: ${result.error}');
      }
      
      return result;
    } catch (error) {
      _logger.error('Error decompressing chart $chartId', exception: error);
      return CompressionResult.failure(
        originalSize: 0,
        error: 'Decompression failed: $error',
      );
    }
  }

  /// Get compression statistics for monitoring
  /// 
  /// Example usage:
  /// ```dart
  /// final stats = await manager.getCompressionStatistics();
  /// print('Total charts compressed: ${stats['total_operations']}');
  /// print('Average compression ratio: ${stats['average_compression_ratio']}');
  /// print('Total space saved: ${stats['total_space_saved']} bytes');
  /// ```
  Future<Map<String, dynamic>> getCompressionStatistics() async {
    try {
      return await _compressionService.getStatistics();
    } catch (error) {
      _logger.error('Error getting compression statistics', exception: error);
      return <String, dynamic>{};
    }
  }

  /// Clean up temporary compression files
  /// 
  /// Example usage:
  /// ```dart
  /// await manager.cleanupTemporaryFiles();
  /// print('Temporary compression files cleaned up');
  /// ```
  Future<bool> cleanupTemporaryFiles() async {
    try {
      _logger.info('Cleaning up temporary compression files');
      await _compressionService.cleanup();
      _logger.info('Compression cleanup completed');
      return true;
    } catch (error) {
      _logger.error('Error during compression cleanup', exception: error);
      return false;
    }
  }
}
