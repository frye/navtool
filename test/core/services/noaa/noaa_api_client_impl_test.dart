import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';

import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';

// Generate mocks for the dependencies
@GenerateMocks([
  HttpClientService,
  RateLimiter,
  AppLogger,
])
import 'noaa_api_client_impl_test.mocks.dart';

void main() {
  group('NoaaApiClientImpl Tests', () {
    late MockHttpClientService mockHttpClient;
    late MockRateLimiter mockRateLimiter;
    late MockAppLogger mockLogger;
    late NoaaApiClientImpl noaaApiClient;

    setUp(() {
      mockHttpClient = MockHttpClientService();
      mockRateLimiter = MockRateLimiter();
      mockLogger = MockAppLogger();
      
      noaaApiClient = NoaaApiClientImpl(
        httpClient: mockHttpClient,
        rateLimiter: mockRateLimiter,
        logger: mockLogger,
      );
    });

    test('should fetch chart catalog successfully', () async {
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
      final result = await noaaApiClient.fetchChartCatalog();

      // Assert
      expect(result, isA<String>());
      expect(result, isNotEmpty);
      verify(mockHttpClient.get(
        any,
        queryParameters: anyNamed('queryParameters'),
      )).called(1);
    });

    test('should handle network errors', () async {
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

    test('should handle rate limiting', () async {
      // Arrange
      when(mockHttpClient.get(
        any,
        queryParameters: anyNamed('queryParameters'),
      )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 429,
        ),
        type: DioExceptionType.badResponse,
      ));

      // Act & Assert
      expect(
        () => noaaApiClient.fetchChartCatalog(),
        throwsA(isA<RateLimitExceededException>()),
      );
    });

    test('should handle chart not available', () async {
      // Arrange
      const cellName = 'NONEXISTENT';
      when(mockHttpClient.get(
        any,
        queryParameters: anyNamed('queryParameters'),
      )).thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: ''),
        data: '{"type":"FeatureCollection","features":[]}',
        statusCode: 200,
      ));

      // Act
      final result = await noaaApiClient.getChartMetadata(cellName);

      // Assert
      expect(result, isNull);
      verify(mockHttpClient.get(
        any,
        queryParameters: anyNamed('queryParameters'),
      )).called(1);
    });

    test('should download chart successfully', () async {
      // Arrange
      const cellName = 'US5CA52M';
      const savePath = '/test/path/US5CA52M.zip';

      when(mockHttpClient.downloadFile(
        any,
        any,
        onReceiveProgress: anyNamed('onReceiveProgress'),
        cancelToken: anyNamed('cancelToken'),
      )).thenAnswer((_) async {});

      // Act
      await noaaApiClient.downloadChart(cellName, savePath);

      // Assert
      verify(mockHttpClient.downloadFile(
        any,
        any,
        onReceiveProgress: anyNamed('onReceiveProgress'),
        cancelToken: anyNamed('cancelToken'),
      )).called(1);
    });
  });
}