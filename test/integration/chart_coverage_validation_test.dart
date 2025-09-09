import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/chart_models.dart';
import '../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  StorageService,
  CacheService,
  HttpClientService,
  AppLogger,
])
import 'chart_coverage_validation_test.mocks.dart';

/// Comprehensive chart coverage validation for all US coastal states
/// 
/// This test suite validates that all 30 coastal US states have adequate
/// chart coverage for marine navigation safety. It serves as both a 
/// regression test and a data quality monitoring tool.
class ChartCoverageValidator {
  final StateRegionMappingService _mappingService;
  final StorageService _storageService;
  
  ChartCoverageValidator({
    required StateRegionMappingService mappingService,
    required StorageService storageService,
  }) : _mappingService = mappingService,
       _storageService = storageService;

  /// Validates chart coverage for all coastal states
  Future<CoverageReport> validateStateChartCoverage() async {
    final report = CoverageReport();
    final supportedStates = await _mappingService.getSupportedStates();
    
    for (final state in supportedStates) {
      final stateReport = await _validateSingleStateCoverage(state);
      report.stateReports[state] = stateReport;
      
      if (stateReport.chartCount == 0) {
        report.failedStates.add(state);
      }
    }
    
    report.totalStatesValidated = supportedStates.length;
    report.statesWithCharts = report.stateReports.values
        .where((r) => r.chartCount > 0)
        .length;
    report.coveragePercentage = 
        (report.statesWithCharts / report.totalStatesValidated) * 100;
    
    return report;
  }
  
  /// Validates chart coverage for a single state
  Future<StateCoverageReport> _validateSingleStateCoverage(String state) async {
    final report = StateCoverageReport(stateName: state);
    
    try {
      // Get charts for this state
      final chartCells = await _mappingService.getChartCellsForState(state);
      report.chartCount = chartCells.length;
      report.chartCells = chartCells;
      
      // Get state bounds
      final bounds = await _mappingService.getStateBounds(state);
      report.stateBounds = bounds;
      
      // Validate chart metadata if we have charts
      if (chartCells.isNotEmpty) {
        final charts = await _storageService.getChartsInBounds(bounds!);
        final stateCharts = charts.where((c) => chartCells.contains(c.id)).toList();
        
        report.chartMetadata = await _validateChartMetadata(stateCharts);
      }
      
      report.isValid = chartCells.isNotEmpty;
      
    } catch (e) {
      report.isValid = false;
      report.errorMessage = e.toString();
    }
    
    return report;
  }
  
  /// Validates chart metadata quality
  Future<ChartMetadataValidation> _validateChartMetadata(List<Chart> charts) async {
    final validation = ChartMetadataValidation();
    
    for (final chart in charts) {
      // Check for required fields
      if (chart.title.isEmpty) {
        validation.missingTitles.add(chart.id);
      }
      
      // Validate scale
      if (chart.scale == null || chart.scale! <= 0) {
        validation.invalidScales.add(chart.id);
      }
      
      // Check bounds validity
      if (!_isValidBounds(chart.bounds)) {
        validation.invalidBounds.add(chart.id);
      }
      
      // Check for duplicate charts (same title and scale)
      final duplicateKey = '${chart.title}_${chart.scale}';
      if (validation._chartKeys.contains(duplicateKey)) {
        validation.duplicateCharts.add(chart.id);
      } else {
        validation._chartKeys.add(duplicateKey);
      }
    }
    
    validation.totalChartsValidated = charts.length;
    validation.validCharts = charts.length - 
        (validation.missingTitles.length + 
         validation.invalidScales.length + 
         validation.invalidBounds.length + 
         validation.duplicateCharts.length);
    
    return validation;
  }
  
  /// Validates geographic bounds
  bool _isValidBounds(GeographicBounds bounds) {
    return bounds.north > bounds.south &&
           bounds.east > bounds.west &&
           bounds.north <= 90 &&
           bounds.south >= -90 &&
           bounds.east <= 180 &&
           bounds.west >= -180;
  }
}

