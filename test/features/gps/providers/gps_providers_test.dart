import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import '../../../../lib/core/models/gps_position.dart';
import '../../../../lib/core/models/gps_signal_quality.dart';
import '../../../../lib/core/models/position_history.dart';
import '../../../../lib/core/services/gps_service.dart';
import '../../../../lib/core/logging/app_logger.dart';
import '../../../../lib/core/state/providers.dart' show gpsServiceProvider;
import '../../../../lib/features/gps/providers/gps_providers.dart';

import 'gps_providers_test.mocks.dart';

@GenerateMocks([GpsService, AppLogger])
void main() {
  group('GPS Providers Tests', () {
    late MockGpsService mockGpsService;
    late ProviderContainer container;

    setUp(() {
      mockGpsService = MockGpsService();
      container = ProviderContainer(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    group('latestGpsPositionProvider', () {
      test('should return null when no GPS position available', () {
        // Arrange
        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.empty(),
        );

        // Act
        final result = container.read(latestGpsPositionProvider);

        // Assert
        expect(result, isNull);
      });

      test('should return latest GPS position from stream', () async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});

        // Act
        final stream = container.read(gpsLocationStreamProvider.stream);
        await expectLater(stream, emits(testPosition));

        // Assert - position should be available in the provider
        await container.pump();
        final result = container.read(latestGpsPositionProvider);
        expect(result, equals(testPosition));
      });
    });

    group('isGpsTrackingProvider', () {
      test('should return false when GPS stream has error', () {
        // Arrange
        when(mockGpsService.startLocationTracking()).thenThrow(Exception('GPS error'));

        // Act
        final result = container.read(isGpsTrackingProvider);

        // Assert
        expect(result, isFalse);
      });

      test('should return true when GPS stream provides data', () async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});

        // Act
        final stream = container.read(gpsLocationStreamProvider.stream);
        await expectLater(stream, emits(testPosition));

        // Assert
        await container.pump();
        final result = container.read(isGpsTrackingProvider);
        expect(result, isTrue);
      });
    });

    group('isMarineGradeGpsProvider', () {
      test('should return false when signal quality is poor', () async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 25.0, // Poor accuracy
        );

        final poorQuality = GpsSignalQuality.fromAccuracy(25.0);

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => poorQuality,
        );

        // Act
        final positionStream = container.read(gpsLocationStreamProvider.stream);
        await expectLater(positionStream, emits(testPosition));

        await container.pump();
        final result = container.read(isMarineGradeGpsProvider);

        // Assert
        expect(result, isFalse);
      });

      test('should return true when signal quality is marine grade', () async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 5.0, // Good accuracy
        );

        final goodQuality = GpsSignalQuality.fromAccuracy(5.0);

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => goodQuality,
        );

        // Act
        final positionStream = container.read(gpsLocationStreamProvider.stream);
        await expectLater(positionStream, emits(testPosition));

        await container.pump();
        final result = container.read(isMarineGradeGpsProvider);

        // Assert
        expect(result, isTrue);
      });
    });

    group('vesselTrackProvider', () {
      test('should return position history for given time window', () async {
        // Arrange
        const timeWindow = Duration(minutes: 30);
        final testHistory = PositionHistory.fromPositions([
          GpsPosition(
            latitude: 47.6062,
            longitude: -122.3321,
            timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
          GpsPosition(
            latitude: 47.6072,
            longitude: -122.3331,
            timestamp: DateTime.now(),
          ),
        ]);

        when(mockGpsService.getPositionHistory(timeWindow)).thenAnswer(
          (_) async => testHistory,
        );

        // Act
        final result = await container.read(vesselTrackProvider(timeWindow).future);

        // Assert
        expect(result, equals(testHistory));
        expect(result.positions.length, equals(2));
        verify(mockGpsService.getPositionHistory(timeWindow)).called(1);
      });
    });
  });
}