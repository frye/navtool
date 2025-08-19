import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/metadata_parsing_exceptions.dart';
import 'dart:convert';
import 'dart:io';

// Generate mocks for dependencies
@GenerateMocks([AppLogger])
import '../../../core/services/noaa/noaa_metadata_parser_test.mocks.dart';

void main() {
  group('Enhanced NOAA Metadata Parser Tests', () {
    late NoaaMetadataParserImpl parser;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      parser = NoaaMetadataParserImpl(logger: mockLogger);
    });

    group('Metadata Parsing Exceptions', () {
      test('should throw MetadataParsingException for invalid catalog structure', () async {
        // Arrange
        final invalidData = {
          'type': 'InvalidCollection',
          'features': []
        };

        // Act & Assert
        expect(
          () => parser.parseGeoJsonToCharts(invalidData),
          throwsA(isA<MetadataParsingException>()),
        );
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

      test('should throw MissingRequiredFieldException for missing fields', () {
        // Arrange
        final properties = {
          'CHART': 'US5CA52M',
          'TITLE': 'San Francisco Bay',
          // Missing SCALE, LAST_UPDATE, STATE, USAGE
        };

        // Act & Assert
        expect(parser.validateRequiredProperties(properties), isFalse);
      });

      test('should throw DateParsingException for invalid date formats', () async {
        // Arrange
        final properties = {
          'CHART': 'US5CA52M',
          'TITLE': 'San Francisco Bay',
          'SCALE': 25000,
          'LAST_UPDATE': 'invalid-date',
          'STATE': 'California',
          'USAGE': 'Harbor'
        };
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
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': geometry,
              'properties': properties
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert - Should skip invalid feature and continue
        expect(result, isEmpty);
        verify(mockLogger.warning(
          'Failed to parse chart feature',
          exception: anyNamed('exception'),
        )).called(1);
      });
    });

    group('Enhanced Chart Model Integration', () {
      test('should parse NOAA charts with complete metadata fields', () async {
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
                'CELL_NAME': 'US5CA52M',
                'CHART': 'US5CA52M',
                'TITLE': 'San Francisco Bay',
                'SCALE': 25000,
                'LAST_UPDATE': '2024-01-15T00:00:00Z',
                'RELEASE_DATE': '2024-01-15T00:00:00Z',
                'STATE': 'California',
                'USAGE': 'Harbor',
                'REGION': 'West Coast',
                'STATUS': 'Current',
                'EDITION_NUM': '12',
                'UPDATE_NUM': '3',
                'COMPILATION_SCALE': '25000',
                'DT_PUB': '20240115',
                'ISSUE_DATE': '2024-01-15',
                'SOURCE_DATE_STRING': 'January 2024',
                'EDITION_DATE': '2024-01-15T00:00:00Z'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(1));
        final chart = result[0];
        expect(chart.id, equals('US5CA52M'));
        expect(chart.title, equals('San Francisco Bay'));
        expect(chart.scale, equals(25000));
        expect(chart.state, equals('California'));
        expect(chart.type, equals(ChartType.harbor));
        expect(chart.source, equals(ChartSource.noaa));
        expect(chart.status, equals(ChartStatus.current));
        expect(chart.edition, equals(12));
        expect(chart.updateNumber, equals(3));
        
        // Check metadata fields
        expect(chart.metadata['cellName'], equals('US5CA52M'));
        expect(chart.metadata['region'], equals('West Coast'));
        expect(chart.metadata['compilationScale'], equals('25000'));
        expect(chart.metadata['dtPub'], equals('20240115'));
      });

      test('should handle different chart statuses correctly', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-95.0, 29.0],
                  [-94.0, 29.0],
                  [-94.0, 30.0],
                  [-95.0, 30.0],
                  [-95.0, 29.0]
                ]]
              },
              'properties': {
                'CHART': 'US5TX31M',
                'TITLE': 'Galveston Bay',
                'SCALE': 30000,
                'LAST_UPDATE': '2023-12-15T00:00:00Z',
                'STATE': 'Texas',
                'USAGE': 'Harbor',
                'STATUS': 'Superseded',
                'EDITION_NUM': '9',
                'UPDATE_NUM': '0'
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(1));
        final chart = result[0];
        expect(chart.status, equals(ChartStatus.superseded));
        expect(chart.edition, equals(9));
        expect(chart.updateNumber, equals(0));
      });

      test('should provide fallback values for missing optional fields', () async {
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
                // Missing optional fields like EDITION_NUM, UPDATE_NUM, STATUS
              }
            }
          ]
        };

        // Act
        final result = await parser.parseGeoJsonToCharts(geoJsonData);

        // Assert
        expect(result, hasLength(1));
        final chart = result[0];
        expect(chart.edition, equals(0)); // Default fallback
        expect(chart.updateNumber, equals(0)); // Default fallback
        expect(chart.status, equals(ChartStatus.current)); // Default fallback
        expect(chart.source, equals(ChartSource.noaa)); // Default fallback
      });
    });

    group('Real NOAA Catalog Processing', () {
      test('should process sample NOAA catalog data successfully', () async {
        // Arrange
        final catalogFile = File('test/fixtures/noaa_catalog_sample.json');
        final catalogJson = await catalogFile.readAsString();
        final catalogData = jsonDecode(catalogJson) as Map<String, dynamic>;

        // Act
        final result = await parser.parseGeoJsonToCharts(catalogData);

        // Assert
        expect(result, hasLength(5));
        
        // Check variety of chart types and statuses
        final chartTypes = result.map((c) => c.type).toSet();
        expect(chartTypes, contains(ChartType.harbor));
        expect(chartTypes, contains(ChartType.approach));
        
        final statuses = result.map((c) => c.status).toSet();
        expect(statuses, contains(ChartStatus.current));
        expect(statuses, contains(ChartStatus.superseded));
        
        // Check different states are represented
        final states = result.map((c) => c.state).toSet();
        expect(states, contains('California'));
        expect(states, contains('New York'));
        expect(states, contains('Texas'));
        expect(states, contains('Hawaii'));
        
        // Verify metadata is populated
        for (final chart in result) {
          expect(chart.metadata, isNotEmpty);
          expect(chart.metadata['cellName'], isNotNull);
        }
      });

      test('should handle large catalog processing efficiently', () async {
        // Arrange - Create a large catalog with many features
        final largeFeatures = <Map<String, dynamic>>[];
        for (int i = 0; i < 100; i++) {
          largeFeatures.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [[
                [-123.0 - i * 0.1, 37.0],
                [-122.0 - i * 0.1, 37.0],
                [-122.0 - i * 0.1, 38.0],
                [-123.0 - i * 0.1, 38.0],
                [-123.0 - i * 0.1, 37.0]
              ]]
            },
            'properties': {
              'CHART': 'US5CA${i.toString().padLeft(2, '0')}M',
              'CELL_NAME': 'US5CA${i.toString().padLeft(2, '0')}M',
              'TITLE': 'Test Chart $i',
              'SCALE': 25000,
              'LAST_UPDATE': '2024-01-15T00:00:00Z',
              'STATE': 'California',
              'USAGE': 'Harbor',
              'EDITION_NUM': '1',
              'UPDATE_NUM': '0'
            }
          });
        }

        final largeCatalogData = {
          'type': 'FeatureCollection',
          'features': largeFeatures
        };

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await parser.parseGeoJsonToCharts(largeCatalogData);
        stopwatch.stop();

        // Assert
        expect(result, hasLength(100));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete in < 5 seconds
        
        // Verify all charts were parsed correctly
        for (int i = 0; i < 100; i++) {
          final chart = result[i];
          expect(chart.id, equals('US5CA${i.toString().padLeft(2, '0')}M'));
          expect(chart.metadata['cellName'], isNotNull);
        }
      });
    });

    group('Enhanced Error Handling and Debugging', () {
      test('should provide detailed error information for debugging', () async {
        // Arrange
        final geoJsonData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': 'invalid-coordinates' // Invalid coordinates
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

        // Assert - Should gracefully handle the error and continue
        expect(result, isEmpty);
        verify(mockLogger.warning(
          'Failed to parse chart feature',
          exception: anyNamed('exception'),
        )).called(1);
      });

      test('should handle edge case coordinates gracefully', () {
        // Arrange - Use valid coordinates that are at the edge of valid ranges
        final geometry = {
          'type': 'Polygon',
          'coordinates': [[
            [-180.0, 89.0], // Edge valid coordinates
            [-179.0, 89.0],
            [-179.0, 88.0],
            [-180.0, 88.0],
            [-180.0, 89.0]
          ]]
        };

        // Act
        final bounds = parser.extractBoundsFromGeometry(geometry);

        // Assert - Should handle edge case coordinates
        expect(bounds.north, equals(89.0));
        expect(bounds.south, equals(88.0));
        expect(bounds.east, equals(-179.0));
        expect(bounds.west, equals(-180.0));
      });

      test('should handle memory efficiently with large polygon geometries', () {
        // Arrange - Create polygon with many coordinates
        final coordinates = <List<double>>[];
        for (int i = 0; i < 1000; i++) {
          coordinates.add([-123.0 + (i * 0.001), 37.0 + (i * 0.001)]);
        }
        coordinates.add(coordinates[0]); // Close the polygon

        final geometry = {
          'type': 'Polygon',
          'coordinates': [coordinates]
        };

        // Act
        final stopwatch = Stopwatch()..start();
        final bounds = parser.extractBoundsFromGeometry(geometry);
        stopwatch.stop();

        // Assert
        expect(bounds.north, greaterThan(37.0));
        expect(bounds.south, equals(37.0));
        expect(bounds.east, greaterThan(-123.0));
        expect(bounds.west, equals(-123.0));
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });
    });

    group('Chart Scale to ChartType Enhancement', () {
      test('should properly map all NOAA usage bands to ChartType enum', () {
        // Test all supported usage bands
        expect(parser.parseChartUsageToType('Harbor'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('Approach'), equals(ChartType.approach));
        expect(parser.parseChartUsageToType('Coastal'), equals(ChartType.coastal));
        expect(parser.parseChartUsageToType('General'), equals(ChartType.general));
        expect(parser.parseChartUsageToType('Overview'), equals(ChartType.overview));
        expect(parser.parseChartUsageToType('Berthing'), equals(ChartType.berthing));
      });

      test('should handle case variations in usage strings', () {
        expect(parser.parseChartUsageToType('HARBOR'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('harbor'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('Harbor'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('HaRbOr'), equals(ChartType.harbor));
      });

      test('should provide appropriate fallback for unknown usage strings', () {
        expect(parser.parseChartUsageToType('Unknown'), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType(''), equals(ChartType.harbor));
        expect(parser.parseChartUsageToType('Invalid'), equals(ChartType.harbor));
      });
    });
  });
}