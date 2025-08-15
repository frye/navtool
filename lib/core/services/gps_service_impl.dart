import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/gps_position.dart';
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
class GpsServiceImpl implements GpsService {
  final AppLogger _logger;
  StreamSubscription<Position>? _positionSubscription;
  StreamController<GpsPosition>? _locationController;

  // Marine navigation requires high accuracy settings
  static const LocationSettings _marineLocationSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 1, // Update every meter for marine navigation
  /// The minimum distance (in meters) the device must move horizontally before
  /// an update is generated. Set to 1 meter for marine navigation to ensure
  /// high-resolution tracking of vessel movement.
  static const int kMarineDistanceFilterMeters = 1;

  /// The maximum duration (in seconds) to wait for a location update.
  /// Set to 30 seconds as a suitable timeout for marine conditions, balancing
  /// responsiveness and battery usage in open water environments.
  static const int kMarineLocationTimeoutSeconds = 30;

  // Marine navigation requires high accuracy settings
  static const LocationSettings _marineLocationSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: kMarineDistanceFilterMeters,
    timeLimit: Duration(seconds: kMarineLocationTimeoutSeconds),
  );

  GpsServiceImpl({required AppLogger logger}) : _logger = logger;

  @override
  Future<bool> requestLocationPermission() async {
    try {
      _logger.debug('Requesting location permission');
      
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      final granted = permission == LocationPermission.whileInUse || 
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
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.whileInUse || 
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
      final enabled = await Geolocator.isLocationServiceEnabled();
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
      _logger.debug('Getting current GPS position with marine accuracy settings');
      
      // Check permissions and services first
      if (!await isLocationEnabled()) {
        _logger.warning('Location services are disabled');
        return null;
      }
      
      if (!await checkLocationPermission()) {
        _logger.warning('Location permission not granted');
        return null;
      }
      
      final position = await Geolocator.getCurrentPosition(
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
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _marineLocationSettings,
      ).listen(
        (Position position) {
          final gpsPosition = _convertToGpsPosition(position);
          
          // Filter out positions with poor accuracy for marine navigation
          if (_isAccurateEnoughForMarine(gpsPosition)) {
            _locationController?.add(gpsPosition);
            _logger.debug('GPS position update: ${gpsPosition.toCoordinateString()}');
          } else {
            _logger.warning('Filtered out inaccurate GPS position: accuracy=${gpsPosition.accuracy}m');
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
      throw StateError('Location tracking not started. Call startLocationTracking() first.');
    }
    
    return _locationController!.stream;
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
    return position.accuracy == null || position.accuracy! <= maxAccuracyForMarine;
  }
}
