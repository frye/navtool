import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/database_storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

void main() {
  group('Washington Chart Discovery Issue #129 - Integration Fix', () {
    late DatabaseStorageService storageService;
    late AppLogger logger;

    setUp(() async {
      logger = ConsoleLogger();
      storageService = DatabaseStorageService(logger: logger);
      await storageService.initialize();
    });

    tearDown(() async {
      await storageService.close();
    });

    test('should demonstrate and fix the Washington chart discovery cache issue', () async {
      // STEP 1: Reproduce the original issue
  logger.info('REPRODUCING ISSUE: Simulating old cached charts with invalid bounds', context: 'WA.ChartDiscovery');
      
      // Create charts that simulate the original Washington discovery issue
      final washingtonChart1 = Chart(
        id: 'US1WC01M',
        title: 'Columbia River to Destruction I.',
        scale: 80000,
        bounds: GeographicBounds.unvalidated(north: 0, south: 0, east: 0, west: 0), // Invalid legacy cached bounds
        lastUpdate: DateTime(2024, 1, 15),
        state: 'Washington',
        type: ChartType.general,
      );
      
      final washingtonChart2 = Chart(
        id: 'US1WC04M',
        title: 'Cape Disappointment to Lincoln City',
        scale: 80000,
        bounds: GeographicBounds.unvalidated(north: 0, south: 0, east: 0, west: 0), // Invalid legacy cached bounds
        lastUpdate: DateTime(2024, 1, 15),
        state: 'Washington',
        type: ChartType.general,
      );
      
      // Store the problematic charts
      await storageService.storeChart(washingtonChart1, [1]);
      await storageService.storeChart(washingtonChart2, [1]);
      
      // STEP 2: Demonstrate the problem
  logger.info('TESTING: Searching for charts in Washington state bounds', context: 'WA.ChartDiscovery');
      
      final washingtonBounds = GeographicBounds(
        north: 49.0, south: 45.5, east: -116.9, west: -124.8
      );
      
    final foundBefore = await storageService.getChartsInBounds(washingtonBounds);
  logger.warning('ISSUE CONFIRMED: Found ${foundBefore.length} charts. Invalid legacy charts should not be discovered due to zero bounds.', context: 'WA.ChartDiscovery');
      
    // Instead of asserting total count == 0 (which can break if other charts exist in DB),
    // assert that the specific invalid charts are NOT present in the discovery results.
    final foundIdsBefore = foundBefore.map((c) => c.id).toSet();
    expect(foundIdsBefore.contains('US1WC01M'), isFalse, reason: 'Invalid bounded chart US1WC01M should not be discovered');
    expect(foundIdsBefore.contains('US1WC04M'), isFalse, reason: 'Invalid bounded chart US1WC04M should not be discovered');
      
      // STEP 3: Apply the cache invalidation fix
  logger.info('APPLYING FIX: Cache invalidation for charts with invalid bounds', context: 'WA.ChartDiscovery');
      
      final invalidCount = await storageService.countChartsWithInvalidBounds();
  logger.info('ANALYSIS: Found $invalidCount charts with invalid bounds (0,0,0,0)', context: 'WA.ChartDiscovery');
      
      expect(invalidCount, equals(2), reason: 'Should detect exactly 2 charts with invalid bounds');
      
      final clearedCount = await storageService.clearChartsWithInvalidBounds();
  logger.info('CACHE INVALIDATION: Cleared $clearedCount charts with invalid bounds', context: 'WA.ChartDiscovery');
      
      expect(clearedCount, equals(2), reason: 'Should clear exactly 2 problematic charts');
      
      // STEP 4: Simulate re-fetching with correct geometry (what would happen after force refresh)
  logger.info('SIMULATION: Re-caching charts with correct bounds from NOAA geometry', context: 'WA.ChartDiscovery');
      
      final correctedChart1 = Chart(
        id: 'US1WC01M',
        title: 'Columbia River to Destruction I.',
        scale: 80000,
        bounds: GeographicBounds(north: 46.3, south: 46.0, east: -123.8, west: -124.2), // Correct bounds
        lastUpdate: DateTime(2024, 1, 15),
        state: 'Washington',
        type: ChartType.general,
      );
      
      final correctedChart2 = Chart(
        id: 'US1WC04M',
        title: 'Cape Disappointment to Lincoln City',
        scale: 80000,
        bounds: GeographicBounds(north: 46.5, south: 44.5, east: -123.5, west: -124.5), // Correct bounds
        lastUpdate: DateTime(2024, 1, 15),
        state: 'Washington',
        type: ChartType.general,
      );
      
      await storageService.storeChart(correctedChart1, [1]);
      await storageService.storeChart(correctedChart2, [1]);
      
      // STEP 5: Verify the fix works
  logger.info('VERIFICATION: Searching for charts in Washington state bounds again', context: 'WA.ChartDiscovery');
      
    final foundAfter = await storageService.getChartsInBounds(washingtonBounds);
  logger.info('ISSUE RESOLVED: Found ${foundAfter.length} charts after re-caching', context: 'WA.ChartDiscovery');
      
    final foundIdsAfter = foundAfter.map((c) => c.id).toSet();
    expect(foundIdsAfter.containsAll({'US1WC01M', 'US1WC04M'}), isTrue, reason: 'Both corrected Washington charts should now be discovered');
      
      // STEP 6: Verify cache is now clean
      final remainingInvalidCount = await storageService.countChartsWithInvalidBounds();
  logger.info('FINAL STATE: $remainingInvalidCount charts with invalid bounds remain', context: 'WA.ChartDiscovery');
      
      expect(remainingInvalidCount, equals(0), reason: 'No charts with invalid bounds should remain after fix');
      
      logger.info('SUCCESS: Washington chart discovery issue #129 resolved', context: 'WA.ChartDiscovery');
      logger.info('SUMMARY: cleared $clearedCount invalid charts; discovery returns ${foundAfter.length}; cache invalidation confirmed', context: 'WA.ChartDiscovery');
    });
  });
}
