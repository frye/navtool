import 'dart:io';
import '../models/chart.dart';
import '../models/route.dart';
import '../models/waypoint.dart';
import '../models/geographic_bounds.dart';
import 'gps_track_recording_service.dart';

/// Service interface for storage operations
abstract class StorageService {
  /// Stores chart data locally
  Future<void> storeChart(Chart chart, List<int> data);

  /// Loads chart data from local storage
  Future<List<int>?> loadChart(String chartId);

  /// Deletes a chart from local storage
  Future<void> deleteChart(String chartId);

  /// Gets storage information (used space, available space, etc.)
  Future<Map<String, dynamic>> getStorageInfo();

  /// Cleans up old or unused data
  Future<void> cleanupOldData();

  /// Gets total storage usage in bytes
  Future<int> getStorageUsage();

  /// Gets the directory where charts are stored
  Future<Directory> getChartsDirectory();

  // Navigation-related storage methods

  /// Stores a navigation route
  Future<void> storeRoute(NavigationRoute route);

  /// Loads a navigation route by ID
  Future<NavigationRoute?> loadRoute(String routeId);

  /// Deletes a navigation route
  Future<void> deleteRoute(String routeId);

  /// Gets all stored routes
  Future<List<NavigationRoute>> getAllRoutes();

  /// Stores a waypoint
  Future<void> storeWaypoint(Waypoint waypoint);

  /// Loads a waypoint by ID
  Future<Waypoint?> loadWaypoint(String waypointId);

  /// Updates an existing waypoint
  Future<void> updateWaypoint(Waypoint waypoint);

  /// Deletes a waypoint
  Future<void> deleteWaypoint(String waypointId);

  /// Gets all stored waypoints
  Future<List<Waypoint>> getAllWaypoints();

  // State-Chart Mapping Operations

  /// Store state-to-chart cell mapping
  Future<void> storeStateCellMapping(String stateName, List<String> chartCells);

  /// Get cached state-to-chart cell mapping
  Future<List<String>?> getStateCellMapping(String stateName);

  /// Clear all state-chart mappings
  Future<void> clearAllStateCellMappings();

  /// Get charts within geographic bounds (used for spatial intersection)
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds);

  /// Count charts with invalid bounds (typically 0,0,0,0 from old cache)
  Future<int> countChartsWithInvalidBounds();

  /// Clear charts with invalid bounds (cache invalidation)
  Future<int> clearChartsWithInvalidBounds();

  // GPS Track Operations

  /// Store a GPS track
  Future<void> saveGpsTrack(GpsTrack track);

  /// Load a GPS track by ID
  Future<GpsTrack?> getGpsTrack(String trackId);

  /// Delete a GPS track
  Future<void> deleteGpsTrack(String trackId);

  /// Get all GPS tracks
  Future<List<GpsTrack>> getAllGpsTracks();

  /// Get GPS tracks within a date range
  Future<List<GpsTrack>> getGpsTracksInDateRange(DateTime startDate, DateTime endDate);
}
