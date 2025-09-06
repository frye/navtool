import 'dart:typed_data';
import '../../../core/services/compression_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/compression_result.dart';

/// Manager for route backup compression operations
/// Provides high-level interface for compressing and managing route backups
class RouteBackupManager {
  final CompressionService _compressionService;
  final AppLogger _logger;

  RouteBackupManager({
    required CompressionService compressionService,
    required AppLogger logger,
  }) : _compressionService = compressionService,
       _logger = logger;

  /// Create a compressed backup of route data
  ///
  /// Example usage:
  /// ```dart
  /// final manager = RouteBackupManager(
  ///   compressionService: ref.read(compressionServiceProvider),
  ///   logger: ref.read(loggerProvider),
  /// );
  ///
  /// final routes = await loadAllRoutes();
  /// final routeData = routes.map((r) => r.toJson()).toList();
  /// final jsonData = jsonEncode(routeData);
  ///
  /// final result = await manager.createBackup(
  ///   backupId: 'routes_backup_${DateTime.now().millisecondsSinceEpoch}',
  ///   routeData: utf8.encode(jsonData),
  /// );
  ///
  /// if (result.isSuccess) {
  ///   print('Backup created with ${result.compressionRatio.toStringAsFixed(2)} compression');
  /// }
  /// ```
  Future<CompressionResult> createBackup({
    required String backupId,
    required Uint8List routeData,
  }) async {
    try {
      _logger.info('Creating route backup: $backupId');

      final result = await _compressionService.compressRouteData(
        routeData,
        routeId: backupId,
      );

      if (result.isSuccess) {
        _logger.info(
          'Route backup $backupId created successfully: '
          '${result.originalSize} → ${result.compressedSize} bytes '
          '(${result.compressionRatio.toStringAsFixed(2)} ratio)',
        );
      } else {
        _logger.warning(
          'Failed to create route backup $backupId: ${result.error}',
        );
      }

      return result;
    } catch (error) {
      _logger.error('Error creating route backup $backupId', exception: error);
      return CompressionResult.failure(
        originalSize: routeData.length,
        error: 'Backup creation failed: $error',
      );
    }
  }

  /// Restore route data from a compressed backup
  ///
  /// Example usage:
  /// ```dart
  /// final compressedBackup = await loadBackupFile('routes_backup_123456');
  /// final result = await manager.restoreBackup(
  ///   backupId: 'routes_backup_123456',
  ///   compressedData: compressedBackup,
  /// );
  ///
  /// if (result.isSuccess && result.data != null) {
  ///   final jsonData = utf8.decode(result.data!);
  ///   final routeList = jsonDecode(jsonData) as List;
  ///   final routes = routeList.map((json) => Route.fromJson(json)).toList();
  ///   await saveRestoredRoutes(routes);
  /// }
  /// ```
  Future<CompressionResult> restoreBackup({
    required String backupId,
    required Uint8List compressedData,
  }) async {
    try {
      _logger.info('Restoring route backup: $backupId');

      final decompressedData = await _compressionService.decompressRouteData(
        compressedData,
        routeId: backupId,
      );

      final result = CompressionResult(
        originalSize: decompressedData.length,
        compressedSize: compressedData.length,
        compressionRatio: compressedData.length / decompressedData.length,
        compressionTime: Duration.zero,
        compressedData: decompressedData,
      );

      if (result.isSuccess) {
        _logger.info(
          'Route backup $backupId restored successfully: '
          '${result.compressedSize} → ${result.originalSize} bytes',
        );
      } else {
        _logger.warning(
          'Failed to restore route backup $backupId: ${result.error}',
        );
      }

      return result;
    } catch (error) {
      _logger.error('Error restoring route backup $backupId', exception: error);
      return CompressionResult.failure(
        originalSize: 0,
        error: 'Backup restoration failed: $error',
      );
    }
  }

  /// Verify the integrity of a compressed backup
  ///
  /// Example usage:
  /// ```dart
  /// final isValid = await manager.verifyBackup(
  ///   backupId: 'routes_backup_123456',
  ///   compressedData: backupData,
  /// );
  ///
  /// if (isValid) {
  ///   print('Backup is valid and can be restored');
  /// } else {
  ///   print('Backup is corrupted and cannot be restored');
  /// }
  /// ```
  Future<bool> verifyBackup({
    required String backupId,
    required Uint8List compressedData,
  }) async {
    try {
      _logger.info('Verifying route backup: $backupId');

      // Try to decompress without saving the result
      await _compressionService.decompressRouteData(
        compressedData,
        routeId: backupId,
      );

      _logger.info('Route backup $backupId verification successful');
      return true;
    } catch (error) {
      _logger.error('Error verifying route backup $backupId', exception: error);
      return false;
    }
  }

  /// Get backup statistics for monitoring
  ///
  /// Example usage:
  /// ```dart
  /// final stats = await manager.getBackupStatistics();
  /// print('Total backups: ${stats['total_backups']}');
  /// print('Total space used: ${stats['total_compressed_size']} bytes');
  /// print('Space saved: ${stats['total_space_saved']} bytes');
  /// ```
  Future<Map<String, dynamic>> getBackupStatistics() async {
    try {
      final allStats = await _compressionService.getCompressionStats();

      // Filter for backup-related statistics
      return {
        'total_backups': allStats['route_backup_operations'] ?? 0,
        'total_compressed_size': allStats['route_backup_compressed_size'] ?? 0,
        'total_original_size': allStats['route_backup_original_size'] ?? 0,
        'total_space_saved':
            (allStats['route_backup_original_size'] ?? 0) -
            (allStats['route_backup_compressed_size'] ?? 0),
        'average_compression_ratio':
            allStats['route_backup_average_ratio'] ?? 0.0,
      };
    } catch (error) {
      _logger.error('Error getting backup statistics', exception: error);
      return <String, dynamic>{};
    }
  }
}
