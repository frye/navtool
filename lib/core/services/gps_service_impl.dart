import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import '../models/gps_position.dart';
import '../models/gps_signal_quality.dart';
import '../models/position_history.dart';
import '../logging/app_logger.dart';
import 'gps_service.dart';

/// Implementation of GPS service using geolocator package
///
/// Provides marine-grade GPS functionality with high accuracy requirements
/// specifically designed for nautical navigation applications.
///
/// Features:
/// - High accuracy positioning (LocationAccuracy.best)
/// - Marine-specific filtering (accuracy ≤ 10m)
/// - Appropriate timeouts for marine environments (30s)
/// - Comprehensive error handling for poor signal conditions
/// - Real-time position streaming with accuracy filtering
/// - Proper permission management for location access
/// - Signal quality monitoring and assessment
/// - Position history tracking and analytics
/// - Marine navigation calculations (COG, SOG)
class GpsServiceImpl implements GpsService {
  final AppLogger _logger;
  StreamSubscription<Position>? _positionSubscription;
  StreamController<GpsPosition>? _locationController;

  // Position history storage for enhanced features
  final List<GpsPosition> _positionHistory = [];
  final List<GpsSignalQuality> _qualityHistory = [];

  // Constants for marine navigation standards
  static const int _maxHistorySize = 1000;
  static const double _marineAccuracyThreshold = 10.0; // meters

