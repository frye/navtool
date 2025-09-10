import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:navtool/core/services/chart_quality_monitor.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/models/chart_models.dart';
import '../../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  StateRegionMappingService,
  StorageService,
  CacheService,
  AppLogger,
])
import 'chart_quality_monitor_test.mocks.dart';

void main() {
  group('ChartQualityMonitor Tests', () {
    late MockStateRegionMappingService mockMappingService;
    late MockStorageService mockStorageService;
    late MockCacheService mockCacheService;
    late MockAppLogger mockLogger;
    late ChartQualityMonitor qualityMonitor;

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

    group('Quality Report Generation', () {
      testWidgets('should generate comprehensive quality report', (tester) async {
        // Setup mock data
        const supportedStates = ['California', 'Florida', 'Washington'];
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => supportedStates);

        // Mock chart data for each state
        for (final state in supportedStates) {
          // Generate enough charts to meet coverage expectations (85%+ to avoid warnings)
          final expectedCount = _getExpectedChartCountForState(state);
          final chartCount = (expectedCount * 0.9).ceil(); // 90% coverage to ensure good quality
          final charts = MarineTestUtils.generateTestChartsForState(state, count: chartCount);
          final chartCells = charts.map((c) => c.id).toList();
          final bounds = MarineTestUtils.getStateBounds(state);

          when(mockMappingService.getChartCellsForState(state))
              .thenAnswer((_) async => chartCells);
          when(mockMappingService.getStateBounds(state))
              .thenAnswer((_) async => bounds);
          when(mockStorageService.getChartsInBounds(bounds))
              .thenAnswer((_) async => charts);
        }

        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(report.totalChartsAnalyzed, greaterThan(0)); // Variable based on coverage calculation
        expect(report.regionReports, hasLength(3));
        expect(report.overallQuality, isNotNull);
        expect(report.generatedAt, isNotNull);
        expect(report.isQualityAcceptable, isTrue);

        // Verify caching was attempted
        verify(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .called(1);
      });

      testWidgets('should identify quality issues in charts', (tester) async {
        const supportedStates = ['California'];
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => supportedStates);

        // Create charts with quality issues
        final charts = [
          TestFixtures.createTestChart(id: 'US5CA01M', title: 'Valid Chart', scale: 25000),
          TestFixtures.createTestChart(id: 'US5CA02M', title: '', scale: 50000), // Missing title - triggers missingMetadata
          // Note: scale <= 0 cannot be tested because Chart constructor validates it
          // Note: invalid bounds cannot be tested because GeographicBounds constructor validates them
          // These validation issues would need to be tested at a different level (e.g., during data import)
        ];

        final chartCells = charts.map((c) => c.id).toList();
        final bounds = MarineTestUtils.getStateBounds('California');

        when(mockMappingService.getChartCellsForState('California'))
            .thenAnswer((_) async => chartCells);
        when(mockMappingService.getStateBounds('California'))
            .thenAnswer((_) async => bounds);
        when(mockStorageService.getChartsInBounds(bounds))
            .thenAnswer((_) async => charts);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(report.issues, isNotEmpty);
        expect(report.issues.any((i) => i.type == QualityIssueType.missingMetadata), isTrue);
        // Note: inconsistentScale and invalidBounds cannot be triggered because Chart constructor validates these
        // These would need to be tested at the data import/parsing level, not at the Chart object level
        expect(report.overallQuality.index, greaterThan(ChartQualityLevel.excellent.index));
      });

      testWidgets('should detect coverage gaps', (tester) async {
        const supportedStates = ['Washington'];
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => supportedStates);

        // Create minimal chart data (insufficient coverage)
        final charts = [TestFixtures.createTestChart(id: 'US5WA01M', title: 'Single Chart', scale: 25000)];
        final chartCells = charts.map((c) => c.id).toList();
        final bounds = MarineTestUtils.getStateBounds('Washington');

        when(mockMappingService.getChartCellsForState('Washington'))
            .thenAnswer((_) async => chartCells);
        when(mockMappingService.getStateBounds('Washington'))
            .thenAnswer((_) async => bounds);
        when(mockStorageService.getChartsInBounds(bounds))
            .thenAnswer((_) async => charts);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(
          report.issues.any((i) => i.type == QualityIssueType.coverageGaps),
          isTrue,
        );
        expect(report.regionReports['Washington']?.hasAdequateCoverage, isFalse);
      });
    });

    group('Quality Monitoring', () {
      testWidgets('should start and stop monitoring', (tester) async {
        expect(qualityMonitor.isMonitoring, isFalse);

        // Setup minimal mock data for monitoring
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => ['California']);
        when(mockMappingService.getChartCellsForState('California'))
            .thenAnswer((_) async => ['US5CA01M']);
        when(mockMappingService.getStateBounds('California'))
            .thenAnswer((_) async => MarineTestUtils.getStateBounds('California'));
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => [TestFixtures.createTestChart(id: 'US5CA01M', title: 'Test Chart')]);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        await qualityMonitor.startMonitoring();
        expect(qualityMonitor.isMonitoring, isTrue);

        await qualityMonitor.stopMonitoring();
        expect(qualityMonitor.isMonitoring, isFalse);
      });

      testWidgets('should emit quality alerts for critical issues', (tester) async {
        // Setup data that will trigger critical issues
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => ['Washington']);
        when(mockMappingService.getChartCellsForState('Washington'))
            .thenAnswer((_) async => []); // No charts - critical issue
        when(mockMappingService.getStateBounds('Washington'))
            .thenAnswer((_) async => MarineTestUtils.getStateBounds('Washington'));
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => []);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final alertsReceived = <QualityAlert>[];
        qualityMonitor.qualityAlerts.listen((alert) {
          alertsReceived.add(alert);
        });

        await qualityMonitor.startMonitoring();

        // Wait a bit for the monitoring to trigger
        await tester.pump(const Duration(milliseconds: 100));

        expect(alertsReceived, isNotEmpty);
        expect(alertsReceived.first.severity, equals(AlertSeverity.critical));

        await qualityMonitor.stopMonitoring();
      });
    });

    group('Cached Reports', () {
      testWidgets('should cache and retrieve quality reports', (tester) async {
        // Mock cached report data
        final cachedReportJson = {
          'generatedAt': DateTime.now().toIso8601String(),
          'overallQuality': ChartQualityLevel.good.toString(),
          'totalChartsAnalyzed': 10,
          'issues': [],
          'regionReports': {},
          'recommendations': ['Test recommendation'],
        };

        final cachedBytes = utf8.encode(jsonEncode(cachedReportJson));
        when(mockCacheService.get('latest_quality_report'))
            .thenAnswer((_) async => Uint8List.fromList(cachedBytes));

        final cachedReport = await qualityMonitor.getCachedQualityReport();

        expect(cachedReport, isNotNull);
        expect(cachedReport!.overallQuality, equals(ChartQualityLevel.good));
        expect(cachedReport.totalChartsAnalyzed, equals(10));
        expect(cachedReport.recommendations, contains('Test recommendation'));
      });

      testWidgets('should handle missing cache gracefully', (tester) async {
        when(mockCacheService.get('latest_quality_report'))
            .thenAnswer((_) async => null);

        final cachedReport = await qualityMonitor.getCachedQualityReport();

        expect(cachedReport, isNull);
      });

      testWidgets('should handle corrupted cache gracefully', (tester) async {
        // Mock corrupted cache data
        final corruptedBytes = Uint8List.fromList([1, 2, 3, 4]); // Invalid JSON
        when(mockCacheService.get('latest_quality_report'))
            .thenAnswer((_) async => corruptedBytes);

        final cachedReport = await qualityMonitor.getCachedQualityReport();

        expect(cachedReport, isNull);
        verify(mockLogger.warning(any)).called(1);
      });
    });

    group('Quality Assessment', () {
      testWidgets('should calculate quality levels correctly', (tester) async {
        // Test excellent quality (no issues)
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => ['California']);

        // Generate enough charts to meet coverage expectations (90% of 20 = 18 charts)
        final excellentCharts = List.generate(18, (i) => 
          TestFixtures.createTestChart(
            id: 'US5CA${(i+1).toString().padLeft(2, '0')}M', 
            title: 'Perfect Chart ${i+1}', 
            scale: 25000 + (i * 1000),
          )
        );

        when(mockMappingService.getChartCellsForState('California'))
            .thenAnswer((_) async => excellentCharts.map((c) => c.id).toList());
        when(mockMappingService.getStateBounds('California'))
            .thenAnswer((_) async => MarineTestUtils.getStateBounds('California'));
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => excellentCharts);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(report.overallQuality, equals(ChartQualityLevel.excellent));
        expect(report.isQualityAcceptable, isTrue);
      });

      testWidgets('should identify critical quality issues', (tester) async {
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => ['Florida']);

        // Charts with critical issues
        final criticalCharts = [
          TestFixtures.createTestChart(
            id: 'US5FL01M',
            title: 'Critical Chart',
            bounds: GeographicBounds(north: 26.0, south: 25.0, east: -79.0, west: -80.0), // Fixed: North > South, East > West
            metadata: {'hasCriticalIssue': true}
          ),
        ];

        when(mockMappingService.getChartCellsForState('Florida'))
            .thenAnswer((_) async => criticalCharts.map((c) => c.id).toList());
        when(mockMappingService.getStateBounds('Florida'))
            .thenAnswer((_) async => MarineTestUtils.getStateBounds('Florida'));
        when(mockStorageService.getChartsInBounds(any))
            .thenAnswer((_) async => criticalCharts);
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(report.overallQuality, equals(ChartQualityLevel.critical));
        expect(report.isQualityAcceptable, isFalse);
        expect(report.criticalIssues, isNotEmpty);
      });
    });

    group('Error Handling', () {
      testWidgets('should handle storage service failures gracefully', (tester) async {
        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => ['Alaska']);
        when(mockMappingService.getChartCellsForState('Alaska'))
            .thenThrow(Exception('Storage service unavailable'));
        when(mockMappingService.getStateBounds('Alaska'))
            .thenAnswer((_) async => MarineTestUtils.getStateBounds('Alaska'));
        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final report = await qualityMonitor.generateQualityReport();

        expect(report.regionReports['Alaska']?.qualityLevel, equals(ChartQualityLevel.critical));
        expect(report.regionReports['Alaska']?.issues, isNotEmpty);
        expect(report.overallQuality, equals(ChartQualityLevel.critical));
      });

      testWidgets('should handle mapping service failures', (tester) async {
        when(mockMappingService.getSupportedStates())
            .thenThrow(Exception('Mapping service error'));

        expect(
          () => qualityMonitor.generateQualityReport(),
          throwsException,
        );
      });

      testWidgets('should emit system alerts for monitoring failures', (tester) async {
        when(mockMappingService.getSupportedStates())
            .thenThrow(Exception('System failure'));

        final alertsReceived = <QualityAlert>[];
        qualityMonitor.qualityAlerts.listen((alert) {
          alertsReceived.add(alert);
        });

        await qualityMonitor.startMonitoring();

        // Wait for the monitoring failure to trigger
        await tester.pump(const Duration(milliseconds: 100));

        expect(alertsReceived, isNotEmpty);
        expect(alertsReceived.first.severity, equals(AlertSeverity.error));
        expect(alertsReceived.first.title, contains('System Error'));

        await qualityMonitor.stopMonitoring();
      });
    });

    group('Performance Requirements', () {
      testWidgets('should generate reports within acceptable time limits', (tester) async {
        // Setup large dataset for performance testing
        const largeStateList = [
          'California', 'Florida', 'Texas', 'Alaska', 'Washington',
          'Maine', 'Massachusetts', 'New York', 'North Carolina', 'South Carolina'
        ];

        when(mockMappingService.getSupportedStates())
            .thenAnswer((_) async => largeStateList);

        // Store charts by state for proper mock setup
        final chartsByState = <String, List<Chart>>{};
        
        for (final state in largeStateList) {
          final charts = MarineTestUtils.generateTestChartsForState(state, count: 8);
          chartsByState[state] = charts;
          
          when(mockMappingService.getChartCellsForState(state))
              .thenAnswer((_) async => charts.map((c) => c.id).toList());
          when(mockMappingService.getStateBounds(state))
              .thenAnswer((_) async => MarineTestUtils.getStateBounds(state));
          
          // Mock getChartsInBounds to return charts for the specific state bounds
          final stateBounds = MarineTestUtils.getStateBounds(state);
          when(mockStorageService.getChartsInBounds(stateBounds))
              .thenAnswer((_) async => charts);
        }

        when(mockCacheService.store(any, any, maxAge: anyNamed('maxAge')))
            .thenAnswer((_) async {});

        final stopwatch = Stopwatch()..start();
        final report = await qualityMonitor.generateQualityReport();
        stopwatch.stop();

        expect(report.totalChartsAnalyzed, equals(80)); // 8 charts per state
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds
      });
    });
  });
}

