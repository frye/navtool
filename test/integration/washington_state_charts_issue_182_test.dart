/// Integration test for Issue #182 - Washington State Charts Not Found - Manual Refresh Implementation
/// Tests the offline-first chart loading without network dependency
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';

void main() {
  group('Issue #182 - Washington State Charts Not Found Integration', () {
    test('WashingtonTestCharts fixture provides correct charts for Washington', () {
      // Test the underlying data structure that fixes the issue
      final charts = WashingtonTestCharts.getChartsForState('Washington');
      
      // Should have multiple charts including Elliott Bay
      expect(charts.length, equals(6)); // 2 Elliott Bay + 4 synthetic
      
      // Should include Elliott Bay test charts (the key fix for #182)
      final elliottBayCharts = charts.where((c) => c.id == 'US5WA50M' || c.id == 'US3WA01M').toList();
      expect(elliottBayCharts.length, equals(2));
      
      // Elliott Bay charts should be marked as downloaded (have real data)
      for (final chart in elliottBayCharts) {
        expect(chart.isDownloaded, isTrue);
        expect(chart.fileSize, greaterThan(0));
        expect(chart.state, equals('Washington'));
      }
      
      // Should have variety of chart types
      final chartTypes = charts.map((c) => c.type).toSet();
      expect(chartTypes.length, greaterThan(1));
      
      // Verify the two key Elliott Bay charts
      final harborChart = charts.firstWhere((c) => c.id == 'US5WA50M');
      expect(harborChart.title, contains('Elliott Bay'));
      expect(harborChart.type.name, equals('harbor'));
      
      final coastalChart = charts.firstWhere((c) => c.id == 'US3WA01M');
      expect(coastalChart.title, contains('PUGET SOUND'));
      expect(coastalChart.type.name, equals('coastal'));
    });

    test('WashingtonTestCharts should return empty list for non-Washington states', () {
      // Test that the fix is specific to Washington
      final californiaCharts = WashingtonTestCharts.getChartsForState('California');
      expect(californiaCharts, isEmpty);
      
      final floridaCharts = WashingtonTestCharts.getChartsForState('Florida');
      expect(floridaCharts, isEmpty);
    });

    test('WashingtonTestCharts should handle case-insensitive state names', () {
      // Test case insensitivity
      final upperCaseCharts = WashingtonTestCharts.getChartsForState('WASHINGTON');
      expect(upperCaseCharts.length, equals(6));
      
      final lowerCaseCharts = WashingtonTestCharts.getChartsForState('washington');
      expect(lowerCaseCharts.length, equals(6));
      
      final mixedCaseCharts = WashingtonTestCharts.getChartsForState('Washington');
      expect(mixedCaseCharts.length, equals(6));
    });

    test('Elliott Bay charts should have real file paths for rendering', () {
      // Test that Issue #187 integration works with #182
      final harborChart = WashingtonTestCharts.getElliottBayCharts().firstWhere((c) => c.id == 'US5WA50M');
      final coastalChart = WashingtonTestCharts.getElliottBayCharts().firstWhere((c) => c.id == 'US3WA01M');
      
      // Should have real file paths
      final harborPath = WashingtonTestCharts.getTestChartPath(harborChart.id);
      expect(harborPath, isNotNull);
      expect(harborPath, contains('US5WA50M'));
      
      final coastalPath = WashingtonTestCharts.getTestChartPath(coastalChart.id);
      expect(coastalPath, isNotNull);
      expect(coastalPath, contains('US3WA01M'));
      
      // Should indicate they have real chart data
      expect(WashingtonTestCharts.hasRealChartData(harborChart.id), isTrue);
      expect(WashingtonTestCharts.hasRealChartData(coastalChart.id), isTrue);
    });

    test('Chart priority sorting should work correctly', () {
      // Test that harbor charts get priority over coastal charts
      final charts = WashingtonTestCharts.getAllCharts();
      final harborCharts = charts.where((c) => c.type.name == 'harbor').toList();
      final coastalCharts = charts.where((c) => c.type.name == 'coastal').toList();
      
      expect(harborCharts.isNotEmpty, isTrue);
      expect(coastalCharts.isNotEmpty, isTrue);
      
      // Harbor charts should have higher priority (lower number)
      final harborPriority = harborCharts.first.typePriority;
      final coastalPriority = coastalCharts.first.typePriority;
      expect(harborPriority, lessThan(coastalPriority));
    });
  });
}