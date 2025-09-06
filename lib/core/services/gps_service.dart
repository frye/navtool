import '../models/gps_position.dart';
import '../models/gps_signal_quality.dart';
import '../models/position_history.dart';

/// Service interface for GPS and location operations
abstract class GpsService {
  /// Starts location tracking
  Future<void> startLocationTracking();

  /// Stops location tracking
  Future<void> stopLocationTracking();

  /// Gets the current position
  Future<GpsPosition?> getCurrentPosition();

  /// Gets current position with Seattle fallback when location services disabled
  ///
  /// This method attempts to get the real GPS position first, but if location
  /// services are disabled or permission is denied, it returns Seattle coordinates
  /// as a fallback location for chart discovery.
  ///
  /// Returns:
  /// - Real GPS position if available and permission granted
  /// - Seattle fallback coordinates if location services disabled/denied
  /// - Never returns null (always provides a usable location)
  Future<GpsPosition?> getCurrentPositionWithFallback();

  /// Gets a stream of location updates
  Stream<GpsPosition> getLocationStream();

  /// Requests location permission
  Future<bool> requestLocationPermission();

  /// Checks if location permission is granted
  Future<bool> checkLocationPermission();

  /// Checks if location services are enabled
  Future<bool> isLocationEnabled();

  // Enhanced functionality for issue #53

  /// Assesses GPS signal quality from position data
  Future<GpsSignalQuality> assessSignalQuality(GpsPosition? position);

  /// Logs a GPS position for history tracking
  Future<void> logPosition(GpsPosition position);

  /// Gets position history within the specified time window
  Future<PositionHistory> getPositionHistory(Duration timeWindow);

  /// Gets signal quality trend over time
  Future<List<GpsSignalQuality>> getSignalQualityTrend(Duration timeWindow);

  /// Clears stored position history
  Future<void> clearPositionHistory();

  /// Gets accuracy statistics for the specified time period
  Future<AccuracyStatistics> getAccuracyStatistics(Duration timeWindow);

  /// Gets current movement state (stationary vs moving)
  Future<MovementState> getMovementState(Duration analysisWindow);

  /// Gets position data freshness information
  Future<PositionFreshness> getPositionFreshness();

  /// Filters positions to meet marine navigation accuracy standards
  Future<List<GpsPosition>> filterForMarineAccuracy(
    List<GpsPosition> positions,
  );

  /// Calculates course over ground from position history
  Future<CourseOverGround?> calculateCourseOverGround(Duration timeWindow);

  /// Calculates speed over ground from position history
  Future<SpeedOverGround?> calculateSpeedOverGround(Duration timeWindow);
}
