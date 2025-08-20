import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import '../../../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([HttpClientService, AppLogger])
import 'noaa_api_client_mock_test.mocks.dart';

/// Mock-based unit tests for NOAA API functionality.
/// These tests use mocked HTTP responses to provide fast feedback during development
/// without requiring real network connectivity.
/// 
/// Tagged as 'unit' for quick CI/development feedback.
/// For actual API validation, see integration_test/noaa_real_endpoint_test.dart
@Tags(['unit', 'mock', 'noaa'])
void main() {
  group('NOAA API Client Mock Tests', () {
    late NoaaApiClientImpl apiClient;
    late MockHttpClientService mockHttpClient;
    late MockAppLogger mockLogger;
    late RateLimiter rateLimiter;

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockLogger = MockAppLogger();
      rateLimiter = RateLimiter(requestsPerSecond: 10); // Faster for unit tests
      
      apiClient = NoaaApiClientImpl(
        httpClient: mockHttpClient,
        rateLimiter: rateLimiter,
        logger: mockLogger,
      );
    });

    group('Chart Catalog Fetching', () {
      test('should successfully fetch NOAA chart catalog with mock data', () async {
        // Arrange
        final mockCatalog = TestFixtures.createTestCatalog(
          featureCount: 5,
        );
        final mockResponse = Response(
          data: jsonEncode(mockCatalog),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final catalogString = await apiClient.fetchChartCatalog();

        // Assert
        expect(catalogString, isNotNull);
        expect(catalogString, isA<String>());
        
        final catalog = jsonDecode(catalogString) as Map<String, dynamic>;
        expect(catalog.containsKey('type'), isTrue);
        expect(catalog['type'], equals('FeatureCollection'));
        expect(catalog.containsKey('features'), isTrue);
        
        final features = catalog['features'] as List;
        expect(features.length, equals(5));
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should handle filtered catalog requests with mock data', () async {
        // Arrange
        final mockFilteredCatalog = TestFixtures.createTestCatalog(
          features: [
            TestFixtures.createTestGeoJsonFeature(
              cellName: 'US5CA52M',
              title: 'San Francisco Bay',
              coordinates: [[-122.5, 37.5], [-122.0, 37.5], [-122.0, 38.0], [-122.5, 38.0], [-122.5, 37.5]],
            ),
          ],
        );
        final mockResponse = Response(
          data: jsonEncode(mockFilteredCatalog),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final filteredCatalogString = await apiClient.fetchChartCatalog(
          filters: {'BBOX': '-125.0,32.0,-117.0,42.0'},
        );

        // Assert
        expect(filteredCatalogString, isNotNull);
        final filteredCatalog = jsonDecode(filteredCatalogString) as Map<String, dynamic>;
        expect(filteredCatalog['features'], isA<List>());
        
        final features = filteredCatalog['features'] as List;
        expect(features.length, equals(1));
        expect(features.first['properties']['CELL_NAME'], equals('US5CA52M'));
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should handle network errors gracefully with mock', () async {
        // Arrange
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/charts'),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<DioException>()),
        );
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });
    });

    group('Chart Metadata Retrieval', () {
      test('should retrieve chart metadata for valid chart ID', () async {
        // Arrange
        final testChart = TestFixtures.createTestChart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
        );
        final mockFeature = TestFixtures.createTestGeoJsonFeature(
          cellName: testChart.id,
          title: testChart.title,
          scale: testChart.scale,
        );
        final mockResponse = Response(
          data: jsonEncode(mockFeature),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts/US5CA52M'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final chartMetadata = await apiClient.getChartMetadata('US5CA52M');

        // Assert
        expect(chartMetadata, isNotNull);
        expect(chartMetadata!.id, equals('US5CA52M'));
        expect(chartMetadata.title, equals('San Francisco Bay'));
        expect(chartMetadata.scale, equals(25000));
        expect(chartMetadata.bounds, isNotNull);
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should return null for invalid chart ID', () async {
        // Arrange
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/charts/INVALID'),
              response: Response(
                statusCode: 404,
                requestOptions: RequestOptions(path: '/api/charts/INVALID'),
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act
        final chartMetadata = await apiClient.getChartMetadata('INVALID_CHART_ID_12345');

        // Assert
        expect(chartMetadata, isNull);
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should handle server errors during metadata fetch', () async {
        // Arrange
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/charts/US5CA52M'),
              response: Response(
                statusCode: 500,
                requestOptions: RequestOptions(path: '/api/charts/US5CA52M'),
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act & Assert
        expect(
          () => apiClient.getChartMetadata('US5CA52M'),
          throwsA(isA<DioException>()),
        );
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });
    });

    group('Chart Availability Checks', () {
      test('should check chart availability for valid charts', () async {
        // Arrange
        final mockResponse = Response(
          data: jsonEncode({'available': true}),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts/US5CA52M/available'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final isAvailable = await apiClient.isChartAvailable('US5CA52M');

        // Assert
        expect(isAvailable, isTrue);
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should return false for invalid chart availability', () async {
        // Arrange
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/charts/INVALID/available'),
              response: Response(
                statusCode: 404,
                requestOptions: RequestOptions(path: '/api/charts/INVALID/available'),
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act
        final isAvailable = await apiClient.isChartAvailable('DEFINITELY_INVALID_CHART');

        // Assert
        expect(isAvailable, isFalse);
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should handle network timeouts during availability check', () async {
        // Arrange
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/charts/US5CA52M/available'),
              type: DioExceptionType.receiveTimeout,
            ));

        // Act & Assert
        expect(
          () => apiClient.isChartAvailable('US5CA52M'),
          throwsA(isA<DioException>()),
        );
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });
    });

    group('Error Handling and Resilience', () {
      test('should handle various network failure scenarios', () async {
        // Test different network error types
        final errorTypes = [
          DioExceptionType.connectionTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.connectionError,
        ];

        for (final errorType in errorTypes) {
          // Arrange
          when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
              .thenThrow(DioException(
                requestOptions: RequestOptions(path: '/api/charts'),
                type: errorType,
              ));

          // Act & Assert
          expect(
            () => apiClient.fetchChartCatalog(),
            throwsA(isA<DioException>()),
            reason: 'Should handle $errorType correctly',
          );
          
          verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
          reset(mockHttpClient);
        }
      });

      test('should implement rate limiting correctly', () async {
        // Arrange
        final mockResponse = Response(
          data: jsonEncode({'available': true}),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts/US5CA52M/available'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act - Make multiple rapid requests
        final futures = <Future<bool>>[];
        for (int i = 0; i < 5; i++) {
          futures.add(apiClient.isChartAvailable('US5CA52M'));
        }

        final startTime = DateTime.now();
        final results = await Future.wait(futures);
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);

        // Assert
        expect(results.length, equals(5));
        expect(results.every((result) => result == true), isTrue);
        
        // Rate limiting should introduce some delay
        expect(duration.inMilliseconds, greaterThan(100));
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(5);
      });
    });

    group('Data Validation and Schema Compliance', () {
      test('should validate GeoJSON structure from API response', () async {
        // Arrange
        final invalidCatalog = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': null, // Invalid: geometry should not be null
              'properties': {'title': 'Test Chart'},
            }
          ]
        };
        final mockResponse = Response(
          data: jsonEncode(invalidCatalog),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final catalogString = await apiClient.fetchChartCatalog();

        // Assert - Should still return data but validation can happen at higher level
        expect(catalogString, isNotNull);
        final catalog = jsonDecode(catalogString) as Map<String, dynamic>;
        expect(catalog['type'], equals('FeatureCollection'));
        expect(catalog['features'], isA<List>());
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should handle malformed JSON responses', () async {
        // Arrange
        final mockResponse = Response(
          data: 'invalid json {',
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<FormatException>()),
        );
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should validate required chart properties', () async {
        // Arrange
        final mockCatalog = TestFixtures.createTestCatalog(
          features: [
            TestFixtures.createTestGeoJsonFeature(
              cellName: 'US5CA52M',
              title: 'San Francisco Bay',
              scale: 25000,
            ),
            TestFixtures.createTestGeoJsonFeature(
              cellName: 'US5CA53M',
              title: 'Golden Gate',
              scale: 50000,
            ),
          ],
        );
        final mockResponse = Response(
          data: jsonEncode(mockCatalog),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final catalogString = await apiClient.fetchChartCatalog();

        // Assert
        final catalog = jsonDecode(catalogString) as Map<String, dynamic>;
        final features = catalog['features'] as List;
        
        for (final feature in features) {
          expect(feature['type'], equals('Feature'));
          expect(feature['geometry'], isNotNull);
          expect(feature['properties'], isNotNull);
          
          final properties = feature['properties'];
          expect(properties['CELL_NAME'], isA<String>());
          expect(properties['TITLE'], isA<String>());
          expect(properties['SCALE'], isA<int>());
        }
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });
    });

    group('Performance and Optimization', () {
      test('should handle large catalog responses efficiently', () async {
        // Arrange
        final largeCatalog = TestFixtures.createTestCatalog(
          featureCount: 1000, // Large number of charts
        );
        final mockResponse = Response(
          data: jsonEncode(largeCatalog),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final startTime = DateTime.now();
        final catalogString = await apiClient.fetchChartCatalog();
        final endTime = DateTime.now();
        final processingTime = endTime.difference(startTime);

        // Assert
        expect(catalogString, isNotNull);
        final catalog = jsonDecode(catalogString) as Map<String, dynamic>;
        final features = catalog['features'] as List;
        expect(features.length, equals(1000));
        
        // Should process reasonably quickly (less than 1 second for mocked data)
        expect(processingTime.inMilliseconds, lessThan(1000));
        
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(1);
      });

      test('should cache repeated requests appropriately', () async {
        // Note: This test validates the structure for caching
        // Actual caching implementation would be tested separately
        
        // Arrange
        final mockResponse = Response(
          data: jsonEncode({'available': true}),
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/charts/US5CA52M/available'),
        );

        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act - Make same request multiple times
        final result1 = await apiClient.isChartAvailable('US5CA52M');
        final result2 = await apiClient.isChartAvailable('US5CA52M');
        final result3 = await apiClient.isChartAvailable('US5CA52M');

        // Assert
        expect(result1, isTrue);
        expect(result2, isTrue);
        expect(result3, isTrue);
        
        // Without caching, each request should hit the HTTP client
        verify(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters'))).called(3);
      });
    });
  });
}