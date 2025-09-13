import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gps_position.dart';
import '../models/gps_signal_quality.dart';
import '../models/position_history.dart';
import '../services/gps_service.dart';
import '../logging/app_logger.dart';
import '../state/providers.dart';

/// State for GPS tracking functionality
class GpsTrackingState {
  final bool isTracking;
  final GpsPosition? currentPosition;
  final List<GpsPosition> trackHistory;
  final GpsSignalQuality? signalQuality;
  final CourseOverGround? courseOverGround;
  final SpeedOverGround? speedOverGround;
  final bool isRecording;
  final DateTime? lastUpdate;
  final String? error;

  const GpsTrackingState({
    this.isTracking = false,
    this.currentPosition,
    this.trackHistory = const [],
    this.signalQuality,
    this.courseOverGround,
    this.speedOverGround,
    this.isRecording = false,
    this.lastUpdate,
    this.error,
  });

  GpsTrackingState copyWith({
    bool? isTracking,
    GpsPosition? currentPosition,
    List<GpsPosition>? trackHistory,
    GpsSignalQuality? signalQuality,
    CourseOverGround? courseOverGround,
    SpeedOverGround? speedOverGround,
    bool? isRecording,
    DateTime? lastUpdate,
    String? error,
  }) {
    return GpsTrackingState(
      isTracking: isTracking ?? this.isTracking,
      currentPosition: currentPosition ?? this.currentPosition,
      trackHistory: trackHistory ?? this.trackHistory,
      signalQuality: signalQuality ?? this.signalQuality,
      courseOverGround: courseOverGround ?? this.courseOverGround,
      speedOverGround: speedOverGround ?? this.speedOverGround,
      isRecording: isRecording ?? this.isRecording,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error,
    );
  }

  /// Whether GPS data is considered fresh (less than 30 seconds old)
  bool get isDataFresh {
    if (lastUpdate == null) return false;
    return DateTime.now().difference(lastUpdate!).inSeconds < 30;
  }

  /// Whether the vessel appears to be moving
  bool get isMoving {
    if (currentPosition?.speed == null) return false;
    return currentPosition!.speed! > 0.5; // Moving if speed > 0.5 m/s
  }
}

/// GPS tracking notifier that manages real-time GPS tracking
class GpsTrackingNotifier extends StateNotifier<GpsTrackingState> {
  final GpsService _gpsService;
  final AppLogger _logger;
  
  StreamSubscription<GpsPosition>? _positionSubscription;
  Timer? _navigationDataTimer;
  
  // Constants for tracking configuration
  static const int _maxTrackHistorySize = 1000;
  static const Duration _navigationDataUpdateInterval = Duration(seconds: 10);

  GpsTrackingNotifier({
    required GpsService gpsService,
    required AppLogger logger,
  })  : _gpsService = gpsService,
        _logger = logger,
        super(const GpsTrackingState());

  /// Starts GPS tracking
  Future<void> startTracking() async {
    if (state.isTracking) {
      _logger.warning('GPS tracking already started');
      return;
    }

    try {
      _logger.info('Starting GPS tracking');
      
      // Check permissions first
      final hasPermission = await _gpsService.checkLocationPermission();
      if (!hasPermission) {
        final granted = await _gpsService.requestLocationPermission();
        if (!granted) {
          state = state.copyWith(
            error: 'Location permission denied',
          );
          return;
        }
      }

      // Check if location services are enabled
      final isEnabled = await _gpsService.isLocationEnabled();
      if (!isEnabled) {
        state = state.copyWith(
          error: 'Location services are disabled',
        );
        return;
      }

      // Start GPS tracking service
      await _gpsService.startLocationTracking();
      
      // Subscribe to position updates
      _positionSubscription = _gpsService.getLocationStream().listen(
        _onPositionUpdate,
        onError: _onPositionError,
      );

      // Start navigation data updates
      _startNavigationDataUpdates();

      state = state.copyWith(
        isTracking: true,
        error: null,
      );

      _logger.info('GPS tracking started successfully');
    } catch (error) {
      _logger.error('Failed to start GPS tracking', exception: error);
      state = state.copyWith(
        error: 'Failed to start GPS tracking: $error',
      );
    }
  }

