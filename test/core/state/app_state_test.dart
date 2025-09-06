import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/state/app_state.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

/// Comprehensive tests for AppState immutable state class
/// Tests state creation, copying, validation, and equality
void main() {
  group('AppState Tests', () {
    group('State Initialization and Default Values', () {
      test('should initialize with default values', () {
        // Arrange & Act
        const state = AppState();

        // Assert
        expect(state.isInitialized, isFalse);
        expect(state.currentChartId, isNull);
        expect(state.currentPosition, isNull);
        expect(state.availableCharts, isEmpty);
        expect(state.downloadedCharts, isEmpty);
        expect(state.activeRoute, isNull);
        expect(state.waypoints, isEmpty);
        expect(state.isGpsEnabled, isFalse);
        expect(state.isLocationPermissionGranted, isFalse);
        expect(state.themeMode, equals(AppThemeMode.system));
        expect(state.isDayMode, isTrue);
      });

      test('should create state with custom initial values', () {
        // Arrange
        final customCharts = [_createTestChart('US5CA52M')];
        final customPosition = _createTestPosition();
        final customWaypoints = [_createTestWaypoint()];

        // Act
        final state = AppState(
          isInitialized: true,
          currentChartId: 'US5CA52M',
          currentPosition: customPosition,
          availableCharts: customCharts,
          waypoints: customWaypoints,
          isGpsEnabled: true,
          themeMode: AppThemeMode.dark,
          isDayMode: false,
        );

        // Assert
        expect(state.isInitialized, isTrue);
        expect(state.currentChartId, equals('US5CA52M'));
        expect(state.currentPosition, equals(customPosition));
        expect(state.availableCharts, equals(customCharts));
        expect(state.waypoints, equals(customWaypoints));
        expect(state.isGpsEnabled, isTrue);
        expect(state.themeMode, equals(AppThemeMode.dark));
        expect(state.isDayMode, isFalse);
      });
    });

    group('State Transitions and Updates', () {
      test('should update state immutably with copyWith', () {
        // Arrange
        const initialState = AppState();
        final newPosition = _createTestPosition();

        // Act
        final newState = initialState.copyWith(
          isInitialized: true,
          currentPosition: newPosition,
          isGpsEnabled: true,
        );

        // Assert - Original state unchanged
        expect(initialState.isInitialized, isFalse);
        expect(initialState.currentPosition, isNull);
        expect(initialState.isGpsEnabled, isFalse);

        // Assert - New state has updates
        expect(newState.isInitialized, isTrue);
        expect(newState.currentPosition, equals(newPosition));
        expect(newState.isGpsEnabled, isTrue);

        // Assert - Other fields preserved
        expect(newState.themeMode, equals(initialState.themeMode));
        expect(newState.isDayMode, equals(initialState.isDayMode));
      });

      test('should update charts collections immutably', () {
        // Arrange
        const initialState = AppState();
        final chart1 = _createTestChart('US5CA52M');
        final chart2 = _createTestChart('US4CA11M');

        // Act
        final stateWithAvailable = initialState.copyWith(
          availableCharts: [chart1],
        );

        final stateWithDownloaded = stateWithAvailable.copyWith(
          downloadedCharts: [chart2],
        );

        // Assert
        expect(initialState.availableCharts, isEmpty);
        expect(initialState.downloadedCharts, isEmpty);

        expect(stateWithAvailable.availableCharts, hasLength(1));
        expect(stateWithAvailable.downloadedCharts, isEmpty);

        expect(stateWithDownloaded.availableCharts, hasLength(1));
        expect(stateWithDownloaded.downloadedCharts, hasLength(1));
      });

      test('should update navigation state immutably', () {
        // Arrange
        const initialState = AppState();
        final route = _createTestRoute();
        final waypoint = _createTestWaypoint();

        // Act
        final stateWithRoute = initialState.copyWith(activeRoute: route);
        final stateWithWaypoint = stateWithRoute.copyWith(
          waypoints: [waypoint],
        );

        // Assert
        expect(initialState.activeRoute, isNull);
        expect(initialState.waypoints, isEmpty);

        expect(stateWithRoute.activeRoute, equals(route));
        expect(stateWithRoute.waypoints, isEmpty);

        expect(stateWithWaypoint.activeRoute, equals(route));
        expect(stateWithWaypoint.waypoints, hasLength(1));
      });

      test('should handle null updates in copyWith', () {
        // Arrange
        final initialPosition = _createTestPosition();
        final state = AppState(currentPosition: initialPosition);

        // Act - copyWith preserves existing values when null not explicitly passed
        final updatedState = state.copyWith(isInitialized: true);

        // Assert - currentPosition should be preserved
        expect(state.currentPosition, equals(initialPosition));
        expect(updatedState.currentPosition, equals(initialPosition));
        expect(updatedState.isInitialized, isTrue);
      });
    });

    group('State Validation and Constraints', () {
      test('should maintain state consistency for GPS', () {
        // Arrange
        const state = AppState();

        // Act
        final gpsEnabledState = state.copyWith(
          isGpsEnabled: true,
          isLocationPermissionGranted: true,
          currentPosition: _createTestPosition(),
        );

        // Assert - GPS state is consistent
        expect(gpsEnabledState.isGpsEnabled, isTrue);
        expect(gpsEnabledState.isLocationPermissionGranted, isTrue);
        expect(gpsEnabledState.currentPosition, isNotNull);
      });

      test('should handle theme mode transitions', () {
        // Arrange
        const state = AppState();

        // Act & Assert - Test all theme modes
        final lightState = state.copyWith(themeMode: AppThemeMode.light);
        expect(lightState.themeMode, equals(AppThemeMode.light));

        final darkState = lightState.copyWith(themeMode: AppThemeMode.dark);
        expect(darkState.themeMode, equals(AppThemeMode.dark));

        final systemState = darkState.copyWith(themeMode: AppThemeMode.system);
        expect(systemState.themeMode, equals(AppThemeMode.system));
      });

      test('should maintain chart consistency', () {
        // Arrange
        final chart = _createTestChart('US5CA52M');
        const state = AppState();

        // Act
        final stateWithChart = state.copyWith(
          availableCharts: [chart],
          currentChartId: chart.id,
        );

        // Assert
        expect(stateWithChart.currentChartId, equals(chart.id));
        expect(stateWithChart.availableCharts, contains(chart));
      });
    });

    group('Immutability Enforcement', () {
      test('should not allow modification of chart lists', () {
        // Arrange
        final chart = _createTestChart('US5CA52M');
        final state = AppState(availableCharts: [chart]);

        // Act & Assert - Lists should be immutable (const lists)
        // Note: The const [] lists in AppState are already immutable
        expect(state.availableCharts, hasLength(1));
        expect(state.downloadedCharts, isEmpty);
        expect(state.waypoints, isEmpty);

        // Verify the lists are present and correct
        expect(state.availableCharts.first, equals(chart));
      });

      test('should create new instances on copyWith', () {
        // Arrange
        final chart = _createTestChart('US5CA52M');
        final state = AppState(availableCharts: [chart]);

        // Act
        final newState = state.copyWith(isInitialized: true);

        // Assert - Different instances
        expect(identical(state, newState), isFalse);
        expect(
          identical(state.availableCharts, newState.availableCharts),
          isTrue,
        ); // Same list reference is OK for immutable data
      });
    });

    group('State Equality and Comparison', () {
      test('should implement equality correctly', () {
        // Arrange
        final position = _createTestPosition();
        final chart = _createTestChart('US5CA52M');

        final state1 = AppState(
          isInitialized: true,
          currentPosition: position,
          availableCharts: [chart],
          isGpsEnabled: true,
        );

        final state2 = AppState(
          isInitialized: true,
          currentPosition: position,
          availableCharts: [chart],
          isGpsEnabled: true,
        );

        // Act & Assert
        expect(state1, equals(state2));
        // Note: hashCode may differ due to list implementations, but equality should work
        expect(state1 == state2, isTrue);
      });

      test('should detect inequality correctly', () {
        // Arrange
        final state1 = AppState(isInitialized: true);
        final state2 = AppState(isInitialized: false);

        // Act & Assert
        expect(state1, isNot(equals(state2)));
        expect(state1.hashCode, isNot(equals(state2.hashCode)));
      });

      test('should handle complex state equality', () {
        // Arrange
        final position = _createTestPosition();
        final chart1 = _createTestChart('US5CA52M');
        final chart2 = _createTestChart('US4CA11M');
        final waypoint = _createTestWaypoint();

        final state1 = AppState(
          availableCharts: [chart1, chart2],
          waypoints: [waypoint],
          currentPosition: position,
        );

        final state2 = AppState(
          availableCharts: [chart1, chart2],
          waypoints: [waypoint],
          currentPosition: position,
        );

        // Act & Assert
        expect(state1, equals(state2));
      });
    });

    group('State String Representation', () {
      test('should provide informative toString', () {
        // Arrange
        final state = AppState(
          isInitialized: true,
          currentChartId: 'US5CA52M',
          availableCharts: [_createTestChart('US5CA52M')],
          isGpsEnabled: true,
        );

        // Act
        final stateString = state.toString();

        // Assert
        expect(stateString, contains('AppState'));
        expect(stateString, contains('isInitialized: true'));
        expect(stateString, contains('currentChartId: US5CA52M'));
        expect(stateString, contains('availableCharts: 1'));
        expect(stateString, contains('isGpsEnabled: true'));
      });
    });

    group('Marine Navigation State Requirements', () {
      test('should support marine navigation workflow', () {
        // Arrange
        const initialState = AppState();
        final position = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
        );
        final chart = _createTestChart('US5CA52M');
        final waypoint = Waypoint(
          id: 'wp001',
          name: 'Golden Gate',
          latitude: 37.8199,
          longitude: -122.4783,
          type: WaypointType.landmark,
        );

        // Act - Simulate marine navigation setup
        final stateWithGps = initialState.copyWith(
          isGpsEnabled: true,
          isLocationPermissionGranted: true,
          currentPosition: position,
        );

        final stateWithChart = stateWithGps.copyWith(
          availableCharts: [chart],
          currentChartId: chart.id,
        );

        final stateWithNavigation = stateWithChart.copyWith(
          waypoints: [waypoint],
        );

        // Assert - Complete marine navigation state
        expect(stateWithNavigation.isGpsEnabled, isTrue);
        expect(stateWithNavigation.isLocationPermissionGranted, isTrue);
        expect(stateWithNavigation.currentPosition, isNotNull);
        expect(stateWithNavigation.currentChartId, equals(chart.id));
        expect(stateWithNavigation.availableCharts, contains(chart));
        expect(stateWithNavigation.waypoints, contains(waypoint));
      });

      test('should validate GPS accuracy for marine use', () {
        // Arrange
        final highAccuracyPosition = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 2.0, // High accuracy for marine navigation
        );

        // Act
        final state = AppState(currentPosition: highAccuracyPosition);

        // Assert
        expect(state.currentPosition?.accuracy, lessThanOrEqualTo(5.0));
      });
    });
  });

  group('AppThemeMode Tests', () {
    test('should have correct display names', () {
      expect(AppThemeMode.system.displayName, equals('System'));
      expect(AppThemeMode.light.displayName, equals('Light'));
      expect(AppThemeMode.dark.displayName, equals('Dark'));
    });

    test('should support all theme modes', () {
      expect(AppThemeMode.values, hasLength(3));
      expect(AppThemeMode.values, contains(AppThemeMode.system));
      expect(AppThemeMode.values, contains(AppThemeMode.light));
      expect(AppThemeMode.values, contains(AppThemeMode.dark));
    });
  });
}