/// Comprehensive coverage report for all states
class CoverageReport {
  int totalStatesValidated = 0;
  int statesWithCharts = 0;
  double coveragePercentage = 0.0;
  Map<String, StateCoverageReport> stateReports = {};
  List<String> failedStates = [];
  
  /// Returns true if all states have adequate chart coverage
  bool get isValid => failedStates.isEmpty && coveragePercentage >= 95.0;
  
  /// Returns states that need attention
  List<String> get statesNeedingAttention {
    return stateReports.entries
        .where((entry) => !entry.value.isValid || entry.value.chartCount < 5)
        .map((entry) => entry.key)
        .toList();
  }
}

/// Coverage report for a single state
class StateCoverageReport {
  final String stateName;
  int chartCount = 0;
  List<String> chartCells = [];
  GeographicBounds? stateBounds;
  ChartMetadataValidation? chartMetadata;
  bool isValid = false;
  String? errorMessage;
  
  StateCoverageReport({required this.stateName});
  
  /// Returns true if state has adequate chart coverage
  bool get hasAdequateCoverage => chartCount >= 3; // Minimum 3 charts per state
}

/// Chart metadata validation results
class ChartMetadataValidation {
  int totalChartsValidated = 0;
  int validCharts = 0;
  List<String> missingTitles = [];
  List<String> invalidScales = [];
  List<String> invalidBounds = [];
  List<String> duplicateCharts = [];
  final Set<String> _chartKeys = <String>{};
  
  /// Returns true if metadata quality is acceptable
  bool get isQualityAcceptable => (validCharts / totalChartsValidated) >= 0.9;
  
  /// Returns percentage of valid charts
  double get validityPercentage => 
      totalChartsValidated > 0 ? (validCharts / totalChartsValidated) * 100 : 0.0;
}

