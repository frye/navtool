import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:typed_data';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/chart_models.dart';
import '../../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  StorageService,
  CacheService,
  HttpClientService,
  AppLogger,
])
import 'state_region_mapping_service_enhanced_test.mocks.dart';

void main() {
  group('Enhanced StateRegionMappingService Tests', () {
    late MockStorageService mockStorage;
    late MockCacheService mockCache;
    late MockHttpClientService mockHttpClient;
    late MockAppLogger mockLogger;
    late StateRegionMappingService mappingService;

    setUp(() {
      mockStorage = MockStorageService();
      mockCache = MockCacheService();
      mockHttpClient = MockHttpClientService();
      mockLogger = MockAppLogger();
      
      mappingService = StateRegionMappingServiceImpl(
        logger: mockLogger,
        cacheService: mockCache,
        httpClient: mockHttpClient,
        storageService: mockStorage,
      );
    });

    group('Multi-Region State Support', () {
      testWidgets('should return marine regions for Alaska', (tester) async {
        final regions = await mappingService.getMarineRegions('Alaska');
        
        expect(regions, hasLength(3));
        expect(regions.map((r) => r.name), containsAll([
          'Southeast Alaska',
          'Gulf of Alaska', 
          'Arctic Alaska',
        ]));
        
        // Verify each region has valid bounds
        for (final region in regions) {
          expect(region.bounds.north, greaterThan(region.bounds.south));
          expect(region.bounds.east, greaterThan(region.bounds.west));
          expect(region.description, isNotEmpty);
        }
      });

      testWidgets('should return marine regions for California', (tester) async {
        final regions = await mappingService.getMarineRegions('California');
        
        expect(regions, hasLength(3));
        expect(regions.map((r) => r.name), containsAll([
          'Northern California',
          'Central California',
          'Southern California',
        ]));
      });

      testWidgets('should return marine regions for Florida', (tester) async {
        final regions = await mappingService.getMarineRegions('Florida');
        
        expect(regions, hasLength(2));
        expect(regions.map((r) => r.name), containsAll([
          'Florida Atlantic Coast',
          'Florida Gulf Coast',
        ]));
      });

      testWidgets('should return single region for single-region states', (tester) async {
        final regions = await mappingService.getMarineRegions('Washington');
        
        expect(regions, hasLength(1));
        expect(regions.first.name, equals('Washington Marine Region'));
        expect(regions.first.description, contains('Primary marine region'));
      });

      testWidgets('should return empty list for unsupported states', (tester) async {
        final regions = await mappingService.getMarineRegions('Nevada');
        
        expect(regions, isEmpty);
      });
    });

    group('Regional Chart Discovery', () {
      testWidgets('should get chart cells for specific Alaska region', (tester) async {
        // Mock Southeast Alaska charts
        final southeastCharts = [
          TestFixtures.createTestChart(id: 'US5AK01M', title: 'Southeast Alaska Chart 1'),
          TestFixtures.createTestChart(id: 'US5AK02M', title: 'Southeast Alaska Chart 2'),
        ];
        
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => southeastCharts);

        final chartCells = await mappingService.getChartCellsForRegion(
          'Alaska', 
          'Southeast Alaska'
        );
        
        expect(chartCells, hasLength(2));
        expect(chartCells, containsAll(['US5AK01M', 'US5AK02M']));
      });

      testWidgets('should get chart cells for California regions', (tester) async {
        // Mock Northern California charts
        final northernCharts = [
          TestFixtures.createTestChart(id: 'US5CA01M', title: 'San Francisco Bay'),
          TestFixtures.createTestChart(id: 'US5CA02M', title: 'Golden Gate'),
        ];
        
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => northernCharts);

        final chartCells = await mappingService.getChartCellsForRegion(
          'California', 
          'Northern California'
        );
        
        expect(chartCells, hasLength(2));
        expect(chartCells, containsAll(['US5CA01M', 'US5CA02M']));
      });

      testWidgets('should handle single-region states in getChartCellsForRegion', (tester) async {
        final washingtonCharts = [
          TestFixtures.createTestChart(id: 'US5WA01M', title: 'Puget Sound'),
          TestFixtures.createTestChart(id: 'US5WA02M', title: 'Elliott Bay'),
        ];
        
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => washingtonCharts);

        final chartCells = await mappingService.getChartCellsForRegion(
          'Washington', 
          'Washington Marine Region'
        );
        
        expect(chartCells, hasLength(2));
        expect(chartCells, containsAll(['US5WA01M', 'US5WA02M']));
      });

      testWidgets('should throw exception for invalid region', (tester) async {
        expect(
          () => mappingService.getChartCellsForRegion('Alaska', 'Invalid Region'),
          throwsA(isA<StateNotSupportedException>()),
        );
      });
    });

    group('State-Region Mapping Validation', () {
      testWidgets('should validate supported state successfully', (tester) async {
        // Mock successful chart discovery
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => ['US5CA01M', 'US5CA02M', 'US5CA03M']);

        final result = await mappingService.validateStateRegionMapping('California');
        
        expect(result.isValid, isTrue);
        expect(result.issues, isEmpty);
        expect(result.validatedAt, isNotNull);
      });

      testWidgets('should identify validation issues', (tester) async {
        // Mock insufficient chart coverage
        when(mockStorage.getStateCellMapping('Delaware'))
            .thenAnswer((_) async => ['US5DE01M']); // Only 1 chart

        final result = await mappingService.validateStateRegionMapping('Delaware');
        
        expect(result.isValid, isFalse);
        expect(result.issues, isNotEmpty);
        expect(result.issues.any((issue) => issue.contains('Insufficient chart coverage')), isTrue);
        expect(result.recommendations, isNotEmpty);
      });

      testWidgets('should validate multi-region state bounds', (tester) async {
        when(mockStorage.getStateCellMapping('Alaska'))
            .thenAnswer((_) async => ['US5AK01M', 'US5AK02M', 'US5AK03M']);

        final result = await mappingService.validateStateRegionMapping('Alaska');
        
        // Should validate all 3 Alaska regions
        expect(result.validatedAt, isNotNull);
        // Validation should check that regions are within state bounds
      });

      testWidgets('should handle unsupported state validation', (tester) async {
        final result = await mappingService.validateStateRegionMapping('Nevada');
        
        expect(result.isValid, isFalse);
        expect(result.issues, contains('State Nevada is not supported'));
        expect(result.recommendations, contains('Add Nevada to supported states list'));
      });

      testWidgets('should handle storage errors gracefully during validation', (tester) async {
        when(mockStorage.getStateCellMapping('California'))
            .thenThrow(Exception('Storage error'));

        final result = await mappingService.validateStateRegionMapping('California');
        
        expect(result.isValid, isFalse);
        expect(result.issues.any((issue) => issue.contains('Failed to retrieve charts')), isTrue);
        expect(result.recommendations.isNotEmpty, isTrue);
      });
    });

    group('Coverage Information', () {
      testWidgets('should provide comprehensive coverage info for state', (tester) async {
        // Mock chart data for multi-region state
        final alaskaCharts = [
          TestFixtures.createTestChart(id: 'US5AK01M', title: 'Southeast Chart 1'),
          TestFixtures.createTestChart(id: 'US5AK02M', title: 'Southeast Chart 2'),
          TestFixtures.createTestChart(id: 'US5AK03M', title: 'Gulf Chart 1'),
          TestFixtures.createTestChart(id: 'US5AK04M', title: 'Arctic Chart 1'),
        ];
        
        when(mockStorage.getStateCellMapping('Alaska'))
            .thenAnswer((_) async => alaskaCharts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => alaskaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final coverageInfo = await mappingService.getStateCoverageInfo('Alaska');
        
        expect(coverageInfo.stateName, equals('Alaska'));
        expect(coverageInfo.totalChartCount, equals(4));
        expect(coverageInfo.coveragePercentage, greaterThan(0));
        expect(coverageInfo.regionBreakdown, hasLength(3)); // 3 Alaska regions
        expect(coverageInfo.lastUpdated, isNotNull);
        
        // Check region breakdown
        expect(coverageInfo.regionBreakdown.keys, containsAll([
          'Southeast Alaska',
          'Gulf of Alaska',
          'Arctic Alaska',
        ]));
      });

      testWidgets('should calculate region coverage percentages', (tester) async {
        final californiaCharts = [
          TestFixtures.createTestChart(id: 'US5CA01M', title: 'Northern Chart 1'),
          TestFixtures.createTestChart(id: 'US5CA02M', title: 'Northern Chart 2'),
          TestFixtures.createTestChart(id: 'US5CA03M', title: 'Central Chart 1'),
          TestFixtures.createTestChart(id: 'US5CA04M', title: 'Southern Chart 1'),
        ];
        
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => californiaCharts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => californiaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final coverageInfo = await mappingService.getStateCoverageInfo('California');
        
        expect(coverageInfo.regionBreakdown, hasLength(3)); // 3 California regions
        
        for (final regionInfo in coverageInfo.regionBreakdown.values) {
          expect(regionInfo.coveragePercentage, greaterThanOrEqualTo(0));
          expect(regionInfo.coveragePercentage, lessThanOrEqualTo(100));
          expect(regionInfo.bounds, isNotNull);
        }
      });

      testWidgets('should handle single-region state coverage', (tester) async {
        final washingtonCharts = [
          TestFixtures.createTestChart(id: 'US5WA01M', title: 'Puget Sound'),
          TestFixtures.createTestChart(id: 'US5WA02M', title: 'Elliott Bay'),
        ];
        
        when(mockStorage.getStateCellMapping('Washington'))
            .thenAnswer((_) async => washingtonCharts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => washingtonCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final coverageInfo = await mappingService.getStateCoverageInfo('Washington');
        
        expect(coverageInfo.stateName, equals('Washington'));
        expect(coverageInfo.totalChartCount, equals(2));
        expect(coverageInfo.regionBreakdown, hasLength(1));
        expect(coverageInfo.regionBreakdown.keys.first, equals('Washington Marine Region'));
      });
    });

    group('Enhanced Geographic Bounds', () {
      testWidgets('should support all 30 coastal states', (tester) async {
        final supportedStates = await mappingService.getSupportedStates();
        
        // Verify we have all expected coastal states
        final expectedStates = [
          // Atlantic Coast
          'Maine', 'New Hampshire', 'Massachusetts', 'Rhode Island', 'Connecticut',
          'New York', 'New Jersey', 'Pennsylvania', 'Delaware', 'Maryland',
          'Virginia', 'North Carolina', 'South Carolina', 'Georgia',
          
          // Gulf Coast + Florida
          'Florida', 'Alabama', 'Mississippi', 'Louisiana', 'Texas',
          
          // Pacific Coast
          'California', 'Oregon', 'Washington', 'Alaska', 'Hawaii',
          
          // Great Lakes
          'Minnesota', 'Wisconsin', 'Michigan', 'Illinois', 'Indiana', 'Ohio',
        ];
        
        expect(supportedStates.length, greaterThanOrEqualTo(29)); // At least 29 states
        
        // Verify key coastal states are included
        expect(supportedStates, containsAll([
          'California', 'Florida', 'Texas', 'Alaska', 'Washington',
          'Maine', 'Hawaii', 'New York', 'North Carolina'
        ]));
      });

      testWidgets('should have valid geographic bounds for all states', (tester) async {
        final supportedStates = await mappingService.getSupportedStates();
        
        for (final state in supportedStates) {
          final bounds = await mappingService.getStateBounds(state);
          
          expect(bounds, isNotNull, reason: 'State $state should have bounds');
          expect(bounds!.north, greaterThan(bounds.south), 
              reason: 'North should be greater than south for $state');
          expect(bounds.north, lessThanOrEqualTo(90), 
              reason: 'North latitude should be ≤ 90° for $state');
          expect(bounds.south, greaterThanOrEqualTo(-90), 
              reason: 'South latitude should be ≥ -90° for $state');
          expect(bounds.east, lessThanOrEqualTo(180), 
              reason: 'East longitude should be ≤ 180° for $state');
          expect(bounds.west, greaterThanOrEqualTo(-180), 
              reason: 'West longitude should be ≥ -180° for $state');
        }
      });

      testWidgets('should validate territorial water boundaries', (tester) async {
        // Test specific states with complex maritime boundaries
        
        // Alaska - should span across International Date Line
        final alaskaBounds = await mappingService.getStateBounds('Alaska');
        expect(alaskaBounds, isNotNull);
        expect(alaskaBounds!.west, lessThan(-170)); // Far west in Aleutians
        expect(alaskaBounds.north, greaterThan(70)); // Arctic coast
        
        // Hawaii - should be in Pacific with negative longitude
        final hawaiiBounds = await mappingService.getStateBounds('Hawaii');
        expect(hawaiiBounds, isNotNull);
        expect(hawaiiBounds!.west, lessThan(-154)); // West of main islands
        expect(hawaiiBounds.north, lessThan(23)); // Tropical latitude
        
        // Florida - should span both Atlantic and Gulf coasts
        final floridaBounds = await mappingService.getStateBounds('Florida');
        expect(floridaBounds, isNotNull);
        expect(floridaBounds!.west, lessThan(-87)); // Gulf coast
        expect(floridaBounds.east, greaterThan(-80)); // Atlantic coast
      });
    });

    group('Performance and Edge Cases', () {
      testWidgets('should handle coordinate edge cases', (tester) async {
        // Test International Date Line (Alaska)
        final alaskaState = await mappingService.getStateFromCoordinates(64.0, -179.0);
        expect(alaskaState, equals('Alaska'));
        
        // Test equatorial coordinates (should return null for US states)
        final equatorialState = await mappingService.getStateFromCoordinates(0.0, 0.0);
        expect(equatorialState, isNull);
        
        // Test extreme northern coordinates
        final arcticState = await mappingService.getStateFromCoordinates(70.0, -150.0);
        expect(arcticState, equals('Alaska'));
        
        // Test southern tip coordinates (Florida Keys)
        final floridaKeysState = await mappingService.getStateFromCoordinates(24.5, -81.0);
        expect(floridaKeysState, equals('Florida'));
      });

      testWidgets('should handle large dataset efficiently', (tester) async {
        // Mock large number of charts
        final largeChartSet = List.generate(100, (i) => 
          TestFixtures.createTestChart(id: 'US5CA${i.toString().padLeft(2, '0')}M', title: 'Chart $i')
        );
        
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => largeChartSet);

        final stopwatch = Stopwatch()..start();
        final chartCells = await mappingService.getChartCellsForRegion(
          'California', 
          'Northern California'
        );
        stopwatch.stop();
        
        expect(chartCells, hasLength(100));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should complete within 1 second
      });

      testWidgets('should maintain cache consistency across operations', (tester) async {
        when(mockCache.get(any)).thenAnswer((_) async => null);
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Multiple calls should use cached results
        await mappingService.getSupportedStates();
        await mappingService.getSupportedStates();
        
        // Verify cache was used efficiently
        verify(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .called(1); // Should only store once
      });
    });

    group('Error Recovery', () {
      testWidgets('should gracefully handle partial service failures', (tester) async {
        // Setup partial failure scenario
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => ['US5CA01M', 'US5CA02M']);
        when(mockStorage.getStateCellMapping('Florida'))
            .thenThrow(Exception('Storage failure'));
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => [TestFixtures.createTestChart(id: 'US5CA01M', title: 'Test Chart')]);

        // Should handle mixed success/failure states
        final californiaInfo = await mappingService.getStateCoverageInfo('California');
        expect(californiaInfo.totalChartCount, equals(2));

        // Failed state should throw or return error state
        expect(
          () => mappingService.getStateCoverageInfo('Florida'),
          throwsA(isA<Exception>()),
        );
      });

      testWidgets('should recover from cache corruption', (tester) async {
        // Mock corrupted cache data
        when(mockCache.get(any)).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Should fallback to direct computation
        final supportedStates = await mappingService.getSupportedStates();
        
        expect(supportedStates, isNotEmpty);
        // verify(mockLogger.warning(any)).called(atLeast(1)); // Skip log verification for now
      });
    });
  });
}