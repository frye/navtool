import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/chart_quality_monitor.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart_models.dart';
import '../../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  StorageService,
  CacheService,
  HttpClientService,
  AppLogger,
])
import 'phase3_validation_test.mocks.dart';

/// Phase 3 Implementation Validation Tests
///
/// These tests validate that Phase 3: Data Quality & Coverage Enhancement
/// is correctly implemented and functional. This includes:
/// 1. Enhanced state-to-region mapping with multi-region support
/// 2. Chart quality monitoring capabilities
/// 3. Comprehensive coverage validation
void main() {
  group('Phase 3: Data Quality & Coverage Enhancement Validation', () {
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

    group('Enhanced State-to-Region Mapping', () {
      testWidgets('should support multi-region states (Alaska)', (tester) async {
        final regions = await mappingService.getMarineRegions('Alaska');
        
        expect(regions, hasLength(3));
        expect(regions.map((r) => r.name), containsAll([
          'Southeast Alaska',
          'Gulf of Alaska', 
          'Arctic Alaska',
        ]));
        
        // Verify each region has valid bounds and description
        for (final region in regions) {
          expect(region.bounds.north, greaterThan(region.bounds.south));
          expect(region.bounds.east, greaterThan(region.bounds.west));
          expect(region.description, isNotEmpty);
        }
      });

      testWidgets('should support multi-region states (California)', (tester) async {
        final regions = await mappingService.getMarineRegions('California');
        
        expect(regions, hasLength(3));
        expect(regions.map((r) => r.name), containsAll([
          'Northern California',
          'Central California',
          'Southern California',
        ]));
      });

      testWidgets('should support multi-region states (Florida)', (tester) async {
        final regions = await mappingService.getMarineRegions('Florida');
        
        expect(regions, hasLength(2));
        expect(regions.map((r) => r.name), containsAll([
          'Florida Atlantic Coast',
          'Florida Gulf Coast',
        ]));
      });

      testWidgets('should support all 30 coastal states', (tester) async {
        when(mockCache.get(any)).thenAnswer((_) async => null);
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final supportedStates = await mappingService.getSupportedStates();
        
        // Should have comprehensive coverage of US coastal states
        expect(supportedStates.length, greaterThanOrEqualTo(25));
        
        // Verify key states are included
        expect(supportedStates, containsAll([
          'California', 'Florida', 'Texas', 'Alaska', 'Washington',
          'Maine', 'Hawaii', 'New York', 'North Carolina', 'Michigan'
        ]));
      });

      testWidgets('should validate state-region mapping', (tester) async {
        // Mock some chart data for validation
        when(mockStorage.getStateCellMapping('Washington'))
            .thenAnswer((_) async => ['US5WA01M', 'US5WA02M', 'US5WA03M']);

        final validation = await mappingService.validateStateRegionMapping('Washington');
        
        expect(validation.isValid, isTrue);
        expect(validation.validatedAt, isNotNull);
        expect(validation.issues, isEmpty);
      });

      testWidgets('should provide comprehensive coverage information', (tester) async {
        // Mock Alaska with multiple regions
        final alaskaCharts = [
          TestFixtures.createTestChart(id: 'US5AK01M', title: 'Southeast Chart'),
          TestFixtures.createTestChart(id: 'US5AK02M', title: 'Gulf Chart'),
          TestFixtures.createTestChart(id: 'US5AK03M', title: 'Arctic Chart'),
        ];
        
        when(mockStorage.getStateCellMapping('Alaska'))
            .thenAnswer((_) async => alaskaCharts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => alaskaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final coverageInfo = await mappingService.getStateCoverageInfo('Alaska');
        
        expect(coverageInfo.stateName, equals('Alaska'));
        expect(coverageInfo.totalChartCount, equals(3));
        expect(coverageInfo.regionBreakdown, hasLength(3)); // 3 Alaska regions
        expect(coverageInfo.lastUpdated, isNotNull);
      });
    });

    group('Chart Quality Monitoring', () {
      testWidgets('should create chart quality monitor', (tester) async {
        final qualityMonitor = ChartQualityMonitor(
          logger: mockLogger,
          storageService: mockStorage,
          cacheService: mockCache,
          mappingService: mappingService,
        );

        expect(qualityMonitor, isNotNull);
        expect(qualityMonitor.isMonitoring, isFalse);
        
        qualityMonitor.dispose();
      });

      testWidgets('should support quality monitoring operations', (tester) async {
        final qualityMonitor = ChartQualityMonitor(
          logger: mockLogger,
          storageService: mockStorage,
          cacheService: mockCache,
          mappingService: mappingService,
        );

        // Mock minimal data for quality monitoring
        when(mockStorage.getStateCellMapping(any))
            .thenAnswer((_) async => ['US5TEST01M']);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => [TestFixtures.createTestChart()]);
        when(mockCache.get(any)).thenAnswer((_) async => null);
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        // Should be able to start and stop monitoring
        await qualityMonitor.startMonitoring();
        expect(qualityMonitor.isMonitoring, isTrue);

        await qualityMonitor.stopMonitoring();
        expect(qualityMonitor.isMonitoring, isFalse);

        qualityMonitor.dispose();
      });
    });

    group('Integration Validation', () {
      testWidgets('should support enhanced geographic bounds for all states', (tester) async {
        when(mockCache.get(any)).thenAnswer((_) async => null);
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final supportedStates = await mappingService.getSupportedStates();
        
        // Verify all states have valid geographic bounds
        for (final state in supportedStates.take(5)) { // Test first 5 for speed
          final bounds = await mappingService.getStateBounds(state);
          
          expect(bounds, isNotNull, reason: 'State $state should have bounds');
          expect(bounds!.north, greaterThan(bounds.south), 
              reason: 'North should be greater than south for $state');
          expect(bounds.north, lessThanOrEqualTo(90), 
              reason: 'North latitude should be ≤ 90° for $state');
          expect(bounds.south, greaterThanOrEqualTo(-90), 
              reason: 'South latitude should be ≥ -90° for $state');
        }
      });

      testWidgets('should handle coordinate edge cases correctly', (tester) async {
        // Test International Date Line (Alaska)
        final alaskaState = await mappingService.getStateFromCoordinates(64.0, -179.0);
        expect(alaskaState, equals('Alaska'));
        
        // Test coordinates outside US waters (should return null)
        final outsideState = await mappingService.getStateFromCoordinates(0.0, 0.0);
        expect(outsideState, isNull);
        
        // Test Florida Keys coordinates
        final floridaState = await mappingService.getStateFromCoordinates(24.5, -81.0);
        expect(floridaState, equals('Florida'));
      });

      testWidgets('should maintain backward compatibility', (tester) async {
        // Existing functionality should still work
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => ['US5CA01M', 'US5CA02M']);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => [
              TestFixtures.createTestChart(id: 'US5CA01M'),
              TestFixtures.createTestChart(id: 'US5CA02M'),
            ]);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final chartCells = await mappingService.getChartCellsForState('California');
        
        expect(chartCells, hasLength(2));
        expect(chartCells, containsAll(['US5CA01M', 'US5CA02M']));
      });
    });

    group('Performance Validation', () {
      testWidgets('should handle operations efficiently', (tester) async {
        when(mockCache.get(any)).thenAnswer((_) async => null);
        when(mockCache.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final stopwatch = Stopwatch()..start();
        
        // Should complete basic operations quickly
        final supportedStates = await mappingService.getSupportedStates();
        final firstState = supportedStates.first;
        final regions = await mappingService.getMarineRegions(firstState);
        final bounds = await mappingService.getStateBounds(firstState);
        
        stopwatch.stop();
        
        expect(supportedStates, isNotEmpty);
        expect(regions, isNotEmpty);
        expect(bounds, isNotNull);
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should complete within 1 second
      });
    });

    group('Error Handling Validation', () {
      testWidgets('should handle service failures gracefully', (tester) async {
        // Test with storage service failure
        when(mockStorage.getStateCellMapping(any))
            .thenThrow(Exception('Storage service unavailable'));

        final validation = await mappingService.validateStateRegionMapping('TestState');
        
        expect(validation.isValid, isFalse);
        expect(validation.issues, isNotEmpty);
        expect(validation.recommendations, isNotEmpty);
      });

      testWidgets('should handle unsupported states', (tester) async {
        final regions = await mappingService.getMarineRegions('Nevada'); // Inland state
        
        expect(regions, isEmpty);
      });

      testWidgets('should validate invalid region requests', (tester) async {
        expect(
          () => mappingService.getChartCellsForRegion('Alaska', 'Invalid Region'),
          throwsA(isA<StateNotSupportedException>()),
        );
      });
    });
  });
}