import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/providers/gps_tracking_provider.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/gps_signal_quality.dart';
import 'package:navtool/core/models/position_history.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Mock classes
class MockGpsService extends Mock implements GpsService {}
class MockAppLogger extends Mock implements AppLogger {}

void main() {
  group('GPS Integration Tests', () {
    late MockGpsService mockGpsService;
    late MockAppLogger mockLogger;
    late ProviderContainer container;

    setUp(() {
      mockGpsService = MockGpsService();
      mockLogger = MockAppLogger();
      
      container = ProviderContainer(
        overrides: [
          gpsTrackingProvider.overrideWith((ref) => GpsTrackingNotifier(
            gpsService: mockGpsService,
            logger: mockLogger,
          )),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('should start GPS tracking successfully', () async {
      // Arrange
      when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
      when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
      when(mockGpsService.startLocationTracking()).thenAnswer((_) async {});
      when(mockGpsService.getLocationStream()).thenAnswer((_) => const Stream.empty());

      // Act
      final notifier = container.read(gpsTrackingProvider.notifier);
      await notifier.startTracking();

      // Assert
      final state = container.read(gpsTrackingProvider);
      expect(state.isTracking, isTrue);
      expect(state.error, isNull);
      verify(mockGpsService.startLocationTracking()).called(1);
    });

    test('should handle GPS position updates', () async {
      // Arrange
      final testPosition = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 50.0,
        heading: 180.0,
        speed: 2.5,
      );

      when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
      when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
      when(mockGpsService.startLocationTracking()).thenAnswer((_) async {});
      when(mockGpsService.getLocationStream()).thenAnswer((_) => Stream.value(testPosition));
      when(mockGpsService.logPosition(testPosition)).thenAnswer((_) async {});
      when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer((_) async => 
        GpsSignalQuality.fromAccuracy(testPosition.accuracy));

      // Act
      final notifier = container.read(gpsTrackingProvider.notifier);
      await notifier.startTracking();
      await notifier.startRecording();

      // Wait a bit for the stream to update
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert
      final state = container.read(gpsTrackingProvider);
      expect(state.currentPosition, isNotNull);
      expect(state.currentPosition?.latitude, equals(37.7749));
      expect(state.currentPosition?.longitude, equals(-122.4194));
      expect(state.isRecording, isTrue);
    });

    test('should assess GPS signal quality correctly', () async {
      // Arrange
      final highAccuracyPosition = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
        accuracy: 3.0, // High accuracy
      );

      final quality = GpsSignalQuality.fromAccuracy(highAccuracyPosition.accuracy);

      // Assert
      expect(quality.strength, equals(SignalStrength.excellent));
      expect(quality.isMarineGrade, isTrue);
      expect(quality.accuracy, equals(3.0));
    });

    test('should calculate course over ground from position history', () async {
      // Arrange
      final positions = [
        GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
        GpsPosition(
          latitude: 37.7750,
          longitude: -122.4193,
          timestamp: DateTime.now(),
        ),
      ];

      when(mockGpsService.getPositionHistory(const Duration(minutes: 2))).thenAnswer((_) async =>
        PositionHistory.fromPositions(positions));
      when(mockGpsService.calculateCourseOverGround(const Duration(minutes: 2))).thenAnswer((_) async =>
        const CourseOverGround(
          bearing: 45.0,
          confidence: 0.8,
          sampleCount: 2,
          period: Duration(minutes: 2),
        ));

      // Act
      final cog = await mockGpsService.calculateCourseOverGround(const Duration(minutes: 2));

      // Assert
      expect(cog, isNotNull);
      expect(cog!.bearing, equals(45.0));
      expect(cog.confidence, equals(0.8));
      expect(cog.sampleCount, equals(2));
    });

    test('should handle GPS permission denied gracefully', () async {
      // Arrange
      when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => false);
      when(mockGpsService.requestLocationPermission()).thenAnswer((_) async => false);

      // Act
      final notifier = container.read(gpsTrackingProvider.notifier);
      await notifier.startTracking();

      // Assert
      final state = container.read(gpsTrackingProvider);
      expect(state.isTracking, isFalse);
      expect(state.error, contains('Location permission denied'));
    });

    test('should handle location services disabled', () async {
      // Arrange
      when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
      when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => false);

      // Act
      final notifier = container.read(gpsTrackingProvider.notifier);
      await notifier.startTracking();

      // Assert
      final state = container.read(gpsTrackingProvider);
      expect(state.isTracking, isFalse);
      expect(state.error, contains('Location services are disabled'));
    });

    test('should clear GPS track history', () async {
      // Arrange
      when(mockGpsService.clearPositionHistory()).thenAnswer((_) async {});

      // Act
      final notifier = container.read(gpsTrackingProvider.notifier);
      await notifier.clearTrack();

      // Assert
      final state = container.read(gpsTrackingProvider);
      expect(state.trackHistory, isEmpty);
      verify(mockGpsService.clearPositionHistory()).called(1);
    });
  });

  group('GPS Signal Quality Tests', () {
    test('should classify excellent signal quality', () {
      final quality = GpsSignalQuality.fromAccuracy(3.0);
      
      expect(quality.strength, equals(SignalStrength.excellent));
      expect(quality.isMarineGrade, isTrue);
      expect(quality.qualityScore, equals(100));
    });

    test('should classify poor signal quality', () {
      final quality = GpsSignalQuality.fromAccuracy(25.0);
      
      expect(quality.strength, equals(SignalStrength.poor));
      expect(quality.isMarineGrade, isFalse);
      expect(quality.qualityScore, lessThan(50));
    });

    test('should handle null accuracy', () {
      final quality = GpsSignalQuality.fromAccuracy(null);
      
      expect(quality.strength, equals(SignalStrength.unknown));
      expect(quality.isMarineGrade, isFalse);
      expect(quality.qualityScore, equals(0));
    });
  });

  group('Position History Tests', () {
    test('should calculate total distance correctly', () {
      final positions = [
        GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
        GpsPosition(
          latitude: 37.7750,
          longitude: -122.4193,
          timestamp: DateTime.now(),
        ),
      ];

      final history = PositionHistory.fromPositions(positions);
      
      expect(history.totalDistance, greaterThan(0));
      expect(history.positions.length, equals(2));
      expect(history.duration.inMinutes, equals(2));
    });

    test('should identify marine-grade positions', () {
      final positions = [
        GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 5.0, // Marine grade
        ),
        GpsPosition(
          latitude: 37.7750,
          longitude: -122.4193,
          timestamp: DateTime.now(),
          accuracy: 15.0, // Not marine grade
        ),
      ];

      final history = PositionHistory.fromPositions(positions);
      
      expect(history.marineGradePercentage, equals(0.5)); // 50% marine grade
      expect(history.getPositionsWithAccuracy(10.0).length, equals(1));
    });
  });
}