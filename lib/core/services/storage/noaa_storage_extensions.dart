import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:sqflite/sqflite.dart';

/// NOAA-specific storage extensions for enhanced chart management
extension NoaaStorageExtensions on DatabaseStorageService {
  
  // NOAA Chart Catalog Caching Operations
  
  /// Updates the NOAA chart catalog cache with new data
  Future<void> updateChartCatalog(String catalogData, {String? etag}) async {
    final db = database!;
    
    try {
      await db.transaction((txn) async {
        // Invalidate old cache entries
        await txn.update('chart_catalog_cache', 
          {'is_valid': 0},
          where: 'catalog_type = ? AND is_valid = ?',
          whereArgs: ['noaa', 1]);
        
        // Insert new catalog
        await txn.insert('chart_catalog_cache', {
          'catalog_type': 'noaa',
          'catalog_data': catalogData,
          'catalog_hash': _generateHash(catalogData),
          'last_updated': DateTime.now().toIso8601String(),
          'etag': etag,
          'is_valid': 1,
          'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        });
      });
      
      logger.info('Updated NOAA chart catalog cache');
    } catch (e) {
      logger.error('Failed to update chart catalog cache: $e');
      rethrow;
    }
  }
  
  /// Retrieves cached NOAA catalog data if valid and not expired
  Future<String?> getCachedCatalog() async {
    final db = database!;
    
    try {
      final results = await db.query('chart_catalog_cache',
        columns: ['catalog_data'],
        where: 'catalog_type = ? AND is_valid = ? AND expires_at > ?',
        whereArgs: ['noaa', 1, DateTime.now().toIso8601String()],
        orderBy: 'last_updated DESC',
        limit: 1);
      
      return results.isNotEmpty ? results.first['catalog_data'] as String : null;
    } catch (e) {
      logger.error('Failed to get cached catalog: $e');
      return null;
    }
  }
  
  /// Clears all cached catalog entries
  Future<void> clearCatalogCache() async {
    final db = database!;
    
    try {
      await db.delete('chart_catalog_cache');
      logger.info('Cleared all catalog cache entries');
    } catch (e) {
      logger.error('Failed to clear catalog cache: $e');
      rethrow;
    }
  }
  
  // NOAA Chart Operations
  
  /// Batch insert/update NOAA charts efficiently
  Future<void> insertNoaaCharts(List<Chart> charts) async {
    final db = database!;
    
    try {
      await db.transaction((txn) async {
        for (final chart in charts) {
          final chartData = _chartToMap(chart);
          await txn.insert('charts', chartData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      
      logger.info('Batch inserted ${charts.length} NOAA charts');
    } catch (e) {
      logger.error('Failed to batch insert NOAA charts: $e');
      rethrow;
    }
  }
  
  /// Gets charts for a specific state from state-chart mapping
  Future<List<Chart>> getChartsForState(String state) async {
    final db = database!;
    
    try {
      final results = await db.rawQuery('''
        SELECT c.* FROM charts c
        JOIN state_chart_mapping scm ON c.cell_name = scm.cell_name
        WHERE scm.state_name = ? AND c.source = ?
        ORDER BY c.title
      ''', [state, 'noaa']);
      
      return results.map((row) => _mapToChart(row)).toList();
    } catch (e) {
      logger.error('Failed to get charts for state $state: $e');
      return [];
    }
  }
  
  /// Updates state-to-chart mappings efficiently
  Future<void> updateStateMappings(String state, List<String> cellNames) async {
    final db = database!;
    
    try {
      await db.transaction((txn) async {
        // Clear existing mappings
        await txn.delete('state_chart_mapping',
          where: 'state_name = ?', whereArgs: [state]);
        
        // Insert new mappings
        for (final cellName in cellNames) {
          await txn.insert('state_chart_mapping', {
            'state_name': state,
            'cell_name': cellName,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      });
      
      logger.info('Updated state mappings for $state: ${cellNames.length} charts');
    } catch (e) {
      logger.error('Failed to update state mappings for $state: $e');
      rethrow;
    }
  }
  
  // Chart Update Detection
  
  /// Checks if a chart update is available based on edition and update numbers
  Future<bool> isChartUpdateAvailable(String cellName, int edition, int updateNumber) async {
    final db = database!;
    
    try {
      final results = await db.query('charts',
        columns: ['edition_number', 'update_number'],
        where: 'cell_name = ?',
        whereArgs: [cellName]);
      
      if (results.isEmpty) return true; // New chart
      
      final stored = results.first;
      final storedEdition = stored['edition_number'] as int? ?? 0;
      final storedUpdate = stored['update_number'] as int? ?? 0;
      
      return edition > storedEdition || 
             (edition == storedEdition && updateNumber > storedUpdate);
    } catch (e) {
      logger.error('Failed to check chart update availability for $cellName: $e');
      return false;
    }
  }
  
  /// Records chart update history when detecting changes
  Future<void> recordChartUpdate(String cellName, int oldEdition, int newEdition, 
                                int oldUpdate, int newUpdate) async {
    final db = database!;
    
    try {
      await db.insert('chart_update_history', {
        'cell_name': cellName,
        'old_edition': oldEdition,
        'new_edition': newEdition,
        'old_update_number': oldUpdate,
        'new_update_number': newUpdate,
        'update_detected_at': DateTime.now().toIso8601String(),
      });
      
      logger.info('Recorded chart update for $cellName: $oldEdition.$oldUpdate -> $newEdition.$newUpdate');
    } catch (e) {
      logger.error('Failed to record chart update for $cellName: $e');
      rethrow;
    }
  }
  
  /// Gets chart update history for a specific cell
  Future<List<Map<String, dynamic>>> getChartUpdateHistory(String cellName) async {
    final db = database!;
    
    try {
      final results = await db.query('chart_update_history',
        where: 'cell_name = ?',
        whereArgs: [cellName],
        orderBy: 'update_detected_at DESC');
      
      return results;
    } catch (e) {
      logger.error('Failed to get chart update history for $cellName: $e');
      return [];
    }
  }
  
  // Database Maintenance
  
  /// Cleans up expired catalog cache entries
  Future<void> cleanupExpiredCache() async {
    final db = database!;
    
    try {
      final deletedCount = await db.delete('chart_catalog_cache',
        where: 'expires_at < ?',
        whereArgs: [DateTime.now().toIso8601String()]);
      
      if (deletedCount > 0) {
        logger.info('Cleaned up $deletedCount expired cache entries');
      }
    } catch (e) {
      logger.error('Failed to cleanup expired cache: $e');
      rethrow;
    }
  }
  
  /// Gets storage statistics for NOAA operations
  Future<Map<String, dynamic>> getNoaaStorageStats() async {
    final db = database!;
    
    try {
      final noaaChartsCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM charts WHERE source = ?', ['noaa'])
      ) ?? 0;
      
      final stateMappingsCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM state_chart_mapping')
      ) ?? 0;
      
      final cacheEntriesCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chart_catalog_cache WHERE is_valid = ?', [1])
      ) ?? 0;
      
      final updateHistoryCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chart_update_history')
      ) ?? 0;
      
      return {
        'noaa_charts_count': noaaChartsCount,
        'state_mappings_count': stateMappingsCount,
        'cache_entries_count': cacheEntriesCount,
        'update_history_count': updateHistoryCount,
      };
    } catch (e) {
      logger.error('Failed to get NOAA storage stats: $e');
      return {};
    }
  }
  
  // Helper Methods
  
  /// Generates a hash for cache validation
  String _generateHash(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// Converts Chart object to database map
  Map<String, dynamic> _chartToMap(Chart chart) {
    final chartData = {
      'id': chart.id,
      'title': chart.title,
      'scale': chart.scale,
      'bounds_north': chart.bounds.north,
      'bounds_south': chart.bounds.south,
      'bounds_east': chart.bounds.east,
      'bounds_west': chart.bounds.west,
      'last_update': chart.lastUpdate.millisecondsSinceEpoch,
      'state': chart.state,
      'type': chart.type.name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'file_size': chart.fileSize ?? 0,
      'edition_number': chart.edition,
      'update_number': chart.updateNumber,
      'source': chart.source.name,
      'status': chart.status.name,
    };

    // Add NOAA-specific metadata if present
    if (chart.metadata.containsKey('cell_name')) {
      chartData['cell_name'] = chart.metadata['cell_name'];
    }
    if (chart.metadata.containsKey('usage_band')) {
      chartData['usage_band'] = chart.metadata['usage_band'];
    }
    if (chart.metadata.containsKey('compilation_scale')) {
      chartData['compilation_scale'] = chart.metadata['compilation_scale'];
    }
    if (chart.metadata.containsKey('region')) {
      chartData['region'] = chart.metadata['region'];
    }
    if (chart.metadata.containsKey('dt_pub')) {
      chartData['dt_pub'] = chart.metadata['dt_pub'];
    }
    if (chart.metadata.containsKey('issue_date')) {
      chartData['issue_date'] = chart.metadata['issue_date'];
    }
    if (chart.metadata.containsKey('source_date_string')) {
      chartData['source_date_string'] = chart.metadata['source_date_string'];
    }
    if (chart.metadata.containsKey('edition_date')) {
      chartData['edition_date'] = chart.metadata['edition_date'];
    }
    if (chart.metadata.containsKey('boundary_polygon')) {
      chartData['boundary_polygon'] = chart.metadata['boundary_polygon'];
    }

    return chartData;
  }
  
  /// Converts database map to Chart object
  Chart _mapToChart(Map<String, dynamic> map) {
    // Extract metadata from database fields
    final metadata = <String, dynamic>{};
    if (map['cell_name'] != null) metadata['cell_name'] = map['cell_name'];
    if (map['usage_band'] != null) metadata['usage_band'] = map['usage_band'];
    if (map['compilation_scale'] != null) metadata['compilation_scale'] = map['compilation_scale'];
    if (map['region'] != null) metadata['region'] = map['region'];
    if (map['dt_pub'] != null) metadata['dt_pub'] = map['dt_pub'];
    if (map['issue_date'] != null) metadata['issue_date'] = map['issue_date'];
    if (map['source_date_string'] != null) metadata['source_date_string'] = map['source_date_string'];
    if (map['edition_date'] != null) metadata['edition_date'] = map['edition_date'];
    if (map['boundary_polygon'] != null) metadata['boundary_polygon'] = map['boundary_polygon'];
    
    return Chart.fromJson({
      'id': map['id'],
      'title': map['title'],
      'scale': map['scale'],
      'bounds': {
        'north': map['bounds_north'],
        'south': map['bounds_south'],
        'east': map['bounds_east'],
        'west': map['bounds_west'],
      },
      'lastUpdate': map['last_update'],
      'state': map['state'],
      'type': map['type'],
      'description': map['description'],
      'isDownloaded': true, // If it's in the database, it's downloaded
      'fileSize': map['file_size'],
      'edition': map['edition_number'] ?? 0,
      'updateNumber': map['update_number'] ?? 0,
      'source': map['source'] ?? 'noaa',
      'status': map['status'] ?? 'current',
      'metadata': metadata,
    });
  }
}