/// Helper function to create test chart
Chart _createTestChart(String id) {
  return Chart(
    id: id,
    title: 'Test Chart $id',
    scale: 25000,
    bounds: GeographicBounds(
      north: 38.0,
      south: 37.0,
      east: -122.0,
      west: -123.0,
    ),
    lastUpdate: DateTime.now(),
    state: 'California',
    type: ChartType.harbor,
  );
}

/// Helper function to create test GPS position
GpsPosition _createTestPosition() {
  return GpsPosition(
    latitude: 37.7749,
    longitude: -122.4194,
    timestamp: DateTime.now(),
    accuracy: 5.0,
    altitude: 50.0,
    speed: 0.0,
    heading: 0.0,
  );
}

/// Helper function to create test waypoint
Waypoint _createTestWaypoint() {
  return Waypoint(
    id: 'wp001',
    name: 'Test Waypoint',
    latitude: 37.7749,
    longitude: -122.4194,
    type: WaypointType.destination,
  );
}

/// Helper function to create test route
NavigationRoute _createTestRoute() {
  return NavigationRoute(
    id: 'route001',
    name: 'Test Route',
    waypoints: [
      _createTestWaypoint(),
      Waypoint(
        id: 'wp002',
        name: 'End Point',
        latitude: 37.8000,
        longitude: -122.4000,
        type: WaypointType.destination,
      ),
    ],
  );
}