  /// Stops GPS tracking
  Future<void> stopTracking() async {
    if (!state.isTracking) {
      _logger.warning('GPS tracking not started');
      return;
    }

    try {
      _logger.info('Stopping GPS tracking');

      // Cancel subscriptions
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      
      _navigationDataTimer?.cancel();
      _navigationDataTimer = null;

      // Stop GPS service
      await _gpsService.stopLocationTracking();

      state = state.copyWith(
        isTracking: false,
        error: null,
      );

      _logger.info('GPS tracking stopped successfully');
    } catch (error) {
      _logger.error('Failed to stop GPS tracking', exception: error);
      state = state.copyWith(
        error: 'Failed to stop GPS tracking: $error',
      );
    }
  }

  /// Starts recording GPS track
  Future<void> startRecording() async {
    if (!state.isTracking) {
      await startTracking();
    }

    state = state.copyWith(isRecording: true);
    _logger.info('GPS track recording started');
  }

  /// Stops recording GPS track
  void stopRecording() {
    state = state.copyWith(isRecording: false);
    _logger.info('GPS track recording stopped');
  }

  /// Clears the recorded GPS track
  Future<void> clearTrack() async {
    try {
      await _gpsService.clearPositionHistory();
      state = state.copyWith(trackHistory: []);
      _logger.info('GPS track cleared');
    } catch (error) {
      _logger.error('Failed to clear GPS track', exception: error);
    }
  }

  /// Gets the current GPS position (one-time request)
  Future<GpsPosition?> getCurrentPosition() async {
    try {
      final position = await _gpsService.getCurrentPosition();
      if (position != null) {
        // Update current position in state even if not tracking
        state = state.copyWith(
          currentPosition: position,
          lastUpdate: DateTime.now(),
        );
      }
      return position;
    } catch (error) {
      _logger.error('Failed to get current GPS position', exception: error);
      return null;
    }
  }

  /// Updates GPS settings and restarts tracking if needed
  Future<void> updateTrackingSettings({
    bool? autoStart,
    Duration? updateInterval,
  }) async {
    // Implementation for updating GPS tracking settings
    // This could include changing update frequency, accuracy requirements, etc.
    _logger.debug('Updating GPS tracking settings');
  }

  /// Handles position updates from GPS stream
  void _onPositionUpdate(GpsPosition position) async {
    try {
      _logger.debug('GPS position update: ${position.toCoordinateString()}');

      // Update current position
      state = state.copyWith(
        currentPosition: position,
        lastUpdate: DateTime.now(),
        error: null,
      );

      // Log position if recording
      if (state.isRecording) {
        await _gpsService.logPosition(position);
        
        // Update track history
        final updatedHistory = List<GpsPosition>.from(state.trackHistory)
          ..add(position);
        
        // Limit history size for performance
        if (updatedHistory.length > _maxTrackHistorySize) {
          updatedHistory.removeAt(0);
        }
        
        state = state.copyWith(trackHistory: updatedHistory);
      }

      // Update signal quality
      _updateSignalQuality(position);
    } catch (error) {
      _logger.error('Error handling GPS position update', exception: error);
    }
  }

  /// Handles GPS position errors
  void _onPositionError(dynamic error) {
    _logger.error('GPS position stream error', exception: error);
    state = state.copyWith(
      error: 'GPS position error: $error',
    );
  }

  /// Updates signal quality assessment
  void _updateSignalQuality(GpsPosition position) async {
    try {
      final quality = await _gpsService.assessSignalQuality(position);
      state = state.copyWith(signalQuality: quality);
    } catch (error) {
      _logger.error('Failed to assess GPS signal quality', exception: error);
    }
  }