/// Helper method to get expected chart counts (matches ChartQualityMonitor internal logic)
int _getExpectedChartCountForState(String state) {
  const expectedCounts = {
    'Alaska': 25,
    'California': 20,
    'Florida': 15,
    'Texas': 12,
    'Washington': 10,
    'Maine': 8,
    'Hawaii': 8,
    'North Carolina': 8,
    'South Carolina': 6,
    'Georgia': 6,
    'Louisiana': 8,
    'Alabama': 4,
    'Mississippi': 4,
    'Oregon': 8,
    'New York': 10,
    'Massachusetts': 8,
    'Connecticut': 4,
    'Rhode Island': 3,
  };
  return expectedCounts[state] ?? 5;
}

/// Extension methods for generating marine test data in quality monitor tests
extension MarineTestUtils on Chart {
  /// Generates test charts for a specific state
  static List<Chart> generateTestChartsForState(String state, {int count = 5}) {
    final charts = <Chart>[];
    final stateBounds = getStateBounds(state);
    
    for (int i = 1; i <= count; i++) {
      charts.add(TestFixtures.createTestChart(
        id: 'US5${state.substring(0, 2).toUpperCase()}${i.toString().padLeft(2, '0')}M',
        title: '$state Chart $i - Navigation',
        scale: 15000 + (i * 5000),
        bounds: _generateBoundsWithinState(stateBounds, i),
        source: ChartSource.noaa,
      ));
    }
    
    return charts;
  }
  
