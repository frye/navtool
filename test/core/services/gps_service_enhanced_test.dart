import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/services/gps_service_impl.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/gps_signal_quality.dart';
import 'package:navtool/core/models/position_history.dart';
import 'package:navtool/core/logging/app_logger.dart';

// Use existing test utilities
class MockAppLogger extends Mock implements AppLogger {}

/// Comprehensive tests for enhanced GPS service functionality
/// Tests signal quality monitoring, position history, and enhanced marine navigation features
void main() {
  group('Enhanced GPS Service Tests', () {
    late GpsService gpsService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      gpsService = GpsServiceImpl(logger: mockLogger);
    });

    group('Signal Quality Monitoring', () {
      test('should assess GPS signal quality from position data', () async {
        // Arrange
        final highQualityPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 3.0, // High accuracy
          altitude: 50.0,
        );

        // Act
        final signalQuality = await gpsService.assessSignalQuality(
          highQualityPosition,
        );

        // Assert
        expect(signalQuality, isA<GpsSignalQuality>());
        expect(signalQuality.strength, equals(SignalStrength.excellent));
        expect(signalQuality.accuracy, equals(3.0));
        expect(signalQuality.isMarineGrade, isTrue);
      });

      test('should identify poor signal quality conditions', () async {
        // Arrange
        final poorQualityPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 25.0, // Poor accuracy for marine use
          altitude: 50.0,
        );

        // Act
        final signalQuality = await gpsService.assessSignalQuality(
          poorQualityPosition,
        );

        // Assert
        expect(signalQuality.strength, equals(SignalStrength.poor));
        expect(signalQuality.accuracy, equals(25.0));
        expect(signalQuality.isMarineGrade, isFalse);
        expect(signalQuality.recommendedAction, contains('better location'));
      });

      test('should provide signal quality recommendations', () async {
        // Arrange
        final moderateQualityPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 8.0, // Moderate accuracy
          altitude: 50.0,
        );

        // Act
        final signalQuality = await gpsService.assessSignalQuality(
          moderateQualityPosition,
        );

        // Assert
        expect(signalQuality.strength, equals(SignalStrength.good));
        expect(
          signalQuality.isMarineGrade,
          isTrue,
        ); // Still acceptable for marine use
        expect(signalQuality.recommendedAction, isNotNull);
      });

      test('should track signal quality over time', () async {
        // Arrange
        final positions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: DateTime.now().subtract(Duration(minutes: 2)),
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7750,
            longitude: -122.4195,
            timestamp: DateTime.now().subtract(Duration(minutes: 1)),
            accuracy: 15.0,
          ),
          GpsPosition(
            latitude: 37.7751,
            longitude: -122.4196,
            timestamp: DateTime.now(),
            accuracy: 8.0,
          ),
        ];

        // Act
        for (final position in positions) {
          await gpsService.logPosition(position);
        }
        final qualityTrend = await gpsService.getSignalQualityTrend(
          Duration(minutes: 5),
        );

        // Assert
        expect(qualityTrend, hasLength(3));
        expect(qualityTrend.first.accuracy, equals(5.0));
        expect(qualityTrend.last.accuracy, equals(8.0));
      });
    });

    group('Position History and Logging', () {
      test('should log GPS positions with timestamp', () async {
        // Arrange
        final position = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          speed: 2.5,
          heading: 45.0,
        );

        // Act
        await gpsService.logPosition(position);
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(history, isA<PositionHistory>());
        expect(history.positions, hasLength(1));
        expect(history.positions.first, equals(position));
        expect(history.totalDistance, equals(0.0)); // Single position
      });

      test('should calculate track distance from position history', () async {
        // Arrange
        final startTime = DateTime.now().subtract(Duration(minutes: 3));
        final positions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: startTime,
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7759,
            longitude: -122.4194,
            timestamp: startTime.add(Duration(minutes: 1)),
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7769,
            longitude: -122.4194,
            timestamp: startTime.add(Duration(minutes: 2)),
            accuracy: 5.0,
          ),
        ];

        // Act
        for (final position in positions) {
          await gpsService.logPosition(position);
        }
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(history.positions, hasLength(3));
        expect(history.totalDistance, greaterThan(0.0));
        expect(history.averageSpeed, greaterThan(0.0));
        expect(history.duration, equals(Duration(minutes: 2)));
      });

      test('should calculate average speed from position history', () async {
        // Arrange
        final startTime = DateTime.now().subtract(Duration(minutes: 2));
        final positions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: startTime,
            speed: 0.0,
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7759,
            longitude: -122.4194,
            timestamp: startTime.add(Duration(minutes: 1)),
            speed: 2.0,
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7769,
            longitude: -122.4194,
            timestamp: startTime.add(Duration(minutes: 2)),
            speed: 3.0,
            accuracy: 5.0,
          ),
        ];

        // Act
        for (final position in positions) {
          await gpsService.logPosition(position);
        }
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(
          history.averageSpeed,
          closeTo(1.67, 0.1),
        ); // (0 + 2 + 3) / 3 ≈ 1.67
        expect(history.maxSpeed, equals(3.0));
        expect(history.minSpeed, equals(0.0));
      });

      test('should limit position history by time window', () async {
        // Arrange
        final now = DateTime.now();
        final oldPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: now.subtract(
            Duration(hours: 1),
          ), // Outside 5-minute window
          accuracy: 5.0,
        );
        final recentPosition = GpsPosition(
          latitude: 37.7759,
          longitude: -122.4204,
          timestamp: now.subtract(
            Duration(minutes: 2),
          ), // Within 5-minute window
          accuracy: 5.0,
        );

        // Act
        await gpsService.logPosition(oldPosition);
        await gpsService.logPosition(recentPosition);
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(history.positions, hasLength(1));
        expect(history.positions.first, equals(recentPosition));
      });

      test('should clear position history when requested', () async {
        // Arrange
        final position = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 5.0,
        );
        await gpsService.logPosition(position);

        // Act
        await gpsService.clearPositionHistory();
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(history.positions, isEmpty);
        expect(history.totalDistance, equals(0.0));
      });
    });

    group('Enhanced Real-time Tracking', () {
      test('should provide position accuracy statistics', () async {
        // Arrange - Don't start tracking in test environment
        // Simulate several position updates with varying accuracy
        final positions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: DateTime.now(),
            accuracy: 3.0,
          ),
          GpsPosition(
            latitude: 37.7750,
            longitude: -122.4195,
            timestamp: DateTime.now(),
            accuracy: 5.0,
          ),
          GpsPosition(
            latitude: 37.7751,
            longitude: -122.4196,
            timestamp: DateTime.now(),
            accuracy: 2.0,
          ),
          GpsPosition(
            latitude: 37.7752,
            longitude: -122.4197,
            timestamp: DateTime.now(),
            accuracy: 8.0,
          ),
        ];

        for (final position in positions) {
          await gpsService.logPosition(position);
        }

        // Act
        final stats = await gpsService.getAccuracyStatistics(
          Duration(minutes: 5),
        );

        // Assert
        expect(stats.averageAccuracy, closeTo(4.5, 0.1)); // (3+5+2+8)/4 = 4.5
        expect(stats.bestAccuracy, equals(2.0));
        expect(stats.worstAccuracy, equals(8.0));
        expect(
          stats.marineGradePercentage,
          greaterThan(0.5),
        ); // Most positions should be marine-grade
      });

      test('should detect stationary vs moving states', () async {
        // Arrange
        final baseTime = DateTime.now();
        final stationaryPositions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: baseTime,
            accuracy: 3.0,
            speed: 0.1,
          ),
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: baseTime.add(Duration(seconds: 30)),
            accuracy: 3.0,
            speed: 0.2,
          ),
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: baseTime.add(Duration(minutes: 1)),
            accuracy: 3.0,
            speed: 0.1,
          ),
        ];

        // Act
        for (final position in stationaryPositions) {
          await gpsService.logPosition(position);
        }
        final movementState = await gpsService.getMovementState(
          Duration(minutes: 2),
        );

        // Assert
        expect(movementState.isStationary, isTrue);
        expect(
          movementState.averageSpeed,
          lessThan(0.5),
        ); // Less than 0.5 m/s indicates stationary
        expect(
          movementState.stationaryDuration,
          greaterThan(Duration(seconds: 30)),
        );
      });

      test('should provide position freshness information', () async {
        // Arrange
        final oldPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now().subtract(Duration(minutes: 2)),
          accuracy: 5.0,
        );

        await gpsService.logPosition(oldPosition);

        // Act
        final freshness = await gpsService.getPositionFreshness();

        // Assert
        expect(freshness.lastUpdateAge, greaterThan(Duration(minutes: 1)));
        expect(freshness.isFresh, isFalse); // > 30 seconds old
        expect(
          freshness.stalenessLevel,
          equals(StalenessLevel.recent),
        ); // 2 minutes = recent, not stale
      });
    });

    group('Marine-Specific Features', () {
      test('should filter positions for marine navigation accuracy', () async {
        // Arrange
        final positions = [
          GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: DateTime.now(),
            accuracy: 3.0,
          ), // Good
          GpsPosition(
            latitude: 37.7750,
            longitude: -122.4195,
            timestamp: DateTime.now(),
            accuracy: 25.0,
          ), // Poor
          GpsPosition(
            latitude: 37.7751,
            longitude: -122.4196,
            timestamp: DateTime.now(),
            accuracy: 8.0,
          ), // Acceptable
          GpsPosition(
            latitude: 37.7752,
            longitude: -122.4197,
            timestamp: DateTime.now(),
            accuracy: 50.0,
          ), // Unacceptable
        ];

        // Act
        final filteredPositions = await gpsService.filterForMarineAccuracy(
          positions,
        );

        // Assert
        expect(
          filteredPositions,
          hasLength(2),
        ); // Only positions with ≤ 10m accuracy
        expect(filteredPositions[0].accuracy, equals(3.0));
        expect(filteredPositions[1].accuracy, equals(8.0));
      });

      test(
        'should calculate course over ground (COG) from position history',
        () async {
          // Arrange
          final baseTime = DateTime.now();
          final positions = [
            GpsPosition(
              latitude: 37.7749,
              longitude: -122.4194,
              timestamp: baseTime,
              accuracy: 3.0,
            ),
            GpsPosition(
              latitude: 37.7759,
              longitude: -122.4194,
              timestamp: baseTime.add(Duration(minutes: 1)),
              accuracy: 3.0,
            ), // Due north
            GpsPosition(
              latitude: 37.7769,
              longitude: -122.4194,
              timestamp: baseTime.add(Duration(minutes: 2)),
              accuracy: 3.0,
            ), // Due north
          ];

          // Act
          for (final position in positions) {
            await gpsService.logPosition(position);
          }
          final cog = await gpsService.calculateCourseOverGround(
            Duration(minutes: 3),
          );

          // Assert
          expect(cog, isNotNull);
          expect(
            cog!.bearing,
            closeTo(0.0, 5.0),
          ); // Should be close to 0° (north)
          expect(
            cog.confidence,
            greaterThan(0.8),
          ); // High confidence with consistent track
        },
      );

      test(
        'should calculate speed over ground (SOG) from position history',
        () async {
          // Arrange
          final baseTime = DateTime.now();
          final distance = 100.0; // meters
          final timeInterval = Duration(minutes: 1);

          // Calculate second position that's ~100m north
          final lat1 = 37.7749;
          final lon1 = -122.4194;
          final lat2 =
              lat1 + (distance / 111000); // Rough conversion: 1° ≈ 111km

          final positions = [
            GpsPosition(
              latitude: lat1,
              longitude: lon1,
              timestamp: baseTime,
              accuracy: 3.0,
            ),
            GpsPosition(
              latitude: lat2,
              longitude: lon1,
              timestamp: baseTime.add(timeInterval),
              accuracy: 3.0,
            ),
          ];

          // Act
          for (final position in positions) {
            await gpsService.logPosition(position);
          }
          final sog = await gpsService.calculateSpeedOverGround(
            Duration(minutes: 2),
          );

          // Assert
          expect(sog, isNotNull);
          expect(
            sog!.speedMetersPerSecond,
            closeTo(distance / timeInterval.inSeconds, 0.5),
          );
          expect(
            sog.speedKnots,
            closeTo(sog.speedMetersPerSecond * 1.944, 0.1),
          ); // m/s to knots conversion
        },
      );
    });

    group('Error Handling and Edge Cases', () {
      test('should handle null positions gracefully', () async {
        // Act & Assert
        expect(
          () async => await gpsService.assessSignalQuality(null),
          throwsArgumentError,
        );
      });

      test('should handle empty position history requests', () async {
        // Act
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(history.positions, isEmpty);
        expect(history.totalDistance, equals(0.0));
        expect(history.duration, equals(Duration.zero));
      });

      test('should handle positions with missing accuracy data', () async {
        // Arrange
        final positionWithoutAccuracy = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          // accuracy: null - missing accuracy data
        );

        // Act
        final signalQuality = await gpsService.assessSignalQuality(
          positionWithoutAccuracy,
        );

        // Assert
        expect(signalQuality.strength, equals(SignalStrength.unknown));
        expect(signalQuality.isMarineGrade, isFalse);
        expect(signalQuality.recommendedAction, contains('unavailable'));
      });

      test('should handle very old position data', () async {
        // Arrange
        final veryOldPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now().subtract(Duration(days: 1)),
          accuracy: 5.0,
        );

        // Act
        await gpsService.logPosition(veryOldPosition);
        final history = await gpsService.getPositionHistory(
          Duration(minutes: 5),
        );

        // Assert
        expect(
          history.positions,
          isEmpty,
        ); // Should be filtered out by time window
      });
    });
  });
}
