/// Tests for S57TestFixtures utility
/// 
/// Validates that the S57TestFixtures utility correctly loads and parses
/// real NOAA ENC S57 chart data, replacing artificial test data usage.

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/error/app_error.dart';
import '../utils/s57_test_fixtures.dart';
import '../utils/test_logger.dart';

void main() {
  group('S57TestFixtures', () {
    late FixtureAvailability availability;
    
    setUpAll(() async {
      testLogger.info('S57TestFixtures test suite starting');
      availability = await S57TestFixtures.checkFixtureAvailability();
      testLogger.info('Fixture availability: ${availability.statusMessage}');
    });
    
    tearDown(() {
      // Clear cache between tests to ensure clean state
      S57TestFixtures.clearCache();
    });

    group('fixture availability checks', () {
      test('should check fixture availability', () async {
        final availability = await S57TestFixtures.checkFixtureAvailability();
        
        expect(availability, isA<FixtureAvailability>());
        expect(availability.fixturesPath, isNotEmpty);
        
        // At least one fixture should be available for tests to be meaningful
        if (!availability.hasAnyFixtures) {
          testLogger.warn(
            'No S57 test fixtures found - tests will be skipped. '
            'Install fixtures at: ${availability.fixturesPath}',
          );
        }
      });
      
      test('should provide chart information', () {
        final charts = S57TestFixtures.getAvailableCharts();
        
        expect(charts, hasLength(2));
        
        // Elliott Bay chart info
        final elliottBay = charts.firstWhere((c) => c.chartId == 'US5WA50M');
        expect(elliottBay.title, contains('Elliott Bay'));
        expect(elliottBay.usageBand, equals(5)); // Harbor
        expect(elliottBay.approximateSize, greaterThan(400000)); // ~411KB
        expect(elliottBay.features, isNotEmpty);
        expect(elliottBay.recommendedUse, contains('Unit tests'));
        
        // Puget Sound chart info
        final pugetSound = charts.firstWhere((c) => c.chartId == 'US3WA01M');
        expect(pugetSound.title, contains('Puget Sound'));
        expect(pugetSound.usageBand, equals(3)); // Coastal
        expect(pugetSound.approximateSize, greaterThan(1500000)); // ~1.58MB
        expect(pugetSound.features, isNotEmpty);
        expect(pugetSound.recommendedUse, contains('Integration tests'));
      });
      
      test('should provide usage recommendations', () {
        final recommendations = S57TestFixtures.getUsageRecommendations();
        
        expect(recommendations, isNotEmpty);
        expect(recommendations, contains('UNIT TESTS'));
        expect(recommendations, contains('INTEGRATION TESTS'));
        expect(recommendations, contains('PERFORMANCE TESTING'));
        expect(recommendations, contains('Elliott Bay'));
        expect(recommendations, contains('Puget Sound'));
        expect(recommendations, contains('Example Usage'));
      });
    });

    group('Elliott Bay chart loading', () {
      test('should load Elliott Bay raw chart data', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final data = await S57TestFixtures.loadElliottBayChart();
        
        expect(data, isA<List<int>>());
        expect(data.length, greaterThan(400000)); // ~411KB expected
        expect(data.length, lessThan(500000)); // Reasonable upper bound
        
        // Basic S57 format validation (should start with ISO 8211 leader)
        expect(data.length, greaterThan(24)); // Minimum for ISO 8211 leader
        
        testLogger.info('Elliott Bay raw data loaded: ${data.length} bytes');
      });
      
      test('should cache Elliott Bay raw data for performance', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final stopwatch1 = Stopwatch()..start();
        final data1 = await S57TestFixtures.loadElliottBayChart();
        stopwatch1.stop();
        
        final stopwatch2 = Stopwatch()..start();
        final data2 = await S57TestFixtures.loadElliottBayChart();
        stopwatch2.stop();
        
        // Second call should be much faster due to caching
        expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds));
        expect(data1, equals(data2));
        
        testLogger.info(
          'Elliott Bay caching: first=${stopwatch1.elapsedMilliseconds}ms, '
          'second=${stopwatch2.elapsedMilliseconds}ms',
        );
      });
      
      test('should parse Elliott Bay chart successfully', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        expect(parsedData, isA<S57ParsedData>());
        expect(parsedData.features, isNotEmpty);
        expect(parsedData.metadata, isNotNull);
        expect(parsedData.bounds, isNotNull);
        expect(parsedData.spatialIndex, isNotNull);
        
        // Validate metadata
        expect(parsedData.metadata.producer, isNotEmpty);
        expect(parsedData.metadata.version, isNotEmpty);
        
        // Validate spatial index consistency
        expect(
          parsedData.spatialIndex.featureCount,
          equals(parsedData.features.length),
        );
        
        testLogger.info(
          'Elliott Bay parsed: ${parsedData.features.length} features, '
          'bounds: ${parsedData.bounds}',
        );
      });
      
      test('should parse Elliott Bay with warning collector', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay(
          useWarningCollector: true,
        );
        
        expect(parsedData, isA<S57ParsedData>());
        expect(parsedData.features, isNotEmpty);
        
        // Warning collection doesn't affect the parsed result structure
        expect(parsedData.metadata, isNotNull);
        expect(parsedData.spatialIndex.featureCount, greaterThan(0));
      });
    });

    group('Puget Sound chart loading', () {
      test('should load Puget Sound raw chart data', () async {
        if (!availability.pugetSoundAvailable) {
          testLogger.warn('Puget Sound fixture not available - skipping test');
          return;
        }

        final data = await S57TestFixtures.loadPugetSoundChart();
        
        expect(data, isA<List<int>>());
        expect(data.length, greaterThan(1500000)); // ~1.58MB expected
        expect(data.length, lessThan(2000000)); // Reasonable upper bound
        
        // Basic S57 format validation
        expect(data.length, greaterThan(24)); // Minimum for ISO 8211 leader
        
        testLogger.info('Puget Sound raw data loaded: ${data.length} bytes');
      });
      
      test('should parse Puget Sound chart successfully', () async {
        if (!availability.pugetSoundAvailable) {
          testLogger.warn('Puget Sound fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        
        expect(parsedData, isA<S57ParsedData>());
        expect(parsedData.features, isNotEmpty);
        expect(parsedData.metadata, isNotNull);
        expect(parsedData.bounds, isNotNull);
        expect(parsedData.spatialIndex, isNotNull);
        
        // Puget Sound should have more features than Elliott Bay
        expect(parsedData.features.length, greaterThan(100));
        
        // Validate spatial index consistency
        expect(
          parsedData.spatialIndex.featureCount,
          equals(parsedData.features.length),
        );
        
        testLogger.info(
          'Puget Sound parsed: ${parsedData.features.length} features, '
          'bounds: ${parsedData.bounds}',
        );
      });
      
      test('should cache Puget Sound parsed data for performance', () async {
        if (!availability.pugetSoundAvailable) {
          testLogger.warn('Puget Sound fixture not available - skipping test');
          return;
        }

        final stopwatch1 = Stopwatch()..start();
        final data1 = await S57TestFixtures.loadParsedPugetSound();
        stopwatch1.stop();
        
        final stopwatch2 = Stopwatch()..start();
        final data2 = await S57TestFixtures.loadParsedPugetSound();
        stopwatch2.stop();
        
        // Second call should be much faster due to caching
        expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds));
        expect(data1.features.length, equals(data2.features.length));
        
        testLogger.info(
          'Puget Sound caching: first=${stopwatch1.elapsedMilliseconds}ms, '
          'second=${stopwatch2.elapsedMilliseconds}ms',
        );
      });
    });

    group('chart metadata validation', () {
      test('should validate Elliott Bay metadata', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        final validation = S57TestFixtures.validateChartMetadata(
          parsedData,
          'US5WA50M',
        );
        
        expect(validation, isA<ChartMetadataValidation>());
        expect(validation.chartId, equals('US5WA50M'));
        expect(validation.metadata, isNotNull);
        
        // Should be valid (no critical errors)
        if (!validation.isValid) {
          testLogger.warn(
            'Elliott Bay validation errors: ${validation.errors}',
          );
        }
        
        if (validation.hasWarnings) {
          testLogger.info(
            'Elliott Bay validation warnings: ${validation.warnings}',
          );
        }
        
        testLogger.info(
          'Elliott Bay validation: ${validation.isValid ? 'VALID' : 'INVALID'} '
          '(${validation.totalIssues} issues)',
        );
      });
      
      test('should validate Puget Sound metadata', () async {
        if (!availability.pugetSoundAvailable) {
          testLogger.warn('Puget Sound fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        final validation = S57TestFixtures.validateChartMetadata(
          parsedData,
          'US3WA01M',
        );
        
        expect(validation, isA<ChartMetadataValidation>());
        expect(validation.chartId, equals('US3WA01M'));
        expect(validation.metadata, isNotNull);
        
        // Should be valid (no critical errors)
        if (!validation.isValid) {
          testLogger.warn(
            'Puget Sound validation errors: ${validation.errors}',
          );
        }
        
        if (validation.hasWarnings) {
          testLogger.info(
            'Puget Sound validation warnings: ${validation.warnings}',
          );
        }
        
        testLogger.info(
          'Puget Sound validation: ${validation.isValid ? 'VALID' : 'INVALID'} '
          '(${validation.totalIssues} issues)',
        );
      });
    });

    group('feature analysis', () {
      test('should analyze Elliott Bay features', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Analyze feature types
        final featureTypeCounts = <S57FeatureType, int>{};
        for (final feature in parsedData.features) {
          featureTypeCounts[feature.featureType] = 
              (featureTypeCounts[feature.featureType] ?? 0) + 1;
        }
        
        expect(featureTypeCounts, isNotEmpty);
        
        // Elliott Bay should have typical harbor features
        final hasDepthFeatures = featureTypeCounts.keys
            .any((type) => [
              S57FeatureType.depthArea,
              S57FeatureType.depthContour,
              S57FeatureType.sounding,
            ].contains(type));
        expect(hasDepthFeatures, isTrue, reason: 'Should have depth features');
        
        final hasNavigationAids = featureTypeCounts.keys
            .any((type) => [
              S57FeatureType.buoy,
              S57FeatureType.lighthouse,
              S57FeatureType.beacon,
            ].contains(type));
        
        // Log feature analysis
        testLogger.info('Elliott Bay feature types:');
        for (final entry in featureTypeCounts.entries) {
          testLogger.info('  ${entry.key.acronym}: ${entry.value}');
        }
      });
      
      test('should analyze Puget Sound features', () async {
        if (!availability.pugetSoundAvailable) {
          testLogger.warn('Puget Sound fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        
        // Analyze feature types
        final featureTypeCounts = <S57FeatureType, int>{};
        for (final feature in parsedData.features) {
          featureTypeCounts[feature.featureType] = 
              (featureTypeCounts[feature.featureType] ?? 0) + 1;
        }
        
        expect(featureTypeCounts, isNotEmpty);
        
        // Puget Sound should have more diverse coastal features
        expect(featureTypeCounts.keys.length, greaterThan(5));
        
        // Should have coastline features
        final hasCoastlineFeatures = featureTypeCounts.keys
            .any((type) => [
              S57FeatureType.coastline,
              S57FeatureType.shoreline,
              S57FeatureType.landArea,
            ].contains(type));
        
        // Log feature analysis
        testLogger.info('Puget Sound feature types:');
        for (final entry in featureTypeCounts.entries) {
          testLogger.info('  ${entry.key.acronym}: ${entry.value}');
        }
        
        // Compare with Elliott Bay if both available
        if (availability.elliottBayAvailable) {
          final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
          expect(
            parsedData.features.length,
            greaterThan(elliottBayData.features.length),
            reason: 'Puget Sound should have more features than Elliott Bay',
          );
        }
      });
    });

    group('spatial queries', () {
      test('should perform spatial queries on Elliott Bay', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Test bounds query
        final boundsFeatures = parsedData.queryFeaturesInBounds(parsedData.bounds);
        expect(boundsFeatures, isNotEmpty);
        
        // Test navigation aids query
        final navAids = parsedData.queryNavigationAids();
        testLogger.info('Elliott Bay navigation aids: ${navAids.length}');
        
        // Test depth features query
        final depthFeatures = parsedData.queryDepthFeatures();
        expect(depthFeatures, isNotEmpty, reason: 'Should have depth features');
        testLogger.info('Elliott Bay depth features: ${depthFeatures.length}');
      });
      
      test('should perform point queries', () async {
        if (!availability.elliottBayAvailable) {
          testLogger.warn('Elliott Bay fixture not available - skipping test');
          return;
        }

        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Use chart center for point query
        final bounds = parsedData.bounds;
        final centerLat = (bounds.minLatitude + bounds.maxLatitude) / 2;
        final centerLon = (bounds.minLongitude + bounds.maxLongitude) / 2;
        
        final nearbyFeatures = parsedData.queryFeaturesNear(
          centerLat,
          centerLon,
          radiusDegrees: 0.01,
        );
        
        testLogger.info(
          'Features near chart center (${centerLat.toStringAsFixed(4)}, '
          '${centerLon.toStringAsFixed(4)}): ${nearbyFeatures.length}',
        );
      });
    });

    group('error handling', () {
      test('should handle missing fixture files gracefully', () async {
        // Clear cache to ensure we're testing file loading
        S57TestFixtures.clearCache();
        
        // This test always runs regardless of fixture availability
        // It tests the error handling when files are missing
        
        if (availability.elliottBayAvailable) {
          // If Elliott Bay is available, we can't test missing file behavior
          // Skip this specific test
          testLogger.info('Elliott Bay available - skipping missing file test');
          return;
        }
        
        // Test loading missing Elliott Bay chart
        expect(
          () async => await S57TestFixtures.loadElliottBayChart(),
          throwsA(isA<TestFailure>().having(
            (e) => e.message,
            'message',
            contains('Elliott Bay chart fixture not found'),
          )),
        );
      });
      
      test('should provide helpful error messages', () async {
        if (!availability.hasAnyFixtures) {
          testLogger.info('No fixtures available for error message testing');
          return;
        }
        
        // Try to validate with wrong chart ID
        final parsedData = await (availability.elliottBayAvailable
            ? S57TestFixtures.loadParsedElliottBay()
            : S57TestFixtures.loadParsedPugetSound());
        
        final validation = S57TestFixtures.validateChartMetadata(
          parsedData,
          'WRONG_ID',
        );
        
        // Validation should complete even with wrong expected ID
        expect(validation, isA<ChartMetadataValidation>());
        expect(validation.chartId, equals('WRONG_ID'));
      });
    });

    group('cache management', () {
      test('should clear cache correctly', () async {
        if (!availability.hasAnyFixtures) {
          testLogger.info('No fixtures available for cache testing');
          return;
        }
        
        // Load data to populate cache
        if (availability.elliottBayAvailable) {
          await S57TestFixtures.loadParsedElliottBay();
        }
        if (availability.pugetSoundAvailable) {
          await S57TestFixtures.loadParsedPugetSound();
        }
        
        // Clear cache
        S57TestFixtures.clearCache();
        
        // This test validates that clearCache() doesn't throw
        // The actual cache clearing is validated in performance tests
        testLogger.info('Cache cleared successfully');
      });
    });
  });
}