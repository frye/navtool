import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/error/app_error.dart';
import 'dart:typed_data';
import 'dart:convert';

// Generate mocks
@GenerateMocks([
  CacheService,
  HttpClientService,
  StorageService,
  AppLogger,
])
import 'state_region_mapping_service_test.mocks.dart';

void main() {
  group('StateRegionMappingService Tests', () {
    late StateRegionMappingService mappingService;
    late MockCacheService mockCacheService;
    late MockHttpClientService mockHttpClient;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockCacheService = MockCacheService();
      mockHttpClient = MockHttpClientService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      
      mappingService = StateRegionMappingServiceImpl(
        cacheService: mockCacheService,
        httpClient: mockHttpClient,
        storageService: mockStorageService,
        logger: mockLogger,
      );
    });

    group('Spatial Intersection Logic', () {
      test('should compute chart cells for state using spatial intersection', () async {
        // Arrange
        const stateName = 'California';
        
        // Mock charts in storage
        final testCharts = [
          _createTestChart(
            id: 'US5CA52M',
            bounds: GeographicBounds(north: 38.0, south: 37.0, east: -122.0, west: -123.0),
          ),
          _createTestChart(
            id: 'US4CA11M', 
            bounds: GeographicBounds(north: 34.0, south: 33.0, east: -118.0, west: -119.0),
          ),
          _createTestChart(
            id: 'US4FL48M', // Florida chart - should not intersect
            bounds: GeographicBounds(north: 26.0, south: 25.0, east: -80.0, west: -81.0),
          ),
        ];

        // Mock database cache miss
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        
        // Mock memory cache miss
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        
        // Mock charts in bounds lookup
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => testCharts);
            
        // Mock storing mapping
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, hasLength(2)); // Only California charts
        expect(result, contains('US5CA52M'));
        expect(result, contains('US4CA11M'));
        expect(result, isNot(contains('US4FL48M')));
      });

      test('should calculate coverage percentage for partially overlapping charts', () async {
        // Arrange
        const stateName = 'California';
        
        // Chart that partially overlaps with California
        final partialChart = _createTestChart(
          id: 'US_PARTIAL',
          bounds: GeographicBounds(north: 42.5, south: 41.5, east: -114.0, west: -125.0),
        );

        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [partialChart]);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert - should include charts with meaningful coverage (>1%)
        expect(result, contains('US_PARTIAL'));
      });

      test('should exclude charts with minimal coverage percentage', () async {
        // Arrange
        const stateName = 'California';
        
        // Chart with minimal overlap (should have <1% coverage)
        final minimalChart = _createTestChart(
          id: 'US_MINIMAL',
          bounds: GeographicBounds(north: 32.51, south: 32.50, east: -114.0, west: -114.1),
        );

        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [minimalChart]);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert - should exclude charts with minimal coverage
        expect(result, isEmpty);
      });

      test('should handle charts spanning multiple states', () async {
        // Arrange
        const stateName = 'California';
        
        // Chart spanning California and Nevada
        final spanningChart = _createTestChart(
          id: 'US_SPANNING',
          bounds: GeographicBounds(north: 40.0, south: 36.0, east: -114.0, west: -120.0),
        );

        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [spanningChart]);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert - should include the chart as it intersects with California
        expect(result, contains('US_SPANNING'));
      });
    });

    group('State Boundary Management', () {
      test('should load state boundary data from assets or API', () async {
        // Arrange
        const stateName = 'California';
        when(mockCacheService.get(any)).thenAnswer((_) async => null);

        // Act
        final bounds = await mappingService.getStateBounds(stateName);

        // Assert
        expect(bounds, isNotNull);
        expect(bounds!.north, equals(42.0));
        expect(bounds.south, equals(32.5));
        expect(bounds.east, equals(-114.1));
        expect(bounds.west, equals(-124.4));
      });

      test('should cache state boundary data', () async {
        // Arrange
        const stateName = 'California';
        when(mockCacheService.get(any)).thenAnswer((_) async => null);

        // Act
        await mappingService.getStateBounds(stateName);

        // Assert
        verify(mockCacheService.store(
          'state_bounds_$stateName',
          any,
          maxAge: const Duration(hours: 24),
        )).called(1);
      });

      test('should return cached state boundary data when available', () async {
        // Arrange
        const stateName = 'California';
        final cachedBounds = {
          'north': 42.0,
          'south': 32.5,
          'east': -114.1,
          'west': -124.4,
        };
        final encodedData = jsonEncode(cachedBounds);
        final cachedBytes = Uint8List.fromList(utf8.encode(encodedData));
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => cachedBytes);

        // Act
        final bounds = await mappingService.getStateBounds(stateName);

        // Assert
        expect(bounds, isNotNull);
        expect(bounds!.north, equals(42.0));
        verify(mockCacheService.get('state_bounds_$stateName')).called(1);
        verifyNever(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')));
      });

      test('should return null for unsupported states', () async {
        // Arrange
        const stateName = 'Nebraska'; // Inland state
        when(mockCacheService.get(any)).thenAnswer((_) async => null);

        // Act
        final bounds = await mappingService.getStateBounds(stateName);

        // Assert
        expect(bounds, isNull);
      });
    });

    group('Database Persistence', () {
      test('should persist computed state-chart mappings to database', () async {
        // Arrange
        const stateName = 'California';
        final chartCells = ['US5CA52M', 'US4CA11M'];
        
        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [
              _createTestChart(id: 'US5CA52M'),
              _createTestChart(id: 'US4CA11M'),
            ]);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, equals(chartCells));
        verify(mockStorageService.storeStateCellMapping(stateName, chartCells)).called(1);
      });

      test('should load cached mappings from database when available', () async {
        // Arrange
        const stateName = 'California';
        final cachedCells = ['US5CA52M', 'US4CA11M'];
        
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => cachedCells);

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, equals(cachedCells));
        verify(mockStorageService.getStateCellMapping(stateName)).called(1);
        verifyNever(mockStorageService.getChartsInBounds(any));
      });

      test('should update existing mappings when refreshed', () async {
        // Arrange
        const stateName = 'California';
        final newMapping = ['US5CA52M', 'US4CA11M', 'US3CA99M'];

        // Act
        await mappingService.updateStateCellMapping(stateName, newMapping);

        // Assert
        verify(mockStorageService.storeStateCellMapping(stateName, newMapping)).called(1);
        verify(mockCacheService.store(
          'state_cells_$stateName',
          any,
          maxAge: const Duration(hours: 24),
        )).called(1);
      });

      test('should clear all state mappings from database and cache', () async {
        // Mock methods
        when(mockStorageService.clearAllStateCellMappings())
            .thenAnswer((_) async {});
        when(mockCacheService.clear()).thenAnswer((_) async => true);

        // Act
        await mappingService.clearStateMappings();

        // Assert
        verify(mockStorageService.clearAllStateCellMappings()).called(1);
        verify(mockCacheService.clear()).called(1);
      });
    });

    group('Performance and Caching', () {
      test('should return cached results for repeated state queries', () async {
        // Arrange
        const stateName = 'California';
        final cachedCells = ['US5CA52M', 'US4CA11M'];
        final encodedData = jsonEncode(cachedCells);
        final cachedBytes = Uint8List.fromList(utf8.encode(encodedData));
        
        // Mock database cache miss, but memory cache hit
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get('state_cells_$stateName'))
            .thenAnswer((_) async => cachedBytes);

        // Act
        final result1 = await mappingService.getChartCellsForState(stateName);
        final result2 = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result1, equals(cachedCells));
        expect(result2, equals(cachedCells));
        verify(mockCacheService.get('state_cells_$stateName')).called(2);
        verifyNever(mockStorageService.getChartsInBounds(any));
      });

      test('should compute and cache results for uncached state queries', () async {
        // Arrange
        const stateName = 'Florida';
        final floridaChart = _createTestChart(
          id: 'US4FL48M',
          bounds: GeographicBounds(
            north: 25.8,  // Florida Keys area
            south: 25.0,
            east: -80.0,
            west: -81.0,
          ),
        );
        final testCharts = [floridaChart];
        
        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => testCharts);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, contains('US4FL48M'));
        verify(mockStorageService.getChartsInBounds(any)).called(1);
        verify(mockStorageService.storeStateCellMapping(stateName, any)).called(1);
        verify(mockCacheService.store(
          'state_cells_$stateName',
          any,
          maxAge: const Duration(hours: 24),
        )).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle storage service errors gracefully', () async {
        // Arrange
        const stateName = 'California';
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);
        when(mockStorageService.getChartsInBounds(any))
            .thenThrow(Exception('Database error'));

        // Act & Assert
        expect(
          () => mappingService.getChartCellsForState(stateName),
          throwsA(isA<AppError>()),
        );
      });

      test('should handle cache service errors gracefully', () async {
        // Arrange
        const stateName = 'California';
        
        // Mock database miss and cache error
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenThrow(Exception('Cache error'));
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [_createTestChart(id: 'US5CA52M')]);
        when(mockStorageService.storeStateCellMapping(any, any))
            .thenAnswer((_) async {});
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert - should still work without cache
        expect(result, contains('US5CA52M'));
      });

      test('should throw StateNotSupportedException for invalid states', () async {
        // Arrange
        const stateName = 'InvalidState';
        
        // Mock database and cache misses
        when(mockStorageService.getStateCellMapping(stateName))
            .thenAnswer((_) async => null);
        when(mockCacheService.get(any)).thenAnswer((_) async => null);

        // Act & Assert
        expect(
          () => mappingService.getChartCellsForState(stateName),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Supported States', () {
      test('should return all US coastal and Great Lakes states', () async {
        // Arrange
        when(mockCacheService.get(any)).thenAnswer((_) async => null);

        // Act
        final states = await mappingService.getSupportedStates();

        // Assert
        expect(states, contains('California'));
        expect(states, contains('Florida'));
        expect(states, contains('Texas'));
        expect(states, contains('Washington'));
        expect(states, contains('Alaska'));
        expect(states, contains('Hawaii'));
        expect(states, contains('Maine'));
        expect(states, contains('Massachusetts'));
        expect(states, contains('New York'));
        expect(states, contains('North Carolina'));
        expect(states, contains('South Carolina'));
        expect(states, contains('Georgia'));
        expect(states, contains('Louisiana'));
        expect(states, contains('Oregon'));
        
        // Should not contain inland states
        expect(states, isNot(contains('Nebraska')));
        expect(states, isNot(contains('Nevada')));
      });
    });
  });
}

// Helper functions
Chart _createTestChart({
  String? id,
  GeographicBounds? bounds,
}) {
  return Chart(
    id: id ?? 'US5CA52M',
    title: 'Test Chart ${id ?? 'Default'}',
    scale: 25000,
    bounds: bounds ?? GeographicBounds(
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

/// Custom exception for unsupported states
class StateNotSupportedException implements Exception {
  final String message;
  StateNotSupportedException(this.message);
  
  @override
  String toString() => 'StateNotSupportedException: $message';
}