import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/state/app_state_notifier.dart';
import 'package:navtool/core/state/app_state.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

// Mock implementations for testing
class MockAppLogger implements AppLogger {
  final List<String> _logs = [];
  List<String> get logs => _logs;

  @override
  void debug(String message, {String? context, Object? exception}) {
    _logs.add('DEBUG: $message');
  }

  @override
  void info(String message, {String? context, Object? exception}) {
    _logs.add('INFO: $message');
  }

  @override
  void warning(String message, {String? context, Object? exception}) {
    _logs.add('WARNING: $message');
  }

  @override
  void error(String message, {String? context, Object? exception}) {
    _logs.add('ERROR: $message');
  }

  @override
  void logError(AppError error) {
    _logs.add('APP_ERROR: ${error.message}');
  }

  void clear() => _logs.clear();
}

class MockErrorHandler implements ErrorHandler {
  final List<String> _errors = [];
  List<String> get errors => _errors;

  @override
  late AppLogger logger;

  MockErrorHandler() {
    logger = MockAppLogger();
  }

  @override
  void handleError(Object error, [StackTrace? stackTrace]) {
    _errors.add('ERROR: $error');
  }

  @override
  bool shouldRetry(AppError error) => false;

  @override
  String getUserMessage(AppError error) => error.message;

  @override
  ErrorRecoveryStrategy getRecoveryStrategy(AppError error) => ErrorRecoveryStrategy(
    shouldRetry: false,
    maxRetries: 0,
    delayBetweenRetries: Duration.zero,
    userActions: [],
  );

  @override
  Future<T> handleWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    return await operation();
  }

  void clear() => _errors.clear();
}