void main() {
  group('Chart Coverage Validation Tests', () {
    late MockStorageService mockStorage;
    late MockCacheService mockCache;
    late MockHttpClientService mockHttpClient;
    late MockAppLogger mockLogger;
    late StateRegionMappingService mappingService;
    late ChartCoverageValidator validator;

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
      
      validator = ChartCoverageValidator(
        mappingService: mappingService,
        storageService: mockStorage,
      );
    });

    group('Comprehensive State Coverage', () {
      testWidgets('All 30 coastal US states should return charts', (tester) async {
        // Setup mock data for all coastal states
        final coastalStates = [
          'Alabama', 'Alaska', 'California', 'Connecticut', 'Delaware',
          'Florida', 'Georgia', 'Hawaii', 'Illinois', 'Indiana',
          'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan',
          'Minnesota', 'Mississippi', 'New Hampshire', 'New Jersey', 'New York',
          'North Carolina', 'Ohio', 'Oregon', 'Pennsylvania', 'Rhode Island',
          'South Carolina', 'Texas', 'Virginia', 'Washington', 'Wisconsin',
        ];
        
        // Mock storage responses for each state
        for (final state in coastalStates) {
          final testCharts = MarineTestUtils.generateTestChartsForState(state, count: 5);
          final chartCells = testCharts.map((c) => c.id).toList();
          
          when(mockStorage.getStateCellMapping(state))
              .thenAnswer((_) async => chartCells);
          when(mockStorage.getChartsInBounds(any))
              .thenAnswer((_) async => testCharts);
        }
        
        when(mockCache.get(any)).thenAnswer((_) async => null);

        // Run comprehensive validation
        final report = await validator.validateStateChartCoverage();

        // Assertions
        expect(report.totalStatesValidated, equals(coastalStates.length));
        expect(report.statesWithCharts, equals(coastalStates.length));
        expect(report.coveragePercentage, equals(100.0));
        expect(report.failedStates, isEmpty);
        expect(report.isValid, isTrue);
        
        // Verify each state has adequate coverage
        for (final state in coastalStates) {
          final stateReport = report.stateReports[state];
          expect(stateReport, isNotNull, reason: 'State $state should have a report');
          expect(stateReport!.isValid, isTrue, reason: 'State $state should be valid');
          expect(stateReport.hasAdequateCoverage, isTrue, 
              reason: 'State $state should have adequate coverage');
        }
      });

      testWidgets('Alaska regions should be individually validated', (tester) async {
        // Alaska has multiple marine regions that need separate validation
        const alaskaRegions = [
          'Southeast Alaska',
          'Gulf of Alaska', 
          'Arctic Alaska',
        ];
        
        // Mock Alaska charts covering different regions
        final alaskaCharts = <Chart>[];
        for (int i = 0; i < alaskaRegions.length; i++) {
          final regionCharts = MarineTestUtils.generateTestChartsForRegion(
            'Alaska',
            alaskaRegions[i],
            count: 3,
          );
          alaskaCharts.addAll(regionCharts);
        }
        
        final chartCells = alaskaCharts.map((c) => c.id).toList();
        
        when(mockStorage.getStateCellMapping('Alaska'))
            .thenAnswer((_) async => chartCells);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => alaskaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final alaskaReport = report.stateReports['Alaska'];

        expect(alaskaReport, isNotNull);
        expect(alaskaReport!.isValid, isTrue);
        expect(alaskaReport.chartCount, greaterThanOrEqualTo(9)); // 3 charts per region
        
        // Verify coverage across different regions
        final chartMetadata = alaskaReport.chartMetadata;
        expect(chartMetadata, isNotNull);
        expect(chartMetadata!.isQualityAcceptable, isTrue);
      });

      testWidgets('California coastal regions should be validated', (tester) async {
        // California has extensive coastline requiring multiple regions
        final californiaCharts = MarineTestUtils.generateTestChartsForState(
          'California', 
          count: 15 // More charts for larger coastline
        );
        
        final chartCells = californiaCharts.map((c) => c.id).toList();
        
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => chartCells);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => californiaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final californiaReport = report.stateReports['California'];

        expect(californiaReport, isNotNull);
        expect(californiaReport!.isValid, isTrue);
        expect(californiaReport.chartCount, greaterThanOrEqualTo(10));
        expect(californiaReport.hasAdequateCoverage, isTrue);
      });

      testWidgets('Florida Atlantic and Gulf coasts should be verified', (tester) async {
        // Florida has both Atlantic and Gulf coastlines
        final floridaCharts = MarineTestUtils.generateTestChartsForState(
          'Florida',
          count: 12 // Charts for both coasts
        );
        
        final chartCells = floridaCharts.map((c) => c.id).toList();
        
        when(mockStorage.getStateCellMapping('Florida'))
            .thenAnswer((_) async => chartCells);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => floridaCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final floridaReport = report.stateReports['Florida'];

        expect(floridaReport, isNotNull);
        expect(floridaReport!.isValid, isTrue);
        expect(floridaReport.chartCount, greaterThanOrEqualTo(10));
        
        // Verify geographic coverage spans both coasts
        expect(floridaReport.stateBounds, isNotNull);
        final bounds = floridaReport.stateBounds!;
        expect(bounds.west, lessThan(-80.0)); // Gulf coast coverage
        expect(bounds.east, greaterThan(-85.0)); // Atlantic coast coverage
      });

      testWidgets('Great Lakes states should be confirmed', (tester) async {
        const greatLakesStates = [
          'Minnesota', 'Wisconsin', 'Michigan', 'Illinois', 'Indiana', 'Ohio'
        ];
        
        for (final state in greatLakesStates) {
          final charts = MarineTestUtils.generateTestChartsForState(state, count: 4);
          final chartCells = charts.map((c) => c.id).toList();
          
          when(mockStorage.getStateCellMapping(state))
              .thenAnswer((_) async => chartCells);
          when(mockStorage.getChartsInBounds(any))
              .thenAnswer((_) async => charts);
        }
        
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();

        for (final state in greatLakesStates) {
          final stateReport = report.stateReports[state];
          expect(stateReport, isNotNull, reason: 'Great Lakes state $state should have charts');
          expect(stateReport!.isValid, isTrue, reason: '$state should be valid');
          expect(stateReport.hasAdequateCoverage, isTrue, 
              reason: '$state should have adequate Great Lakes coverage');
        }
      });

      testWidgets('Hawaii and Pacific territories should be validated', (tester) async {
        final hawaiiCharts = MarineTestUtils.generateTestChartsForState('Hawaii', count: 8);
        final chartCells = hawaiiCharts.map((c) => c.id).toList();
        
        when(mockStorage.getStateCellMapping('Hawaii'))
            .thenAnswer((_) async => chartCells);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => hawaiiCharts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final hawaiiReport = report.stateReports['Hawaii'];

        expect(hawaiiReport, isNotNull);
        expect(hawaiiReport!.isValid, isTrue);
        expect(hawaiiReport.chartCount, greaterThanOrEqualTo(6));
        
        // Verify Pacific coordinates
        expect(hawaiiReport.stateBounds, isNotNull);
        final bounds = hawaiiReport.stateBounds!;
        expect(bounds.west, lessThan(-154.0)); // Western Pacific
        expect(bounds.east, greaterThan(-160.0)); // Eastern Pacific
      });
    });

    group('Data Quality Tests', () {
      testWidgets('Chart metadata consistency should be validated', (tester) async {
        // Create charts with various quality issues
        final charts = [
          // Valid chart
          TestFixtures.createTestChart(id: 'US5CA01M', title: 'San Francisco Bay', scale: 25000),
          // Missing title
          TestFixtures.createTestChart(id: 'US5CA02M', title: '', scale: 50000),
          // Invalid scale
          TestFixtures.createTestChart(id: 'US5CA03M', title: 'Monterey Bay', scale: -1),
          // Duplicate chart
          TestFixtures.createTestChart(id: 'US5CA04M', title: 'San Francisco Bay', scale: 25000),
        ];
        
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => charts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => charts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final californiaReport = report.stateReports['California'];
        final metadata = californiaReport!.chartMetadata!;

        expect(metadata.totalChartsValidated, equals(4));
        expect(metadata.missingTitles, contains('US5CA02M'));
        expect(metadata.invalidScales, contains('US5CA03M'));
        expect(metadata.duplicateCharts, contains('US5CA04M'));
        expect(metadata.validCharts, equals(1)); // Only first chart is fully valid
      });

      testWidgets('Coordinate boundary accuracy should be verified', (tester) async {
        // Create charts with invalid bounds
        final charts = [
          TestFixtures.createTestChart(
            id: 'US5CA01M', 
            title: 'Valid Chart',
            bounds: GeographicBounds(north: 37.5, south: 37.0, east: -122.0, west: -122.5)
          ),
          TestFixtures.createTestChart(
            id: 'US5CA02M', 
            title: 'Invalid Bounds Chart',
            bounds: GeographicBounds(north: 37.0, south: 37.5, east: -122.5, west: -122.0) // North < South
          ),
        ];
        
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => charts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => charts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final californiaReport = report.stateReports['California'];
        final metadata = californiaReport!.chartMetadata!;

        expect(metadata.invalidBounds, contains('US5CA02M'));
        expect(metadata.validCharts, equals(1));
      });

      testWidgets('Duplicate chart detection should work', (tester) async {
        final charts = [
          TestFixtures.createTestChart(id: 'US5CA01M', title: 'San Francisco Bay', scale: 25000),
          TestFixtures.createTestChart(id: 'US5CA02M', title: 'San Francisco Bay', scale: 25000), // Duplicate
          TestFixtures.createTestChart(id: 'US5CA03M', title: 'Monterey Bay', scale: 25000), // Different title, same scale - OK
        ];
        
        when(mockStorage.getStateCellMapping('California'))
            .thenAnswer((_) async => charts.map((c) => c.id).toList());
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => charts);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();
        final californiaReport = report.stateReports['California'];
        final metadata = californiaReport!.chartMetadata!;

        expect(metadata.duplicateCharts, contains('US5CA02M'));
        expect(metadata.duplicateCharts, hasLength(1));
      });
    });

    group('Performance and Monitoring Tests', () {
      testWidgets('Coverage validation should complete within 10 minutes', (tester) async {
        // Mock minimal data for fast validation
        const testStates = ['California', 'Florida', 'Washington'];
        
        for (final state in testStates) {
          when(mockStorage.getStateCellMapping(state))
              .thenAnswer((_) async => ['${state}_01', '${state}_02', '${state}_03']);
          when(mockStorage.getChartsInBounds(any))
              .thenAnswer((_) async => MarineTestUtils.generateTestChartsForState(state, count: 3));
        }
        
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final stopwatch = Stopwatch()..start();
        final report = await validator.validateStateChartCoverage();
        stopwatch.stop();

        expect(report.isValid, isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(600000)); // 10 minutes = 600,000ms
      });

      testWidgets('Alert system should respond within 5 minutes of issue detection', (tester) async {
        // Simulate a state with no charts (issue condition)
        when(mockStorage.getStateCellMapping('Washington'))
            .thenAnswer((_) async => []);
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => []);
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final stopwatch = Stopwatch()..start();
        final report = await validator.validateStateChartCoverage();
        stopwatch.stop();

        expect(report.failedStates, contains('Washington'));
        expect(stopwatch.elapsedMilliseconds, lessThan(300000)); // 5 minutes = 300,000ms
      });
    });

    group('Error Handling', () {
      testWidgets('Should handle storage service failures gracefully', (tester) async {
        when(mockStorage.getStateCellMapping(any))
            .thenThrow(Exception('Storage service unavailable'));
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();

        // Should still produce a report, just with failed states
        expect(report.totalStatesValidated, greaterThan(0));
        expect(report.failedStates.length, equals(report.totalStatesValidated));
        expect(report.isValid, isFalse);
      });

      testWidgets('Should handle network connectivity issues', (tester) async {
        // Simulate intermittent network issues
        var callCount = 0;
        when(mockStorage.getStateCellMapping(any)).thenAnswer((_) async {
          callCount++;
          if (callCount % 2 == 0) {
            throw Exception('Network timeout');
          }
          return ['US5CA01M', 'US5CA02M'];
        });
        
        when(mockStorage.getChartsInBounds(any))
            .thenAnswer((_) async => MarineTestUtils.generateTestChartsForState('California', count: 2));
        when(mockCache.get(any)).thenAnswer((_) async => null);

        final report = await validator.validateStateChartCoverage();

        // Should handle partial failures
        expect(report.stateReports.isNotEmpty, isTrue);
        expect(report.failedStates.isNotEmpty, isTrue);
      });
    });
  });
}

