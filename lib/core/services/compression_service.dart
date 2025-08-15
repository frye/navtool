import 'dart:typed_data';
import '../models/compression_result.dart';

/// Service interface for compression and decompression operations
/// Handles chart files, routes, cache data, and archive extraction
abstract class CompressionService {
  /// Compress S-57 chart file data
  Future<CompressionResult> compressChartData(
    Uint8List data, {
    required String chartId,
    CompressionLevel level = CompressionLevel.balanced,
  });

  /// Decompress S-57 chart file data
  Future<Uint8List> decompressChartData(
    Uint8List compressedData, {
    required String chartId,
  });

  /// Compress chart data with custom settings
  Future<CompressionResult> compressChartDataWithSettings(
    Uint8List data, {
    required String chartId,
    required CompressionSettings settings,
  });

  /// Compress route JSON data for backup
  Future<CompressionResult> compressRouteData(
    Uint8List routeData, {
    required String routeId,
    CompressionLevel level = CompressionLevel.balanced,
  });

  /// Decompress route JSON data from backup
  Future<Uint8List> decompressRouteData(
    Uint8List compressedData, {
    required String routeId,
  });

  /// Compress multiple routes for backup archive
  Future<CompressionResult> compressRoutesBackup(
    List<Uint8List> routesData, {
    required String backupId,
    CompressionLevel level = CompressionLevel.maximum,
  });

  /// Extract chart archive downloaded from NOAA/IHO sources
  Future<List<ExtractedFile>> extractChartArchive(
    Uint8List archiveData, {
    required String chartId,
  });

  /// Compress cache data for offline storage
  Future<CompressionResult> compressCacheData(
    Uint8List cacheData, {
    required String cacheKey,
    CompressionLevel level = CompressionLevel.balanced,
  });

  /// Decompress cache data from offline storage
  Future<Uint8List> decompressCacheData(
    Uint8List compressedData, {
    required String cacheKey,
  });

  /// Get compression statistics for monitoring
  Future<Map<String, dynamic>> getCompressionStats();

  /// Clean up temporary compression files
  Future<void> cleanup();
}
