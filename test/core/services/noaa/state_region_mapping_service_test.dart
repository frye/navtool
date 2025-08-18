import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';

// Generate mocks for dependencies
@GenerateMocks([CacheService, AppLogger])
import 'state_region_mapping_service_test.mocks.dart';

void main() {
  group('StateRegionMappingService Tests', () {
    late StateRegionMappingServiceImpl mappingService;
    late MockCacheService mockCacheService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockCacheService = MockCacheService();
      mockLogger = MockAppLogger();
      
      mappingService = StateRegionMappingServiceImpl(
        cacheService: mockCacheService,
        logger: mockLogger,
      );
    });

    group('getChartCellsForState', () {
      test('should return chart cells for California', () async {
        // Arrange
        const stateName = 'California';
        final expectedCells = ['US5CA52M', 'US4CA11M', 'US5CA51M'];
        
        when(mockCacheService.get('state_cells_$stateName'))
            .thenAnswer((_) async => expectedCells);

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, hasLength(3));
        expect(result, containsAll(expectedCells));
        verify(mockCacheService.get('state_cells_$stateName')).called(1);
      });

      test('should return empty list for landlocked states', () async {
        // Arrange
        const stateName = 'Nevada';
        
        when(mockCacheService.get('state_cells_$stateName'))
            .thenAnswer((_) async => <String>[]);

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, isEmpty);
      });

      test('should load and cache chart cells if not cached', () async {
        // Arrange
        const stateName = 'Florida';
        final expectedCells = ['US5FL11M', 'US4FL22M'];
        
        when(mockCacheService.get('state_cells_$stateName'))
            .thenAnswer((_) async => null);
        when(mockCacheService.put('state_cells_$stateName', expectedCells))
            .thenAnswer((_) async => {});

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, hasLength(2));
        expect(result, equals(expectedCells));
        verify(mockCacheService.get('state_cells_$stateName')).called(1);
        verify(mockCacheService.put('state_cells_$stateName', expectedCells)).called(1);
      });

      test('should validate state name input', () async {
        // Act & Assert
        expect(
          () async => await mappingService.getChartCellsForState(''),
          throwsA(isA<ArgumentError>()),
        );
        
        expect(
          () async => await mappingService.getChartCellsForState('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle cache errors gracefully', () async {
        // Arrange
        const stateName = 'California';
        
        when(mockCacheService.get('state_cells_$stateName'))
            .thenThrow(AppError.storage('Cache error'));

        // Act
        final result = await mappingService.getChartCellsForState(stateName);

        // Assert
        expect(result, isEmpty);
        verify(mockLogger.error(
          'Failed to get cached chart cells for state $stateName',
          exception: any,
        )).called(1);
      });
    });

    group('getStateBounds', () {
      test('should return bounds for California', () async {
        // Arrange
        const stateName = 'California';
        final expectedBounds = GeographicBounds(
          north: 42.0,
          south: 32.5,
          east: -114.1,
          west: -124.4,
        );
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => expectedBounds);

        // Act
        final result = await mappingService.getStateBounds(stateName);

        // Assert
        expect(result, isNotNull);
        expect(result!.north, equals(42.0));
        expect(result.south, equals(32.5));
        expect(result.east, equals(-114.1));
        expect(result.west, equals(-124.4));
      });

      test('should return null for invalid state', () async {
        // Arrange
        const stateName = 'InvalidState';
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => null);

        // Act
        final result = await mappingService.getStateBounds(stateName);

        // Assert
        expect(result, isNull);
      });

      test('should load and cache state bounds if not cached', () async {
        // Arrange
        const stateName = 'Florida';
        final expectedBounds = GeographicBounds(
          north: 31.0,
          south: 24.5,
          east: -80.0,
          west: -87.6,
        );
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => null);
        when(mockCacheService.put('state_bounds_$stateName', expectedBounds))
            .thenAnswer((_) async => {});

        // Act
        final result = await mappingService.getStateBounds(stateName);

        // Assert
        expect(result, isNotNull);
        expect(result!.north, equals(31.0));
        verify(mockCacheService.put('state_bounds_$stateName', expectedBounds)).called(1);
      });
    });

    group('intersectsStateBounds', () {
      test('should return true for chart that intersects state bounds', () async {
        // Arrange
        const stateName = 'California';
        final stateBounds = GeographicBounds(
          north: 42.0,
          south: 32.5,
          east: -114.1,
          west: -124.4,
        );
        final chartBounds = GeographicBounds(
          north: 38.0,
          south: 37.0,
          east: -122.0,
          west: -123.0,
        );
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => stateBounds);

        // Act
        final result = await mappingService.intersectsStateBounds(stateName, chartBounds);

        // Assert
        expect(result, isTrue);
      });

      test('should return false for chart that does not intersect state bounds', () async {
        // Arrange
        const stateName = 'California';
        final stateBounds = GeographicBounds(
          north: 42.0,
          south: 32.5,
          east: -114.1,
          west: -124.4,
        );
        final chartBounds = GeographicBounds(
          north: 30.0,
          south: 29.0,
          east: -94.0,
          west: -95.0, // Texas chart bounds
        );
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => stateBounds);

        // Act
        final result = await mappingService.intersectsStateBounds(stateName, chartBounds);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for invalid state', () async {
        // Arrange
        const stateName = 'InvalidState';
        final chartBounds = GeographicBounds(
          north: 38.0,
          south: 37.0,
          east: -122.0,
          west: -123.0,
        );
        
        when(mockCacheService.get('state_bounds_$stateName'))
            .thenAnswer((_) async => null);

        // Act
        final result = await mappingService.intersectsStateBounds(stateName, chartBounds);

        // Assert
        expect(result, isFalse);
      });
    });

    group('getAllSupportedStates', () {
      test('should return list of all US coastal states', () async {
        // Arrange
        final expectedStates = [
          'California', 'Oregon', 'Washington', 'Alaska', 'Hawaii',
          'Texas', 'Louisiana', 'Mississippi', 'Alabama', 'Florida',
          'Georgia', 'South Carolina', 'North Carolina', 'Virginia',
          'Maryland', 'Delaware', 'New Jersey', 'New York',
          'Connecticut', 'Rhode Island', 'Massachusetts', 'New Hampshire', 'Maine',
          'Michigan', 'Wisconsin', 'Minnesota', 'Illinois', 'Indiana', 'Ohio', 'Pennsylvania'
        ];
        
        when(mockCacheService.get('supported_states'))
            .thenAnswer((_) async => expectedStates);

        // Act
        final result = await mappingService.getAllSupportedStates();

        // Assert
        expect(result, hasLength(greaterThan(20)));
        expect(result, contains('California'));
        expect(result, contains('Florida'));
        expect(result, contains('Alaska'));
        expect(result, contains('Hawaii'));
      });

      test('should load and cache supported states if not cached', () async {
        // Arrange
        final expectedStates = ['California', 'Florida', 'Texas'];
        
        when(mockCacheService.get('supported_states'))
            .thenAnswer((_) async => null);
        when(mockCacheService.put('supported_states', any))
            .thenAnswer((_) async => {});

        // Act
        final result = await mappingService.getAllSupportedStates();

        // Assert
        expect(result, isNotEmpty);
        verify(mockCacheService.put('supported_states', any)).called(1);
      });
    });

    group('loadStateChartMapping', () {
      test('should load predefined state-to-chart mapping', () async {
        // Arrange
        const stateName = 'California';
        
        when(mockCacheService.put('state_cells_$stateName', any))
            .thenAnswer((_) async => {});

        // Act
        final result = await mappingService.loadStateChartMapping(stateName);

        // Assert
        expect(result, isNotEmpty);
        verify(mockCacheService.put('state_cells_$stateName', result)).called(1);
      });

      test('should return empty list for unsupported states', () async {
        // Arrange
        const stateName = 'Nevada';

        // Act
        final result = await mappingService.loadStateChartMapping(stateName);

        // Assert
        expect(result, isEmpty);
      });

      test('should handle invalid state names', () async {
        // Act & Assert
        expect(
          () async => await mappingService.loadStateChartMapping(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('clearCache', () {
      test('should clear all state mapping cache', () async {
        // Arrange
        when(mockCacheService.clear(prefix: 'state_'))
            .thenAnswer((_) async => {});

        // Act
        await mappingService.clearCache();

        // Assert
        verify(mockCacheService.clear(prefix: 'state_')).called(1);
        verify(mockLogger.info('State region mapping cache cleared')).called(1);
      });

      test('should handle clear cache errors', () async {
        // Arrange
        when(mockCacheService.clear(prefix: 'state_'))
            .thenThrow(AppError.storage('Cache clear error'));

        // Act & Assert
        expect(
          () async => await mappingService.clearCache(),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('getBoundsIntersection', () {
      test('should calculate intersection of overlapping bounds', () {
        // Arrange
        final bounds1 = GeographicBounds(
          north: 38.0,
          south: 36.0,
          east: -122.0,
          west: -124.0,
        );
        final bounds2 = GeographicBounds(
          north: 37.0,
          south: 35.0,
          east: -121.0,
          west: -123.0,
        );

        // Act
        final result = mappingService.getBoundsIntersection(bounds1, bounds2);

        // Assert
        expect(result, isNotNull);
        expect(result!.north, equals(37.0));
        expect(result.south, equals(36.0));
        expect(result.east, equals(-122.0));
        expect(result.west, equals(-123.0));
      });

      test('should return null for non-overlapping bounds', () {
        // Arrange
        final bounds1 = GeographicBounds(
          north: 38.0,
          south: 37.0,
          east: -122.0,
          west: -123.0,
        );
        final bounds2 = GeographicBounds(
          north: 30.0,
          south: 29.0,
          east: -94.0,
          west: -95.0,
        );

        // Act
        final result = mappingService.getBoundsIntersection(bounds1, bounds2);

        // Assert
        expect(result, isNull);
      });
    });
  });
}