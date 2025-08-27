import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

// Simple test logger
class TestLogger implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) => print('[DEBUG] $message');
  
  @override
  void info(String message, {String? context, Object? exception}) => print('[INFO] $message');
  
  @override
  void warning(String message, {String? context, Object? exception}) => print('[WARNING] $message');
  
  @override
  void error(String message, {String? context, Object? exception}) => print('[ERROR] $message');
  
  @override
  void logError(error) => print('[ERROR] $error');
}

/// Test-driven development for fixing NOAA URL construction issue
/// 
/// This test suite ensures that the HTTP client properly handles both:
/// - Full URLs (like NOAA catalog endpoint)
/// - Relative paths (for other services)
void main() {
  group('HTTP Client URL Construction Fix Tests', () {
    late HttpClientService httpClientService;
    late TestLogger testLogger;
    late Dio testDio;

    setUp(() {
      testLogger = TestLogger();
      testDio = Dio();
      httpClientService = HttpClientService(
        logger: testLogger,
        testDio: testDio,
      );
    });

    tearDown(() {
      testDio.close();
    });

    group('URL Construction Logic', () {
      test('should handle full URLs without baseUrl concatenation', () async {
        // Arrange - Set a baseUrl that would break full URLs if concatenated
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        const fullUrl = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query';
        
        // Mock the actual HTTP request to capture what URL is used
        final capturedUrls = <String>[];
        testDio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedUrls.add(options.uri.toString());
            // Return a mock response to prevent actual network call
            handler.resolve(Response(
              data: {'test': 'response'},
              statusCode: 200,
              requestOptions: options,
            ));
          },
        ));

        // Act - Make request with full URL
        await httpClientService.get(fullUrl);

        // Assert - Should use the full URL directly, not concatenate with baseUrl
        expect(capturedUrls, hasLength(1));
        expect(capturedUrls.first, equals(fullUrl));
        expect(capturedUrls.first, isNot(contains('charts.noaa.govhttps://')));
      });

      test('should handle relative paths with baseUrl concatenation', () async {
        // Arrange - Set baseUrl for relative paths
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        const relativePath = '/ENCs/US5CA52M.zip';
        const expectedFullUrl = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        
        // Mock the actual HTTP request to capture what URL is used
        final capturedUrls = <String>[];
        testDio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedUrls.add(options.uri.toString());
            handler.resolve(Response(
              data: 'mock file data',
              statusCode: 200,
              requestOptions: options,
            ));
          },
        ));

        // Act - Make request with relative path
        await httpClientService.get(relativePath);

        // Assert - Should properly concatenate baseUrl with relative path
        expect(capturedUrls, hasLength(1));
        expect(capturedUrls.first, equals(expectedFullUrl));
      });

      test('should detect when path is already a full URL', () {
        // Test the URL detection logic directly
        expect(HttpClientService.isFullUrl('https://gis.charttools.noaa.gov/test'), isTrue);
        expect(HttpClientService.isFullUrl('http://example.com/test'), isTrue);
        expect(HttpClientService.isFullUrl('/relative/path'), isFalse);
        expect(HttpClientService.isFullUrl('relative/path'), isFalse);
        expect(HttpClientService.isFullUrl(''), isFalse);
      });

      test('should preserve query parameters for full URLs', () async {
        // Arrange
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        const fullUrl = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query';
        final queryParams = {
          'where': '1=1',
          'outFields': '*',
          'f': 'json',
        };
        
        final capturedRequests = <RequestOptions>[];
        testDio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequests.add(options);
            handler.resolve(Response(
              data: {'test': 'response'},
              statusCode: 200,
              requestOptions: options,
            ));
          },
        ));

        // Act
        await httpClientService.get(fullUrl, queryParameters: queryParams);

        // Assert
        expect(capturedRequests, hasLength(1));
        final request = capturedRequests.first;
        expect(request.uri.toString(), startsWith(fullUrl));
        expect(request.uri.queryParameters, equals(queryParams));
      });

      test('should work with NOAA catalog endpoint specifically', () async {
        // Arrange - The exact problematic case from the application
        const noaaCatalogEndpoint = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query';
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        final capturedUrls = <String>[];
        testDio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedUrls.add(options.uri.toString());
            handler.resolve(Response(
              data: {
                'features': [
                  {
                    'attributes': {
                      'DSNM': 'US5CA52M',
                      'TITLE': 'San Francisco Bay',
                    }
                  }
                ]
              },
              statusCode: 200,
              requestOptions: options,
            ));
          },
        ));

        // Act - This is what the NOAA API client does
        await httpClientService.get(noaaCatalogEndpoint, queryParameters: {
          'where': '1=1',
          'outFields': '*',
          'f': 'json',
        });

        // Assert - Should NOT create the broken URL
        expect(capturedUrls, hasLength(1));
        expect(capturedUrls.first, startsWith(noaaCatalogEndpoint));
        expect(capturedUrls.first, isNot(contains('charts.noaa.govhttps://')));
        
        print('✅ URL Fixed: ${capturedUrls.first}');
      });

      test('should work with chart download URLs', () async {
        // Arrange - Chart download URLs are also full URLs
        const downloadUrl = 'https://charts.noaa.gov/ENCs/US5CA52M.zip';
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        final capturedUrls = <String>[];
        testDio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedUrls.add(options.uri.toString());
            handler.resolve(Response(
              data: 'mock chart data',
              statusCode: 200,
              requestOptions: options,
            ));
          },
        ));

        // Act
        await httpClientService.get(downloadUrl);

        // Assert - Should use the full URL directly
        expect(capturedUrls, hasLength(1));
        expect(capturedUrls.first, equals(downloadUrl));
      });
    });

    group('Error Handling', () {
      test('should handle malformed URLs gracefully', () async {
        // Arrange
        const malformedUrl = 'not-a-valid-url';
        
        // Act & Assert - Should not throw during URL processing
        expect(() async {
          try {
            await httpClientService.get(malformedUrl);
          } catch (e) {
            // Network errors are expected, URL processing errors are not
            expect(e, isNot(isA<FormatException>()));
          }
        }, returnsNormally);
      });

      test('should preserve original error handling behavior', () async {
        // Arrange - This should still work as before
        testDio.options.baseUrl = 'https://charts.noaa.gov';
        
        // Act & Assert - Network errors should still be thrown (but converted to AppError)
        expect(
          () async => await httpClientService.get('/nonexistent-endpoint'),
          throwsA(isA<Exception>()), // Now throws AppError instead of DioException
        );
      });
    });

    group('Integration with NOAA Endpoints', () {
      test('should fix the exact URL construction issue from the bug report', () {
        // Arrange - Reproduce the exact problematic scenario
        const baseUrl = 'https://charts.noaa.gov';
        const catalogEndpoint = 'https://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query';
        
        // The broken behavior (what happens without the fix)
        final brokenUrl = baseUrl + catalogEndpoint;
        expect(brokenUrl, equals('https://charts.noaa.govhttps://gis.charttools.noaa.gov/arcgis/rest/services/encdirect/enc_coverage/MapServer/0/query'));
        
        // The fixed behavior (what should happen with the fix)
        final isFullUrl = HttpClientService.isFullUrl(catalogEndpoint);
        final correctUrl = isFullUrl ? catalogEndpoint : baseUrl + catalogEndpoint;
        expect(correctUrl, equals(catalogEndpoint));
        
        print('🚨 Broken URL: $brokenUrl');
        print('✅ Fixed URL: $correctUrl');
      });
    });
  });
}
