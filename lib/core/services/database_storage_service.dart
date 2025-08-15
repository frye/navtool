import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/chart.dart';
import '../models/route.dart';
import '../models/waypoint.dart';
import '../models/geographic_bounds.dart';
import '../logging/app_logger.dart';
import 'storage_service.dart';

/// SQLite implementation of StorageService for marine navigation data
class DatabaseStorageService implements StorageService {
  final AppLogger _logger;
  Database? _database;
  final Database? _testDatabase; // For testing purposes

  DatabaseStorageService({
    required AppLogger logger,
    Database? testDatabase,
  }) : _logger = logger,
       _testDatabase = testDatabase;

  /// Database schema version
  static const int _databaseVersion = 1;

  /// Database name
  static const String _databaseName = 'navtool.db';

  /// Initialize the database
  Future<void> initialize() async {
    if (_testDatabase != null) {
      _database = _testDatabase;
      await _createTables(_database!);
      await _createIndexes(_database!);
      return;
    }

    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, _databaseName);

    _database = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    _logger.info('Database initialized at: $dbPath');
  }

  /// Create database tables and indexes
  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _createIndexes(db);
    _logger.info('Database created with version $version');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.info('Database upgrade from $oldVersion to $newVersion');
    // Future migrations will be handled here
  }

  /// Create all database tables
  Future<void> _createTables(Database db) async {
    // Charts table for chart metadata
    await db.execute('''
      CREATE TABLE charts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        scale INTEGER NOT NULL,
        bounds_north REAL NOT NULL,
        bounds_south REAL NOT NULL,
        bounds_east REAL NOT NULL,
        bounds_west REAL NOT NULL,
        last_update INTEGER NOT NULL,
        state TEXT,
        type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        file_size INTEGER DEFAULT 0
      )
    ''');

    // Chart data table for binary chart data
    await db.execute('''
      CREATE TABLE chart_data (
        chart_id TEXT PRIMARY KEY,
        data BLOB NOT NULL,
        FOREIGN KEY (chart_id) REFERENCES charts (id) ON DELETE CASCADE
      )
    ''');

    // Routes table
    await db.execute('''
      CREATE TABLE routes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        is_active INTEGER DEFAULT 0
      )
    ''');

    // Waypoints table
    await db.execute('''
      CREATE TABLE waypoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        route_id TEXT,
        route_order INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        FOREIGN KEY (route_id) REFERENCES routes (id) ON DELETE CASCADE
      )
    ''');

    // Download queue table
    await db.execute('''
      CREATE TABLE download_queue (
        chart_id TEXT PRIMARY KEY,
        download_url TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        progress REAL DEFAULT 0.0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Chart metadata view (alias for compatibility)
    await db.execute('''
      CREATE VIEW IF NOT EXISTS chart_metadata AS 
      SELECT * FROM charts
    ''');
  }

  /// Create database indexes for performance
  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_charts_bounds ON charts (bounds_north, bounds_south, bounds_east, bounds_west)');
    await db.execute('CREATE INDEX idx_charts_scale ON charts (scale)');
    await db.execute('CREATE INDEX idx_waypoints_route_id ON waypoints (route_id)');
    await db.execute('CREATE INDEX idx_waypoints_location ON waypoints (latitude, longitude)');
    await db.execute('CREATE INDEX idx_download_queue_status ON download_queue (status)');
  }

  /// Get database version
  Future<int> getDatabaseVersion() async {
    return _database?.getVersion() ?? 0;
  }

  // Chart Operations
  @override
  Future<void> storeChart(Chart chart, List<int> data) async {
    if (data.isEmpty) {
      throw ArgumentError('Chart data cannot be empty');
    }

    final db = _database!;
    
    try {
      await db.transaction((txn) async {
        // Check if chart already exists
        final existing = await txn.query('charts', where: 'id = ?', whereArgs: [chart.id]);
        if (existing.isNotEmpty) {
          throw Exception('Chart with ID ${chart.id} already exists');
        }

        // Insert chart metadata
        await txn.insert('charts', {
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
          'file_size': data.length,
        });

        // Insert chart data
        await txn.insert('chart_data', {
          'chart_id': chart.id,
          'data': Uint8List.fromList(data),
        });
      });

      _logger.info('Stored chart: ${chart.id} (${data.length} bytes)');
    } catch (e) {
      _logger.error('Failed to store chart ${chart.id}: $e');
      rethrow;
    }
  }

  @override
  Future<List<int>?> loadChart(String chartId) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'chart_data',
        where: 'chart_id = ?',
        whereArgs: [chartId],
      );

      if (result.isEmpty) return null;

      final data = result.first['data'] as Uint8List;
      _logger.debug('Loaded chart: $chartId (${data.length} bytes)');
      return data.toList();
    } catch (e) {
      _logger.error('Failed to load chart $chartId: $e');
      return null;
    }
  }

  @override
  Future<void> deleteChart(String chartId) async {
    final db = _database!;
    
    try {
      await db.transaction((txn) async {
        // Delete chart data first
        await txn.delete('chart_data', where: 'chart_id = ?', whereArgs: [chartId]);
        // Delete chart metadata
        await txn.delete('charts', where: 'id = ?', whereArgs: [chartId]);
      });
      
      _logger.info('Deleted chart: $chartId');
    } catch (e) {
      _logger.error('Failed to delete chart $chartId: $e');
      // Don't rethrow for non-existent charts
    }
  }

  /// Get chart metadata without the binary data
  Future<Chart?> getChartMetadata(String chartId) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'charts',
        where: 'id = ?',
        whereArgs: [chartId],
      );

      if (result.isEmpty) return null;

      return _chartFromMap(result.first);
    } catch (e) {
      _logger.error('Failed to get chart metadata $chartId: $e');
      return null;
    }
  }

  /// Update chart metadata
  Future<void> updateChartMetadata(Chart chart) async {
    final db = _database!;
    
    try {
      await db.update(
        'charts',
        {
          'title': chart.title,
          'scale': chart.scale,
          'bounds_north': chart.bounds.north,
          'bounds_south': chart.bounds.south,
          'bounds_east': chart.bounds.east,
          'bounds_west': chart.bounds.west,
          'last_update': chart.lastUpdate.millisecondsSinceEpoch,
          'state': chart.state,
          'type': chart.type.name,
        },
        where: 'id = ?',
        whereArgs: [chart.id],
      );
      
      _logger.info('Updated chart metadata: ${chart.id}');
    } catch (e) {
      _logger.error('Failed to update chart metadata ${chart.id}: $e');
      rethrow;
    }
  }

  /// Get charts within geographic bounds
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'charts',
        where: '''
          bounds_north >= ? AND bounds_south <= ? AND 
          bounds_east >= ? AND bounds_west <= ?
        ''',
        whereArgs: [bounds.south, bounds.north, bounds.west, bounds.east],
      );

      return result.map(_chartFromMap).toList();
    } catch (e) {
      _logger.error('Failed to get charts in bounds: $e');
      return [];
    }
  }

  /// Get charts by scale range
  Future<List<Chart>> getChartsByScaleRange(int minScale, int maxScale) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'charts',
        where: 'scale >= ? AND scale <= ?',
        whereArgs: [minScale, maxScale],
      );

      return result.map(_chartFromMap).toList();
    } catch (e) {
      _logger.error('Failed to get charts by scale range: $e');
      return [];
    }
  }

  // Route Operations
  /// Store a navigation route
  Future<void> storeRoute(NavigationRoute route) async {
    final db = _database!;
    
    try {
      await db.transaction((txn) async {
        // Insert route
        await txn.insert('routes', {
          'id': route.id,
          'name': route.name,
          'description': route.description,
          'created_at': route.createdAt.millisecondsSinceEpoch,
          'updated_at': route.updatedAt?.millisecondsSinceEpoch,
          'is_active': route.isActive ? 1 : 0,
        });

        // Insert waypoints
        for (int i = 0; i < route.waypoints.length; i++) {
          final waypoint = route.waypoints[i];
          await txn.insert('waypoints', {
            'id': waypoint.id,
            'name': waypoint.name,
            'latitude': waypoint.latitude,
            'longitude': waypoint.longitude,
            'type': waypoint.type.name,
            'description': waypoint.description,
            'route_id': route.id,
            'route_order': i,
            'created_at': waypoint.createdAt.millisecondsSinceEpoch,
            'updated_at': waypoint.updatedAt?.millisecondsSinceEpoch,
          });
        }
      });

      _logger.info('Stored route: ${route.id} with ${route.waypoints.length} waypoints');
    } catch (e) {
      _logger.error('Failed to store route ${route.id}: $e');
      rethrow;
    }
  }

  /// Get a navigation route by ID
  Future<NavigationRoute?> getRoute(String routeId) async {
    final db = _database!;
    
    try {
      final routeResult = await db.query(
        'routes',
        where: 'id = ?',
        whereArgs: [routeId],
      );

      if (routeResult.isEmpty) return null;

      final waypointsResult = await db.query(
        'waypoints',
        where: 'route_id = ?',
        whereArgs: [routeId],
        orderBy: 'route_order ASC',
      );

      final waypoints = waypointsResult.map(_waypointFromMap).toList();
      
      return _routeFromMap(routeResult.first, waypoints);
    } catch (e) {
      _logger.error('Failed to get route $routeId: $e');
      return null;
    }
  }

  /// Update a navigation route
  Future<void> updateRoute(NavigationRoute route) async {
    final db = _database!;
    
    try {
      await db.update(
        'routes',
        {
          'name': route.name,
          'description': route.description,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'is_active': route.isActive ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [route.id],
      );
      
      _logger.info('Updated route: ${route.id}');
    } catch (e) {
      _logger.error('Failed to update route ${route.id}: $e');
      rethrow;
    }
  }

  /// Delete a navigation route
  Future<void> deleteRoute(String routeId) async {
    final db = _database!;
    
    try {
      final deletedCount = await db.delete('routes', where: 'id = ?', whereArgs: [routeId]);
      if (deletedCount > 0) {
        _logger.info('Deleted route: $routeId');
      }
    } catch (e) {
      _logger.error('Failed to delete route $routeId: $e');
    }
  }

  /// Get all navigation routes
  Future<List<NavigationRoute>> getAllRoutes() async {
    final db = _database!;
    
    try {
      final routesResult = await db.query('routes', orderBy: 'created_at DESC');
      final routes = <NavigationRoute>[];

      for (final routeMap in routesResult) {
        final routeId = routeMap['id'] as String;
        final waypointsResult = await db.query(
          'waypoints',
          where: 'route_id = ?',
          whereArgs: [routeId],
          orderBy: 'route_order ASC',
        );

        final waypoints = waypointsResult.map(_waypointFromMap).toList();
        routes.add(_routeFromMap(routeMap, waypoints));
      }

      return routes;
    } catch (e) {
      _logger.error('Failed to get all routes: $e');
      return [];
    }
  }

  // Waypoint Operations
  /// Store a standalone waypoint
  Future<void> storeWaypoint(Waypoint waypoint) async {
    final db = _database!;
    
    try {
      await db.insert('waypoints', {
        'id': waypoint.id,
        'name': waypoint.name,
        'latitude': waypoint.latitude,
        'longitude': waypoint.longitude,
        'type': waypoint.type.name,
        'description': waypoint.description,
        'route_id': null,
        'route_order': null,
        'created_at': waypoint.createdAt.millisecondsSinceEpoch,
        'updated_at': waypoint.updatedAt?.millisecondsSinceEpoch,
      });

      _logger.info('Stored waypoint: ${waypoint.id}');
    } catch (e) {
      _logger.error('Failed to store waypoint ${waypoint.id}: $e');
      rethrow;
    }
  }

  /// Get a waypoint by ID
  Future<Waypoint?> getWaypoint(String waypointId) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'waypoints',
        where: 'id = ?',
        whereArgs: [waypointId],
      );

      if (result.isEmpty) return null;
      return _waypointFromMap(result.first);
    } catch (e) {
      _logger.error('Failed to get waypoint $waypointId: $e');
      return null;
    }
  }

  /// Delete a waypoint
  Future<void> deleteWaypoint(String waypointId) async {
    final db = _database!;
    
    try {
      final deletedCount = await db.delete('waypoints', where: 'id = ?', whereArgs: [waypointId]);
      if (deletedCount > 0) {
        _logger.info('Deleted waypoint: $waypointId');
      }
    } catch (e) {
      _logger.error('Failed to delete waypoint $waypointId: $e');
    }
  }

  /// Load a navigation route by ID (interface requirement)
  @override
  Future<NavigationRoute?> loadRoute(String routeId) async {
    final db = _database!;
    
    try {
      final routeResult = await db.query('routes', where: 'id = ?', whereArgs: [routeId]);
      if (routeResult.isEmpty) {
        return null;
      }

      final routeMap = routeResult.first;
      final waypointIds = (routeMap['waypoint_ids'] as String?)?.split(',') ?? [];
      
      final waypoints = <Waypoint>[];
      for (final waypointId in waypointIds) {
        final waypoint = await loadWaypoint(waypointId);
        if (waypoint != null) {
          waypoints.add(waypoint);
        }
      }

      return _routeFromMap(routeMap, waypoints);
    } catch (e) {
      _logger.error('Failed to load route $routeId: $e');
      return null;
    }
  }

  /// Load a waypoint by ID (interface requirement)
  @override
  Future<Waypoint?> loadWaypoint(String waypointId) async {
    final db = _database!;
    
    try {
      final result = await db.query('waypoints', where: 'id = ?', whereArgs: [waypointId]);
      if (result.isEmpty) {
        return null;
      }
      
      return _waypointFromMap(result.first);
    } catch (e) {
      _logger.error('Failed to load waypoint $waypointId: $e');
      return null;
    }
  }

  /// Update an existing waypoint (interface requirement)
  @override
  Future<void> updateWaypoint(Waypoint waypoint) async {
    final db = _database!;
    
    try {
      final updatedWaypoint = waypoint.copyWith(updatedAt: DateTime.now());
      await db.update(
        'waypoints',
        {
          'id': updatedWaypoint.id,
          'name': updatedWaypoint.name,
          'latitude': updatedWaypoint.latitude,
          'longitude': updatedWaypoint.longitude,
          'type': updatedWaypoint.type.name,
          'description': updatedWaypoint.description,
          'route_id': null,
          'route_order': null,
          'created_at': updatedWaypoint.createdAt.millisecondsSinceEpoch,
          'updated_at': updatedWaypoint.updatedAt?.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [waypoint.id],
      );
      _logger.info('Updated waypoint: ${waypoint.id}');
    } catch (e) {
      _logger.error('Failed to update waypoint ${waypoint.id}: $e');
      rethrow;
    }
  }

  /// Get all stored waypoints (interface requirement)
  @override
  Future<List<Waypoint>> getAllWaypoints() async {
    final db = _database!;
    
    try {
      final result = await db.query('waypoints', orderBy: 'created_at DESC');
      return result.map((map) => _waypointFromMap(map)).toList();
    } catch (e) {
      _logger.error('Failed to get all waypoints: $e');
      return [];
    }
  }

  /// Get waypoints within geographic area
  Future<List<Waypoint>> getWaypointsInArea(GeographicBounds bounds) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'waypoints',
        where: 'latitude >= ? AND latitude <= ? AND longitude >= ? AND longitude <= ?',
        whereArgs: [bounds.south, bounds.north, bounds.west, bounds.east],
      );

      return result.map(_waypointFromMap).toList();
    } catch (e) {
      _logger.error('Failed to get waypoints in area: $e');
      return [];
    }
  }

  // Download Queue Operations
  /// Add chart to download queue
  Future<void> addToDownloadQueue(String chartId, String downloadUrl) async {
    final db = _database!;
    
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('download_queue', {
        'chart_id': chartId,
        'download_url': downloadUrl,
        'status': 'pending',
        'progress': 0.0,
        'created_at': now,
        'updated_at': now,
      });

      _logger.info('Added to download queue: $chartId');
    } catch (e) {
      _logger.error('Failed to add to download queue $chartId: $e');
      rethrow;
    }
  }

  /// Update download queue item status
  Future<void> updateDownloadQueueStatus(String chartId, String status, double progress) async {
    final db = _database!;
    
    try {
      await db.update(
        'download_queue',
        {
          'status': status,
          'progress': progress,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'chart_id = ?',
        whereArgs: [chartId],
      );
      
      _logger.debug('Updated download status: $chartId -> $status ($progress)');
    } catch (e) {
      _logger.error('Failed to update download status $chartId: $e');
      rethrow;
    }
  }

  /// Remove chart from download queue
  Future<void> removeFromDownloadQueue(String chartId) async {
    final db = _database!;
    
    try {
      final deletedCount = await db.delete('download_queue', where: 'chart_id = ?', whereArgs: [chartId]);
      if (deletedCount > 0) {
        _logger.info('Removed from download queue: $chartId');
      }
    } catch (e) {
      _logger.error('Failed to remove from download queue $chartId: $e');
    }
  }

  /// Get download queue item
  Future<Map<String, dynamic>?> getDownloadQueueItem(String chartId) async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'download_queue',
        where: 'chart_id = ?',
        whereArgs: [chartId],
      );

      return result.isEmpty ? null : result.first;
    } catch (e) {
      _logger.error('Failed to get download queue item $chartId: $e');
      return null;
    }
  }

  /// Get pending downloads
  Future<List<Map<String, dynamic>>> getPendingDownloads() async {
    final db = _database!;
    
    try {
      final result = await db.query(
        'download_queue',
        where: 'status != ?',
        whereArgs: ['completed'],
        orderBy: 'created_at ASC',
      );

      return result;
    } catch (e) {
      _logger.error('Failed to get pending downloads: $e');
      return [];
    }
  }

  // Storage Utilities
  @override
  Future<Map<String, dynamic>> getStorageInfo() async {
    final db = _database!;
    
    try {
      final chartsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM charts')) ?? 0;
      final routesCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM routes')) ?? 0;
      final waypointsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM waypoints WHERE route_id IS NULL')) ?? 0;
      final downloadsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM download_queue WHERE status != "completed"')) ?? 0;

      // Calculate database size
      int databaseSize = 0;
      if (_testDatabase == null) {
        final databasesPath = await getDatabasesPath();
        final dbPath = path.join(databasesPath, _databaseName);
        final file = File(dbPath);
        if (await file.exists()) {
          databaseSize = await file.length();
        }
      } else {
        // For test databases, calculate size based on data
        final chartDataSize = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM chart_data')
        ) ?? 0;
        databaseSize = chartDataSize + 10000; // Add overhead estimate
      }

      return {
        'total_charts': chartsCount,
        'total_routes': routesCount,
        'total_waypoints': waypointsCount,
        'total_downloads_pending': downloadsCount,
        'database_size_bytes': databaseSize,
      };
    } catch (e) {
      _logger.error('Failed to get storage info: $e');
      return {};
    }
  }

  @override
  Future<int> getStorageUsage() async {
    final storageInfo = await getStorageInfo();
    return storageInfo['database_size_bytes'] as int? ?? 0;
  }

  @override
  Future<Directory> getChartsDirectory() async {
    final databasesPath = await getDatabasesPath();
    return Directory(databasesPath);
  }

  @override
  Future<void> cleanupOldData() async {
    await _cleanupOldData(maxAge: const Duration(days: 365));
  }

  /// Cleanup old data with custom max age (public for testing)
  Future<int> cleanupOldDataWithAge({required Duration maxAge}) async {
    return await _cleanupOldData(maxAge: maxAge);
  }

  /// Cleanup old data with custom max age
  Future<int> _cleanupOldData({required Duration maxAge}) async {
    final db = _database!;
    final cutoffTime = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    
    try {
      final deletedCount = await db.delete(
        'charts',
        where: 'last_update < ?',
        whereArgs: [cutoffTime],
      );

      if (deletedCount > 0) {
        _logger.info('Cleaned up $deletedCount old charts');
      }

      return deletedCount;
    } catch (e) {
      _logger.error('Failed to cleanup old data: $e');
      return 0;
    }
  }

  // Helper methods for data conversion
  Chart _chartFromMap(Map<String, dynamic> map) {
    return Chart(
      id: map['id'] as String,
      title: map['title'] as String,
      scale: map['scale'] as int,
      bounds: GeographicBounds(
        north: map['bounds_north'] as double,
        south: map['bounds_south'] as double,
        east: map['bounds_east'] as double,
        west: map['bounds_west'] as double,
      ),
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(map['last_update'] as int),
      state: map['state'] as String? ?? '',
      type: ChartType.values.firstWhere((t) => t.name == map['type']),
    );
  }

  NavigationRoute _routeFromMap(Map<String, dynamic> map, List<Waypoint> waypoints) {
    return NavigationRoute(
      id: map['id'] as String,
      name: map['name'] as String,
      waypoints: waypoints,
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Waypoint _waypointFromMap(Map<String, dynamic> map) {
    return Waypoint(
      id: map['id'] as String,
      name: map['name'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      type: WaypointType.values.firstWhere((t) => t.name == map['type']),
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
    );
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null && _testDatabase == null) {
      await _database!.close();
      _database = null;
      _logger.info('Database connection closed');
    }
  }
}
