import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

void main() {
  group('Chart Model Tests', () {
    test('Chart should be created with valid data', () {
      // Arrange
      const chartId = 'US5CA52M';
      const title = 'San Francisco Bay';
      const scale = 25000;
      final bounds = GeographicBounds(
        north: 37.8,
        south: 37.6,
        east: -122.3,
        west: -122.5,
      );
      final lastUpdate = DateTime(2024, 1, 15);

      // Act
      final chart = Chart(
        id: chartId,
        title: title,
        scale: scale,
        bounds: bounds,
        lastUpdate: lastUpdate,
        state: 'California',
        type: ChartType.harbor,
      );

      // Assert
      expect(chart.id, equals(chartId));
      expect(chart.title, equals(title));
      expect(chart.scale, equals(scale));
      expect(chart.bounds, equals(bounds));
      expect(chart.lastUpdate, equals(lastUpdate));
      expect(chart.state, equals('California'));
      expect(chart.type, equals(ChartType.harbor));
      expect(chart.isDownloaded, isFalse);
    });

    test('Chart should validate scale is positive', () {
      // Arrange & Act & Assert
      expect(
        () => Chart(
          id: 'US5CA52M',
          title: 'Test Chart',
          scale: -1000, // Invalid negative scale
          bounds: GeographicBounds(north: 1, south: 0, east: 1, west: 0),
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.harbor,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Chart should validate bounds are valid', () {
      // Arrange & Act & Assert
      expect(
        () => Chart(
          id: 'US5CA52M',
          title: 'Test Chart',
          scale: 25000,
          bounds: GeographicBounds(
            north: 37.6, // Invalid: north < south
            south: 37.8,
            east: -122.3,
            west: -122.5,
          ),
          lastUpdate: DateTime.now(),
          state: 'California',
          type: ChartType.harbor,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Chart equality should work correctly', () {
      // Arrange
      final bounds = GeographicBounds(north: 1, south: 0, east: 1, west: 0);
      final lastUpdate = DateTime(2024, 1, 15);
      
      final chart1 = Chart(
        id: 'US5CA52M',
        title: 'Test Chart',
        scale: 25000,
        bounds: bounds,
        lastUpdate: lastUpdate,
        state: 'California',
        type: ChartType.harbor,
      );
      
      final chart2 = Chart(
        id: 'US5CA52M',
        title: 'Test Chart',
        scale: 25000,
        bounds: bounds,
        lastUpdate: lastUpdate,
        state: 'California',
        type: ChartType.harbor,
      );

      // Act & Assert
      expect(chart1, equals(chart2));
      expect(chart1.hashCode, equals(chart2.hashCode));
    });

    test('Chart copyWith should work correctly', () {
      // Arrange
      final originalChart = Chart(
        id: 'US5CA52M',
        title: 'Test Chart',
        scale: 25000,
        bounds: GeographicBounds(north: 1, south: 0, east: 1, west: 0),
        lastUpdate: DateTime(2024, 1, 15),
        state: 'California',
        type: ChartType.harbor,
      );

      // Act
      final updatedChart = originalChart.copyWith(
        title: 'Updated Test Chart',
        isDownloaded: true,
      );

      // Assert
      expect(updatedChart.id, equals(originalChart.id));
      expect(updatedChart.title, equals('Updated Test Chart'));
      expect(updatedChart.isDownloaded, isTrue);
      expect(updatedChart.scale, equals(originalChart.scale));
    });
  });

  group('ChartType Tests', () {
    test('ChartType should have correct display names', () {
      expect(ChartType.overview.displayName, equals('Overview'));
      expect(ChartType.general.displayName, equals('General'));
      expect(ChartType.coastal.displayName, equals('Coastal'));
      expect(ChartType.approach.displayName, equals('Approach'));
      expect(ChartType.harbor.displayName, equals('Harbor'));
    });

    test('ChartType should have correct scale ranges', () {
      expect(ChartType.overview.scaleRange.contains(1000000), isTrue);
      expect(ChartType.general.scaleRange.contains(500000), isTrue);
      expect(ChartType.coastal.scaleRange.contains(150000), isTrue);
      expect(ChartType.approach.scaleRange.contains(50000), isTrue);
      expect(ChartType.harbor.scaleRange.contains(25000), isTrue);
    });
  });
}
