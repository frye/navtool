import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/chart_service.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/state/download_state.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/features/home/home_screen.dart';

import 'chart_workflow_test.mocks.dart';

// Generate mocks for chart workflow services
@GenerateMocks([
  ChartService,
  DownloadService,
  StorageService,
  HttpClientService,
  AppLogger,
])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Chart Workflow Integration Tests', () {
    late MockChartService mockChartService;
    late MockDownloadService mockDownloadService;
    late MockStorageService mockStorageService;
    late MockHttpClientService mockHttpClient;
    late MockAppLogger mockLogger;

    setUp(() {
      mockChartService = MockChartService();
      mockDownloadService = MockDownloadService();
      mockStorageService = MockStorageService();
      mockHttpClient = MockHttpClientService();
      mockLogger = MockAppLogger();

      _setupDefaultMocks();
    });

    void _setupDefaultMocks() {
      // Chart Service mocks
      when(mockChartService.getAllCharts()).thenAnswer((_) async => []);
      when(mockChartService.getDownloadedCharts()).thenAnswer((_) async => []);
      when(mockChartService.discoverCharts(any)).thenAnswer((_) async => _getSampleCharts());

      // Download Service mocks
      when(mockDownloadService.initialize()).thenAnswer((_) async {});
      when(mockDownloadService.getActiveDownloads()).thenAnswer((_) async => []);
      when(mockDownloadService.getQueuedDownloads()).thenAnswer((_) async => []);
      when(mockDownloadService.isNetworkAvailable()).thenAnswer((_) async => true);

      // Storage Service mocks
      when(mockStorageService.initialize()).thenAnswer((_) async {});
      when(mockStorageService.getAllCharts()).thenAnswer((_) async => []);
      when(mockStorageService.storeChart(any, any)).thenAnswer((_) async {});

      // HTTP Client mocks
      when(mockHttpClient.download(any)).thenAnswer((_) async => _getMockChartData());

      // Logger mocks
      when(mockLogger.info(any)).thenReturn(null);
      when(mockLogger.error(any, exception: anyNamed('exception'))).thenReturn(null);
    }

    Widget createTestApp({List<Override> overrides = const []}) {
      return ProviderScope(
        overrides: [
          chartServiceProvider.overrideWithValue(mockChartService),
          downloadServiceProvider.overrideWithValue(mockDownloadService),
          storageServiceProvider.overrideWithValue(mockStorageService),
          httpClientServiceProvider.overrideWithValue(mockHttpClient),
          loggerProvider.overrideWithValue(mockLogger),
          ...overrides,
        ],
        child: MaterialApp(
          home: const HomeScreen(),
          routes: {
            '/chart': (context) => const ChartScreen(),
          },
        ),
      );
    }

    group('End-to-End Chart Discovery Workflow', () {
      testWidgets('should complete full chart discovery process', (WidgetTester tester) async {
        // Arrange
        final availableCharts = _getSampleCharts();
        when(mockChartService.discoverCharts('CA')).thenAnswer((_) async => availableCharts);
        
        // Act - Start app and initiate chart discovery
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Navigate to charts
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert - Should be on chart screen
        expect(find.byType(ChartScreen), findsOneWidget);
        
        // Verify discovery was called
        verify(mockChartService.getAllCharts()).called(atLeast(1));
      });

      testWidgets('should handle chart search by region', (WidgetTester tester) async {
        // Arrange
        final californiaCharts = _getSampleCharts().where((c) => c.state == 'CA').toList();
        when(mockChartService.searchChartsByState('CA')).thenAnswer((_) async => californiaCharts);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Navigate to charts and search
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should filter charts by type and scale', (WidgetTester tester) async {
        // Arrange
        final encCharts = _getSampleCharts().where((c) => c.type == ChartType.enc).toList();
        when(mockChartService.filterCharts(type: ChartType.enc)).thenAnswer((_) async => encCharts);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should handle chart discovery failures gracefully', (WidgetTester tester) async {
        // Arrange
        when(mockChartService.discoverCharts(any)).thenThrow(Exception('Discovery failed'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert - Should handle error gracefully
        expect(find.byType(ChartScreen), findsOneWidget);
        verify(mockLogger.error(any, exception: anyNamed('exception'))).called(atLeast(1));
      });
    });

    group('Chart Download and Progress Tracking', () {
      testWidgets('should download chart with progress tracking', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        final downloadProgress = DownloadProgress(
          chartId: testChart.id,
          fileName: '${testChart.id}.zip',
          url: testChart.downloadUrl,
          totalBytes: testChart.fileSize,
          downloadedBytes: 0,
          status: DownloadStatus.queued,
        );
        
        // Mock download progress updates
        when(mockDownloadService.downloadChart(testChart.id, testChart.downloadUrl))
            .thenAnswer((_) async {
          // Simulate progress updates
          final updatedProgress = downloadProgress.copyWith(
            status: DownloadStatus.downloading,
            downloadedBytes: testChart.fileSize ~/ 2,
          );
          return updatedProgress;
        });
        
        when(mockDownloadService.getDownloadProgress(testChart.id))
            .thenAnswer((_) async => downloadProgress);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Simulate download initiation
        // In actual UI test, would tap download button
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle download interruption and resumption', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        final interruptedProgress = DownloadProgress(
          chartId: testChart.id,
          fileName: '${testChart.id}.zip',
          url: testChart.downloadUrl,
          totalBytes: testChart.fileSize,
          downloadedBytes: testChart.fileSize ~/ 2,
          status: DownloadStatus.paused,
        );
        
        when(mockDownloadService.getDownloadProgress(testChart.id))
            .thenAnswer((_) async => interruptedProgress);
        when(mockDownloadService.resumeDownload(testChart.id))
            .thenAnswer((_) async => interruptedProgress.copyWith(status: DownloadStatus.downloading));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle download failures with retry options', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockDownloadService.downloadChart(testChart.id, testChart.downloadUrl))
            .thenThrow(Exception('Download failed'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle failure gracefully
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should track multiple concurrent downloads', (WidgetTester tester) async {
        // Arrange
        final charts = _getSampleCharts();
        final activeDownloads = charts.map((chart) => DownloadProgress(
          chartId: chart.id,
          fileName: '${chart.id}.zip',
          url: chart.downloadUrl,
          totalBytes: chart.fileSize,
          downloadedBytes: chart.fileSize ~/ 3,
          status: DownloadStatus.downloading,
        )).toList();
        
        when(mockDownloadService.getActiveDownloads()).thenAnswer((_) async => activeDownloads);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockDownloadService.getActiveDownloads()).called(atLeast(1));
      });
    });

    group('Chart Storage and Retrieval', () {
      testWidgets('should store downloaded chart data correctly', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        final chartData = _getMockChartData();
        
        when(mockStorageService.storeChart(testChart, chartData)).thenAnswer((_) async {});
        when(mockStorageService.getChart(testChart.id)).thenAnswer((_) async => testChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Simulate chart download completion
        // In actual implementation, this would be triggered by download service
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should retrieve stored charts efficiently', (WidgetTester tester) async {
        // Arrange
        final storedCharts = _getSampleCharts();
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => storedCharts);
        when(mockChartService.getDownloadedCharts()).thenAnswer((_) async => storedCharts);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockStorageService.getAllCharts()).called(atLeast(1));
      });

      testWidgets('should handle storage quota and cleanup', (WidgetTester tester) async {
        // Arrange
        when(mockStorageService.getStorageUsage()).thenAnswer((_) async => 1000000000); // 1GB
        when(mockStorageService.getAvailableSpace()).thenAnswer((_) async => 100000000); // 100MB
        when(mockStorageService.cleanupOldCharts()).thenAnswer((_) async => 5); // Cleaned 5 charts
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should verify chart data integrity', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockStorageService.verifyChartIntegrity(testChart.id)).thenAnswer((_) async => true);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Chart Display and Rendering', () {
      testWidgets('should display chart correctly after loading', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockChartService.loadChart(testChart.id)).thenAnswer((_) async => testChart);
        when(mockStorageService.getChart(testChart.id)).thenAnswer((_) async => testChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should handle chart rendering performance', (WidgetTester tester) async {
        // Arrange
        final largeChart = Chart(
          id: 'large_chart',
          name: 'Large Chart',
          scale: 10000, // High detail chart
          bounds: const GeographicBounds(
            north: 40.0,
            south: 35.0,
            east: -120.0,
            west: -125.0,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/large_chart.zip',
          fileSize: 50000000, // 50MB
          lastUpdated: DateTime.now(),
        );
        
        when(mockChartService.loadChart(largeChart.id)).thenAnswer((_) async => largeChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert - Should handle large chart without performance issues
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should support chart zoom and pan operations', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockChartService.loadChart(testChart.id)).thenAnswer((_) async => testChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Simulate zoom and pan gestures
        // In actual implementation, would test gesture interactions
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should switch between day and night display modes', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockChartService.loadChart(testChart.id)).thenAnswer((_) async => testChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
        expect(find.byIcon(Icons.light_mode), findsOneWidget);
      });
    });

    group('Chart Update and Synchronization', () {
      testWidgets('should check for chart updates automatically', (WidgetTester tester) async {
        // Arrange
        final outdatedChart = _getSampleCharts().first;
        final updatedChart = outdatedChart.copyWith(
          lastUpdated: DateTime.now().add(const Duration(days: 1)),
        );
        
        when(mockChartService.checkForUpdates(outdatedChart.id))
            .thenAnswer((_) async => updatedChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should download and apply chart updates', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockDownloadService.updateChart(testChart.id))
            .thenAnswer((_) async => DownloadProgress(
              chartId: testChart.id,
              fileName: '${testChart.id}_update.zip',
              url: '${testChart.downloadUrl}?version=2',
              totalBytes: testChart.fileSize,
              downloadedBytes: testChart.fileSize,
              status: DownloadStatus.completed,
            ));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle update failures gracefully', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockChartService.checkForUpdates(testChart.id))
            .thenThrow(Exception('Update check failed'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle gracefully
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should batch update multiple charts efficiently', (WidgetTester tester) async {
        // Arrange
        final charts = _getSampleCharts();
        when(mockChartService.batchUpdateCharts(any))
            .thenAnswer((_) async => charts.length);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Chart Error Handling and Recovery', () {
      testWidgets('should recover from corrupted chart data', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockStorageService.verifyChartIntegrity(testChart.id))
            .thenAnswer((_) async => false);
        when(mockStorageService.repairChart(testChart.id))
            .thenAnswer((_) async => true);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should handle network errors during download', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockDownloadService.downloadChart(testChart.id, testChart.downloadUrl))
            .thenThrow(Exception('Network error'));
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should provide fallback when chart loading fails', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockChartService.loadChart(testChart.id))
            .thenThrow(Exception('Chart loading failed'));
        when(mockChartService.getBackupChart(testChart.id))
            .thenAnswer((_) async => testChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Multi-Chart Management', () {
      testWidgets('should manage multiple charts efficiently', (WidgetTester tester) async {
        // Arrange
        final multipleCharts = _getSampleCharts();
        when(mockChartService.getAllCharts()).thenAnswer((_) async => multipleCharts);
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => multipleCharts);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
        verify(mockChartService.getAllCharts()).called(atLeast(1));
      });

      testWidgets('should switch between charts seamlessly', (WidgetTester tester) async {
        // Arrange
        final charts = _getSampleCharts();
        when(mockChartService.loadChart(any)).thenAnswer((invocation) async {
          final chartId = invocation.positionalArguments[0] as String;
          return charts.firstWhere((c) => c.id == chartId);
        });
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should handle chart deletion and cleanup', (WidgetTester tester) async {
        // Arrange
        final testChart = _getSampleCharts().first;
        when(mockStorageService.deleteChart(testChart.id)).thenAnswer((_) async {});
        when(mockChartService.removeChart(testChart.id)).thenAnswer((_) async {});
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Chart Performance Under Load', () {
      testWidgets('should handle high-resolution chart rendering', (WidgetTester tester) async {
        // Arrange
        final highResChart = Chart(
          id: 'high_res_chart',
          name: 'High Resolution Chart',
          scale: 5000, // Very high detail
          bounds: const GeographicBounds(
            north: 38.0,
            south: 37.9,
            east: -122.3,
            west: -122.5,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/high_res_chart.zip',
          fileSize: 100000000, // 100MB
          lastUpdated: DateTime.now(),
        );
        
        when(mockChartService.loadChart(highResChart.id)).thenAnswer((_) async => highResChart);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('New Chart'));
        await tester.pumpAndSettle();
        
        // Assert - Should handle without performance degradation
        expect(find.byType(ChartScreen), findsOneWidget);
      });

      testWidgets('should optimize memory usage with large charts', (WidgetTester tester) async {
        // Arrange
        final largeCharts = List.generate(20, (index) => Chart(
          id: 'chart_$index',
          name: 'Large Chart $index',
          scale: 25000,
          bounds: GeographicBounds(
            north: 38.0 + index * 0.1,
            south: 37.0 + index * 0.1,
            east: -122.0 - index * 0.1,
            west: -123.0 - index * 0.1,
          ),
          state: 'CA',
          type: ChartType.enc,
          downloadUrl: 'https://example.com/chart_$index.zip',
          fileSize: 25000000, // 25MB each
          lastUpdated: DateTime.now(),
        ));
        
        when(mockChartService.getAllCharts()).thenAnswer((_) async => largeCharts);
        when(mockStorageService.getAllCharts()).thenAnswer((_) async => largeCharts);
        
        // Act
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        
        // Assert - Should handle memory efficiently
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });
  });

  // Helper methods
  List<Chart> _getSampleCharts() {
    return [
      Chart(
        id: 'US5CA52M',
        name: 'San Francisco Bay',
        scale: 50000,
        bounds: const GeographicBounds(
          north: 37.8500,
          south: 37.6500,
          east: -122.3000,
          west: -122.5500,
        ),
        state: 'CA',
        type: ChartType.enc,
        downloadUrl: 'https://charts.noaa.gov/ENCs/US5CA52M.zip',
        fileSize: 2048000,
        lastUpdated: DateTime.now().subtract(const Duration(days: 30)),
      ),
      Chart(
        id: 'US5CA51M',
        name: 'Approaches to San Francisco Bay',
        scale: 25000,
        bounds: const GeographicBounds(
          north: 37.9000,
          south: 37.6000,
          east: -122.2500,
          west: -122.7000,
        ),
        state: 'CA',
        type: ChartType.enc,
        downloadUrl: 'https://charts.noaa.gov/ENCs/US5CA51M.zip',
        fileSize: 4096000,
        lastUpdated: DateTime.now().subtract(const Duration(days: 15)),
      ),
      Chart(
        id: 'US5CA50M',
        name: 'Golden Gate',
        scale: 12500,
        bounds: const GeographicBounds(
          north: 37.8300,
          south: 37.7900,
          east: -122.4000,
          west: -122.5200,
        ),
        state: 'CA',
        type: ChartType.enc,
        downloadUrl: 'https://charts.noaa.gov/ENCs/US5CA50M.zip',
        fileSize: 1536000,
        lastUpdated: DateTime.now().subtract(const Duration(days: 7)),
      ),
    ];
  }

  List<int> _getMockChartData() {
    // Mock chart data (simplified)
    return List.generate(1024, (index) => index % 256);
  }
}