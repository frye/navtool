import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';

@GenerateMocks([
  ChartCatalogService,
  StateRegionMappingService,
  StorageService,
  AppLogger,
])
import 'noaa_chart_discovery_cache_fix_test.mocks.dart';

void main() {
  group('NoaaChartDiscoveryService Cache Fix', () {
    late NoaaChartDiscoveryService discoveryService;
    late MockChartCatalogService mockCatalogService;
    late MockStateRegionMappingService mockMappingService;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockCatalogService = MockChartCatalogService();
      mockMappingService = MockStateRegionMappingService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();

      discoveryService = NoaaChartDiscoveryServiceImpl(
        catalogService: mockCatalogService,
        mappingService: mockMappingService,
        storageService: mockStorageService,
        logger: mockLogger,
      );
    });

    group('fixChartDiscoveryCache', () {
      test('should detect and fix Washington chart discovery issue', () async {
        // Arrange - Simulate the real issue: charts with invalid bounds from old cache
        when(mockStorageService.countChartsWithInvalidBounds())
            .thenAnswer((_) async => 3); // 3 charts with 0,0,0,0 bounds
        
        when(mockStorageService.clearChartsWithInvalidBounds())
            .thenAnswer((_) async => 3); // Clear all 3 charts
        
        when(mockCatalogService.refreshCatalog(force: true))
            .thenAnswer((_) async => true);
        
        when(mockCatalogService.ensureCatalogBootstrapped())
            .thenAnswer((_) async => {});

        // Act
        final clearedCount = await discoveryService.fixChartDiscoveryCache();

        // Assert
        expect(clearedCount, equals(3), reason: 'Should clear exactly 3 charts with invalid bounds');
        
        // Verify the cache invalidation workflow
        verify(mockStorageService.countChartsWithInvalidBounds()).called(1);
        verify(mockStorageService.clearChartsWithInvalidBounds()).called(1);
        verify(mockCatalogService.refreshCatalog(force: true)).called(1);
        verify(mockCatalogService.ensureCatalogBootstrapped()).called(1);
        
        // Verify logging
        verify(mockLogger.info('Starting chart discovery cache fix for invalid bounds issue')).called(1);
        verify(mockLogger.warning('Found 3 charts with invalid bounds - clearing and forcing refresh')).called(1);
        verify(mockLogger.info('Chart discovery cache fix completed: cleared 3 charts, forcing catalog refresh')).called(1);
      });

      test('should handle clean cache gracefully', () async {
        // Arrange - Cache is already clean
        when(mockStorageService.countChartsWithInvalidBounds())
            .thenAnswer((_) async => 0); // No charts with invalid bounds

        // Act
        final clearedCount = await discoveryService.fixChartDiscoveryCache();

        // Assert
        expect(clearedCount, equals(0), reason: 'Should return 0 when cache is clean');
        
        // Verify only counting was called
        verify(mockStorageService.countChartsWithInvalidBounds()).called(1);
        verifyNever(mockStorageService.clearChartsWithInvalidBounds());
        verifyNever(mockCatalogService.refreshCatalog(force: true));
        verifyNever(mockCatalogService.ensureCatalogBootstrapped());
        
        // Verify logging
        verify(mockLogger.info('Starting chart discovery cache fix for invalid bounds issue')).called(1);
        verify(mockLogger.info('No charts with invalid bounds found - cache is clean')).called(1);
      });

      test('should handle storage errors gracefully', () async {
        // Arrange - Storage service throws an error
        when(mockStorageService.countChartsWithInvalidBounds())
            .thenThrow(Exception('Database error'));

        // Act & Assert
        expect(
          () => discoveryService.fixChartDiscoveryCache(),
          throwsA(isA<Exception>()),
        );
        
        // Verify error logging
        verify(mockLogger.error('Failed to fix chart discovery cache', exception: anyNamed('exception'))).called(1);
      });

      test('should handle catalog refresh errors gracefully', () async {
        // Arrange - Catalog service throws an error during refresh
        when(mockStorageService.countChartsWithInvalidBounds())
            .thenAnswer((_) async => 2);
        
        when(mockStorageService.clearChartsWithInvalidBounds())
            .thenAnswer((_) async => 2);
        
        when(mockCatalogService.refreshCatalog(force: true))
            .thenThrow(Exception('NOAA API error'));

        // Act & Assert
        await expectLater(
          discoveryService.fixChartDiscoveryCache(),
          throwsA(isA<Exception>()),
        );
        
        // Verify partial execution
        verify(mockStorageService.countChartsWithInvalidBounds()).called(1);
        verify(mockStorageService.clearChartsWithInvalidBounds()).called(1);
        verify(mockCatalogService.refreshCatalog(force: true)).called(1);
        verifyNever(mockCatalogService.ensureCatalogBootstrapped());
      });
    });
  });
}
