/// Example migration of chart quality monitor test to use real S57 data
/// 
/// This demonstrates how to migrate from TestFixtures.createTestChart() to
/// S57TestFixtures for realistic marine navigation testing.
/// 
/// BEFORE: Uses synthetic chart data via TestFixtures.createTestChart()
/// AFTER: Uses real NOAA ENC S57 charts via S57TestFixtures
///
/// This migration example addresses Issue #211 and shows patterns for other tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/chart_quality_monitor.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart_models.dart';

// Import the new S57TestFixtures utility instead of synthetic TestFixtures
import '../../utils/s57_test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  StateRegionMappingService,
  StorageService,
  CacheService,
  AppLogger,
])
import 'chart_quality_monitor_s57_test.mocks.dart';

/// Chart Quality Monitor test using real S57 NOAA ENC data
/// 
/// This demonstrates the migration from synthetic test data to real S57 charts
/// for improved marine navigation testing validity.
void main() {
  group('ChartQualityMonitor with Real S57 Data', () {
    late MockStateRegionMappingService mockMappingService;
    late MockStorageService mockStorageService;
    late MockCacheService mockCacheService;
    late MockAppLogger mockLogger;
    late ChartQualityMonitor qualityMonitor;

    setUpAll(() {
      // Verify S57 fixtures are available before running tests
      if (!S57TestFixtures.areAllChartsAvailable()) {
        print('Skipping S57 chart quality tests - fixtures not available');
        return;
      }
    });

    setUp(() {
      mockMappingService = MockStateRegionMappingService();
      mockStorageService = MockStorageService();
      mockCacheService = MockCacheService();
      mockLogger = MockAppLogger();

      qualityMonitor = ChartQualityMonitor(
        logger: mockLogger,
        storageService: mockStorageService,
        cacheService: mockCacheService,
        mappingService: mockMappingService,
      );
    });

    tearDown(() {
      qualityMonitor.dispose();
    });

    group('Chart Validation with Real S57 Data', () {
      test('should validate real Elliott Bay chart meets quality standards', () async {
        // Skip if fixtures not available
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        // BEFORE: Used synthetic chart data
        // final charts = [TestFixtures.createTestChart(id: 'TEST001', title: 'Test Chart')];
        
        // AFTER: Use real Elliott Bay S57 data
        final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
        
        // Convert S57 data to Chart objects for quality monitoring
        final realChart = _convertS57DataToChart(
          elliottBayData,
          S57TestFixtures.elliottBayMetadata,
        );
        
        final charts = [realChart];

        // Set up mock responses
        when(mockMappingService.getStateRegion(any))
            .thenAnswer((_) async => 'Washington');

        // Test chart validation with real data
        final result = await qualityMonitor.validateCharts(charts);

        // Verify validation results with real chart characteristics
        expect(result.isValid, isTrue, reason: 'Real Elliott Bay chart should be valid');
        expect(result.validatedCharts, hasLength(1));
        expect(result.validatedCharts.first.id, equals('US5WA50M'));
        expect(result.validatedCharts.first.title, contains('ELLIOTT BAY'));
        expect(result.validatedCharts.first.scale, equals(20000)); // Harbor scale
      });

      test('should detect quality issues with real chart geographic bounds', () async {
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        // Load real Puget Sound chart for coastal-scale testing
        final pugetSoundData = await S57TestFixtures.loadParsedPugetSound();
        final realBounds = S57TestFixtures.getChartBounds(pugetSoundData);
        
        // Create chart with real S57 bounds
        final coastalChart = Chart(
          id: 'US3WA01M',
          title: 'PUGET SOUND NORTHERN PART',
          scale: 90000, // Coastal scale
          bounds: realBounds,
          lastUpdate: DateTime.now().subtract(const Duration(days: 30)),
          state: 'Washington',
          type: ChartType.coastal,
          source: ChartSource.noaa,
          status: ChartStatus.current,
          edition: 1,
          updateNumber: 0,
        );

        // Validate bounds are realistic for marine navigation
        expect(realBounds.isValidForMarine, isTrue,
            reason: 'Real Puget Sound bounds should be valid for marine use');
        expect(realBounds.north, greaterThan(47.0),
            reason: 'Puget Sound is in Pacific Northwest');
        expect(realBounds.west, lessThan(-122.0),
            reason: 'Puget Sound is west of -122°');

        // Test quality monitoring with real geographic data
        final result = await qualityMonitor.validateCharts([coastalChart]);
        expect(result.isValid, isTrue);
      });

      test('should validate real S57 feature distribution for quality assessment', () async {
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        // Load Elliott Bay for feature analysis
        final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
        final featureDistribution = S57TestFixtures.getFeatureTypeDistribution(elliottBayData);

        // Verify real chart has expected marine navigation features
        expect(featureDistribution, isNotEmpty,
            reason: 'Elliott Bay should contain S57 features');
        
        // Quality check: Harbor chart should have navigation aids
        final hasNavigationFeatures = featureDistribution.keys.any((type) =>
            [S57FeatureType.beacon, S57FeatureType.buoy, S57FeatureType.lighthouse]
            .contains(type));
        
        expect(hasNavigationFeatures, isTrue,
            reason: 'Harbor chart should contain navigation aids for safety');

        // Quality check: Should have depth information
        final hasDepthFeatures = featureDistribution.keys.any((type) =>
            [S57FeatureType.depthArea, S57FeatureType.sounding, S57FeatureType.depthContour]
            .contains(type));
            
        expect(hasDepthFeatures, isTrue,
            reason: 'Marine chart should contain depth information for navigation');
      });

      test('should handle performance requirements with real S57 chart processing', () async {
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        final stopwatch = Stopwatch()..start();
        
        // Test performance with real chart loading and validation
        final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
        final realChart = _convertS57DataToChart(
          elliottBayData, 
          S57TestFixtures.elliottBayMetadata,
        );
        
        final result = await qualityMonitor.validateCharts([realChart]);
        stopwatch.stop();

        // Verify performance meets marine navigation requirements
        expect(stopwatch.elapsedMilliseconds, lessThan(5000),
            reason: 'Chart quality validation should complete within 5 seconds for marine safety');
        expect(result.isValid, isTrue);
      });
    });

    group('Real Chart Metadata Validation', () {
      test('should validate real Elliott Bay metadata matches NOAA specifications', () async {
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        final elliottBayData = await S57TestFixtures.loadParsedElliottBay();
        
        // Validate chart metadata against known NOAA specifications
        S57TestFixtures.validateChartMetadata(elliottBayData, ChartType.harbor);
        
        // Verify expected Elliott Bay characteristics
        final metadata = S57TestFixtures.elliottBayMetadata;
        expect(metadata.cellId, equals('US5WA50M'));
        expect(metadata.usageBand, equals(5)); // Harbor scale
        expect(metadata.scale, equals('1:20,000'));
        expect(metadata.region, contains('Elliott Bay'));
        
        // Verify feature count meets expectations for harbor chart
        expect(elliottBayData.features.length, 
            greaterThanOrEqualTo(metadata.expectedMinFeatures));
      });

      test('should validate real Puget Sound metadata for coastal navigation', () async {
        if (!S57TestFixtures.areAllChartsAvailable()) return;

        final pugetSoundData = await S57TestFixtures.loadParsedPugetSound();
        
        // Validate coastal chart metadata
        S57TestFixtures.validateChartMetadata(pugetSoundData, ChartType.coastal);
        
        // Verify expected Puget Sound characteristics  
        final metadata = S57TestFixtures.pugetSoundMetadata;
        expect(metadata.cellId, equals('US3WA01M'));
        expect(metadata.usageBand, equals(3)); // Coastal scale
        expect(metadata.scale, equals('1:90,000'));
        expect(metadata.region, contains('Puget Sound'));
        
        // Coastal charts should have more features than harbor charts
        expect(pugetSoundData.features.length,
            greaterThan(elliottBayData.features.length),
            reason: 'Coastal charts typically have more features than harbor charts');
      });
    });
  });
}

/// Helper function to convert S57ParsedData to Chart object
/// 
/// This demonstrates the conversion pattern needed when migrating tests
/// from synthetic Chart objects to real S57 data.
Chart _convertS57DataToChart(S57ParsedData s57Data, ChartTestMetadata metadata) {
  final bounds = S57TestFixtures.getChartBounds(s57Data);
  
  return Chart(
    id: metadata.cellId,
    title: metadata.title,
    scale: int.parse(metadata.scale.replaceAll(RegExp(r'[^0-9]'), '')), // Extract scale number
    bounds: bounds,
    lastUpdate: DateTime.now().subtract(const Duration(days: 30)),
    state: 'Washington', // Elliott Bay and Puget Sound are in Washington
    type: metadata.usageBand == 5 ? ChartType.harbor : ChartType.coastal,
    source: ChartSource.noaa,
    status: ChartStatus.current,
    edition: 1,
    updateNumber: 0,
    metadata: {
      'feature_count': s57Data.features.length,
      'feature_types': S57TestFixtures.getFeatureTypeDistribution(s57Data)
          .map((k, v) => MapEntry(k.name, v)),
      's57_metadata': s57Data.metadata,
    },
  );
}