/// Comprehensive tests for AppStateNotifier
/// Tests state changes, error handling, and marine navigation workflows
void main() {
  group('AppStateNotifier Tests', () {
    late MockAppLogger mockLogger;
    late MockErrorHandler mockErrorHandler;
    late AppStateNotifier notifier;
    late ProviderContainer container;

    setUp(() {
      mockLogger = MockAppLogger();
      mockErrorHandler = MockErrorHandler();
      
      // Create notifier with mocked dependencies
      notifier = AppStateNotifier(
        logger: mockLogger,
        errorHandler: mockErrorHandler,
      );
      
      // Create provider container for testing
      container = ProviderContainer();
    });

    tearDown(() {
      notifier.dispose();
      container.dispose();
    });

    group('State Change Operations', () {
      test('should initialize with default state', () async {
        // Arrange - Wait for initialization
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Act
        final state = notifier.state;
        
        // Assert
        expect(state.isInitialized, isTrue);
        expect(state.currentPosition, isNull);
        expect(state.availableCharts, isEmpty);
        expect(state.isGpsEnabled, isFalse);
        
        // Verify initialization was logged
        expect(mockLogger.logs, contains('INFO: Initializing application state'));
        expect(mockLogger.logs, contains('INFO: Application state initialized successfully'));
      });

      test('should update current position correctly', () {
        // Arrange
        final initialState = notifier.state;
        final testPosition = _createTestPosition();
        
        // Act
        notifier.updateCurrentPosition(testPosition);
        
        // Assert
        expect(notifier.state.currentPosition, equals(testPosition));
        expect(notifier.state, isNot(equals(initialState))); // State changed
        
        // Verify logging
        expect(mockLogger.logs.any((log) => log.contains('Updated current position')), isTrue);
      });

      test('should update GPS enabled status', () {
        // Arrange
        final initialState = notifier.state;
        
        // Act
        notifier.setGpsEnabled(true);
        
        // Assert
        expect(notifier.state.isGpsEnabled, isTrue);
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: GPS enabled status changed: true'));
      });

      test('should update location permission status', () {
        // Arrange
        final initialState = notifier.state;
        
        // Act
        notifier.setLocationPermissionGranted(true);
        
        // Assert
        expect(notifier.state.isLocationPermissionGranted, isTrue);
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Location permission status changed: true'));
      });

      test('should update available charts', () {
        // Arrange
        final initialState = notifier.state;
        final testCharts = [_createTestChart('US5CA52M'), _createTestChart('US4CA11M')];
        
        // Act
        notifier.updateAvailableCharts(testCharts);
        
        // Assert
        expect(notifier.state.availableCharts, equals(testCharts));
        expect(notifier.state.availableCharts, hasLength(2));
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Updated available charts: 2 charts'));
      });

      test('should add downloaded chart', () {
        // Arrange
        final initialState = notifier.state;
        final testChart = _createTestChart('US5CA52M');
        
        // Act
        notifier.addDownloadedChart(testChart);
        
        // Assert
        expect(notifier.state.downloadedCharts, contains(testChart));
        expect(notifier.state.downloadedCharts, hasLength(1));
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Added downloaded chart: ${testChart.id}'));
      });

      test('should set active route', () {
        // Arrange
        final initialState = notifier.state;
        final testRoute = _createTestRoute();
        
        // Act
        notifier.setActiveRoute(testRoute);
        
        // Assert
        expect(notifier.state.activeRoute, equals(testRoute));
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Active route changed: ${testRoute.id}'));
      });

      test('should add waypoint', () {
        // Arrange
        final initialState = notifier.state;
        final testWaypoint = _createTestWaypoint();
        
        // Act
        notifier.addWaypoint(testWaypoint);
        
        // Assert
        expect(notifier.state.waypoints, contains(testWaypoint));
        expect(notifier.state.waypoints, hasLength(1));
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Added waypoint: ${testWaypoint.id}'));
      });
    });

    group('State Observation Through Container', () {
      test('should allow watching state changes through container', () {
        // Arrange
        final testContainer = ProviderContainer();
        final stateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) => 
          AppStateNotifier(
            logger: MockAppLogger(),
            errorHandler: MockErrorHandler(),
          )
        );
        final testPosition = _createTestPosition();
        
        try {
          // Act
          final initialState = testContainer.read(stateProvider);
          testContainer.read(stateProvider.notifier).updateCurrentPosition(testPosition);
          final updatedState = testContainer.read(stateProvider);
          
          // Assert
          expect(initialState.currentPosition, isNull);
          expect(updatedState.currentPosition, equals(testPosition));
        } finally {
          testContainer.dispose();
        }
      });

      test('should support multiple state changes', () {
        // Arrange
        final testContainer = ProviderContainer();
        final stateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) => 
          AppStateNotifier(
            logger: MockAppLogger(),
            errorHandler: MockErrorHandler(),
          )
        );
        
        try {
          // Act
          final stateNotifier = testContainer.read(stateProvider.notifier);
          stateNotifier.setGpsEnabled(true);
          stateNotifier.setLocationPermissionGranted(true);
          final finalState = testContainer.read(stateProvider);
          
          // Assert
          expect(finalState.isGpsEnabled, isTrue);
          expect(finalState.isLocationPermissionGranted, isTrue);
        } finally {
          testContainer.dispose();
        }
      });
    });

    group('Async State Updates', () {
      test('should handle async state updates correctly', () async {
        // Arrange
        final testPosition = _createTestPosition();
        
        // Act - Simulate async GPS update
        await Future.delayed(const Duration(milliseconds: 10));
        notifier.updateCurrentPosition(testPosition);
        
        // Assert
        expect(notifier.state.currentPosition, equals(testPosition));
      });

      test('should handle rapid sequential updates', () {
        // Arrange
        final positions = [
          GpsPosition(latitude: 37.7749, longitude: -122.4194, timestamp: DateTime.now()),
          GpsPosition(latitude: 37.7750, longitude: -122.4195, timestamp: DateTime.now()),
          GpsPosition(latitude: 37.7751, longitude: -122.4196, timestamp: DateTime.now()),
        ];
        
        // Act - Rapid updates
        for (final position in positions) {
          notifier.updateCurrentPosition(position);
        }
        
        // Assert - Last position should be current
        expect(notifier.state.currentPosition, equals(positions.last));
        
        // Verify all updates were logged
        final positionUpdateLogs = mockLogger.logs.where((log) => log.contains('Updated current position'));
        expect(positionUpdateLogs.length, equals(3));
      });

      test('should maintain state consistency during concurrent updates', () {
        // Arrange
        final testChart = _createTestChart('US5CA52M');
        final testPosition = _createTestPosition();
        
        // Act - Concurrent updates
        notifier.addDownloadedChart(testChart);
        notifier.updateCurrentPosition(testPosition);
        notifier.setGpsEnabled(true);
        
        // Assert - All updates applied
        expect(notifier.state.downloadedCharts, contains(testChart));
        expect(notifier.state.currentPosition, equals(testPosition));
        expect(notifier.state.isGpsEnabled, isTrue);
      });
    });

    group('Error Handling in State Changes', () {
      test('should handle position updates without errors', () {
        // Arrange
        final validPosition = _createTestPosition();
        
        // Act
        notifier.updateCurrentPosition(validPosition);
        
        // Assert
        expect(notifier.state.currentPosition, equals(validPosition));
        expect(mockErrorHandler.errors, isEmpty);
      });

      test('should handle chart updates without errors', () {
        // Arrange
        final validChart = _createTestChart('US5CA52M');
        
        // Act
        notifier.addDownloadedChart(validChart);
        
        // Assert
        expect(notifier.state.downloadedCharts, contains(validChart));
        expect(mockErrorHandler.errors, isEmpty);
      });

      test('should handle normal operations without triggering error handler', () {
        // Arrange
        final testPosition = _createTestPosition();
        
        // Act
        notifier.updateCurrentPosition(testPosition);
        notifier.setGpsEnabled(true);
        
        // Assert
        expect(mockErrorHandler.errors, isEmpty);
      });
    });

    group('Performance of State Updates', () {
      test('should complete state updates within performance thresholds', () {
        // Arrange
        final stopwatch = Stopwatch();
        final testPosition = _createTestPosition();
        
        // Act
        stopwatch.start();
        for (int i = 0; i < 100; i++) {
          notifier.updateCurrentPosition(testPosition);
        }
        stopwatch.stop();
        
        // Assert - Should complete within 100ms for 100 updates
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('should handle large chart collections efficiently', () {
        // Arrange
        final largeChartList = List.generate(
          1000,
          (index) => _createTestChart('CHART_$index'),
        );
        final stopwatch = Stopwatch();
        
        // Act
        stopwatch.start();
        notifier.updateAvailableCharts(largeChartList);
        stopwatch.stop();
        
        // Assert - Should handle large collections efficiently
        expect(stopwatch.elapsedMilliseconds, lessThan(50));
        expect(notifier.state.availableCharts, hasLength(1000));
      });
    });

    group('Memory Management', () {
      test('should properly dispose without errors', () {
        // Arrange
        final testNotifier = AppStateNotifier(
          logger: MockAppLogger(),
          errorHandler: MockErrorHandler(),
        );
        final testPosition = _createTestPosition();
        testNotifier.updateCurrentPosition(testPosition);
        
        // Act & Assert - Should not throw on disposal
        expect(() => testNotifier.dispose(), returnsNormally);
      });

      test('should handle disposal after state changes', () {
        // Arrange
        final testNotifier = AppStateNotifier(
          logger: MockAppLogger(),
          errorHandler: MockErrorHandler(),
        );
        testNotifier.setGpsEnabled(true);
        testNotifier.setLocationPermissionGranted(true);
        
        // Act & Assert
        expect(() => testNotifier.dispose(), returnsNormally);
      });
    });

    group('Marine Navigation State Workflows', () {
      test('should support complete marine navigation setup workflow', () {
        // Arrange - Simulate marine navigation initialization
        final position = GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 3.0, // High accuracy for marine navigation
        );
        final chart = _createTestChart('US5CA52M');
        final route = _createTestRoute();
        
        // Act - Complete setup workflow
        notifier.setLocationPermissionGranted(true);
        notifier.setGpsEnabled(true);
        notifier.updateCurrentPosition(position);
        notifier.addDownloadedChart(chart);
        notifier.setCurrentChart(chart.id);
        notifier.setActiveRoute(route);
        
        // Assert - Complete marine navigation state
        expect(notifier.state.isLocationPermissionGranted, isTrue);
        expect(notifier.state.isGpsEnabled, isTrue);
        expect(notifier.state.currentPosition, equals(position));
        expect(notifier.state.downloadedCharts, contains(chart));
        expect(notifier.state.currentChartId, equals(chart.id));
        expect(notifier.state.activeRoute, equals(route));
      });

      test('should handle GPS signal loss scenario', () {
        // Arrange - Start with good GPS
        final goodPosition = _createTestPosition();
        notifier.setGpsEnabled(true);
        notifier.updateCurrentPosition(goodPosition);
        
        // Act - Simulate GPS signal loss
        notifier.setGpsEnabled(false);
        
        // Assert - Position retained but GPS disabled
        expect(notifier.state.currentPosition, equals(goodPosition));
        expect(notifier.state.isGpsEnabled, isFalse);
        
        // Verify appropriate logging
        expect(mockLogger.logs, contains('INFO: GPS enabled status changed: false'));
      });

      test('should handle chart switching during navigation', () {
        // Arrange
        final chart1 = _createTestChart('US5CA52M');
        final chart2 = _createTestChart('US4CA11M');
        
        notifier.addDownloadedChart(chart1);
        notifier.addDownloadedChart(chart2);
        notifier.setCurrentChart(chart1.id);
        
        // Act - Switch charts
        notifier.setCurrentChart(chart2.id);
        
        // Assert
        expect(notifier.state.currentChartId, equals(chart2.id));
        expect(notifier.state.downloadedCharts, hasLength(2));
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Current chart changed: ${chart2.id}'));
      });

      test('should handle waypoint management workflow', () {
        // Arrange
        final waypoint1 = _createTestWaypoint();
        final waypoint2 = Waypoint(
          id: 'wp002',
          name: 'Second Waypoint',
          latitude: 37.8000,
          longitude: -122.4000,
          type: WaypointType.destination,
        );
        
        // Act - Add waypoints
        notifier.addWaypoint(waypoint1);
        notifier.addWaypoint(waypoint2);
        
        // Assert
        expect(notifier.state.waypoints, hasLength(2));
        expect(notifier.state.waypoints, contains(waypoint1));
        expect(notifier.state.waypoints, contains(waypoint2));
        
        // Act - Remove waypoint
        notifier.removeWaypoint(waypoint1.id);
        
        // Assert
        expect(notifier.state.waypoints, hasLength(1));
        expect(notifier.state.waypoints, contains(waypoint2));
        expect(notifier.state.waypoints, isNot(contains(waypoint1)));
      });

      test('should handle theme and display mode changes', () {
        // Arrange
        final initialState = notifier.state;
        
        // Act - Change theme and day mode
        notifier.setThemeMode(AppThemeMode.dark);
        notifier.setDayMode(false);
        
        // Assert
        expect(notifier.state.themeMode, equals(AppThemeMode.dark));
        expect(notifier.state.isDayMode, isFalse);
        expect(notifier.state, isNot(equals(initialState)));
        
        // Verify logging
        expect(mockLogger.logs.any((log) => log.contains('Theme mode changed')), isTrue);
        expect(mockLogger.logs.any((log) => log.contains('Chart day mode changed')), isTrue);
      });

      test('should support state reset functionality', () {
        // Arrange - Set up some state
        final testPosition = _createTestPosition();
        final testChart = _createTestChart('US5CA52M');
        
        notifier.updateCurrentPosition(testPosition);
        notifier.addDownloadedChart(testChart);
        notifier.setGpsEnabled(true);
        
        // Act - Reset state
        notifier.reset();
        
        // Assert - State is reset to defaults
        expect(notifier.state.currentPosition, isNull);
        expect(notifier.state.downloadedCharts, isEmpty);
        expect(notifier.state.isGpsEnabled, isFalse);
        expect(notifier.state.isInitialized, isFalse); // Reset to initial state
        
        // Verify logging
        expect(mockLogger.logs, contains('INFO: Application state reset'));
      });
    });
  });
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
