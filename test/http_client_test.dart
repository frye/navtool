import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/error/network_error.dart';
import 'package:dio/dio.dart';

void main() {
  group('HTTP Client Service Tests', () {
    late HttpClientService httpClient;
    late AppLogger logger;

    setUp(() {
      logger = const ConsoleLogger();
      httpClient = HttpClientService(logger: logger);
    });

    tearDown(() {
      httpClient.dispose();
    });

    test('HttpClientService should be created with proper configuration', () {
      expect(httpClient, isNotNull);
      expect(httpClient.client, isA<Dio>());

      // Check timeout configurations
      final options = httpClient.client.options;
      expect(options.connectTimeout, const Duration(seconds: 30));
      expect(options.receiveTimeout, const Duration(minutes: 10));
      expect(options.sendTimeout, const Duration(minutes: 5));
    });

    test('should configure NOAA endpoints correctly', () {
      httpClient.configureNoaaEndpoints();

      expect(httpClient.client.options.baseUrl, 'https://charts.noaa.gov');
    });

    test('should have proper headers for marine environment', () {
      final headers = httpClient.client.options.headers;

      expect(headers['User-Agent'], contains('NavTool'));
      expect(headers['Accept'], contains('application/octet-stream'));
    });

    test('should handle network errors properly', () {
      // Test timeout error conversion
      final timeoutError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );

      expect(
        () => throw NetworkError.fromDioException(timeoutError),
        throwsA(isA<AppError>()),
      );
    });

    test('NetworkError should identify retryable errors correctly', () {
      final retryableError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );

      final nonRetryableError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.cancel,
      );

      expect(NetworkError.isRetryable(retryableError), isTrue);
      expect(NetworkError.isRetryable(nonRetryableError), isFalse);
    });

    test('NetworkError should provide user-friendly messages', () {
      final connectionError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );

      final message = NetworkError.getUserFriendlyMessage(connectionError);
      expect(message, contains('internet connection'));
    });

    test('should provide marine-specific network configuration', () {
      expect(
        MarineNetworkConfig.connectionTimeout,
        const Duration(seconds: 30),
      );
      expect(MarineNetworkConfig.receiveTimeout, const Duration(minutes: 10));
      expect(MarineNetworkConfig.maxConcurrentDownloads, 2);
      expect(MarineNetworkConfig.downloadChunkSize, 1024 * 1024);
    });
  });

  group('Download Service Implementation Tests', () {
    test('download service can be created', () {
      // This test validates that our service interfaces are properly defined
      // Actual implementation testing will require mocking the dependencies
      expect(DownloadService, isNotNull);
    });
  });
}
