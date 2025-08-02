import '../models/gps_position.dart';

/// Service interface for GPS and location operations
abstract class GpsService {
  /// Starts location tracking
  Future<void> startLocationTracking();

  /// Stops location tracking
  Future<void> stopLocationTracking();

  /// Gets the current position
  Future<GpsPosition?> getCurrentPosition();

  /// Gets a stream of location updates
  Stream<GpsPosition> getLocationStream();

  /// Requests location permission
  Future<bool> requestLocationPermission();

  /// Checks if location permission is granted
  Future<bool> checkLocationPermission();

  /// Checks if location services are enabled
  Future<bool> isLocationEnabled();
}
