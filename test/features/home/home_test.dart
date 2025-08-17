import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/features/home/home_screen.dart';
import 'package:navtool/widgets/app_icon.dart';
import 'package:navtool/widgets/gps_status_widget.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/models/gps_position.dart';

import 'home_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([GpsService, AppLogger])
void main() {
  group('Home Feature Tests', () {
    late MockGpsService mockGpsService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockGpsService = MockGpsService();
      mockLogger = MockAppLogger();
      
      // Setup default mock behaviors
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
    });

    Widget createTestWidget({List<Override> overrides = const []}) {
      return ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
          loggerProvider.overrideWithValue(mockLogger),
          ...overrides,
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      );
    }

    group('Home Screen Initialization and Layout', () {
      testWidgets('should display marine navigation dashboard', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Welcome to NavTool'), findsOneWidget);
        expect(find.text('Marine Navigation and Routing Application'), findsOneWidget);
        expect(find.byType(AppIcon), findsAtLeastNWidgets(1));
      });

      testWidgets('should display GPS status widget', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(GpsStatusWidget), findsOneWidget);
      });

      testWidgets('should display navigation buttons on home', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('New Chart'), findsOneWidget);
        expect(find.text('Open Chart'), findsOneWidget);
      });

      testWidgets('should display marine dashboard layout correctly', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Check for key marine navigation elements
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);
        expect(find.byIcon(Icons.folder_open), findsOneWidget);
      });
    });

    group('Navigation from Home to Other Features', () {
      testWidgets('should navigate to charts when New Chart button tapped', (WidgetTester tester) async {
        // Arrange
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gpsServiceProvider.overrideWithValue(mockGpsService),
              loggerProvider.overrideWithValue(mockLogger),
            ],
            child: MaterialApp(
              home: const HomeScreen(),
              routes: {
                '/chart': (context) => const Scaffold(body: Text('Chart Screen')),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Act
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('Chart Screen'), findsOneWidget);
      });

      testWidgets('should navigate to charts when Open Chart button tapped', (WidgetTester tester) async {
        // Arrange
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gpsServiceProvider.overrideWithValue(mockGpsService),
              loggerProvider.overrideWithValue(mockLogger),
            ],
            child: MaterialApp(
              home: const HomeScreen(),
              routes: {
                '/chart': (context) => const Scaffold(body: Text('Chart Screen')),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Act
        await tester.tap(find.text('Open Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('Chart Screen'), findsOneWidget);
      });

      testWidgets('should navigate to about screen from drawer', (WidgetTester tester) async {
        // Set small screen size to show mobile layout with drawer
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Arrange
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gpsServiceProvider.overrideWithValue(mockGpsService),
              loggerProvider.overrideWithValue(mockLogger),
            ],
            child: MaterialApp(
              home: const HomeScreen(),
              routes: {
                '/about': (context) => const Scaffold(body: Text('About Screen')),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Act - Open drawer and tap About
        await tester.tap(find.byType(DrawerButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('About Screen'), findsOneWidget);
      });
    });

    group('Home Screen State Management', () {
      testWidgets('should handle GPS status changes', (WidgetTester tester) async {
        // Arrange - Mock GPS enabled initially
        when(mockGpsService.isLocationServiceEnabled()).thenAnswer((_) async => true);
        when(mockGpsService.hasLocationPermission()).thenAnswer((_) async => true);
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - GPS status widget should be present
        expect(find.byType(GpsStatusWidget), findsOneWidget);
        
        // Act - Change GPS status
        when(mockGpsService.isLocationServiceEnabled()).thenAnswer((_) async => false);
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - GPS status widget should still be present (handles state change)
        expect(find.byType(GpsStatusWidget), findsOneWidget);
      });

      testWidgets('should maintain state during screen rebuilds', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Trigger rebuild
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - All elements should still be present
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Welcome to NavTool'), findsOneWidget);
        expect(find.byType(GpsStatusWidget), findsOneWidget);
      });
    });

    group('Quick Action Buttons Functionality', () {
      testWidgets('should handle New Chart button functionality', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        final newChartButton = find.text('New Chart');
        expect(newChartButton, findsOneWidget);
        
        // Assert button is enabled and visible
        final button = tester.widget<ElevatedButton>(find.ancestor(
          of: newChartButton,
          matching: find.byType(ElevatedButton),
        ));
        expect(button.onPressed, isNotNull);
      });

      testWidgets('should handle Open Chart button functionality', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        final openChartButton = find.text('Open Chart');
        expect(openChartButton, findsOneWidget);
        
        // Assert button is enabled and visible
        final button = tester.widget<OutlinedButton>(find.ancestor(
          of: openChartButton,
          matching: find.byType(OutlinedButton),
        ));
        expect(button.onPressed, isNotNull);
      });
    });

    group('Home Screen Responsiveness', () {
      testWidgets('should adapt to desktop layout on large screens', (WidgetTester tester) async {
        // Arrange - Set large screen size
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should show desktop layout (no drawer button)
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(DrawerButton), findsNothing);
        expect(find.text('Welcome to NavTool'), findsOneWidget);
      });

      testWidgets('should adapt to mobile layout on small screens', (WidgetTester tester) async {
        // Arrange - Set small screen size
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should show mobile layout with drawer
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(DrawerButton), findsOneWidget);
        expect(find.text('Welcome to NavTool'), findsOneWidget);
      });

      testWidgets('should handle orientation changes gracefully', (WidgetTester tester) async {
        // Arrange - Start with portrait
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Act - Change to landscape
        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should still function correctly
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Welcome to NavTool'), findsOneWidget);
        
        // Cleanup
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      });
    });

    group('Chart Summary Information', () {
      testWidgets('should display application status information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should show status information on desktop layout
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Look for status information
        expect(find.byIcon(Icons.info_outline), findsWidgets);
      });

      testWidgets('should show GPS integration status', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(GpsStatusWidget), findsOneWidget);
      });
    });

    group('Marine Navigation Context', () {
      testWidgets('should display marine-specific branding and context', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('NavTool'), findsAtLeastNWidgets(1));
        expect(find.text('Marine Navigation and Routing Application'), findsOneWidget);
        expect(find.byType(AppIcon), findsAtLeastNWidgets(1));
      });

      testWidgets('should provide clear navigation entry points', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should have clear entry points to main features
        expect(find.text('New Chart'), findsOneWidget);
        expect(find.text('Open Chart'), findsOneWidget);
      });
    });
  });
}