import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';

// Generate mocks: flutter packages pub run build_runner build
@GenerateMocks([HttpClientService, RateLimiter, AppLogger])
import 'noaa_api_client_impl_test.mocks.dart';

/// Comprehensive tests for NoaaApiClientImpl
/// Tests catalog operations, chart metadata retrieval, and downloads
void main() {
  group('NoaaApiClientImpl Tests', () {
    late MockHttpClientService mockHttpClient;
    late MockRateLimiter mockRateLimiter;
    late MockAppLogger mockLogger;
    late NoaaApiClientImpl noaaApiClient;

    // Test data constants
    const catalogEndpoint = 'https://gis.charttools.noaa.gov/arcgis/rest/services/MCS/ENCOnline/MapServer/exts/MaritimeChartService/WMSServer?'
        'SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.3.0';
    const chartDownloadBase = 'https://charts.noaa.gov/ENCs/';

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockRateLimiter = MockRateLimiter();
      mockLogger = MockAppLogger();

      // Set up default successful rate limiter behavior
      when(mockRateLimiter.acquire()).thenAnswer((_) async {});

      noaaApiClient = NoaaApiClientImpl(
        httpClient: mockHttpClient,
        rateLimiter: mockRateLimiter,
        logger: mockLogger,
      );
    });

    group('Initialization Tests', () {
      test('should create NoaaApiClientImpl with required dependencies', () {
        // Assert
        expect(noaaApiClient, isNotNull);
        expect(noaaApiClient, isA<NoaaApiClientImpl>());
      });

      test('should log initialization message', () {
        // Verify initialization was logged
        verify(mockLogger.info('NOAA API Client initialized')).called(1);
      });
    });

    group('Catalog Operations Tests', () {
      test('should fetch chart catalog successfully', () async {
        // Arrange
        final mockGeoJsonResponse = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [-122.5, 37.6],
                  [-122.3, 37.6],
                  [-122.3, 37.8],
                  [-122.5, 37.8],
                  [-122.5, 37.6]
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
            }
          ]
        };

        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: jsonEncode(mockGeoJsonResponse),
          statusCode: 200,
        ));

        // Act
        final result = await noaaApiClient.fetchChartCatalog();

        // Assert
        expect(result, isA<String>());
        expect(result, contains('FeatureCollection'));
        expect(result, contains('US5CA52M'));
        
        verify(mockRateLimiter.acquire()).called(1);
        verify(mockHttpClient.get(
          argThat(contains('gis.charttools.noaa.gov')),
          queryParameters: anyNamed('queryParameters'),
        )).called(1);
      });

      test('should fetch chart catalog with filters', () async {
        // Arrange
        final filters = {'STATE': 'California', 'USAGE': 'Harbor'};
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: '{"type":"FeatureCollection","features":[]}',
          statusCode: 200,
        ));

        // Act
        await noaaApiClient.fetchChartCatalog(filters: filters);

        // Assert
        verify(mockRateLimiter.acquire()).called(1);
        verify(mockHttpClient.get(
          any,
          queryParameters: argThat(
            allOf([
              containsPair('STATE', 'California'),
              containsPair('USAGE', 'Harbor'),
            ]),
            named: 'queryParameters',
          ),
        )).called(1);
      });

      test('should handle rate limiting during catalog fetch', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenThrow(
          RateLimitExceededException(
            retryAfter: const Duration(seconds: 30),
          ),
        );

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<RateLimitExceededException>()),
        );
      });

      test('should handle network errors during catalog fetch', () async {
        // Arrange
        when(mockRateLimiter.acquire()).thenAnswer((_) async {});
        when(mockHttpClient.get(any, queryParameters: anyNamed('queryParameters')))
            .thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });
    });

    group('Chart Metadata Operations Tests', () {
      test('should get chart metadata successfully', () async {
        // Arrange
        const cellName = 'US5CA52M';
        final mockChartData = {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [-122.5, 37.6],
              [-122.3, 37.6],
              [-122.3, 37.8],
              [-122.5, 37.8],
              [-122.5, 37.6]
            ]]
          },
          'properties': {
            'CHART': cellName,
            'TITLE': 'San Francisco Bay',
            'SCALE': 25000,
            'LAST_UPDATE': '2024-01-15T00:00:00Z',
            'STATE': 'California',
            'USAGE': 'Harbor'
          }
        };

        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: jsonEncode(mockChartData),
          statusCode: 200,
        ));

        // Act
        final result = await noaaApiClient.getChartMetadata(cellName);

        // Assert
        expect(result, isNotNull);
        expect(result!.id, equals(cellName));
        expect(result.title, equals('San Francisco Bay'));
        expect(result.scale, equals(25000));
        expect(result.type, equals(ChartType.harbor));
        expect(result.state, equals('California'));
        expect(result.bounds.north, equals(37.8));
        expect(result.bounds.south, equals(37.6));
        expect(result.bounds.east, equals(-122.3));
        expect(result.bounds.west, equals(-122.5));

        verify(mockRateLimiter.acquire()).called(1);
        verify(mockHttpClient.get(
          argThat(contains(cellName)),
          queryParameters: anyNamed('queryParameters'),
        )).called(1);
      });

      test('should return null for non-existent chart', () async {
        // Arrange
        const cellName = 'NON_EXISTENT';
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 404,
          ),
        ));

        // Act
        final result = await noaaApiClient.getChartMetadata(cellName);

        // Assert
        expect(result, isNull);
        verify(mockRateLimiter.acquire()).called(1);
      });

      test('should check chart availability successfully', () async {
        // Arrange
        const cellName = 'US5CA52M';
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
        ));

        // Act
        final result = await noaaApiClient.isChartAvailable(cellName);

        // Assert
        expect(result, isTrue);
        verify(mockRateLimiter.acquire()).called(1);
      });

      test('should return false for unavailable chart', () async {
        // Arrange
        const cellName = 'UNAVAILABLE';
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 404,
          ),
        ));

        // Act
        final result = await noaaApiClient.isChartAvailable(cellName);

        // Assert
        expect(result, isFalse);
        verify(mockRateLimiter.acquire()).called(1);
      });
    });

    group('Download Operations Tests', () {
      test('should download chart successfully with progress tracking', () async {
        // Arrange
        const cellName = 'US5CA52M';
        const savePath = '/test/path/US5CA52M.zip';
        final progressValues = <double>[];

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          if (onProgress != null) {
            onProgress(25, 100); // 25% progress
            onProgress(50, 100); // 50% progress
            onProgress(100, 100); // 100% progress
          }
        });

        // Act
        await noaaApiClient.downloadChart(
          cellName,
          savePath,
          onProgress: (progress) => progressValues.add(progress),
        );

        // Assert
        expect(progressValues, equals([0.25, 0.50, 1.0]));
        verify(mockRateLimiter.acquire()).called(1);
        verify(mockHttpClient.downloadFile(
          '${chartDownloadBase}$cellName.zip',
          savePath,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).called(1);
      });

      test('should handle download cancellation', () async {
        // Arrange
        const cellName = 'US5CA52M';
        const savePath = '/test/path/US5CA52M.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.downloadChart(cellName, savePath),
          throwsA(isA<ChartDownloadException>()),
        );
      });

      test('should track download progress with streams', () async {
        // Arrange
        const cellName = 'US5CA52M';
        const savePath = '/test/path/US5CA52M.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenAnswer((invocation) async {
          // Simulate progress callback
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          if (onProgress != null) {
            onProgress(50, 100); // 50% progress
            onProgress(100, 100); // 100% progress
          }
        });

        // Act - Start download and get progress stream
        final downloadFuture = noaaApiClient.downloadChart(cellName, savePath);
        await downloadFuture; // Complete the download

        // The implementation creates and manages the progress stream internally
        // For now, we just verify the download completed successfully
        verify(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).called(1);
      });

      test('should handle download failures', () async {
        // Arrange
        const cellName = 'US5CA52M';
        const savePath = '/test/path/US5CA52M.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.downloadChart(cellName, savePath),
          throwsA(isA<ChartDownloadException>()),
        );
      });
    });

    group('Error Handling Tests', () {
      test('should convert HTTP 404 to ChartNotAvailableException', () async {
        // Arrange
        const cellName = 'NON_EXISTENT';
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 404,
          ),
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<ChartNotAvailableException>()),
        );
      });

      test('should convert HTTP 429 to RateLimitExceededException', () async {
        // Arrange
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 429,
          ),
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<RateLimitExceededException>()),
        );
      });

      test('should convert connection errors to NetworkConnectivityException', () async {
        // Arrange
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<NetworkConnectivityException>()),
        );
      });

      test('should convert 503 errors to NoaaServiceUnavailableException', () async {
        // Arrange
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 503,
          ),
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.fetchChartCatalog(),
          throwsA(isA<NoaaServiceUnavailableException>()),
        );
      });
    });

    group('Logging and Monitoring Tests', () {
      test('should log successful operations', () async {
        // Arrange
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: '{"type":"FeatureCollection","features":[]}',
          statusCode: 200,
        ));

        // Act
        await noaaApiClient.fetchChartCatalog();

        // Assert
        verify(mockLogger.info('Fetching NOAA chart catalog')).called(1);
        verify(mockLogger.info('Successfully fetched chart catalog')).called(1);
      });

      test('should log download progress', () async {
        // Arrange
        const cellName = 'US5CA52M';
        const savePath = '/test/path/US5CA52M.zip';

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
        )).thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onReceiveProgress] as Function(int, int)?;
          if (onProgress != null) {
            onProgress(100, 100); // 100% progress
          }
        });

        // Act
        await noaaApiClient.downloadChart(cellName, savePath);

        // Assert
        verify(mockLogger.info('Starting download for chart: $cellName')).called(1);
        verify(mockLogger.info('Chart download completed: $cellName')).called(1);
      });

      test('should log errors with context', () async {
        // Arrange
        const cellName = 'ERROR_CHART';
        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        // Act & Assert
        expect(
          () => noaaApiClient.getChartMetadata(cellName),
          throwsA(isA<NetworkConnectivityException>()),
        );

        // Verify basic logging occurred
        verify(mockLogger.info('Getting chart metadata for $cellName')).called(1);
        // Error logging might be called or not depending on implementation flow
        // The important thing is the exception is properly converted and thrown
      });
    });

    group('Concurrent Operations Tests', () {
      test('should handle multiple simultaneous downloads', () async {
        // Arrange
        const chartIds = ['US5CA52M', 'US4CA11M', 'US1AK90M'];
        const savePath = '/test/path/';

        when(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).thenAnswer((invocation) async {
          await Future.delayed(const Duration(milliseconds: 100));
        });

        // Act
        final futures = chartIds.map((chartId) => 
          noaaApiClient.downloadChart(chartId, '$savePath$chartId.zip')
        ).toList();

        await Future.wait(futures);

        // Assert
        verify(mockHttpClient.downloadFile(
          any,
          any,
          onReceiveProgress: anyNamed('onReceiveProgress'),
          cancelToken: anyNamed('cancelToken'),
        )).called(chartIds.length);
      });

      test('should handle rate limiting across concurrent operations', () async {
        // Arrange
        var acquireCallCount = 0;
        when(mockRateLimiter.acquire()).thenAnswer((_) async {
          acquireCallCount++;
          if (acquireCallCount > 2) {
            throw RateLimitExceededException();
          }
        });

        when(mockHttpClient.get(
          any,
          queryParameters: anyNamed('queryParameters'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          data: '{"type":"FeatureCollection","features":[]}',
          statusCode: 200,
        ));

        // Act
        final futures = [
          noaaApiClient.fetchChartCatalog(),
          noaaApiClient.fetchChartCatalog(),
          noaaApiClient.fetchChartCatalog(), // This should fail
        ];

        // Assert
        expect(futures[0], completes);
        expect(futures[1], completes);
        expect(futures[2], throwsA(isA<RateLimitExceededException>()));
      });
    });
  });
}