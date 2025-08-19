import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/metadata_parsing_exceptions.dart';
import 'dart:convert';

// Generate mocks for dependencies
@GenerateMocks([AppLogger])
import 'noaa_metadata_parser_test.mocks.dart';

void main() {
  group('NoaaMetadataParser Tests', () {
    late NoaaMetadataParserImpl parser;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      parser = NoaaMetadataParserImpl(logger: mockLogger);
    });

    group('parseGeoJsonToCharts', () {
      test('should parse valid GeoJSON to charts', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-123.0, 37.0],
                  [-122.0, 37.0],
                  [-122.0, 38.0],
                  [-123.0, 38.0],
                  [-123.0, 37.0]
                ]]
              },
              'properties': {
                'CHART': 'US5CA52M',
                'TITLE': 'San Francisco Bay',
                'SCALE': 25000,
                'LAST_UPDATE': '2024-01-15T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor'
              }
            },
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-119.0, 33.0],
                  [-118.0, 33.0],
                  [-118.0, 34.0],
                  [-119.0, 34.0],
                  [-119.0, 33.0]
                ]]
              },
              'properties': {
                'CHART': 'US4CA11M',
                'TITLE': 'Los Angeles Harbor',
                'SCALE': 50000,
                'LAST_UPDATE': '2024-01-10T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(2));
        
        final chart1 = result[0];
        expect(chart1.id, equals('US5CA52M'));
        expect(chart1.title, equals('San Francisco Bay'));
        expect(chart1.scale, equals(25000));
        expect(chart1.state, equals('California'));
        expect(chart1.type, equals(ChartType.harbor));
        expect(chart1.bounds.north, equals(38.0));
        expect(chart1.bounds.south, equals(37.0));
        expect(chart1.bounds.east, equals(-122.0));
        expect(chart1.bounds.west, equals(-123.0));

        final chart2 = result[1];
        expect(chart2.id, equals('US4CA11M'));
        expect(chart2.title, equals('Los Angeles Harbor'));
      });

      test('should handle empty GeoJSON feature collection', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': []
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, isEmpty);
      });

      test('should skip invalid features with missing required properties', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-123.0, 37.0],
                  [-122.0, 37.0],
                  [-122.0, 38.0],
                  [-123.0, 38.0],
                  [-123.0, 37.0]
                ]]
              },
              'properties': {
                'CHART': 'US5CA52M',
                'TITLE': 'San Francisco Bay',
                // Missing SCALE, LAST_UPDATE, STATE, USAGE
              }
            },
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-119.0, 33.0],
                  [-118.0, 33.0],
                  [-118.0, 34.0],
                  [-119.0, 34.0],
                  [-119.0, 33.0]
                ]]
              },
              'properties': {
                'CHART': 'US4CA11M',
                'TITLE': 'Los Angeles Harbor',
                'SCALE': 50000,
                'LAST_UPDATE': '2024-01-10T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].id, equals('US4CA11M'));
        verify(mockLogger.warning(
          'Skipping chart feature with missing required properties: US5CA52M'
        )).called(1);
      });

      test('should handle various chart types from USAGE property', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-123.0, 37.0],
                  [-122.0, 37.0],
                  [-122.0, 38.0],
                  [-123.0, 38.0],
                  [-123.0, 37.0]
                ]]
              },
              'properties': {
                'CHART': 'US5CA52M',
                'TITLE': 'Test Chart',
                'SCALE': 25000,
                'LAST_UPDATE': '2024-01-15T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Overview'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(1));
        expect(result[0].type, equals(ChartType.overview));
      });

      test('should throw MetadataParsingException for invalid GeoJSON structure', () async {
        // Arrange
        final invalidGeoJson = {
          'type': 'InvalidType',
          'features': []
        };

        // Act & Assert
        expect(
          () async => await parser.parseGeoJsonToCharts(invalidGeoJson),
          throwsA(isA<MetadataParsingException>()),
        );
      });

      test('should handle invalid geometry gracefully', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point', // Invalid for chart bounds
                'coordinates': [-122.0, 37.0]
              },
              'properties': {
                'CHART': 'US5CA52M',
                'TITLE': 'San Francisco Bay',
                'SCALE': 25000,
                'LAST_UPDATE': '2024-01-15T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, isEmpty);
        verify(mockLogger.warning(
          'Skipping chart feature with invalid geometry: US5CA52M'
        )).called(1);
      });
    });

    group('parseChartUsageToType', () {
      test('should map usage strings to chart types correctly', () {
        // Act & Assert
        expect(parser.parseChartUsageToType('Harbor'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('Approach'), equals(ChartType.approach));
        expect(parser.parseChartUsageToType('Coastal'), equals(ChartType.coastal));
        expect(parser.parseChartUsageToType('General'), equals(ChartType.general));
        expect(parser.parseChartUsageToType('Overview'), equals(ChartType.overview));
        expect(parser.parseChartUsageToType('Berthing'), equals(ChartType.berthing));
      });

      test('should handle case-insensitive usage strings', () {
        // Act & Assert
        expect(parser.parseChartUsageToType('harbor'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('HARBOR'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('HaRbOr'), equals(ChartType.harbor));
      });

      test('should default to harbor for unknown usage strings', () {
        // Act & Assert
        expect(parser.parseChartUsageToType('Unknown'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType(''), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('invalid'), equals(ChartType.harbor));
      });
    });

    group('extractBoundsFromGeometry', () {
      test('should extract bounds from polygon geometry', () {
        // Arrange
        final geometry = {
          'type': 'Polygon',
          'coordinates': [[
            [-123.0, 37.0],
            [-122.0, 37.0],
            [-122.0, 38.0],
            [-123.0, 38.0],
            [-123.0, 37.0]
          ]]
        };

        // Act
        final bounds = parser.extractBoundsFromGeometry(geometry);

        // Assert
        expect(bounds.north, equals(38.0));
        expect(bounds.south, equals(37.0));
        expect(bounds.east, equals(-122.0));
        expect(bounds.west, equals(-123.0));
      });

      test('should extract bounds from multi-polygon geometry', () {
        // Arrange
        final geometry = {
          'type': 'MultiPolygon',
          'coordinates': [
            [[
              [-123.0, 37.0],
              [-122.0, 37.0],
              [-122.0, 38.0],
              [-123.0, 38.0],
              [-123.0, 37.0]
            ]],
            [[
              [-121.0, 36.0],
              [-120.0, 36.0],
              [-120.0, 37.0],
              [-121.0, 37.0],
              [-121.0, 36.0]
            ]]
          ]
        };

        // Act
        final bounds = parser.extractBoundsFromGeometry(geometry);

        // Assert
        expect(bounds.north, equals(38.0));
        expect(bounds.south, equals(36.0));
        expect(bounds.east, equals(-120.0));
        expect(bounds.west, equals(-123.0));
      });

      test('should throw InvalidGeometryException for unsupported geometry types', () {
        // Arrange
        final geometry = {
          'type': 'Point',
          'coordinates': [-122.0, 37.0]
        };

        // Act & Assert
        expect(
          () => parser.extractBoundsFromGeometry(geometry),
          throwsA(isA<InvalidGeometryException>()),
        );
      });

      test('should throw InvalidGeometryException for invalid coordinates', () {
        // Arrange
        final geometry = {
          'type': 'Polygon',
          'coordinates': [[
            [-123.0], // Missing latitude
            [-122.0, 37.0],
            [-122.0, 38.0]
          ]]
        };

        // Act & Assert
        expect(
          () => parser.extractBoundsFromGeometry(geometry),
          throwsA(isA<InvalidGeometryException>()),
        );
      });
    });

    group('validateRequiredProperties', () {
      test('should return true for valid properties', () {
        // Arrange
        final properties = {
          'CHART': 'US5CA52M',
          'TITLE': 'San Francisco Bay',
          'SCALE': 25000,
          'LAST_UPDATE': '2024-01-15T00:00:00Z',
          'STATE': 'California',
          'USAGE': 'Harbor'
        };

        // Act
        final result = parser.validateRequiredProperties(properties);

        // Assert
        expect(result, isTrue);
      });

      test('should return false for missing required properties', () {
        // Arrange
        final properties = {
          'CHART': 'US5CA52M',
          'TITLE': 'San Francisco Bay',
          // Missing SCALE, LAST_UPDATE, STATE, USAGE
        };

        // Act
        final result = parser.validateRequiredProperties(properties);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for null or empty required properties', () {
        // Arrange
        final properties = {
          'CHART': '',
          'TITLE': null,
          'SCALE': 25000,
          'LAST_UPDATE': '2024-01-15T00:00:00Z',
          'STATE': 'California',
          'USAGE': 'Harbor'
        };

        // Act
        final result = parser.validateRequiredProperties(properties);

        // Assert
        expect(result, isFalse);
      });
    });
  });
}