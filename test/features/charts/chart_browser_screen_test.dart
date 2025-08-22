import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';

// Generate mocks for dependencies
@GenerateMocks([NoaaChartDiscoveryService, AppLogger])
import 'chart_browser_screen_test.mocks.dart';

void main() {
  group('ChartBrowserScreen Tests', () {
    late MockNoaaChartDiscoveryService mockDiscoveryService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockDiscoveryService = MockNoaaChartDiscoveryService();
      mockLogger = MockAppLogger();
    });

    Widget createTestWidget({bool withNavigation = false}) {
      return ProviderScope(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWithValue(mockDiscoveryService),
          loggerProvider.overrideWithValue(mockLogger),
        ],
        child: MaterialApp(
          home: const ChartBrowserScreen(),
          routes: withNavigation ? {
            '/chart': (context) => const Scaffold(body: Text('Chart Display')),
          } : null,
        ),
      );
    }

    List<Chart> createTestCharts() {
      return [
        Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 37.9,
            south: 37.7,
            east: -122.3,
            west: -122.5,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
          description: 'Detailed harbor chart of San Francisco Bay',
          fileSize: 15728640, // 15MB
        ),
        Chart(
          id: 'US4CA11M',
          title: 'Monterey Bay',
          scale: 50000,
          bounds: GeographicBounds(
            north: 36.8,
            south: 36.5,
            east: -121.7,
            west: -122.1,
          ),
          lastUpdate: DateTime(2024, 1, 10),
          state: 'California',
          type: ChartType.coastal,
          description: 'Coastal chart covering Monterey Bay area',
          fileSize: 23068672, // 22MB
        ),
      ];
    }

    group('Screen Structure and Layout', () {
      testWidgets('should create ChartBrowserScreen with all required components', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ChartBrowserScreen), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Chart Browser'), findsOneWidget);
      });

      testWidgets('should have state selection dropdown', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        expect(find.text('Select State'), findsOneWidget);
      });

      testWidgets('should have search field', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(TextField), findsAtLeastNWidgets(1));
        expect(find.text('Search charts...'), findsOneWidget);
      });

      testWidgets('should have chart type filter chips', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(FilterChip), findsAtLeastNWidgets(3));
        expect(find.text('Harbor'), findsOneWidget);
        expect(find.text('Coastal'), findsOneWidget);
        expect(find.text('Approach'), findsOneWidget);
      });
    });

    group('State Selection Functionality', () {
      testWidgets('should display US coastal states in dropdown', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap dropdown to open it
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('California'), findsOneWidget);
        expect(find.text('Florida'), findsOneWidget);
        expect(find.text('Washington'), findsOneWidget);
        expect(find.text('Maine'), findsOneWidget);
      });

      testWidgets('should discover charts when state is selected', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California from dropdown
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        verify(mockDiscoveryService.discoverChartsByState('California')).called(1);
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsOneWidget);
      });

      testWidgets('should show loading indicator during chart discovery', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) => Future.delayed(const Duration(seconds: 1), () => createTestCharts()));

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state to trigger loading
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pump(); // Don't settle, check loading state

        // Assert
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('should handle discovery errors gracefully', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenThrow(Exception('Network error'));

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state to trigger error
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Failed to load charts'), findsOneWidget);
        expect(find.byIcon(Icons.error), findsOneWidget);
      });
    });

    group('Chart List Display', () {
      testWidgets('should display chart cards with metadata', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Scale: 1:25,000'), findsOneWidget);
        expect(find.text('15.0 MB'), findsOneWidget);
        expect(find.text('Harbor'), findsOneWidget);
        
        expect(find.text('Monterey Bay'), findsOneWidget);
        expect(find.text('Scale: 1:50,000'), findsOneWidget);
        expect(find.text('22.0 MB'), findsOneWidget);
        expect(find.text('Coastal'), findsOneWidget);
      });

      testWidgets('should display chart bounds information', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.textContaining('37.7° - 37.9°N'), findsOneWidget);
        expect(find.textContaining('122.3° - 122.5°W'), findsOneWidget);
      });

      testWidgets('should show empty state when no charts found', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState('Nevada'))
            .thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select Nevada (inland state with no charts)
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nevada'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('No charts found'), findsOneWidget);
        expect(find.text('No charts are available for the selected state and filters.'), findsOneWidget);
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      });
    });

    group('Search and Filtering', () {
      testWidgets('should filter charts by search query', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);
        when(mockDiscoveryService.searchCharts('San Francisco', filters: anyNamed('filters')))
            .thenAnswer((_) async => [testCharts[0]]);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Search for San Francisco
        await tester.enterText(find.byType(TextField), 'San Francisco');
        await tester.pump(const Duration(milliseconds: 300)); // Debounce delay

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsNothing);
      });

      testWidgets('should filter charts by type using filter chips', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap Harbor filter chip
        await tester.tap(find.widgetWithText(FilterChip, 'Harbor'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsNothing);
      });

      testWidgets('should clear search when clear button tapped', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California and search
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'San Francisco');
        await tester.pump(const Duration(milliseconds: 300));

        // Clear search
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsOneWidget);
      });
    });

    group('Chart Selection and Actions', () {
      testWidgets('should support multi-select with checkboxes', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Select first chart
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);
      });

      testWidgets('should show download action when charts selected', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California and chart
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        // Assert
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(find.text('Download Selected'), findsOneWidget);
      });

      testWidgets('should navigate to chart display when chart tapped', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget(withNavigation: true));
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap on chart card (not checkbox)
        await tester.tap(find.text('San Francisco Bay'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Chart Display'), findsOneWidget);
      });

      testWidgets('should show chart preview dialog on info button tap', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap info button
        await tester.tap(find.byIcon(Icons.info_outline).first);
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Chart Details'), findsOneWidget);
        expect(find.text('Detailed harbor chart of San Francisco Bay'), findsOneWidget);
      });
    });

    group('Performance and Error Handling', () {
      testWidgets('should handle large chart lists efficiently', (WidgetTester tester) async {
        // Arrange
        final largeChartList = List.generate(100, (index) => Chart(
          id: 'US_TEST_$index',
          title: 'Test Chart $index',
          scale: 25000 + index * 1000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.harbor,
        ));

        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => largeChartList);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('Test Chart 0'), findsOneWidget);
        
        // Scroll to load more items
        await tester.drag(find.byType(ListView), const Offset(0, -1000));
        await tester.pumpAndSettle();
        
        expect(find.text('Test Chart 10'), findsOneWidget);
      });

      testWidgets('should debounce search input', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => createTestCharts());
        when(mockDiscoveryService.searchCharts(any, filters: anyNamed('filters')))
            .thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Type rapidly
        await tester.enterText(find.byType(TextField), 'S');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'Sa');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'San');
        await tester.pump(const Duration(milliseconds: 500)); // Wait for debounce

        // Assert
        verify(mockDiscoveryService.searchCharts('San', filters: anyNamed('filters'))).called(1);
        verifyNever(mockDiscoveryService.searchCharts('S', filters: anyNamed('filters')));
        verifyNever(mockDiscoveryService.searchCharts('Sa', filters: anyNamed('filters')));
      });
    });

    group('Accessibility', () {
      testWidgets('should have proper semantic labels', (WidgetTester tester) async {
        // Arrange
        when(mockDiscoveryService.discoverChartsByState(any)).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.bySemanticsLabel('Select a US state to browse charts'), findsOneWidget);
        expect(find.bySemanticsLabel('Search charts by name or description'), findsOneWidget);
        expect(find.bySemanticsLabel('Filter charts by type'), findsOneWidget);
      });

      testWidgets('should support keyboard navigation', (WidgetTester tester) async {
        // Arrange
        final testCharts = createTestCharts();
        when(mockDiscoveryService.discoverChartsByState('California'))
            .thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Test tab navigation through chart cards
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        // Assert - Focus should be navigable
        expect(find.byType(ChartBrowserScreen), findsOneWidget);
      });
    });
  });
}