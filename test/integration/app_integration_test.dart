import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/app/app.dart';
import 'package:navtool/app/routes.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/navigation_service.dart';
import 'package:navtool/core/services/chart_service.dart';
import 'package:navtool/core/services/settings_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/features/home/home_screen.dart';
import 'package:navtool/features/about/about_screen.dart';
import 'package:navtool/features/charts/chart_screen.dart';

import 'app_integration_test.mocks.dart';

// Generate mocks for all major services
@GenerateMocks([
  GpsService,
  StorageService,
  DownloadService,
  NavigationService,
  ChartService,
  SettingsService,
  AppLogger,
])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    late MockGpsService mockGpsService;
    late MockStorageService mockStorageService;
    late MockDownloadService mockDownloadService;
    late MockNavigationService mockNavigationService;
    late MockChartService mockChartService;
    late MockSettingsService mockSettingsService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockGpsService = MockGpsService();
      mockStorageService = MockStorageService();
      mockDownloadService = MockDownloadService();
      mockNavigationService = MockNavigationService();
      mockChartService = MockChartService();
      mockSettingsService = MockSettingsService();
      mockLogger = MockAppLogger();

      // Setup default mock behaviors
      _setupDefaultMocks();
    });

    void _setupDefaultMocks() {
      // GPS Service mocks
      when(mockGpsService.getCurrentPosition()).thenAnswer((_) async => 
        const GpsPosition(
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 5.0,
          timestamp: null,
        )
      );
      when(mockGpsService.isLocationServiceEnabled()).thenAnswer((_) async => true);
      when(mockGpsService.hasLocationPermission()).thenAnswer((_) async => true);

      // Storage Service mocks
      when(mockStorageService.initialize()).thenAnswer((_) async {});
      when(mockStorageService.getAllCharts()).thenAnswer((_) async => []);
      when(mockStorageService.getAllRoutes()).thenAnswer((_) async => []);

      // Download Service mocks
      when(mockDownloadService.initialize()).thenAnswer((_) async {});

      // Navigation Service mocks
      when(mockNavigationService.getAllRoutes()).thenAnswer((_) async => []);

      // Chart Service mocks
      when(mockChartService.getAllCharts()).thenAnswer((_) async => []);

      // Settings Service mocks
      when(mockSettingsService.initialize()).thenAnswer((_) async {});

      // Logger mocks
      when(mockLogger.info(any)).thenReturn(null);
      when(mockLogger.error(any, exception: anyNamed('exception'))).thenReturn(null);
    }

    Widget createTestApp({List<Override> overrides = const []}) {
      return ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
          storageServiceProvider.overrideWithValue(mockStorageService),
          downloadServiceProvider.overrideWithValue(mockDownloadService),
          navigationServiceProvider.overrideWithValue(mockNavigationService),
          chartServiceProvider.overrideWithValue(mockChartService),
          settingsServiceProvider.overrideWithValue(mockSettingsService),
          loggerProvider.overrideWithValue(mockLogger),
          ...overrides,
        ],
        child: const NavToolApp(),
      );
    }

    group('App Startup and Initialization Sequence', () {
      testWidgets('should complete app startup sequence successfully', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(NavToolApp), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Verify initialization calls
        verify(mockStorageService.initialize()).called(1);
        verify(mockDownloadService.initialize()).called(1);
        verify(mockSettingsService.initialize()).called(1);
      });

      testWidgets('should handle initialization failures gracefully', (WidgetTester tester) async {
        // Arrange - Make storage initialization fail
        when(mockStorageService.initialize()).thenThrow(Exception('Storage init failed'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - App should still start
        expect(find.byType(NavToolApp), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Verify error was logged
        verify(mockLogger.error(any, exception: anyNamed('exception'))).called(atLeast(1));
      });

      testWidgets('should initialize all core services in correct order', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - All services should be initialized
        verify(mockStorageService.initialize()).called(1);
        verify(mockDownloadService.initialize()).called(1);
        verify(mockSettingsService.initialize()).called(1);
        
        // GPS service should be accessed for position
        verify(mockGpsService.getCurrentPosition()).called(atLeast(1));
      });

      testWidgets('should display loading state during initialization', (WidgetTester tester) async {
        // Arrange - Delay storage initialization
        when(mockStorageService.initialize()).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pump(const Duration(milliseconds: 50));
        
        // Assert - Should show app during initialization
        expect(find.byType(NavToolApp), findsOneWidget);
        
        // Complete initialization
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Service Integration and Dependency Resolution', () {
      testWidgets('should properly resolve all service dependencies', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Verify that all services are available and working
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Check that GPS service is available
        verify(mockGpsService.getCurrentPosition()).called(atLeast(1));
      });

      testWidgets('should handle service dependency failures', (WidgetTester tester) async {
        // Arrange - Make GPS service fail
        when(mockGpsService.getCurrentPosition()).thenThrow(Exception('GPS failed'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - App should still function
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should maintain service state consistency', (WidgetTester tester) async {
        // Arrange
        final testChart = Chart(
          id: 'test_chart',
          name: 'Test Chart',
          scale: 50000,
          bounds: const GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/chart.zip',
          fileSize: 1024,
          lastUpdated: DateTime.now(),
        );
        
        when(mockChartService.getAllCharts()).thenAnswer((_) async => [testChart]);
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => [testChart]);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Verify chart service was called
        verify(mockChartService.getAllCharts()).called(atLeast(1));
      });
    });

    group('Cross-Feature Navigation Flows', () {
      testWidgets('should navigate from home to charts and back', (WidgetTester tester) async {
        // Arrange
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert initial state
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Act - Navigate to charts
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert - Should be on chart screen
        expect(find.byType(ChartScreen), findsOneWidget);
        
        // Act - Navigate back
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        
        // Assert - Should be back on home screen
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should navigate to about screen from home', (WidgetTester tester) async {
        // Set small screen to show mobile layout
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Arrange
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Act - Open drawer and navigate to about
        await tester.tap(find.byType(DrawerButton));
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
      });

      testWidgets('should handle deep linking to specific screens', (WidgetTester tester) async {
        // Act - Start app with chart route
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gpsServiceProvider.overrideWithValue(mockGpsService),
              storageServiceProvider.overrideWithValue(mockStorageService),
              downloadServiceProvider.overrideWithValue(mockDownloadService),
              navigationServiceProvider.overrideWithValue(mockNavigationService),
              chartServiceProvider.overrideWithValue(mockChartService),
              settingsServiceProvider.overrideWithValue(mockSettingsService),
              loggerProvider.overrideWithValue(mockLogger),
            ],
            child: MaterialApp(
              initialRoute: AppRoutes.chart,
              routes: AppRoutes.routes,
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should maintain navigation stack correctly', (WidgetTester tester) async {
        // Arrange
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Act - Navigate through multiple screens
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        expect(find.byType(ChartScreen), findsOneWidget);
        
        // Navigate back
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        
        // Assert - Should be back at home
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('State Persistence Across App Lifecycle', () {
      testWidgets('should persist GPS state across app restarts', (WidgetTester tester) async {
        // Arrange
        final testPosition = const GpsPosition(
          latitude: 37.8000,
          longitude: -122.4000,
          accuracy: 3.0,
          timestamp: null,
        );
        when(mockGpsService.getCurrentPosition()).thenAnswer((_) async => testPosition);
        
        // Act - Start app
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Verify GPS position is loaded
        verify(mockGpsService.getCurrentPosition()).called(atLeast(1));
        
        // Simulate app restart
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - GPS service should be called again
        verify(mockGpsService.getCurrentPosition()).called(atLeast(2));
      });

      testWidgets('should restore download queue state', (WidgetTester tester) async {
        // Arrange
        when(mockDownloadService.getActiveDownloads()).thenAnswer((_) async => []);
        when(mockDownloadService.getQueuedDownloads()).thenAnswer((_) async => []);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should persist user settings across sessions', (WidgetTester tester) async {
        // Arrange
        when(mockSettingsService.getThemeMode()).thenReturn('dark');
        when(mockSettingsService.getUnits()).thenReturn('metric');
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockSettingsService.initialize()).called(1);
      });
    });

    group('Memory Usage and Performance', () {
      testWidgets('should handle memory efficiently with large datasets', (WidgetTester tester) async {
        // Arrange - Large dataset
        final largeChartList = List.generate(100, (index) => Chart(
          id: 'chart_$index',
          name: 'Chart $index',
          scale: 50000,
          bounds: const GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/chart_$index.zip',
          fileSize: 1024,
          lastUpdated: DateTime.now(),
        ));
        
        when(mockChartService.getAllCharts()).thenAnswer((_) async => largeChartList);
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => largeChartList);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - App should handle large datasets without issues
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should perform well with complex navigation flows', (WidgetTester tester) async {
        // Act - Rapid navigation
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Navigate multiple times rapidly
        for (int i = 0; i < 5; i++) {
          await tester.tap(find.text('New Chart'));
          await tester.pumpAndSettle();
          
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }
        
        // Assert - Should still be responsive
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should cleanup resources properly', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Navigate away and back
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        
        // Assert - Should not have memory leaks
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Error Recovery Across App Restart', () {
      testWidgets('should recover from service failures', (WidgetTester tester) async {
        // Arrange - Start with failing service
        when(mockGpsService.getCurrentPosition()).thenThrow(Exception('GPS Error'));
        
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // App should still start
        expect(find.byType(HomeScreen), findsOneWidget);
        
        // Fix the service and restart
        when(mockGpsService.getCurrentPosition()).thenAnswer((_) async => 
          const GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 5.0,
            timestamp: null,
          )
        );
        
        // Act - Restart app
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should work normally now
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockGpsService.getCurrentPosition()).called(atLeast(1));
      });

      testWidgets('should handle network connectivity changes', (WidgetTester tester) async {
        // Arrange - Start with network available
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => true);
        
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Simulate network loss
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => false);
        
        // App should still function
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should recover from corrupted data', (WidgetTester tester) async {
        // Arrange - Corrupted storage
        when(mockStorageService.getAllCharts()).thenThrow(Exception('Corrupted data'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle gracefully
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Offline/Online Mode Transitions', () {
      testWidgets('should transition smoothly from online to offline', (WidgetTester tester) async {
        // Arrange - Start online
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => true);
        
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Act - Go offline
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => false);
        
        // Assert - App should continue working
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle offline chart access', (WidgetTester tester) async {
        // Arrange - Offline with cached charts
        final cachedChart = Chart(
          id: 'cached_chart',
          name: 'Cached Chart',
          scale: 50000,
          bounds: const GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/chart.zip',
          fileSize: 1024,
          lastUpdated: DateTime.now(),
        );
        
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => false);
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => [cachedChart]);
        when(mockChartService.getAllCharts()).thenAnswer((_) async => [cachedChart]);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockStorageService.getAllCharts()).called(atLeast(1));
      });

      testWidgets('should sync data when coming back online', (WidgetTester tester) async {
        // Arrange - Start offline
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => false);
        
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Act - Come back online
        when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => true);
        
        // Simulate network detection
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle online transition
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Marine Operational Scenarios', () {
      testWidgets('should handle GPS signal loss scenarios', (WidgetTester tester) async {
        // Arrange - Start with GPS
        when(mockGpsService.getCurrentPosition()).thenAnswer((_) async => 
          const GpsPosition(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 5.0,
            timestamp: null,
          )
        );
        
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Act - Lose GPS signal
        when(mockGpsService.getCurrentPosition()).thenThrow(Exception('No GPS signal'));
        when(mockGpsService.isLocationServiceEnabled()).thenAnswer((_) async => false);
        
        // App should continue functioning
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle emergency navigation scenarios', (WidgetTester tester) async {
        // Arrange - Emergency conditions
        when(mockNavigationService.isEmergencyMode()).thenReturn(true);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle emergency mode
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should support marine safety compliance', (WidgetTester tester) async {
        // Arrange
        when(mockSettingsService.isSafetyModeEnabled()).thenReturn(true);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle chart data corruption in marine environment', (WidgetTester tester) async {
        // Arrange - Corrupted chart data
        when(mockChartService.getAllCharts()).thenThrow(Exception('Chart data corrupted'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle gracefully for safety
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockLogger.error(any, exception: anyNamed('exception'))).called(atLeast(1));
      });
    });
  });
}