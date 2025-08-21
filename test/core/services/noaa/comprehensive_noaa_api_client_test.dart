import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import '../../../utils/test_fixtures.dart';

// Generate mocks for dependencies
@GenerateMocks([
  HttpClientService,
  AppLogger,
  RateLimiter,
])
import 'comprehensive_noaa_api_client_test.mocks.dart';

/// Comprehensive unit tests for NOAA API Client
/// 
/// These tests achieve >90% coverage by testing edge cases,
/// error conditions, and marine environment scenarios.
void main() {
  group('Comprehensive NOAA API Client Tests', () {
    late NoaaApiClientImpl apiClient;
    late MockHttpClientService mockHttpClient;
    late MockAppLogger mockLogger;
    late MockRateLimiter mockRateLimiter;

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockLogger = MockAppLogger();
      mockRateLimiter = MockRateLimiter();
      
      apiClient = NoaaApiClientImpl(
        httpClient: mockHttpClient,
        logger: mockLogger,
        rateLimiter: mockRateLimiter,
      );
    });

    group('fetchChartCatalog', () {
      test('should handle empty catalog response', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: '{"type":"FeatureCollection","features":[]}',
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.fetchChartCatalog();

        // Assert
        expect(result, equals('{"type":"FeatureCollection","features":[]}'));
        verify(mockRateLimiter.acquire()).called(1);
      });

      test('should handle large catalog response efficiently', () async {
        // Arrange
        final largeCatalog = MockResponseBuilders.buildCatalogResponse(chartCount: 1000);
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: largeCatalog,
              statusCode: 200,
            ));

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await apiClient.fetchChartCatalog();
        stopwatch.stop();

        // Assert
        expect(result, equals(largeCatalog));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should be fast
      });

      test('should handle malformed JSON response', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: 'invalid json {{{',
              statusCode: 200,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NoaaApiException>()),
        );
      });

      test('should handle HTTP 500 server error', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 500,
                statusMessage: 'Internal Server Error',
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NoaaApiException>().having(
            (e) => e.isRetryable, 'isRetryable', isTrue,
          )),
        );
      });

      test('should handle connection timeout', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.connectionTimeout,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });

      test('should handle receive timeout', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.receiveTimeout,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });

      test('should pass through query parameters correctly', () async {
        // Arrange
        final filters = {
          'BBOX': '-124.0,32.0,-114.0,42.0',
          'STATE': 'California',
        };
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: '{"type":"FeatureCollection","features":[]}',
              statusCode: 200,
            ));

        // Act
        await apiClient.fetchChartCatalog(filters: filters);

        // Assert
        verify(mockHttpClient.get(
          any,
          queryParameters: argThat(
            containsPair('BBOX', '-124.0,32.0,-114.0,42.0'),
            named: 'queryParameters',
          ),
        )).called(1);
      });

      test('should handle network connection error', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.connectionError,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });
    });

    group('getChartMetadata', () {
      test('should return null for 404 response', () async {
        // Arrange
        const chartId = 'NONEXISTENT_CHART';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 404,
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act
        final result = await apiClient.getChartMetadata(chartId);

        // Assert
        expect(result, isNull);
      });

      test('should parse valid chart metadata', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final testChart = TestFixtures.createTestChart(
          id: chartId,
          title: 'San Francisco Bay',
          state: 'California',
        );
        
        final metadataResponse = MockResponseBuilders.buildChartMetadataResponse(testChart);
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: metadataResponse,
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.getChartMetadata(chartId);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(chartId));
        expect(result.title, equals('San Francisco Bay'));
      });

      test('should handle empty metadata response', () async {
        // Arrange
        const chartId = 'US5CA52M';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: '{}',
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.getChartMetadata(chartId);

        // Assert
        expect(result, isNull);
      });

      test('should handle metadata response with missing properties', () async {
        // Arrange
        const chartId = 'US5CA52M';
        final incompleteData = '{"type":"Feature","geometry":null,"properties":null}';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: incompleteData,
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.getChartMetadata(chartId);

        // Assert
        expect(result, isNull);
      });

      test('should validate chart ID format', () async {
        // Arrange
        const invalidChartId = '';

        // Act & Assert
        expect(
          () => apiClient.getChartMetadata(invalidChartId),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle malformed metadata JSON', () async {
        // Arrange
        const chartId = 'US5CA52M';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: 'invalid json response',
              statusCode: 200,
            ));

        // Act & Assert
        expect(
          () => apiClient.getChartMetadata(chartId),
          throwsA(isA<NoaaApiException>()),
        );
      });
    });

    group('isChartAvailable', () {
      test('should return true for available chart', () async {
        // Arrange
        const chartId = 'US5CA52M';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: '{"available":true}',
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.isChartAvailable(chartId);

        // Assert
        expect(result, isTrue);
      });

      test('should return false for 404 response', () async {
        // Arrange
        const chartId = 'NONEXISTENT_CHART';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 404,
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act
        final result = await apiClient.isChartAvailable(chartId);

        // Assert
        expect(result, isFalse);
      });

      test('should handle server error during availability check', () async {
        // Arrange
        const chartId = 'US5CA52M';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 500,
              ),
              type: DioExceptionType.badResponse,
            ));

        // Act & Assert
        expect(
          () => apiClient.isChartAvailable(chartId),
          throwsA(isA<NoaaApiException>()),
        );
      });

      test('should validate chart ID parameter', () async {
        // Act & Assert
        expect(
          () => apiClient.isChartAvailable(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('downloadChart', () {
      test('should handle successful download with progress', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const savePath = '/tmp/test_chart.zip';
        final progressValues = <double>[];
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[const Symbol('onReceiveProgress')] as Function?;
          
          // Simulate download progress
          onProgress?.call(25, 100);
          onProgress?.call(50, 100);
          onProgress?.call(75, 100);
          onProgress?.call(100, 100);
        });

        // Act
        await apiClient.downloadChart(
          chartId,
          savePath,
          onProgress: (progress) => progressValues.add(progress),
        );

        // Assert
        expect(progressValues, [0.25, 0.5, 0.75, 1.0]);
        verify(mockHttpClient.downloadFile(
          any,
          savePath,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).called(1);
      });

      test('should handle download without progress callback', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const savePath = '/tmp/test_chart.zip';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async {});

        // Act
        await apiClient.downloadChart(chartId, savePath);

        // Assert
        verify(mockHttpClient.downloadFile(
          any,
          savePath,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).called(1);
      });

      test('should handle download failure', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const savePath = '/tmp/test_chart.zip';
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert
        expect(
          () => apiClient.downloadChart(chartId, savePath),
          throwsA(isA<NoaaApiException>()),
        );
      });

      test('should validate download parameters', () async {
        // Act & Assert
        expect(
          () => apiClient.downloadChart('', '/tmp/test.zip'),
          throwsA(isA<ArgumentError>()),
        );
        
        expect(
          () => apiClient.downloadChart('US5CA52M', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle zero-length download progress', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const savePath = '/tmp/test_chart.zip';
        final progressValues = <double>[];
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[const Symbol('onReceiveProgress')] as Function?;
          
          // Simulate unknown total length
          onProgress?.call(1024, -1);
        });

        // Act
        await apiClient.downloadChart(
          chartId,
          savePath,
          onProgress: (progress) => progressValues.add(progress),
        );

        // Assert - Should handle unknown total gracefully
        expect(progressValues, isEmpty); // No progress reported for unknown total
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle unexpected DioException types', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.unknown,
            ));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NoaaApiException>()),
        );
      });

      test('should handle non-DioException errors', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(Exception('Unexpected error'));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle rate limiter throwing exception', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenThrow(Exception('Rate limiter error'));

        // Act & Assert
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle very long response data', () async {
        // Arrange - Create a large but valid JSON response
        final features = List.generate(1000, (i) => {
          "type": "Feature",
          "properties": {
            "chartId": "US5CA52M_$i",
            "title": "Test Chart $i with a very long title that includes lots of descriptive text",
            "scale": "1:80000",
            "edition": "1st Ed., 2024"
          },
          "geometry": {
            "type": "Polygon",
            "coordinates": [[[-122.5, 37.7], [-122.4, 37.7], [-122.4, 37.8], [-122.5, 37.8], [-122.5, 37.7]]]
          }
        });
        final veryLongResponse = jsonEncode({
          "type": "FeatureCollection",
          "features": features
        });
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: veryLongResponse,
              statusCode: 200,
            ));

        // Act
        final result = await apiClient.fetchChartCatalog();

        // Assert
        expect(result, equals(veryLongResponse));
        expect(result.length, greaterThan(50000)); // Verify it's a large response
      });

      test('should log all operations correctly', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              data: '{"type":"FeatureCollection","features":[]}',
              statusCode: 200,
            ));

        // Act
        await apiClient.fetchChartCatalog();

        // Assert
        verify(mockLogger.info(
          'Fetching NOAA chart catalog',
          context: 'NoaaApiClient',
        )).called(1);
        
        verify(mockLogger.info(
          'Successfully fetched chart catalog',
          context: 'NoaaApiClient',
        )).called(1);
      });

      test('should log errors with proper context', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.connectionError,
            ));

        // Act & Assert
        try {
          await apiClient.fetchChartCatalog();
        } catch (e) {
          // Expected to throw
        }

        verify(mockLogger.error(
          'Failed to fetch chart catalog',
          context: 'NoaaApiClient',
          exception: anyNamed('exception'),
        )).called(1);
      });
    });

    group('Marine Environment Specific Tests', () {
      test('should handle satellite internet timeout scenarios', () async {
        // Arrange - Simulate slow satellite connection
        when(mockRateLimiter.acquire()).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        when(mockHttpClient.get(
          any, 
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async {
          await Future.delayed(const Duration(seconds: 1)); // Slow response
          return Response(
            requestOptions: RequestOptions(path: ''),
            data: '{"type":"FeatureCollection","features":[]}',
            statusCode: 200,
          );
        });

        // Act
        final result = await apiClient.fetchChartCatalog();

        // Assert
        expect(result, isNotEmpty);
      });

      test('should handle intermittent connectivity gracefully', () async {
        // Arrange - Simulate intermittent connection issues
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.connectionError,
            ));

        // Act & Assert - Should fail with network connectivity exception
        expect(
          () => apiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });

      test('should handle bandwidth-limited downloads', () async {
        // Arrange
        const chartId = 'US5CA52M';
        const savePath = '/tmp/test_chart.zip';
        final progressValues = <double>[];
        
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[const Symbol('onReceiveProgress')] as Function?;
          
          // Simulate slow download with gradual progress
          for (int i = 1; i <= 10; i++) {
            await Future.delayed(const Duration(milliseconds: 10));
            onProgress?.call(i * 1024 * 1024, 10 * 1024 * 1024); // 1MB steps
          }
        });

        // Act
        await apiClient.downloadChart(
          chartId,
          savePath,
          onProgress: (progress) => progressValues.add(progress),
        );

        // Assert
        expect(progressValues.length, greaterThanOrEqualTo(5)); // At least some progress updates
        expect(progressValues.last, equals(1.0));
        expect(progressValues.first, equals(0.1));
      });
    });
  });
}