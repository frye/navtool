import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/services/database_storage_service.dart';

// Generate mocks for dependencies
@GenerateMocks([CacheService, AppLogger, NoaaApiClient, DatabaseStorageService])
import 'chart_catalog_service_test.mocks.dart';

void main() {
  group('ChartCatalogService Tests', () {
    late ChartCatalogServiceImpl catalogService;
    late MockCacheService mockCacheService;
    late MockAppLogger mockLogger;
    late MockNoaaApiClient mockApiClient;
    late MockDatabaseStorageService mockDatabaseStorageService;

    setUp(() {
      mockCacheService = MockCacheService();
      mockLogger = MockAppLogger();
      mockApiClient = MockNoaaApiClient();
      mockDatabaseStorageService = MockDatabaseStorageService();
      
      catalogService = ChartCatalogServiceImpl(
        cacheService: mockCacheService,
        logger: mockLogger,
        noaaApiClient: mockApiClient,
        databaseStorageService: mockDatabaseStorageService,
      );
    });

    group('getCachedChart', () {
      test('should return cached chart if available', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final expectedChart = Chart(
          id: chartId,
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(mockCacheService.get('chart_$chartId'))
            .thenAnswer((_) async => Uint8List.fromList(utf8.encode(json.encode(expectedChart.toJson()))));

        // Act
        final result = await catalogService.getCachedChart(chartId);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(chartId));
        expect(result.title, equals('San Francisco Bay'));
        verify(mockCacheService.get('chart_$chartId')).called(1);
      });

      test('should return null if chart not cached', () async {
        // Arrange
        const chartId = 'US5CA52M';

        when(mockCacheService.get('chart_$chartId'))
            .thenAnswer((_) async => null);

        // Act
        final result = await catalogService.getCachedChart(chartId);

        // Assert
        expect(result, isNull);
        verify(mockCacheService.get('chart_$chartId')).called(1);
      });

      test('should handle cache service errors gracefully', () async {
        // Arrange
        const chartId = 'US5CA52M';

        when(mockCacheService.get('chart_$chartId'))
            .thenThrow(AppError.storage('Cache error'));

        // Act
        final result = await catalogService.getCachedChart(chartId);

        // Assert
        expect(result, isNull);
        verify(mockLogger.error(
          'Failed to get cached chart $chartId',
          exception: anyNamed('exception'),
        )).called(1);
      });

      test('should validate chart ID input', () async {
        // Act & Assert
        expect(
          () async => await catalogService.getCachedChart(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('cacheChart', () {
      test('should cache chart successfully', () async {
        // Arrange
        final chart = Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});
        when(mockCacheService.get('chart_list'))
            .thenAnswer((_) async => null);
        when(mockCacheService.store('chart_list', any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Act
        await catalogService.cacheChart(chart);

        // Assert
        verify(mockCacheService.store('chart_${chart.id}', any, maxAge: anyNamed('maxAge'))).called(1);
        verify(mockLogger.info('Cached chart metadata: ${chart.id}')).called(1);
      });

      test('should handle cache errors', () async {
        // Arrange
        final chart = Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenThrow(AppError.storage('Cache write error'));

        // Act & Assert
        expect(
          () async => await catalogService.cacheChart(chart),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('getChartById', () {
      test('should return chart from cache', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final expectedChart = Chart(
          id: chartId,
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(mockCacheService.get('chart_$chartId'))
            .thenAnswer((_) async => Uint8List.fromList(utf8.encode(json.encode(expectedChart.toJson()))));

        // Act
        final result = await catalogService.getChartById(chartId);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(chartId));
      });

      test('should return null for non-existent chart', () async {
        // Arrange
        const chartId = 'INVALID_ID';

        when(mockCacheService.get('chart_$chartId'))
            .thenAnswer((_) async => null);

        // Act
        final result = await catalogService.getChartById(chartId);

        // Assert
        expect(result, isNull);
      });
    });

    group('searchCharts', () {
      test('should search charts by title', () async {
        // Arrange
        const query = 'San Francisco';
        final cachedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay',
            scale: 25000,
            bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
          Chart(
            id: 'US4CA11M',
            title: 'Los Angeles Harbor',
            scale: 50000,
            bounds: GeographicBounds(north: 34.0, south: 33.0, east: -118.0, west: -119.0),
            lastUpdate: DateTime(2024, 1, 10),
            state: 'California',
            type: ChartType.harbor,
          ),
        ];

        // Mock chart list
        final chartListJson = jsonEncode(['US5CA52M', 'US4CA11M']);
        final chartListBytes = Uint8List.fromList(utf8.encode(chartListJson));
        when(mockCacheService.get('chart_list'))
            .thenAnswer((_) async => chartListBytes);
        
        // Mock individual chart retrievals
        final chart1Json = jsonEncode(cachedCharts[0].toJson());
        final chart1Bytes = Uint8List.fromList(utf8.encode(chart1Json));
        when(mockCacheService.get('chart_US5CA52M'))
            .thenAnswer((_) async => chart1Bytes);
            
        final chart2Json = jsonEncode(cachedCharts[1].toJson());
        final chart2Bytes = Uint8List.fromList(utf8.encode(chart2Json));
        when(mockCacheService.get('chart_US4CA11M'))
            .thenAnswer((_) async => chart2Bytes);

        // Act
        final result = await catalogService.searchCharts(query);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].title, contains('San Francisco'));
      });

      test('should return empty list for no matches', () async {
        // Arrange
        const query = 'NonExistent';
        final cachedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay',
            scale: 25000,
            bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
        ];

        // Mock empty chart list
        when(mockCacheService.get('chart_list'))
            .thenAnswer((_) async => null);

        // Act
        final result = await catalogService.searchCharts(query);

        // Assert
        expect(result, isEmpty);
      });
    });

    group('searchChartsWithFilters', () {
      test('should search charts with state filter', () async {
        // Arrange
        const query = 'Harbor';
        final filters = {'state': 'California'};
        final cachedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay Harbor',
            scale: 25000,
            bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
          Chart(
            id: 'US4TX11M',
            title: 'Texas Harbor',
            scale: 50000,
            bounds: GeographicBounds(north: 30.0, south: 29.0, east: -94.0, west: -95.0),
            lastUpdate: DateTime(2024, 1, 10),
            state: 'Texas',
            type: ChartType.harbor,
          ),
        ];

        // Mock chart list
        final chartListJson = jsonEncode(['US5CA52M', 'US4TX11M']);
        final chartListBytes = Uint8List.fromList(utf8.encode(chartListJson));
        when(mockCacheService.get('chart_list'))
            .thenAnswer((_) async => chartListBytes);
        
        // Mock individual chart retrievals
        final chart1Json = jsonEncode(cachedCharts[0].toJson());
        final chart1Bytes = Uint8List.fromList(utf8.encode(chart1Json));
        when(mockCacheService.get('chart_US5CA52M'))
            .thenAnswer((_) async => chart1Bytes);
            
        final chart2Json = jsonEncode(cachedCharts[1].toJson());
        final chart2Bytes = Uint8List.fromList(utf8.encode(chart2Json));
        when(mockCacheService.get('chart_US4TX11M'))
            .thenAnswer((_) async => chart2Bytes);

        // Act
        final result = await catalogService.searchChartsWithFilters(query, filters);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].state, equals('California'));
        expect(result[0].title, contains('Harbor'));
      });

      test('should search charts with type filter', () async {
        // Arrange
        const query = 'Chart';
        final filters = {'type': 'harbor'};
        final cachedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Chart',
            scale: 25000,
            bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
          Chart(
            id: 'US4CA11M',
            title: 'Los Angeles Chart',
            scale: 500000,
            bounds: GeographicBounds(north: 34.0, south: 33.0, east: -118.0, west: -119.0),
            lastUpdate: DateTime(2024, 1, 10),
            state: 'California',
            type: ChartType.general,
          ),
        ];

        // Mock chart list
        final chartListJson = jsonEncode(['US5CA52M', 'US4CA11M']);
        final chartListBytes = Uint8List.fromList(utf8.encode(chartListJson));
        when(mockCacheService.get('chart_list'))
            .thenAnswer((_) async => chartListBytes);
        
        // Mock individual chart retrievals  
        final chart1Json = jsonEncode(cachedCharts[0].toJson());
        final chart1Bytes = Uint8List.fromList(utf8.encode(chart1Json));
        when(mockCacheService.get('chart_US5CA52M'))
            .thenAnswer((_) async => chart1Bytes);
            
        final chart2Json = jsonEncode(cachedCharts[1].toJson());
        final chart2Bytes = Uint8List.fromList(utf8.encode(chart2Json));
        when(mockCacheService.get('chart_US4CA11M'))
            .thenAnswer((_) async => chart2Bytes);

        // Act
        final result = await catalogService.searchChartsWithFilters(query, filters);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].type, equals(ChartType.harbor));
      });
    });

    group('refreshCatalog', () {
      test('should refresh catalog cache', () async {
        // Arrange
        when(mockCacheService.clear())
            .thenAnswer((_) async => true);

        // Act
        final result = await catalogService.refreshCatalog();

        // Assert
        expect(result, isTrue);
        verify(mockCacheService.clear()).called(1);
        verify(mockLogger.info('Chart catalog cache refreshed')).called(1);
      });

      test('should force refresh even if not necessary', () async {
        // Arrange
        when(mockCacheService.clear())
            .thenAnswer((_) async => true);

        // Act
        final result = await catalogService.refreshCatalog(force: true);

        // Assert
        expect(result, isTrue);
        verify(mockCacheService.clear()).called(1);
      });

      test('should handle refresh errors', () async {
        // Arrange
        when(mockCacheService.clear())
            .thenThrow(AppError.storage('Cache clear error'));

        // Act & Assert
        expect(
          () async => await catalogService.refreshCatalog(),
          throwsA(isA<AppError>()),
        );
      });
    });
  });
}