  /// Gets predefined bounds for a state
  static GeographicBounds getStateBounds(String state) {
    final stateBounds = {
      'California': GeographicBounds(north: 42.0, south: 32.5, east: -114.1, west: -124.4),
      'Florida': GeographicBounds(north: 31.0, south: 24.4, east: -80.0, west: -87.6),
      'Washington': GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8),
      'Alaska': GeographicBounds(north: 71.4, south: 51.2, east: -129.9, west: -179.1),
      'Hawaii': GeographicBounds(north: 22.2, south: 18.9, east: -154.8, west: -160.2),
      'Texas': GeographicBounds(north: 36.5, south: 25.8, east: -93.5, west: -106.6),
      'Maine': GeographicBounds(north: 47.5, south: 44.0, east: -66.9, west: -71.0),
      'Massachusetts': GeographicBounds(north: 42.9, south: 41.2, east: -69.9, west: -71.2),
      'New York': GeographicBounds(north: 45.0, south: 40.4, east: -71.8, west: -79.8),
      'North Carolina': GeographicBounds(north: 36.6, south: 33.8, east: -75.4, west: -84.3),
      'South Carolina': GeographicBounds(north: 35.2, south: 32.0, east: -78.5, west: -83.4),
    };
    
    return stateBounds[state] ?? 
           GeographicBounds(north: 45, south: 30, east: -70, west: -130);
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