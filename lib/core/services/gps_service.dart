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
  Future<List<GpsPosition>> filterForMarineAccuracy(List<GpsPosition> positions);

  /// Calculates course over ground from position history
  Future<CourseOverGround?> calculateCourseOverGround(Duration timeWindow);

  /// Calculates speed over ground from position history
  Future<SpeedOverGround?> calculateSpeedOverGround(Duration timeWindow);
}
