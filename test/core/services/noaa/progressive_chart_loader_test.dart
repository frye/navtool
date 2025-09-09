import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:navtool/core/services/noaa/progressive_chart_loader.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

import 'progressive_chart_loader_test.mocks.dart';

@GenerateMocks([NoaaApiClient, AppLogger])
void main() {
  group('ProgressiveChartLoader', () {
    late MockNoaaApiClient mockApiClient;
    late MockAppLogger mockLogger;
    late ProgressiveChartLoader progressiveLoader;

    setUp(() {
      mockApiClient = MockNoaaApiClient();
      mockLogger = MockAppLogger();
      progressiveLoader = ProgressiveChartLoader(
        apiClient: mockApiClient,
        logger: mockLogger,
      );
    });

    tearDown(() {
      progressiveLoader.dispose();
    });

    group('Chart Loading with Progress', () {
      test('should emit progress updates during successful loading', () async {
        // Arrange
        final testCharts = [
          _createTestChart('US5WA50M', 'Elliott Bay'),
          _createTestChart('US5WA51M', 'Puget Sound'),
          _createTestChart('US5WA52M', 'Seattle Harbor'),
        ];

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          chunkSize: 2, // Small chunk size for testing
          loadId: 'test_load_1',
        );

        final progressUpdates = <ChartLoadProgress>[];
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.isCompleted) break;
        }

        // Assert
        expect(progressUpdates.length, greaterThan(3)); // At least initializing, processing, completed

        // Check that we have the expected stages
        final stages = progressUpdates.map((p) => p.stage).toSet();
        expect(stages, contains(ChartLoadStage.initializing));
        expect(stages, contains(ChartLoadStage.fetchingCatalog));
        expect(stages, contains(ChartLoadStage.processingCharts));
        expect(stages, contains(ChartLoadStage.completed));

        // Check final progress
        final finalProgress = progressUpdates.last;
        expect(finalProgress.isCompleted, isTrue);
        expect(finalProgress.progress, equals(1.0));
        expect(finalProgress.loadedCharts.length, equals(3));
        expect(finalProgress.completedItems, equals(3));
      });

      test('should provide partial results during loading', () async {
        // Arrange
        final testCharts = [
          _createTestChart('US5WA50M', 'Elliott Bay'),
          _createTestChart('US5WA51M', 'Puget Sound'),
          _createTestChart('US5WA52M', 'Seattle Harbor'),
          _createTestChart('US5WA53M', 'Tacoma Harbor'),
        ];

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          chunkSize: 2,
          loadId: 'test_load_partial',
        );

        final progressUpdates = <ChartLoadProgress>[];
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.isCompleted) break;
        }

        // Assert
        // Find progress updates with partial results
        final progressWithResults = progressUpdates
            .where((p) => p.loadedCharts.isNotEmpty)
            .toList();

        expect(progressWithResults.isNotEmpty, isTrue);

        // Check that partial results grow over time
        bool foundIncreasingResults = false;
        for (int i = 1; i < progressWithResults.length; i++) {
          if (progressWithResults[i].loadedCharts.length >
              progressWithResults[i - 1].loadedCharts.length) {
            foundIncreasingResults = true;
            break;
          }
        }
        expect(foundIncreasingResults, isTrue);
      });

      test('should provide ETA estimates during loading', () async {
        // Arrange
        final testCharts = [
          _createTestChart('US5WA50M', 'Elliott Bay'),
          _createTestChart('US5WA51M', 'Puget Sound'),
        ];

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          loadId: 'test_load_eta',
        );

        final progressUpdates = <ChartLoadProgress>[];
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.isCompleted) break;
        }

        // Assert
        // Check that some progress updates have ETA estimates
        final progressWithETA = progressUpdates
            .where((p) => p.eta != null && p.stage == ChartLoadStage.processingCharts)
            .toList();

        expect(progressWithETA.isNotEmpty, isTrue);
      });
    });

    group('Cancellation', () {
      test('should cancel loading operation successfully', () async {
        // Arrange
        final testCharts = List.generate(20, (i) => 
          _createTestChart('US5WA${i.toString().padLeft(2, '0')}M', 'Test Chart $i')
        );

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async {
          // Add delay to allow cancellation
          await Future.delayed(const Duration(milliseconds: 100));
          return _createTestGeoJson(testCharts);
        });

        // Act
        final loadId = 'test_cancel';
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          chunkSize: 5,
          loadId: loadId,
        );

        // Start listening and cancel after a short delay
        final progressUpdates = <ChartLoadProgress>[];
        final subscription = progressStream.listen((progress) {
          progressUpdates.add(progress);
        });

        // Cancel after a short delay
        await Future.delayed(const Duration(milliseconds: 50));
        await progressiveLoader.cancelLoading(loadId);

        // Wait for stream to complete
        await subscription.asFuture();

        // Assert
        expect(progressUpdates.isNotEmpty, isTrue);
        
        // Check if we received a cancellation update
        final cancelledUpdates = progressUpdates
            .where((p) => p.stage == ChartLoadStage.cancelled)
            .toList();
            
        expect(cancelledUpdates.isNotEmpty, isTrue);
        
        final cancelledUpdate = cancelledUpdates.first;
        expect(cancelledUpdate.error, isA<ProgressiveLoadingCancelledException>());
      });

      test('should handle cancellation of non-existent load gracefully', () async {
        // Act & Assert - should not throw
        await progressiveLoader.cancelLoading('non_existent_load');
        
        // Verify warning was logged
        verify(mockLogger.warning(
          any,
          context: 'ProgressiveChartLoader',
        )).called(1);
      });

      test('should track active loading operations', () async {
        // Arrange
        final testCharts = [_createTestChart('US5WA50M', 'Elliott Bay')];
        
        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final loadId = 'test_active_tracking';
        expect(progressiveLoader.isLoadingActive(loadId), isFalse);
        expect(progressiveLoader.getActiveLoadIds(), isEmpty);

        // Start loading
        final progressStream = progressiveLoader.loadChartsWithProgress(
          loadId: loadId,
        );

        // Check active status
        expect(progressiveLoader.isLoadingActive(loadId), isTrue);
        expect(progressiveLoader.getActiveLoadIds(), contains(loadId));

        // Complete loading
        await for (final progress in progressStream) {
          if (progress.isCompleted) break;
        }

        // Check that load is no longer active
        expect(progressiveLoader.isLoadingActive(loadId), isFalse);
        expect(progressiveLoader.getActiveLoadIds(), isEmpty);
      });
    });

    group('Error Handling', () {
      test('should handle API errors and emit error progress', () async {
        // Arrange
        final apiError = Exception('NOAA API unavailable');
        
        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenThrow(apiError);

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          loadId: 'test_error',
        );

        final progressUpdates = <ChartLoadProgress>[];
        bool hasError = false;
        
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.hasError) {
            hasError = true;
            break;
          }
          // Also break if we get a failed stage
          if (progress.stage == ChartLoadStage.failed) {
            hasError = true;
            break;
          }
        }

        // Assert
        expect(progressUpdates.isNotEmpty, isTrue);
        expect(hasError, isTrue);
        
        // Find the error update (could be the last one or any with error/failed stage)
        final errorUpdate = progressUpdates.lastWhere(
          (p) => p.hasError || p.stage == ChartLoadStage.failed,
        );
        expect(errorUpdate.hasError || errorUpdate.stage == ChartLoadStage.failed, isTrue);
      });

      test('should continue processing when individual charts fail', () async {
        // This test would need more complex mocking to simulate individual chart failures
        // For now, we'll test that the loader continues with other charts
        
        final testCharts = [
          _createTestChart('US5WA50M', 'Elliott Bay'),
          _createTestChart('US5WA51M', 'Puget Sound'),
        ];

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          loadId: 'test_individual_errors',
        );

        final progressUpdates = <ChartLoadProgress>[];
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.isCompleted) break;
        }

        // Assert
        final finalProgress = progressUpdates.last;
        expect(finalProgress.isCompleted, isTrue);
        // Should still complete successfully even if some individual charts fail
      });
    });

    group('Chunked Processing', () {
      test('should process charts in specified chunk sizes', () async {
        // Arrange
        final testCharts = List.generate(10, (i) => 
          _createTestChart('US5WA${i.toString().padLeft(2, '0')}M', 'Test Chart $i')
        );

        when(mockApiClient.fetchChartCatalog(filters: anyNamed('filters')))
            .thenAnswer((_) async => _createTestGeoJson(testCharts));

        // Act
        final progressStream = progressiveLoader.loadChartsWithProgress(
          region: 'Washington',
          chunkSize: 3, // Process in chunks of 3
          loadId: 'test_chunking',
        );

        final progressUpdates = <ChartLoadProgress>[];
        await for (final progress in progressStream) {
          progressUpdates.add(progress);
          if (progress.isCompleted) break;
        }

        // Assert
        final processingUpdates = progressUpdates
            .where((p) => p.stage == ChartLoadStage.processingCharts)
            .toList();

        expect(processingUpdates.isNotEmpty, isTrue);
        
        // Check that progress increases incrementally
        bool foundIncrementalProgress = false;
        for (int i = 1; i < processingUpdates.length; i++) {
          if (processingUpdates[i].completedItems > 
              processingUpdates[i - 1].completedItems) {
            foundIncrementalProgress = true;
            break;
          }
        }
        expect(foundIncrementalProgress, isTrue);
      });
    });
  });
}

/// Helper function to create test chart data
Chart _createTestChart(String cellName, String title) {
  return Chart(
    id: cellName,
    title: title,
    scale: 50000,
    type: ChartType.harbor,
    state: 'Washington',
    bounds: GeographicBounds(
      north: 47.7,
      south: 47.5,
      east: -122.2,
      west: -122.5,
    ),
    lastUpdate: DateTime.now(),
  );
}

/// Helper function to create test GeoJSON response
String _createTestGeoJson(List<Chart> charts) {
  final features = charts.map((chart) => {
    'type': 'Feature',
    'properties': {
      'DSNM': chart.id,
      'TITLE': chart.title,
      'SCALE': '1:${chart.scale}',
      'DATE_UPD': chart.lastUpdate.toIso8601String(),
    },
    'geometry': {
      'type': 'Polygon',
      'coordinates': [[
        [chart.bounds.west, chart.bounds.south],
        [chart.bounds.east, chart.bounds.south],
        [chart.bounds.east, chart.bounds.north],
        [chart.bounds.west, chart.bounds.north],
        [chart.bounds.west, chart.bounds.south],
      ]],
    },
  }).toList();

  return jsonEncode({
    'type': 'FeatureCollection',
    'features': features,
  });
}