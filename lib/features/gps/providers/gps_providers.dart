import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/gps_position.dart';
import '../../../core/models/gps_signal_quality.dart';
import '../../../core/models/position_history.dart';
import '../../../core/state/providers.dart' show gpsServiceProvider;

/// Provider for real-time GPS position stream
final gpsLocationStreamProvider = StreamProvider<GpsPosition>((ref) async* {
  final gpsService = ref.read(gpsServiceProvider);
  
  try {
    // Start location tracking if not already started
    await gpsService.startLocationTracking();
    
    // Yield positions from the GPS service stream
    await for (final position in gpsService.getLocationStream()) {
      // Log position for history tracking
      await gpsService.logPosition(position);
      yield position;
    }
  } catch (error) {
    // If streaming fails, try to get current position as fallback
    final position = await gpsService.getCurrentPosition();
    if (position != null) {
      yield position;
    }
  }
});

/// Provider for current GPS signal quality
final gpsSignalQualityProvider = StreamProvider<GpsSignalQuality>((ref) async* {
  final gpsService = ref.read(gpsServiceProvider);
  
  // Listen to position stream and assess signal quality
  await for (final position in ref.watch(gpsLocationStreamProvider.stream)) {
    if (position != null) {
      final quality = await gpsService.assessSignalQuality(position);
      yield quality;
    }
  }
});

/// Provider for vessel position history (track)
final vesselTrackProvider = FutureProvider.family<PositionHistory, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getPositionHistory(timeWindow);
});

/// Provider for course over ground
final courseOverGroundProvider = FutureProvider.family<CourseOverGround?, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.calculateCourseOverGround(timeWindow);
});

/// Provider for speed over ground
final speedOverGroundProvider = FutureProvider.family<SpeedOverGround?, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.calculateSpeedOverGround(timeWindow);
});

/// Provider for GPS accuracy statistics
final gpsAccuracyStatsProvider = FutureProvider.family<AccuracyStatistics, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getAccuracyStatistics(timeWindow);
});

/// Provider for movement state (stationary vs moving)
final movementStateProvider = FutureProvider.family<MovementState, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getMovementState(timeWindow);
});

/// Provider for position freshness
final positionFreshnessProvider = FutureProvider<PositionFreshness>((ref) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getPositionFreshness();
});

/// Provider for signal quality trend over time
final signalQualityTrendProvider = FutureProvider.family<List<GpsSignalQuality>, Duration>((ref, timeWindow) async {
  final gpsService = ref.read(gpsServiceProvider);
  return await gpsService.getSignalQualityTrend(timeWindow);
});

/// Provider that checks if GPS is actively tracking
final isGpsTrackingProvider = Provider<bool>((ref) {
  return ref.watch(gpsLocationStreamProvider).when(
    data: (_) => true,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// Provider for latest GPS position (from stream)
final latestGpsPositionProvider = Provider<GpsPosition?>((ref) {
  return ref.watch(gpsLocationStreamProvider).when(
    data: (position) => position,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Provider for current GPS signal strength
final currentSignalStrengthProvider = Provider<SignalStrength>((ref) {
  return ref.watch(gpsSignalQualityProvider).when(
    data: (quality) => quality.strength,
    loading: () => SignalStrength.unknown,
    error: (_, __) => SignalStrength.unknown,
  );
});

/// Provider that determines if GPS signal is suitable for marine navigation
final isMarineGradeGpsProvider = Provider<bool>((ref) {
  return ref.watch(gpsSignalQualityProvider).when(
    data: (quality) => quality.isMarineGrade,
    loading: () => false,
    error: (_, __) => false,
  );
});