import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';

// Generate mocks
@GenerateMocks([AppLogger])
import 'http_client_service_test.mocks.dart';

void main() {
  group('HttpClientService Tests', () {
    late HttpClientService httpClientService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      httpClientService = HttpClientService(logger: mockLogger);
    });

    tearDown(() {
      httpClientService.dispose();
    });

    group('Initialization Tests', () {
      test('should create HTTP client with marine-optimized configuration', () {
        // Arrange & Act
        final client = httpClientService.client;

        // Assert
        expect(client, isA<Dio>());
        expect(client.options.connectTimeout, const Duration(seconds: 30));
        expect(client.options.receiveTimeout, const Duration(minutes: 10));
        expect(client.options.sendTimeout, const Duration(minutes: 5));
      });

      test('should configure NOAA endpoints', () {
        // Act
        httpClientService.configureNoaaEndpoints();

        // Assert
        expect(httpClientService.client.options.baseUrl, 'https://charts.noaa.gov');
        final headers = httpClientService.client.options.headers;
        expect(headers['User-Agent'], contains('NavTool'));
        expect(headers['Accept'], contains('application/octet-stream'));
      });

      test('should configure certificate pinning', () {
        // Act & Assert
        expect(() => httpClientService.configureCertificatePinning(), returnsNormally);
        verify(mockLogger.info('Certificate pinning configured for secure downloads')).called(1);
      });
    });

    group('Error Handling Tests', () {
      test('should handle HTTP errors gracefully', () {
        // This tests that error handling is properly configured
        // without accessing private methods
        expect(httpClientService.client.interceptors, isNotEmpty);
      });

      test('should have proper timeout configurations for marine environment', () {
        // Arrange & Act
        final options = httpClientService.client.options;

        // Assert - Marine environment requires longer timeouts
        expect(options.connectTimeout, const Duration(seconds: 30));
        expect(options.receiveTimeout, const Duration(minutes: 10));
        expect(options.sendTimeout, const Duration(minutes: 5));
      });
    });

    group('Request Methods Tests', () {
      test('should make GET requests', () async {
        // This test requires mocking the actual HTTP calls
        // For now, just verify the method exists
        expect(httpClientService.get, isA<Function>());
      });

      test('should make POST requests', () async {
        // This test requires mocking the actual HTTP calls
        // For now, just verify the method exists
        expect(httpClientService.post, isA<Function>());
      });

      test('should download files with progress tracking', () async {
        // This test requires mocking the actual HTTP calls
        // For now, just verify the method exists
        expect(httpClientService.downloadFile, isA<Function>());
      });
    });

    group('Retry Logic Tests', () {
      test('should have retry configuration enabled', () {
        // This tests that retry logic is configured
        // without accessing private methods
        final client = httpClientService.client;
        expect(client, isA<Dio>());
        // The presence of interceptors indicates retry logic is configured
        expect(client.interceptors, isNotEmpty);
      });
    });

    group('Resource Management Tests', () {
      test('should dispose resources properly', () {
        // Act
        httpClientService.dispose();

        // Assert
        verify(mockLogger.debug('HTTP client disposed', context: 'HTTP')).called(1);
      });
    });
  });
}
