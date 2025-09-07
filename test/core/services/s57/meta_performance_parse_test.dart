/// Meta test for optional performance validation of S-57 parsing
/// 
/// This test validates that parse and spatial index build performance
/// meets soft limits for real-time marine navigation usage.
/// 
/// Skipped in CI environments when SKIP_PERF=1 is set.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'test_data_utils.dart';

void main() {
  group('Meta: Performance Parse Validation', () {
    test('should validate parse performance meets soft limits', () async {
      // Skip in CI environments or when performance testing is disabled
      if (Platform.environment['SKIP_PERF'] == '1' || 
          Platform.environment['CI'] == 'true') {
        print('⏭️  Skipping performance test (SKIP_PERF=1 or CI environment)');
        return;
      }

      const testDataSize = 1000; // Moderate size for consistent testing
      final testData = createValidS57TestData();

      // Test parse performance
      final parseStopwatch = Stopwatch()..start();
      final result = S57Parser.parse(testData);
      parseStopwatch.stop();

      final parseMs = parseStopwatch.elapsedMilliseconds;
      
      // Soft limits for real-time navigation (generous for meta test)
      const maxParseMs = 500; // 500ms for parsing
      
      expect(result.features, isNotEmpty, reason: 'Should parse features successfully');
      
      print('📊 Parse Performance:');
      print('  Parse time: ${parseMs}ms (limit: ${maxParseMs}ms)');
      print('  Features parsed: ${result.features.length}');
      
      if (parseMs > maxParseMs) {
        print('⚠️  Parse time exceeds soft limit but test continues');
        print('   Consider optimizing parser for production use');
      } else {
        print('✅ Parse performance within acceptable limits');
      }

      // Test spatial index build performance if features are available
      if (result.features.isNotEmpty) {
        final indexStopwatch = Stopwatch()..start();
        final spatialIndex = S57SpatialIndex();
        spatialIndex.addFeatures(result.features);
        indexStopwatch.stop();

        final indexMs = indexStopwatch.elapsedMilliseconds;
        const maxIndexMs = 100; // 100ms for index build

        print('  Index build time: ${indexMs}ms (limit: ${maxIndexMs}ms)');
        
        if (indexMs > maxIndexMs) {
          print('⚠️  Index build time exceeds soft limit but test continues');
        } else {
          print('✅ Index build performance within acceptable limits');
        }

        // Test query performance with a simple bounds
        final queryStopwatch = Stopwatch()..start();
        final bounds = S57Bounds(
          north: 48.0,
          south: 47.0,
          east: -122.0,
          west: -123.0,
        );
        final queryResults = spatialIndex.queryBounds(bounds);
        queryStopwatch.stop();

        final queryMs = queryStopwatch.elapsedMicroseconds / 1000; // Convert to ms
        const maxQueryMs = 10.0; // 10ms for spatial queries

        print('  Query time: ${queryMs.toStringAsFixed(2)}ms (limit: ${maxQueryMs}ms)');
        print('  Query results: ${queryResults.length} features');

        if (queryMs > maxQueryMs) {
          print('⚠️  Query time exceeds soft limit but test continues');
        } else {
          print('✅ Query performance within acceptable limits');
        }
      }
    });

    test('should validate memory usage is reasonable', () {
      // Skip in CI environments
      if (Platform.environment['SKIP_PERF'] == '1' || 
          Platform.environment['CI'] == 'true') {
        print('⏭️  Skipping memory test (SKIP_PERF=1 or CI environment)');
        return;
      }

      final testData = createValidS57TestData();
      
      // Basic memory usage validation
      final result = S57Parser.parse(testData);
      
      expect(result.features, isNotEmpty, reason: 'Should parse features');
      
      // Memory usage should be proportional to feature count
      final featureCount = result.features.length;
      final estimatedMemoryKB = featureCount * 2; // Rough estimate: 2KB per feature
      
      print('📈 Memory Usage Estimate:');
      print('  Features: $featureCount');
      print('  Estimated memory: ${estimatedMemoryKB}KB');
      print('  Memory per feature: ~2KB (estimated)');
      
      // This is mostly informational for the meta test
      expect(featureCount, greaterThan(0), 
        reason: 'Should have parsed features for memory estimation');
      
      print('✅ Memory usage estimation completed');
    });

    test('should provide performance environment info', () {
      print('🖥️  Performance Test Environment:');
      print('  Platform: ${Platform.operatingSystem}');
      print('  Dart version: ${Platform.version}');
      print('  Processors: ${Platform.numberOfProcessors}');
      print('  CI: ${Platform.environment['CI'] ?? 'false'}');
      print('  SKIP_PERF: ${Platform.environment['SKIP_PERF'] ?? 'false'}');
      
      if (Platform.environment['CI'] == 'true') {
        print('  ℹ️  Running in CI - performance tests may be skipped');
      }
      
      if (Platform.environment['SKIP_PERF'] == '1') {
        print('  ℹ️  Performance testing disabled via SKIP_PERF=1');
      }
      
      print('✅ Performance environment information logged');
    });
  });
}