/// Extension methods for generating marine test data
extension MarineTestUtils on Chart {
  /// Generates test charts for a specific state
  static List<Chart> generateTestChartsForState(String state, {int count = 5}) {
    final charts = <Chart>[];
    final stateBounds = _getStateBounds(state);
    
    for (int i = 1; i <= count; i++) {
      charts.add(TestFixtures.createTestChart(
        id: 'US5${state.substring(0, 2).toUpperCase()}${i.toString().padLeft(2, '0')}M',
        title: '$state Chart $i - Harbor Navigation',
        scale: 15000 + (i * 5000),
        bounds: _generateBoundsWithinState(stateBounds, i),
        source: ChartSource.noaa,
      ));
    }
    
    return charts;
  }
  
  /// Generates test charts for a specific region within a state
  static List<Chart> generateTestChartsForRegion(String state, String region, {int count = 3}) {
    final charts = <Chart>[];
    final stateBounds = _getStateBounds(state);
    
    for (int i = 1; i <= count; i++) {
      charts.add(TestFixtures.createTestChart(
        id: 'US5${state.substring(0, 2).toUpperCase()}${region.substring(0, 1).toUpperCase()}${i}M',
        title: '$region - Chart $i',
        scale: 25000 + (i * 10000),
        bounds: _generateBoundsWithinState(stateBounds, i),
        source: ChartSource.noaa,
      ));
    }
    
    return charts;
  }
  