  // Marine navigation requires high accuracy settings
  static const LocationSettings _marineLocationSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 1, // Update every meter for marine navigation
    timeLimit: Duration(seconds: 30), // Suitable timeout for marine conditions
  );

  GpsServiceImpl({required AppLogger logger}) : _logger = logger;

  @override
  Future<bool> requestLocationPermission() async {
    try {
      _logger.debug('Requesting location permission');

      LocationPermission permission = await GeolocatorPlatform.instance
          .checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await GeolocatorPlatform.instance.requestPermission();
      }

      final granted =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      _logger.info('Location permission request result: $permission');
      return granted;
    } catch (error) {
      _logger.error('Error requesting location permission', exception: error);
      return false;
    }
  }

  @override
  Future<bool> checkLocationPermission() async {
    try {
      final permission = await GeolocatorPlatform.instance.checkPermission();
      final granted =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      _logger.debug('Location permission status: $permission');
      return granted;
    } catch (error) {
      _logger.error('Error checking location permission', exception: error);
      return false;
    }
  }

  @override
  Future<bool> isLocationEnabled() async {
    try {
      final enabled = await GeolocatorPlatform.instance
          .isLocationServiceEnabled();
      _logger.debug('Location services enabled: $enabled');
      return enabled;
    } catch (error) {
      _logger.error('Error checking location services', exception: error);
      return false;
    }
  }

  @override
  Future<GpsPosition?> getCurrentPosition() async {
    try {
      _logger.debug(
        'Getting current GPS position with marine accuracy settings',
      );

      // Check permissions and services first
      if (!await isLocationEnabled()) {
        _logger.warning('Location services are disabled');
        return null;
      }

      if (!await checkLocationPermission()) {
        _logger.warning('Location permission not granted');
        return null;
      }

      final position = await GeolocatorPlatform.instance.getCurrentPosition(
        locationSettings: _marineLocationSettings,
      );

      final gpsPosition = _convertToGpsPosition(position);
      _logger.debug('Got GPS position: ${gpsPosition.toCoordinateString()}');

      return gpsPosition;
    } on LocationServiceDisabledException {
      _logger.error('Location services are disabled');
      return null;
    } on PermissionDeniedException {
      _logger.error('Location permission denied');
      return null;
    } on TimeoutException {
      _logger.error('GPS position timeout in marine environment');
      return null;
    } catch (error) {
      _logger.error('Error getting current position', exception: error);
      return null;
    }
  }

  @override
  Future<void> startLocationTracking() async {
    try {
      _logger.info('Starting GPS location tracking for marine navigation');

      if (!await isLocationEnabled() || !await checkLocationPermission()) {
        throw Exception('Location services not available');
      }

      // Initialize stream controller if not already done
      _locationController ??= StreamController<GpsPosition>.broadcast();

      // Start position stream with marine settings
      _positionSubscription = GeolocatorPlatform.instance
          .getPositionStream(locationSettings: _marineLocationSettings)
          .listen(
            (Position position) {
              final gpsPosition = _convertToGpsPosition(position);

              // Filter out positions with poor accuracy for marine navigation
              if (_isAccurateEnoughForMarine(gpsPosition)) {
                _locationController?.add(gpsPosition);
                _logger.debug(
                  'GPS position update: ${gpsPosition.toCoordinateString()}',
                );
              } else {
                _logger.warning(
                  'Filtered out inaccurate GPS position: accuracy=${gpsPosition.accuracy}m',
                );
              }
            },
            onError: (error) {
              _logger.error('GPS position stream error', exception: error);
              _locationController?.addError(error);
            },
          );
    } catch (error) {
      _logger.error('Error starting location tracking', exception: error);
      rethrow;
    }
  }

  @override
  Future<void> stopLocationTracking() async {
    try {
      _logger.info('Stopping GPS location tracking');

      await _positionSubscription?.cancel();
      _positionSubscription = null;

      await _locationController?.close();
      _locationController = null;
    } catch (error) {
      _logger.error('Error stopping location tracking', exception: error);
    }
  }

  @override
  Stream<GpsPosition> getLocationStream() {
    if (_locationController == null) {
      throw StateError(
        'Location tracking not started. Call startLocationTracking() first.',
      );
    }

    return _locationController!.stream;
  }

  // Enhanced functionality for issue #53

  @override
  Future<GpsSignalQuality> assessSignalQuality(GpsPosition? position) async {
    try {
      _logger.debug('Assessing GPS signal quality');

      if (position == null) {
        throw ArgumentError('Position cannot be null');
      }

      final quality = GpsSignalQuality.fromAccuracy(position.accuracy);
      _logger.debug('Signal quality assessed: ${quality.strength}');

      return quality;
    } catch (error) {
      _logger.error('Error assessing signal quality', exception: error);
      rethrow;
    }
  }

  @override
  Future<void> logPosition(GpsPosition position) async {
    try {
      _logger.debug('Logging GPS position: ${position.toCoordinateString()}');

      _addPositionToHistory(position);

      // Also log signal quality for this position
      final quality = await assessSignalQuality(position);
      _addQualityToHistory(quality);
    } catch (error) {
      _logger.error('Error logging position', exception: error);
    }
  }

  @override
  Future<PositionHistory> getPositionHistory(Duration timeWindow) async {
    try {
      _logger.debug(
        'Getting position history for ${timeWindow.inMinutes} minutes',
      );

      final filteredPositions = _getPositionsInTimeWindow(timeWindow);
      return PositionHistory.fromPositions(filteredPositions);
    } catch (error) {
      _logger.error('Error getting position history', exception: error);
      return _createEmptyPositionHistory();
    }
  }

  @override
  Future<List<GpsSignalQuality>> getSignalQualityTrend(
    Duration timeWindow,
  ) async {
    try {
      _logger.debug(
        'Getting signal quality trend for ${timeWindow.inMinutes} minutes',
      );

      final cutoffTime = DateTime.now().subtract(timeWindow);
      return _qualityHistory
          .where((quality) => quality.assessmentTime.isAfter(cutoffTime))
          .toList();
    } catch (error) {
      _logger.error('Error getting signal quality trend', exception: error);
      return [];
    }
  }

  @override
  Future<void> clearPositionHistory() async {
    try {
      _logger.info('Clearing GPS position history');

      _positionHistory.clear();
      _qualityHistory.clear();
    } catch (error) {
      _logger.error('Error clearing position history', exception: error);
    }
  }

  // Position History Management Helper Methods

  /// Adds a position to history with size management
  void _addPositionToHistory(GpsPosition position) {
    _positionHistory.add(position);

    // Keep history manageable
    if (_positionHistory.length > _maxHistorySize) {
      _positionHistory.removeAt(0);
    }
  }

  /// Adds signal quality to history with size management
  void _addQualityToHistory(GpsSignalQuality quality) {
    _qualityHistory.add(quality);

    // Keep history manageable
    if (_qualityHistory.length > _maxHistorySize) {
      _qualityHistory.removeAt(0);
    }
  }

  /// Gets positions within the specified time window
  List<GpsPosition> _getPositionsInTimeWindow(Duration timeWindow) {
    final cutoffTime = DateTime.now().subtract(timeWindow);
    return _positionHistory
        .where((position) => position.timestamp.isAfter(cutoffTime))
        .toList();
  }

  /// Creates an empty position history for error cases
  PositionHistory _createEmptyPositionHistory() {
    return const PositionHistory(
      positions: [],
      totalDistance: 0.0,
      averageSpeed: 0.0,
      maxSpeed: 0.0,
      minSpeed: 0.0,
      duration: Duration.zero,
    );
  }

  // Enhanced Analytics and Statistics Methods

  @override
  Future<AccuracyStatistics> getAccuracyStatistics(Duration timeWindow) async {
    try {
      final history = await getPositionHistory(timeWindow);
      return AccuracyStatistics.fromPositions(history.positions, timeWindow);
    } catch (error) {
      _logger.error('Error getting accuracy statistics', exception: error);
      return _createEmptyAccuracyStatistics(timeWindow);
    }
  }

  @override
  Future<MovementState> getMovementState(Duration analysisWindow) async {
    try {
      final history = await getPositionHistory(analysisWindow);
      return MovementState.fromPositions(history.positions, analysisWindow);
    } catch (error) {
      _logger.error('Error getting movement state', exception: error);
      return _createDefaultMovementState();
    }
  }

  @override
  Future<PositionFreshness> getPositionFreshness() async {
    try {
      final lastPosition = _positionHistory.isNotEmpty
          ? _positionHistory.last
          : null;
      return PositionFreshness.fromLastUpdate(lastPosition?.timestamp);
    } catch (error) {
      _logger.error('Error getting position freshness', exception: error);
      return _createStalePositionFreshness();
    }
  }

  // Marine Navigation Calculations

  @override
  Future<List<GpsPosition>> filterForMarineAccuracy(
    List<GpsPosition> positions,
  ) async {
    try {
      _logger.debug(
        'Filtering ${positions.length} positions for marine accuracy',
      );

      final filteredPositions = positions
          .where((position) => _isMarineGradeAccuracy(position))
          .toList();

      _logger.debug(
        'Filtered to ${filteredPositions.length} marine-grade positions',
      );
      return filteredPositions;
    } catch (error) {
      _logger.error(
        'Error filtering positions for marine accuracy',
        exception: error,
      );
      return [];
    }
  }

  @override
  Future<CourseOverGround?> calculateCourseOverGround(
    Duration timeWindow,
  ) async {
    try {
      final history = await getPositionHistory(timeWindow);

      if (history.positions.length < 2) {
        _logger.debug('Insufficient positions for COG calculation');
        return null;
      }

      return _calculateCourseFromHistory(history, timeWindow);
    } catch (error) {
      _logger.error('Error calculating course over ground', exception: error);
      return null;
    }
  }

  @override
  Future<SpeedOverGround?> calculateSpeedOverGround(Duration timeWindow) async {
    try {
      final history = await getPositionHistory(timeWindow);

      if (history.positions.length < 2) {
        _logger.debug('Insufficient positions for SOG calculation');
        return null;
      }

      return _calculateSpeedFromHistory(history, timeWindow);
    } catch (error) {
      _logger.error('Error calculating speed over ground', exception: error);
      return null;
    }
  }

  // Helper Methods for Analytics

  /// Creates empty accuracy statistics for error cases
  AccuracyStatistics _createEmptyAccuracyStatistics(Duration period) {
    return AccuracyStatistics(
      averageAccuracy: 0.0,
      bestAccuracy: 0.0,
      worstAccuracy: 0.0,
      marineGradePercentage: 0.0,
      sampleCount: 0,
      period: period,
    );
  }

  /// Creates default movement state for error cases
  MovementState _createDefaultMovementState() {
    return const MovementState(
      isStationary: true,
      averageSpeed: 0.0,
      confidence: 0.0,
      movementRadius: 0.0,
    );
  }

  /// Creates stale position freshness for error cases
  PositionFreshness _createStalePositionFreshness() {
    return const PositionFreshness(
      lastUpdateAge: Duration(days: 1),
      isFresh: false,
      stalenessLevel: StalenessLevel.veryStale,
    );
  }

  /// Checks if position meets marine-grade accuracy standards
  bool _isMarineGradeAccuracy(GpsPosition position) {
    return position.accuracy != null &&
        position.accuracy! <= _marineAccuracyThreshold;
  }

  /// Calculates course over ground from position history
  CourseOverGround _calculateCourseFromHistory(
    PositionHistory history,
    Duration timeWindow,
  ) {
    final firstPos = history.positions.first;
    final lastPos = history.positions.last;
    final bearing = firstPos.bearingTo(lastPos);

    // Calculate confidence based on track consistency
    double confidence = _calculateCourseConfidence(history);

    return CourseOverGround(
      bearing: bearing,
      confidence: confidence,
      sampleCount: history.positions.length,
      period: timeWindow,
    );
  }

  /// Calculates speed over ground from position history
  SpeedOverGround _calculateSpeedFromHistory(
    PositionHistory history,
    Duration timeWindow,
  ) {
    double speedMs = history.averageSpeed;
    double confidence = _calculateSpeedConfidence(history);

    return SpeedOverGround(
      speedMetersPerSecond: speedMs,
      confidence: confidence,
      sampleCount: history.positions.length,
      period: timeWindow,
    );
  }

  /// Calculates confidence level for course calculations
  double _calculateCourseConfidence(PositionHistory history) {
    double confidence = 0.6; // Higher base confidence for consistent tracks

    // Higher confidence for more positions
    if (history.positions.length >= 3) {
      confidence += 0.15; // 3 points form a good track
    }
    if (history.positions.length >= 5) confidence += 0.1;
    if (history.positions.length >= 10) confidence += 0.1;

    // Higher confidence for longer tracks
    if (history.totalDistance > 50) confidence += 0.05;
    if (history.totalDistance > 100) confidence += 0.05;

    return math.min(confidence, 1.0);
  }

  /// Calculates confidence level for speed calculations
  double _calculateSpeedConfidence(PositionHistory history) {
    double confidence = 0.5; // Base confidence

    // Higher confidence for more positions and longer duration
    if (history.positions.length >= 5) confidence += 0.2;
    if (history.duration.inMinutes >= 2) confidence += 0.2;
    if (history.totalDistance > 50) confidence += 0.1;

    return math.min(confidence, 1.0);
  }

  /// Gets current position with Seattle fallback when location services disabled
  ///
  /// This method attempts to get the real GPS position first, but if location
  /// services are disabled or permission is denied, it returns Seattle coordinates
  /// as a fallback location for chart discovery.
  ///
  /// Seattle coordinates: 47.6062°N, 122.3321°W (Space Needle area)
  ///
  /// Returns:
  /// - Real GPS position if available and permission granted
  /// - Seattle fallback coordinates if location services disabled/denied
  /// - Never returns null (always provides a usable location)
  @override
  Future<GpsPosition?> getCurrentPositionWithFallback() async {
    try {
      _logger.debug('Attempting to get current position with Seattle fallback');

      // First try to get real GPS position
      final realPosition = await getCurrentPosition();
      if (realPosition != null) {
        _logger.debug(
          'Using real GPS position: ${realPosition.latitude}, ${realPosition.longitude}',
        );
        return realPosition;
      }

      // If real position unavailable, use Seattle fallback
      _logger.info(
        'Location services unavailable, using Seattle fallback coordinates',
      );
      return _getSeattleFallbackPosition();
    } catch (e) {
      _logger.warning('Error getting position, using Seattle fallback: $e');
      return _getSeattleFallbackPosition();
    }
  }

  /// Creates a fallback GPS position for Seattle area
  ///
  /// Uses Space Needle coordinates as a central Seattle location
  /// that will discover Pacific Northwest marine charts.
  GpsPosition _getSeattleFallbackPosition() {
    return GpsPosition(
      latitude: 47.6062, // Seattle Space Needle latitude
      longitude: -122.3321, // Seattle Space Needle longitude
      timestamp: DateTime.now(),
      altitude: 56.0, // Approximate Seattle elevation in meters
      accuracy: 1000.0, // Large accuracy radius for fallback
      heading: null, // No heading for fallback position
      speed: null, // No speed for fallback position
    );
  }

  /// Converts geolocator Position to our GpsPosition model
  GpsPosition _convertToGpsPosition(Position position) {
    return GpsPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      altitude: position.altitude,
      accuracy: position.accuracy,
      heading: position.heading >= 0 ? position.heading : null,
      speed: position.speed >= 0 ? position.speed : null,
    );
  }

  /// Checks if position accuracy is suitable for marine navigation
  /// Marine navigation typically requires accuracy better than 10 meters
  bool _isAccurateEnoughForMarine(GpsPosition position) {
    const double maxAccuracyForMarine = 10.0; // meters
    return position.accuracy == null ||
        position.accuracy! <= maxAccuracyForMarine;
  }
}
