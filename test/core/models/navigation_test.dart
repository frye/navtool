import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/gps_position.dart';

void main() {
  group('Waypoint Tests', () {
    test('Waypoint should be created with valid data', () {
      // Arrange
      const id = 'wp001';
      const name = 'Golden Gate Bridge';
      const latitude = 37.8199;
      const longitude = -122.4783;
      const description = 'Famous bridge landmark';

      // Act
      final waypoint = Waypoint(
        id: id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        description: description,
        type: WaypointType.landmark,
      );

      // Assert
      expect(waypoint.id, equals(id));
      expect(waypoint.name, equals(name));
      expect(waypoint.latitude, equals(latitude));
      expect(waypoint.longitude, equals(longitude));
      expect(waypoint.description, equals(description));
      expect(waypoint.type, equals(WaypointType.landmark));
      expect(waypoint.createdAt, isA<DateTime>());
    });

    test('Waypoint should validate latitude range', () {
      // Arrange & Act & Assert
      expect(
        () => Waypoint(
          id: 'wp001',
          name: 'Test',
          latitude: 91.0, // Invalid: > 90
          longitude: -122.4783,
          type: WaypointType.destination,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Waypoint should validate longitude range', () {
      // Arrange & Act & Assert
      expect(
        () => Waypoint(
          id: 'wp001',
          name: 'Test',
          latitude: 37.8199,
          longitude: 181.0, // Invalid: > 180
          type: WaypointType.destination,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Waypoint should convert to GpsPosition', () {
      // Arrange
      final waypoint = Waypoint(
        id: 'wp001',
        name: 'Test Point',
        latitude: 37.8199,
        longitude: -122.4783,
        type: WaypointType.destination,
      );

      // Act
      final position = waypoint.toPosition();

      // Assert
      expect(position.latitude, equals(waypoint.latitude));
      expect(position.longitude, equals(waypoint.longitude));
      expect(position.timestamp, isA<DateTime>());
    });

    test('Waypoint equality should work correctly', () {
      // Arrange
      final timestamp = DateTime(2024, 8, 1, 12, 0, 0);
      final waypoint1 = Waypoint(
        id: 'wp001',
        name: 'Test Point',
        latitude: 37.8199,
        longitude: -122.4783,
        type: WaypointType.destination,
        createdAt: timestamp,
      );

      final waypoint2 = Waypoint(
        id: 'wp001',
        name: 'Test Point',
        latitude: 37.8199,
        longitude: -122.4783,
        type: WaypointType.destination,
        createdAt: timestamp,
      );

      // Act & Assert
      expect(waypoint1, equals(waypoint2));
      expect(waypoint1.hashCode, equals(waypoint2.hashCode));
    });
  });

  group('NavigationRoute Tests', () {
    test('NavigationRoute should be created with valid data', () {
      // Arrange
      const id = 'route001';
      const name = 'Golden Gate to Alcatraz';
      final waypoints = [
        Waypoint(
          id: 'wp001',
          name: 'Start',
          latitude: 37.8199,
          longitude: -122.4783,
          type: WaypointType.departure,
        ),
        Waypoint(
          id: 'wp002',
          name: 'End',
          latitude: 37.8267,
          longitude: -122.4230,
          type: WaypointType.destination,
        ),
      ];

      // Act
      final route = NavigationRoute(
        id: id,
        name: name,
        waypoints: waypoints,
        description: 'Scenic route to Alcatraz',
      );

      // Assert
      expect(route.id, equals(id));
      expect(route.name, equals(name));
      expect(route.waypoints, equals(waypoints));
      expect(route.description, equals('Scenic route to Alcatraz'));
      expect(route.createdAt, isA<DateTime>());
      expect(route.isActive, isFalse);
    });

    test('NavigationRoute should require at least 2 waypoints', () {
      // Arrange & Act & Assert
      expect(
        () => NavigationRoute(
          id: 'route001',
          name: 'Invalid Route',
          waypoints: [
            Waypoint(
              id: 'wp001',
              name: 'Only One',
              latitude: 37.8199,
              longitude: -122.4783,
              type: WaypointType.departure,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NavigationRoute should calculate total distance', () {
      // Arrange
      final waypoints = [
        Waypoint(
          id: 'wp001',
          name: 'Start',
          latitude: 37.8199,
          longitude: -122.4783,
          type: WaypointType.departure,
        ),
        Waypoint(
          id: 'wp002',
          name: 'Middle',
          latitude: 37.8267,
          longitude: -122.4230,
          type: WaypointType.intermediate,
        ),
        Waypoint(
          id: 'wp003',
          name: 'End',
          latitude: 37.8300,
          longitude: -122.4200,
          type: WaypointType.destination,
        ),
      ];

      final route = NavigationRoute(
        id: 'route001',
        name: 'Test Route',
        waypoints: waypoints,
      );

      // Act
      final totalDistance = route.totalDistance;

      // Assert
      expect(totalDistance, greaterThan(0));
      expect(totalDistance, isA<double>());
    });

    test('NavigationRoute should find next waypoint correctly', () {
      // Arrange
      final waypoints = [
        Waypoint(
          id: 'wp001',
          name: 'Start',
          latitude: 37.8199,
          longitude: -122.4783,
          type: WaypointType.departure,
        ),
        Waypoint(
          id: 'wp002',
          name: 'Middle',
          latitude: 37.8267,
          longitude: -122.4230,
          type: WaypointType.intermediate,
        ),
        Waypoint(
          id: 'wp003',
          name: 'End',
          latitude: 37.8300,
          longitude: -122.4200,
          type: WaypointType.destination,
        ),
      ];

      final route = NavigationRoute(
        id: 'route001',
        name: 'Test Route',
        waypoints: waypoints,
      );

      final currentPosition = GpsPosition(
        latitude: 37.8250,
        longitude: -122.4250,
        timestamp: DateTime.now(),
      );

      // Act
      final nextWaypoint = route.getNextWaypoint(currentPosition);

      // Assert
      expect(nextWaypoint, isNotNull);
      expect(nextWaypoint!.id, equals('wp002'));
    });

    test('NavigationRoute should activate/deactivate correctly', () {
      // Arrange
      final route = NavigationRoute(
        id: 'route001',
        name: 'Test Route',
        waypoints: [
          Waypoint(
            id: 'wp001',
            name: 'Start',
            latitude: 37.8199,
            longitude: -122.4783,
            type: WaypointType.departure,
          ),
          Waypoint(
            id: 'wp002',
            name: 'End',
            latitude: 37.8267,
            longitude: -122.4230,
            type: WaypointType.destination,
          ),
        ],
      );

      // Act
      final activatedRoute = route.copyWith(isActive: true);
      final deactivatedRoute = activatedRoute.copyWith(isActive: false);

      // Assert
      expect(route.isActive, isFalse);
      expect(activatedRoute.isActive, isTrue);
      expect(deactivatedRoute.isActive, isFalse);
    });
  });

  group('WaypointType Tests', () {
    test('WaypointType should have correct display names', () {
      expect(WaypointType.departure.displayName, equals('Departure'));
      expect(WaypointType.intermediate.displayName, equals('Intermediate'));
      expect(WaypointType.destination.displayName, equals('Destination'));
      expect(WaypointType.landmark.displayName, equals('Landmark'));
      expect(WaypointType.hazard.displayName, equals('Hazard'));
      expect(WaypointType.anchorage.displayName, equals('Anchorage'));
    });

    test('WaypointType should have correct icons', () {
      expect(WaypointType.departure.iconData, isNotNull);
      expect(WaypointType.intermediate.iconData, isNotNull);
      expect(WaypointType.destination.iconData, isNotNull);
      expect(WaypointType.landmark.iconData, isNotNull);
      expect(WaypointType.hazard.iconData, isNotNull);
      expect(WaypointType.anchorage.iconData, isNotNull);
    });
  });
}