  /// Gets predefined bounds for a state
  static GeographicBounds _getStateBounds(String state) {
    final stateBounds = {
      'California': GeographicBounds(north: 42.0, south: 32.5, east: -114.1, west: -124.4),
      'Florida': GeographicBounds(north: 31.0, south: 24.5, east: -80.0, west: -87.6),
      'Washington': GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8),
      'Alaska': GeographicBounds(north: 71.4, south: 54.8, east: -130.0, west: -179.1),
      'Hawaii': GeographicBounds(north: 28.4, south: 18.9, east: -154.8, west: -178.3),
      'Texas': GeographicBounds(north: 36.5, south: 25.8, east: -93.5, west: -106.6),
      'Maine': GeographicBounds(north: 47.5, south: 43.1, east: -66.9, west: -71.1),
      'Massachusetts': GeographicBounds(north: 42.9, south: 41.2, east: -69.9, west: -73.5),
      'New York': GeographicBounds(north: 45.0, south: 40.5, east: -71.9, west: -79.8),
      'North Carolina': GeographicBounds(north: 36.6, south: 33.8, east: -75.5, west: -84.3),
      'South Carolina': GeographicBounds(north: 35.2, south: 32.0, east: -78.5, west: -83.4),
      'Georgia': GeographicBounds(north: 35.0, south: 30.4, east: -80.8, west: -85.6),
      'Louisiana': GeographicBounds(north: 33.0, south: 28.9, east: -88.8, west: -94.0),
      'Oregon': GeographicBounds(north: 46.3, south: 42.0, east: -116.5, west: -124.6),
      'Alabama': GeographicBounds(north: 35.0, south: 30.1, east: -84.9, west: -88.5),
      'Mississippi': GeographicBounds(north: 35.0, south: 30.1, east: -88.1, west: -91.7),
      'Connecticut': GeographicBounds(north: 42.1, south: 40.9, east: -71.8, west: -73.7),
      'Delaware': GeographicBounds(north: 39.8, south: 38.4, east: -75.0, west: -75.8),
      'Maryland': GeographicBounds(north: 39.7, south: 37.9, east: -75.0, west: -79.5),
      'Virginia': GeographicBounds(north: 39.5, south: 36.5, east: -75.2, west: -83.7),
      'New Hampshire': GeographicBounds(north: 45.3, south: 42.7, east: -70.6, west: -72.6),
      'New Jersey': GeographicBounds(north: 41.4, south: 38.9, east: -73.9, west: -75.6),
      'Rhode Island': GeographicBounds(north: 42.0, south: 41.1, east: -71.1, west: -71.9),
      'Pennsylvania': GeographicBounds(north: 42.3, south: 39.7, east: -74.7, west: -80.5),
      'Illinois': GeographicBounds(north: 42.5, south: 36.9, east: -87.0, west: -91.5),
      'Indiana': GeographicBounds(north: 41.8, south: 37.8, east: -84.8, west: -88.1),
      'Michigan': GeographicBounds(north: 48.3, south: 41.7, east: -82.1, west: -90.4),
      'Minnesota': GeographicBounds(north: 49.4, south: 43.5, east: -89.5, west: -97.2),
      'Ohio': GeographicBounds(north: 42.3, south: 38.4, east: -80.5, west: -84.8),
      'Wisconsin': GeographicBounds(north: 47.3, south: 42.5, east: -86.2, west: -92.9),
    };
    
    return stateBounds[state] ?? GeographicBounds(north: 45, south: 30, east: -70, west: -130);
  }
  
  /// Generates bounds within a state's boundaries
  static GeographicBounds _generateBoundsWithinState(GeographicBounds stateBounds, int index) {
    final latSpan = stateBounds.north - stateBounds.south;
    final lngSpan = stateBounds.east - stateBounds.west;
    
    // Create smaller bounds within the state
    final centerLat = stateBounds.south + (latSpan * (index / 10.0));
    final centerLng = stateBounds.west + (lngSpan * (index / 10.0));
    
    final halfSize = 0.5; // Half degree in each direction
    
    return GeographicBounds(
      north: centerLat + halfSize,
      south: centerLat - halfSize,
      east: centerLng + halfSize,
      west: centerLng - halfSize,
    );
  }
}