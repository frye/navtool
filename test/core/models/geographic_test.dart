import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/gps_position.dart';

void main() {
  group('GeographicBounds Tests', () {
    test('GeographicBounds should be created with valid coordinates', () {
      // Arrange & Act
      final bounds = GeographicBounds(
        north: 37.8,
        south: 37.6,
        east: -122.3,
        west: -122.5,
      );

      // Assert
      expect(bounds.north, equals(37.8));
      expect(bounds.south, equals(37.6));
      expect(bounds.east, equals(-122.3));
      expect(bounds.west, equals(-122.5));
    });

    test('GeographicBounds should validate north > south', () {
      // Arrange & Act & Assert
      expect(
        () => GeographicBounds(
          north: 37.6,
          south: 37.8, // Invalid: south > north
          east: -122.3,
          west: -122.5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GeographicBounds should validate east > west', () {
      // Arrange & Act & Assert
      expect(
        () => GeographicBounds(
          north: 37.8,
          south: 37.6,
          east: -122.5, // Invalid: east < west
          west: -122.3,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GeographicBounds should validate latitude range', () {
      // Arrange & Act & Assert
      expect(
        () => GeographicBounds(
          north: 91.0, // Invalid: > 90
          south: 37.6,
          east: -122.3,
          west: -122.5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GeographicBounds should validate longitude range', () {
      // Arrange & Act & Assert
      expect(
        () => GeographicBounds(
          north: 37.8,
          south: 37.6,
          east: 181.0, // Invalid: > 180
          west: -122.5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GeographicBounds should calculate center correctly', () {
      // Arrange
      final bounds = GeographicBounds(
        north: 38.0,
        south: 37.0,
        east: -122.0,
        west: -123.0,
      );

      // Act
      final center = bounds.center;

      // Assert
      expect(center.latitude, equals(37.5));
      expect(center.longitude, equals(-122.5));
    });

    test('GeographicBounds should detect if contains position', () {
      // Arrange
      final bounds = GeographicBounds(
        north: 38.0,
        south: 37.0,
        east: -122.0,
        west: -123.0,
      );
      
      final insidePosition = GpsPosition(
        latitude: 37.5,
        longitude: -122.5,
        timestamp: DateTime.now(),
      );
      
      final outsidePosition = GpsPosition(
        latitude: 39.0,
        longitude: -122.5,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(bounds.contains(insidePosition), isTrue);
      expect(bounds.contains(outsidePosition), isFalse);
    });

    test('GeographicBounds should calculate area correctly', () {
      // Arrange
      final bounds = GeographicBounds(
        north: 38.0,
        south: 37.0,
        east: -122.0,
        west: -123.0,
      );

      // Act
      final area = bounds.area;

      // Assert
      expect(area, greaterThan(0));
      expect(area, equals(1.0)); // 1 degree lat * 1 degree lon
    });
  });

  group('GpsPosition Tests', () {
    test('GpsPosition should be created with valid data', () {
      // Arrange
      const latitude = 37.7749;
      const longitude = -122.4194;
      final timestamp = DateTime(2024, 8, 1, 12, 0, 0);

      // Act
      final position = GpsPosition(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        altitude: 10.0,
        accuracy: 5.0,
        heading: 45.0,
        speed: 2.5,
      );

      // Assert
      expect(position.latitude, equals(latitude));
      expect(position.longitude, equals(longitude));
      expect(position.timestamp, equals(timestamp));
      expect(position.altitude, equals(10.0));
      expect(position.accuracy, equals(5.0));
      expect(position.heading, equals(45.0));
      expect(position.speed, equals(2.5));
    });

    test('GpsPosition should validate latitude range', () {
      // Arrange & Act & Assert
      expect(
        () => GpsPosition(
          latitude: 91.0, // Invalid: > 90
          longitude: -122.4194,
          timestamp: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GpsPosition should validate longitude range', () {
      // Arrange & Act & Assert
      expect(
        () => GpsPosition(
          latitude: 37.7749,
          longitude: 181.0, // Invalid: > 180
          timestamp: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GpsPosition should validate heading range', () {
      // Arrange & Act & Assert
      expect(
        () => GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          heading: 361.0, // Invalid: > 360
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('GpsPosition should calculate distance to another position', () {
      // Arrange
      final position1 = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
      );
      
      final position2 = GpsPosition(
        latitude: 37.7849, // ~1.1km north
        longitude: -122.4194,
        timestamp: DateTime.now(),
      );

      // Act
      final distance = position1.distanceTo(position2);

      // Assert
      expect(distance, greaterThan(1000)); // ~1100 meters
      expect(distance, lessThan(1200));
    });

    test('GpsPosition should calculate bearing to another position', () {
      // Arrange
      final position1 = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
      );
      
      final position2 = GpsPosition(
        latitude: 37.7849, // Due north
        longitude: -122.4194,
        timestamp: DateTime.now(),
      );

      // Act
      final bearing = position1.bearingTo(position2);

      // Assert
      expect(bearing, closeTo(0.0, 1.0)); // Should be close to 0 degrees (north)
    });

    test('GpsPosition equality should work correctly', () {
      // Arrange
      final timestamp = DateTime(2024, 8, 1, 12, 0, 0);
      final position1 = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: timestamp,
      );
      
      final position2 = GpsPosition(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: timestamp,
      );

      // Act & Assert
      expect(position1, equals(position2));
      expect(position1.hashCode, equals(position2.hashCode));
    });
  });
}
