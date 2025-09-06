import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/services/storage_service.dart';
import '../../../helpers/noaa_test_utils.dart';

// Generate mocks for dependencies
@GenerateMocks([
  ChartCatalogService,
  StateRegionMappingService,
  AppLogger,
  StorageService,
])
import 'noaa_chart_discovery_service_test.mocks.dart';

void main() {
  group('NoaaChartDiscoveryService Tests', () {
    late NoaaChartDiscoveryServiceImpl discoveryService;
    late MockChartCatalogService mockCatalogService;
    late MockStateRegionMappingService mockMappingService;
    late MockAppLogger mockLogger;
    late MockStorageService mockStorageService;

    setUp(() {
      mockCatalogService = MockChartCatalogService();
      mockMappingService = MockStateRegionMappingService();
      mockLogger = MockAppLogger();
      mockStorageService = MockStorageService();

      discoveryService = createDiscoveryService(
        catalogService: mockCatalogService,
        mappingService: mockMappingService,
        storageService: mockStorageService,
        logger: mockLogger,
      );
    });

    group('discoverChartsByState', () {
      test('should return charts for valid state', () async {
        // Arrange
        const stateName = 'California';
        final chartCells = ['US5CA52M', 'US4CA11M'];
        final expectedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay',
            scale: 25000,
            bounds: GeographicBounds(
              north: 38.0,
              south: 37.0,
              east: -122.0,
              west: -123.0,
            ),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
          Chart(
            id: 'US4CA11M',
            title: 'Los Angeles Harbor',
            scale: 50000,
            bounds: GeographicBounds(
              north: 34.0,
              south: 33.0,
              east: -118.0,
              west: -119.0,
            ),
            lastUpdate: DateTime(2024, 1, 10),
            state: 'California',
            type: ChartType.harbor,
          ),
        ];

        // Mock bootstrap method
        when(
          mockCatalogService.ensureCatalogBootstrapped(),
        ).thenAnswer((_) async {});

        when(
          mockMappingService.getChartCellsForState(stateName),
        ).thenAnswer((_) async => chartCells);
        when(
          mockCatalogService.getCachedChart('US5CA52M'),
        ).thenAnswer((_) async => expectedCharts[0]);
        when(
          mockCatalogService.getCachedChart('US4CA11M'),
        ).thenAnswer((_) async => expectedCharts[1]);

        // Act
        final result = await discoveryService.discoverChartsByState(stateName);

        // Assert
        expect(result, hasLength(2));
        expect(result[0].id, equals('US5CA52M'));
        expect(result[1].id, equals('US4CA11M'));
        verify(mockMappingService.getChartCellsForState(stateName)).called(1);
        verify(mockCatalogService.getCachedChart('US5CA52M')).called(1);
        verify(mockCatalogService.getCachedChart('US4CA11M')).called(1);
      });

      test('should return empty list for state with no charts', () async {
        // Arrange
        const stateName = 'Nevada';

        // Mock bootstrap method
        when(
          mockCatalogService.ensureCatalogBootstrapped(),
        ).thenAnswer((_) async {});

        when(
          mockMappingService.getChartCellsForState(stateName),
        ).thenAnswer((_) async => <String>[]);

        // Act
        final result = await discoveryService.discoverChartsByState(stateName);

        // Assert
        expect(result, isEmpty);
        verify(mockMappingService.getChartCellsForState(stateName)).called(1);
        verifyNever(mockCatalogService.getCachedChart(any));
      });

      test('should skip charts that are not cached', () async {
        // Arrange
        const stateName = 'California';
        final chartCells = ['US5CA52M', 'US4CA11M'];
        final availableChart = Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        // Mock bootstrap method
        when(
          mockCatalogService.ensureCatalogBootstrapped(),
        ).thenAnswer((_) async {});

        when(
          mockMappingService.getChartCellsForState(stateName),
        ).thenAnswer((_) async => chartCells);
        when(
          mockCatalogService.getCachedChart('US5CA52M'),
        ).thenAnswer((_) async => availableChart);
        when(
          mockCatalogService.getCachedChart('US4CA11M'),
        ).thenAnswer((_) async => null); // Not cached

        // Act
        final result = await discoveryService.discoverChartsByState(stateName);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].id, equals('US5CA52M'));
      });

      test('should throw AppError when mapping service fails', () async {
        // Arrange
        const stateName = 'California';

        // Mock bootstrap method
        when(
          mockCatalogService.ensureCatalogBootstrapped(),
        ).thenAnswer((_) async {});

        when(
          mockMappingService.getChartCellsForState(stateName),
        ).thenThrow(AppError.storage('Failed to get chart cells'));

        // Act & Assert
        expect(
          () async => await discoveryService.discoverChartsByState(stateName),
          throwsA(isA<AppError>()),
        );
      });

      test('should validate state name input', () async {
        // Act & Assert
        expect(
          () async => await discoveryService.discoverChartsByState(''),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () async => await discoveryService.discoverChartsByState('   '),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('searchCharts', () {
      test('should search charts by query string', () async {
        // Arrange
        const query = 'San Francisco';
        final expectedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay',
            scale: 25000,
            bounds: GeographicBounds(
              north: 38.0,
              south: 37.0,
              east: -122.0,
              west: -123.0,
            ),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
        ];

        when(
          mockCatalogService.searchCharts(query),
        ).thenAnswer((_) async => expectedCharts);

        // Act
        final result = await discoveryService.searchCharts(query);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].title, contains('San Francisco'));
        verify(mockCatalogService.searchCharts(query)).called(1);
      });

      test('should search charts with filters', () async {
        // Arrange
        const query = 'harbor';
        final filters = {'type': 'harbor', 'state': 'California'};
        final expectedCharts = [
          Chart(
            id: 'US5CA52M',
            title: 'San Francisco Bay',
            scale: 25000,
            bounds: GeographicBounds(
              north: 38.0,
              south: 37.0,
              east: -122.0,
              west: -123.0,
            ),
            lastUpdate: DateTime(2024, 1, 15),
            state: 'California',
            type: ChartType.harbor,
          ),
        ];

        when(
          mockCatalogService.searchChartsWithFilters(query, filters),
        ).thenAnswer((_) async => expectedCharts);

        // Act
        final result = await discoveryService.searchCharts(
          query,
          filters: filters,
        );

        // Assert
        expect(result, hasLength(1));
        expect(result[0].type, equals(ChartType.harbor));
        verify(
          mockCatalogService.searchChartsWithFilters(query, filters),
        ).called(1);
      });

      test('should validate query input', () async {
        // Act & Assert
        expect(
          () async => await discoveryService.searchCharts(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('getChartMetadata', () {
      test('should return chart metadata for valid chart ID', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final expectedChart = Chart(
          id: chartId,
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(
          mockCatalogService.getChartById(chartId),
        ).thenAnswer((_) async => expectedChart);

        // Act
        final result = await discoveryService.getChartMetadata(chartId);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(chartId));
        expect(result.title, equals('San Francisco Bay'));
        verify(mockCatalogService.getChartById(chartId)).called(1);
      });

      test('should return null for non-existent chart ID', () async {
        // Arrange
        const chartId = 'INVALID_ID';

        when(
          mockCatalogService.getChartById(chartId),
        ).thenAnswer((_) async => null);

        // Act
        final result = await discoveryService.getChartMetadata(chartId);

        // Assert
        expect(result, isNull);
        verify(mockCatalogService.getChartById(chartId)).called(1);
      });

      test('should validate chart ID input', () async {
        // Act & Assert
        expect(
          () async => await discoveryService.getChartMetadata(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('watchChartsForState', () {
      test('should return stream of charts for state', () async {
        // Arrange
        const stateName = 'California';
        final chartCells = ['US5CA52M'];
        final expectedChart = Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 38.0,
            south: 37.0,
            east: -122.0,
            west: -123.0,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
        );

        when(
          mockMappingService.getChartCellsForState(stateName),
        ).thenAnswer((_) async => chartCells);
        when(
          mockCatalogService.getCachedChart('US5CA52M'),
        ).thenAnswer((_) async => expectedChart);

        // Act
        final stream = discoveryService.watchChartsForState(stateName);
        final result = await stream.first;

        // Assert
        expect(result, hasLength(1));
        expect(result[0].id, equals('US5CA52M'));
      });

      test('should validate state name input for stream', () {
        // Act & Assert
        expect(
          () => discoveryService.watchChartsForState(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('refreshCatalog', () {
      test('should refresh catalog without force', () async {
        // Arrange
        when(
          mockCatalogService.refreshCatalog(force: false),
        ).thenAnswer((_) async => true);

        // Act
        final result = await discoveryService.refreshCatalog();

        // Assert
        expect(result, isTrue);
        verify(mockCatalogService.refreshCatalog(force: false)).called(1);
      });

      test('should refresh catalog with force', () async {
        // Arrange
        when(
          mockCatalogService.refreshCatalog(force: true),
        ).thenAnswer((_) async => true);

        // Act
        final result = await discoveryService.refreshCatalog(force: true);

        // Assert
        expect(result, isTrue);
        verify(mockCatalogService.refreshCatalog(force: true)).called(1);
      });

      test('should handle refresh failures', () async {
        // Arrange
        when(
          mockCatalogService.refreshCatalog(force: false),
        ).thenThrow(AppError.network('Network error'));

        // Act & Assert
        expect(
          () async => await discoveryService.refreshCatalog(),
          throwsA(isA<AppError>()),
        );
      });
    });
  });
}
