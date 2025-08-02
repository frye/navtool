import '../models/waypoint.dart';
import '../models/route.dart';
import '../models/gps_position.dart';

/// Service interface for navigation operations
abstract class NavigationService {
  /// Creates a new route from waypoints
  Future<NavigationRoute> createRoute(List<Waypoint> waypoints);

  /// Activates a route for navigation
  Future<void> activateRoute(NavigationRoute route);

  /// Deactivates the current route
  Future<void> deactivateRoute();

  /// Adds a waypoint to the navigation system
  Future<void> addWaypoint(Waypoint waypoint);

  /// Removes a waypoint by ID
  Future<void> removeWaypoint(String waypointId);

  /// Updates an existing waypoint
  Future<void> updateWaypoint(Waypoint waypoint);

  /// Calculates bearing between two GPS positions
  double calculateBearing(GpsPosition from, GpsPosition to);

  /// Calculates distance between two GPS positions
  double calculateDistance(GpsPosition from, GpsPosition to);
}