  /// Starts periodic navigation data updates
  void _startNavigationDataUpdates() {
    _navigationDataTimer = Timer.periodic(
      _navigationDataUpdateInterval,
      (_) => _updateNavigationData(),
    );
  }

  /// Updates course over ground and speed over ground
  void _updateNavigationData() async {
    try {
      const timeWindow = Duration(minutes: 2);
      
      final cogFuture = _gpsService.calculateCourseOverGround(timeWindow);
      final sogFuture = _gpsService.calculateSpeedOverGround(timeWindow);
      
      final results = await Future.wait([cogFuture, sogFuture]);
      final cog = results[0] as CourseOverGround?;
      final sog = results[1] as SpeedOverGround?;
      
      state = state.copyWith(
        courseOverGround: cog,
        speedOverGround: sog,
      );
    } catch (error) {
      _logger.error('Failed to update navigation data', exception: error);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _navigationDataTimer?.cancel();
    super.dispose();
  }
}

/// Provider for GPS tracking functionality
final gpsTrackingProvider = StateNotifierProvider<GpsTrackingNotifier, GpsTrackingState>((ref) {
  final gpsService = ref.read(gpsServiceProvider);
  final logger = ref.read(loggerProvider);
  
  return GpsTrackingNotifier(
    gpsService: gpsService,
    logger: logger,
  );
});

/// Providers for specific GPS tracking data
final currentGpsPositionProvider = Provider<GpsPosition?>((ref) {
  return ref.watch(gpsTrackingProvider).currentPosition;
});

final gpsTrackHistoryProvider = Provider<List<GpsPosition>>((ref) {
  return ref.watch(gpsTrackingProvider).trackHistory;
});

final gpsSignalQualityProvider = Provider<GpsSignalQuality?>((ref) {
  return ref.watch(gpsTrackingProvider).signalQuality;
});

final courseOverGroundProvider = Provider<CourseOverGround?>((ref) {
  return ref.watch(gpsTrackingProvider).courseOverGround;
});

final speedOverGroundProvider = Provider<SpeedOverGround?>((ref) {
  return ref.watch(gpsTrackingProvider).speedOverGround;
});

final isGpsTrackingProvider = Provider<bool>((ref) {
  return ref.watch(gpsTrackingProvider).isTracking;
});

final isGpsRecordingProvider = Provider<bool>((ref) {
  return ref.watch(gpsTrackingProvider).isRecording;
});

final gpsDataFreshnessProvider = Provider<bool>((ref) {
  return ref.watch(gpsTrackingProvider).isDataFresh;
});

final isVesselMovingProvider = Provider<bool>((ref) {
  return ref.watch(gpsTrackingProvider).isMoving;
});

/// Stream provider for real-time GPS position updates
final gpsPositionStreamProvider = StreamProvider<GpsPosition?>((ref) async* {
  final trackingNotifier = ref.read(gpsTrackingProvider.notifier);
  
  // Start tracking automatically when this stream is watched
  await trackingNotifier.startTracking();
  
  // Yield position updates from the tracking state
  ref.listen(gpsTrackingProvider.select((state) => state.currentPosition), (previous, next) {
    // Stream will update when currentPosition changes
  });
  
  yield ref.read(gpsTrackingProvider).currentPosition;
});

/// Provider for GPS statistics
final gpsStatisticsProvider = FutureProvider<AccuracyStatistics?>((ref) async {
  final gpsService = ref.read(gpsServiceProvider);
  try {
    return await gpsService.getAccuracyStatistics(const Duration(hours: 1));
  } catch (error) {
    ref.read(loggerProvider).error('Failed to get GPS statistics', exception: error);
    return null;
  }
});

/// Provider for vessel movement state
final vesselMovementStateProvider = FutureProvider<MovementState?>((ref) async {
  final gpsService = ref.read(gpsServiceProvider);
  try {
    return await gpsService.getMovementState(const Duration(minutes: 5));
  } catch (error) {
    ref.read(loggerProvider).error('Failed to get movement state', exception: error);
    return null;
  }
});