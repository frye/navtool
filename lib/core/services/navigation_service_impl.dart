import 'dart:math' as math;
import 'package:navtool/core/services/navigation_service.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';

/// Implementation of NavigationService for marine navigation calculations
/// Handles route creation, waypoint management, and navigation computations
class NavigationServiceImpl implements NavigationService {
  final AppLogger _logger;
  final Map<String, NavigationRoute> _routeCache = {};
  final Map<String, Waypoint> _waypointCache = {};
  NavigationRoute? _activeRoute;

  NavigationServiceImpl({required AppLogger logger}) : _logger = logger;

  @override
  Future<NavigationRoute> createRoute(List<Waypoint> waypoints) async {
    try {
      _logger.info('Creating route with ${waypoints.length} waypoints');

      // Validate route requirements
      if (waypoints.length < 2) {
        throw AppError(
          message: 'Route must have at least 2 waypoints',
          type: AppErrorType.validation,
        );
      }

      // Validate all waypoints have valid coordinates
      for (final waypoint in waypoints) {
        _validateGpsPosition(
          GpsPosition(
            latitude: waypoint.latitude,
            longitude: waypoint.longitude,
            timestamp: DateTime.now(),
          ),
        );
      }

      final route = NavigationRoute(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Route ${waypoints.length} waypoints',
        waypoints: waypoints,
      );

      _routeCache[route.id] = route;
      _logger.info('Route created successfully with ID: ${route.id}');

      return route;
    } catch (e) {
      _logger.error('Failed to create route', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to create route',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  Future<void> activateRoute(NavigationRoute route) async {
    try {
      _logger.info('Activating route: ${route.id}');

      // Validate route
      if (route.waypoints.length < 2) {
        throw AppError(
          message: 'Cannot activate route with insufficient waypoints',
          type: AppErrorType.validation,
        );
      }

      _activeRoute = route;
      _logger.info('Route ${route.id} activated successfully');
    } catch (e) {
      _logger.error('Failed to activate route: ${route.id}', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to activate route',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  Future<void> deactivateRoute() async {
    try {
      final currentRouteId = _activeRoute?.id ?? 'none';
      _activeRoute = null;
      _logger.info('Deactivated route: $currentRouteId');
    } catch (e) {
      _logger.error('Failed to deactivate route', exception: e);
      throw AppError(
        message: 'Failed to deactivate route',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  Future<void> addWaypoint(Waypoint waypoint) async {
    try {
      _logger.info('Adding waypoint: ${waypoint.name}');

      // Validate waypoint
      _validateGpsPosition(
        GpsPosition(
          latitude: waypoint.latitude,
          longitude: waypoint.longitude,
          timestamp: DateTime.now(),
        ),
      );

      _waypointCache[waypoint.id] = waypoint;
      _logger.info('Waypoint ${waypoint.name} added successfully');
    } catch (e) {
      _logger.error('Failed to add waypoint: ${waypoint.name}', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to add waypoint',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  Future<void> removeWaypoint(String waypointId) async {
    try {
      _logger.info('Removing waypoint: $waypointId');

      if (_waypointCache.containsKey(waypointId)) {
        _waypointCache.remove(waypointId);
        _logger.info('Waypoint $waypointId removed successfully');
      } else {
        _logger.warning('Waypoint $waypointId not found for removal');
      }
    } catch (e) {
      _logger.error('Failed to remove waypoint: $waypointId', exception: e);
      throw AppError(
        message: 'Failed to remove waypoint',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  Future<void> updateWaypoint(Waypoint waypoint) async {
    try {
      _logger.info('Updating waypoint: ${waypoint.id}');

      // Validate waypoint
      _validateGpsPosition(
        GpsPosition(
          latitude: waypoint.latitude,
          longitude: waypoint.longitude,
          timestamp: DateTime.now(),
        ),
      );

      _waypointCache[waypoint.id] = waypoint;
      _logger.info('Waypoint ${waypoint.id} updated successfully');
    } catch (e) {
      _logger.error('Failed to update waypoint: ${waypoint.id}', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to update waypoint',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  double calculateBearing(GpsPosition from, GpsPosition to) {
    try {
      _validateGpsPosition(from);
      _validateGpsPosition(to);

      final double lat1Rad = from.latitude * (math.pi / 180);
      final double lat2Rad = to.latitude * (math.pi / 180);
      final double deltaLonRad =
          (to.longitude - from.longitude) * (math.pi / 180);

      final double x = math.sin(deltaLonRad) * math.cos(lat2Rad);
      final double y =
          math.cos(lat1Rad) * math.sin(lat2Rad) -
          math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLonRad);

      double bearingRad = math.atan2(x, y);
      double bearingDeg = bearingRad * (180 / math.pi);

      // Normalize to 0-360 degrees
      bearingDeg = (bearingDeg + 360) % 360;

      return bearingDeg;
    } catch (e) {
      _logger.error('Failed to calculate bearing', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to calculate bearing',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  @override
  double calculateDistance(GpsPosition from, GpsPosition to) {
    try {
      _validateGpsPosition(from);
      _validateGpsPosition(to);

      // Use Haversine formula for great circle distance
      const double earthRadiusKm = 6371.0;

      final double lat1Rad = from.latitude * (math.pi / 180);
      final double lat2Rad = to.latitude * (math.pi / 180);
      final double deltaLatRad =
          (to.latitude - from.latitude) * (math.pi / 180);
      final double deltaLonRad =
          (to.longitude - from.longitude) * (math.pi / 180);

      final double a =
          math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
          math.cos(lat1Rad) *
              math.cos(lat2Rad) *
              math.sin(deltaLonRad / 2) *
              math.sin(deltaLonRad / 2);

      final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      final double distanceKm = earthRadiusKm * c;

      // Convert to nautical miles (1 km = 0.539957 nautical miles)
      final double distanceNauticalMiles = distanceKm * 0.539957;

      return distanceNauticalMiles;
    } catch (e) {
      _logger.error('Failed to calculate distance', exception: e);
      if (e is AppError) rethrow;
      throw AppError(
        message: 'Failed to calculate distance',
        type: AppErrorType.unknown,
        originalError: e,
      );
    }
  }

  /// Validate GPS position bounds
  void _validateGpsPosition(GpsPosition position) {
    if (position.latitude < -90 || position.latitude > 90) {
      throw AppError(
        message: 'Latitude must be between -90 and 90',
        type: AppErrorType.validation,
      );
    }
    if (position.longitude < -180 || position.longitude > 180) {
      throw AppError(
        message: 'Longitude must be between -180 and 180',
        type: AppErrorType.validation,
      );
    }
  }

  /// Get the currently active route (helper method for testing)
  NavigationRoute? get activeRoute => _activeRoute;

  /// Get all cached waypoints (helper method for testing)
  List<Waypoint> get allWaypoints => _waypointCache.values.toList();

  /// Get all cached routes (helper method for testing)
  List<NavigationRoute> get allRoutes => _routeCache.values.toList();
}
