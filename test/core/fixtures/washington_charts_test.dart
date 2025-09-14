import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/core/models/chart.dart';

void main() {
  group('WashingtonTestCharts', () {
    test('should return all Washington charts', () {
      final charts = WashingtonTestCharts.getAllCharts();
      expect(charts.length, equals(6)); // 2 Elliott Bay + 4 synthetic
      
      // Check that all charts are for Washington state
      for (final chart in charts) {
        expect(chart.state, equals('Washington'));
      }
    });
    
    test('should return only Elliott Bay charts with real data', () {
      final elliottBayCharts = WashingtonTestCharts.getElliottBayCharts();
      expect(elliottBayCharts.length, equals(2));
      
      // Check Elliott Bay charts are marked as downloaded
      for (final chart in elliottBayCharts) {
        expect(chart.isDownloaded, isTrue);
        expect(chart.fileSize, greaterThan(0));
      }
      
      // Verify specific Elliott Bay charts
      final us5wa50m = elliottBayCharts.firstWhere((c) => c.id == 'US5WA50M');
      expect(us5wa50m.title, contains('Elliott Bay Harbor'));
      expect(us5wa50m.type, equals(ChartType.harbor));
      expect(us5wa50m.fileSize, equals(147361)); // Matches actual test file
      
      final us3wa01m = elliottBayCharts.firstWhere((c) => c.id == 'US3WA01M');
      expect(us3wa01m.title, contains('PUGET SOUND'));
      expect(us3wa01m.type, equals(ChartType.coastal));
      expect(us3wa01m.fileSize, equals(640268)); // Matches actual test file
    });
    
    test('should return charts for Washington state', () {
      final washingtonCharts = WashingtonTestCharts.getChartsForState('Washington');
      expect(washingtonCharts.length, equals(6));
      
      // Case insensitive
      final washingtonLowerCase = WashingtonTestCharts.getChartsForState('washington');
      expect(washingtonLowerCase.length, equals(6));
      
      // Other states return empty
      final californiaCharts = WashingtonTestCharts.getChartsForState('California');
      expect(californiaCharts, isEmpty);
    });
    
    test('should identify charts with real data', () {
      expect(WashingtonTestCharts.hasRealChartData('US5WA50M'), isTrue);
      expect(WashingtonTestCharts.hasRealChartData('US3WA01M'), isTrue);
      expect(WashingtonTestCharts.hasRealChartData('US1WC01M'), isFalse);
      expect(WashingtonTestCharts.hasRealChartData('NONEXISTENT'), isFalse);
    });
    
    test('should return correct test chart paths', () {
      expect(
        WashingtonTestCharts.getTestChartPath('US5WA50M'), 
        equals('test/fixtures/charts/s57_data/US5WA50M_harbor_elliott_bay.zip'),
      );
      expect(
        WashingtonTestCharts.getTestChartPath('US3WA01M'),
        equals('test/fixtures/charts/s57_data/US3WA01M_coastal_puget_sound.zip'),
      );
      expect(WashingtonTestCharts.getTestChartPath('US1WC01M'), isNull);
      expect(WashingtonTestCharts.getTestChartPath('NONEXISTENT'), isNull);
    });
    
    test('should have proper chart type priority ordering', () {
      final charts = WashingtonTestCharts.getAllCharts();
      
      // Find charts by type
      final harborCharts = charts.where((c) => c.type == ChartType.harbor).toList();
      final coastalCharts = charts.where((c) => c.type == ChartType.coastal).toList();
      final approachCharts = charts.where((c) => c.type == ChartType.approach).toList();
      final generalCharts = charts.where((c) => c.type == ChartType.general).toList();
      
      // Verify we have charts of each expected type
      expect(harborCharts.length, equals(1)); // US5WA50M
      expect(coastalCharts.length, equals(2)); // US3WA01M, US4WA02M
      expect(approachCharts.length, equals(2)); // US5WA10M, US2WA03M
      expect(generalCharts.length, equals(1)); // US1WC01M
      
      // Verify harbor chart has highest priority (lowest number)
      expect(harborCharts.first.typePriority, equals(2));
    });
    
    test('should have valid geographic bounds for Elliott Bay area', () {
      final elliottBayCharts = WashingtonTestCharts.getElliottBayCharts();
      
      for (final chart in elliottBayCharts) {
        // Verify bounds are in Puget Sound/Elliott Bay region
        expect(chart.bounds.north, greaterThan(47.0));
        expect(chart.bounds.south, lessThan(49.0));
        expect(chart.bounds.east, greaterThan(-125.0));
        expect(chart.bounds.west, lessThan(-122.0));
        
        // Verify bounds are valid (north > south, east > west)
        expect(chart.bounds.north, greaterThan(chart.bounds.south));
        expect(chart.bounds.east, greaterThan(chart.bounds.west));
      }
    });
  });
}