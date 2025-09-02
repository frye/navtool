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
      print('\n🔴 REPRODUCING ISSUE: Simulating old cached charts with invalid bounds');
      
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
      print('📍 TESTING: Searching for charts in Washington state bounds');
      
      final washingtonBounds = GeographicBounds(
        north: 49.0, south: 45.5, east: -116.9, west: -124.8
      );
      
      final foundBefore = await storageService.getChartsInBounds(washingtonBounds);
      print('❌ ISSUE CONFIRMED: Found ${foundBefore.length} charts (should be 2, but invalid bounds cause 0 results)');
      
      expect(foundBefore.length, equals(0), reason: 'Old cached charts with invalid bounds should not be found');
      
      // STEP 3: Apply the cache invalidation fix
      print('\n🔧 APPLYING FIX: Cache invalidation for charts with invalid bounds');
      
      final invalidCount = await storageService.countChartsWithInvalidBounds();
      print('📊 ANALYSIS: Found $invalidCount charts with invalid bounds (0,0,0,0)');
      
      expect(invalidCount, equals(2), reason: 'Should detect exactly 2 charts with invalid bounds');
      
      final clearedCount = await storageService.clearChartsWithInvalidBounds();
      print('🧹 CACHE INVALIDATION: Cleared $clearedCount charts with invalid bounds');
      
      expect(clearedCount, equals(2), reason: 'Should clear exactly 2 problematic charts');
      
      // STEP 4: Simulate re-fetching with correct geometry (what would happen after force refresh)
      print('\n✅ SIMULATION: Re-caching charts with correct bounds from NOAA geometry');
      
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
      print('🔍 VERIFICATION: Searching for charts in Washington state bounds again');
      
      final foundAfter = await storageService.getChartsInBounds(washingtonBounds);
      print('✅ ISSUE RESOLVED: Found ${foundAfter.length} charts (correct result!)');
      
      expect(foundAfter.length, equals(2), reason: 'After cache invalidation and correction, both Washington charts should be found');
      expect(foundAfter.map((c) => c.id).toSet(), equals({'US1WC01M', 'US1WC04M'}));
      
      // STEP 6: Verify cache is now clean
      final remainingInvalidCount = await storageService.countChartsWithInvalidBounds();
      print('🎯 FINAL STATE: $remainingInvalidCount charts with invalid bounds remain');
      
      expect(remainingInvalidCount, equals(0), reason: 'No charts with invalid bounds should remain after fix');
      
      print('\n🎉 SUCCESS: Washington chart discovery issue #129 has been resolved!');
      print('📋 SUMMARY:');
      print('   - Detected and cleared $clearedCount charts with invalid bounds');
      print('   - Washington state chart discovery now returns ${foundAfter.length} charts');
      print('   - Cache invalidation workflow confirmed working');
    });
  });
}
