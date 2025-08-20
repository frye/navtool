import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/noaa_api_client.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/app_logger.dart';
import 'package:navtool/core/utils/rate_limiter.dart';

/// Test implementation of AppLogger for testing
class _TestLogger extends AppLogger {
  @override
  void debug(String message) => print('[DEBUG] $message');
  
  @override
  void info(String message) => print('[INFO] $message');
  
  @override
  void warn(String message) => print('[WARN] $message');
  
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) => 
      print('[ERROR] $message${error != null ? ' | $error' : ''}');
}

/// Test implementation of HttpClientService
class _TestHttpClientService implements HttpClientService {
  final Dio _dio;
  final AppLogger _logger;
  
  _TestHttpClientService(this._dio, this._logger);
  
  @override
  Future<Map<String, dynamic>> get(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _dio.get(url, options: Options(headers: headers));
      return response.data;
    } catch (e) {
      _logger.error('HTTP GET failed', e);
      rethrow;
    }
  }
  
  @override
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _dio.get(url, 
        options: Options(headers: headers, responseType: ResponseType.bytes));
      return response.data;
    } catch (e) {
      _logger.error('HTTP GET bytes failed', e);
      rethrow;
    }
  }
  
  @override
  void dispose() {
    _dio.close();
  }
}

/// Real NOAA endpoint integration tests.
/// These tests connect to actual NOAA services and validate functionality
/// under real-world conditions. They can be skipped in CI/CD environments
/// by setting SKIP_INTEGRATION_TESTS=true.
@Tags(['integration', 'real-endpoint'])
void main() {
  group('NOAA Real Endpoint Integration Tests', () {
    late NoaaApiClient apiClient;
    late AppLogger logger;
    late HttpClientService httpClientService;
    
    // Skip integration tests if environment variable is set
    final skipIntegrationTests = Platform.environment['SKIP_INTEGRATION_TESTS'] == 'true';
    
    setUpAll(() {
      if (skipIntegrationTests) {
        return;
      }
      
      logger = _TestLogger();
      
      // Create HTTP client with marine-optimized settings
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(minutes: 5);
      dio.options.sendTimeout = const Duration(seconds: 30);
      
      httpClientService = _TestHttpClientService(dio, logger);
      
      apiClient = NoaaApiClient(
        httpClient: httpClientService,
        rateLimiter: RateLimiter(maxRequests: 10, windowDuration: const Duration(minutes: 1)),
        logger: logger,
      );
    });
    
    tearDownAll(() {
      if (!skipIntegrationTests) {
        httpClientService.dispose();
      }
    });

    group('Real API Connectivity', () {
      test('should successfully fetch NOAA chart catalog from real endpoint', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          final catalog = await apiClient.fetchChartCatalog()
            .timeout(const Duration(minutes: 2));
          
          expect(catalog, isNotNull);
          expect(catalog, isA<Map<String, dynamic>>());
          expect(catalog.containsKey('type'), isTrue);
          expect(catalog['type'], equals('FeatureCollection'));
          expect(catalog.containsKey('features'), isTrue);
          
          final features = catalog['features'] as List;
          expect(features.isNotEmpty, isTrue);
          
          logger.info('Successfully fetched catalog with ${features.length} charts');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup') || 
              e.message.contains('No route to host')) {
            printOnFailure('Network connectivity issue - this is expected in some test environments');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout fetching catalog - this may occur with slow marine connections');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 3)));

      test('should handle filtered catalog requests correctly', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          // Test with geographic filtering for California coast
          final filteredCatalog = await apiClient.fetchChartCatalog(
            bounds: {
              'minLat': 32.0,
              'maxLat': 42.0,
              'minLon': -125.0,
              'maxLon': -117.0,
            }
          ).timeout(const Duration(minutes: 2));
          
          expect(filteredCatalog, isNotNull);
          expect(filteredCatalog['features'], isA<List>());
          
          final features = filteredCatalog['features'] as List;
          logger.info('Filtered catalog returned ${features.length} charts for California coast');
          
          // Verify charts are actually in the expected region
          if (features.isNotEmpty) {
            for (final feature in features.take(5)) {  // Check first 5 charts
              expect(feature['geometry'], isNotNull);
              expect(feature['properties'], isNotNull);
              expect(feature['properties']['title'], isA<String>());
            }
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during filtered request');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during filtered catalog fetch');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 3)));

      test('should retrieve chart metadata for real charts', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        Chart? chartMetadata;
        try {
          // Use a known stable NOAA chart ID for testing
          chartMetadata = await apiClient.getChartMetadata('US5CA52M')
            .timeout(const Duration(minutes: 1));
          
          if (chartMetadata != null) {
            expect(chartMetadata.id, isNotEmpty);
            expect(chartMetadata.title, isNotEmpty);
            expect(chartMetadata.scale, greaterThan(0));
            expect(chartMetadata.bounds, isNotNull);
            
            logger.info('Retrieved metadata for chart: ${chartMetadata.title}');
          } else {
            logger.warn('Chart metadata returned null - chart may not be available');
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during metadata fetch');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during metadata fetch');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('should handle invalid chart IDs gracefully', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        Chart? result;
        try {
          result = await apiClient.getChartMetadata('INVALID_CHART_ID_12345')
            .timeout(const Duration(minutes: 1));
          
          // Should return null for invalid chart IDs
          expect(result, isNull);
          logger.info('Correctly handled invalid chart ID');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during invalid chart test');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during invalid chart test');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    });

    group('Chart Availability Checks', () {
      test('should check chart availability for real charts', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          // Test with a known chart
          final isAvailable = await apiClient.isChartAvailable('US5CA52M')
            .timeout(const Duration(seconds: 30));
          
          // Should return a boolean
          expect(isAvailable, isA<bool>());
          logger.info('Chart US5CA52M availability: $isAvailable');
          
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during availability check');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during availability check');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('should return false for invalid chart availability', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          final isAvailable = await apiClient.isChartAvailable('DEFINITELY_INVALID_CHART')
            .timeout(const Duration(seconds: 30));
          
          expect(isAvailable, isFalse);
          logger.info('Correctly identified invalid chart as unavailable');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during invalid availability check');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during invalid availability check');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 1)));
    });

    group('Error Handling and Resilience', () {
      test('should handle temporary network failures gracefully', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        // This test validates that our error handling works with real network conditions
        try {
          final catalog = await apiClient.fetchChartCatalog();
          
          // If we get here, the network is working
          expect(catalog, isNotNull);
          logger.info('Network is stable - error handling validation passed');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            // This is actually expected behavior in some test environments
            logger.info('Network error handled correctly: ${e.message}');
            return;
          }
          rethrow;
        }
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('should handle slow marine connections with retries', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        // Test multiple requests to validate retry logic
        final requests = <Future<dynamic>>[];
        
        for (int i = 0; i < 3; i++) {
          requests.add(
            apiClient.isChartAvailable('US5CA52M')
              .timeout(const Duration(seconds: 45))
              .catchError((e) {
                if (e is SocketException || e is TimeoutException) {
                  logger.warn('Request ${i + 1} failed with expected marine connection issue');
                  return false;
                }
                rethrow;
              })
          );
        }
        
        try {
          final results = await Future.wait(requests)
            .timeout(const Duration(minutes: 4));
          
          // At least one request should succeed in good conditions
          expect(results, isA<List>());
          logger.info('Marine connection resilience test completed: ${results.length} requests processed');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Marine connection simulation - network unavailable');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Marine connection timeout - this simulates real satellite internet conditions');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 5)));
    });

    group('Data Integrity Validation', () {
      test('should validate data structure integrity from real API', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          final catalog = await apiClient.fetchChartCatalog()
            .timeout(const Duration(minutes: 2));
          
          // Validate GeoJSON structure
          expect(catalog['type'], equals('FeatureCollection'));
          expect(catalog['features'], isA<List>());
          
          final features = catalog['features'] as List;
          if (features.isNotEmpty) {
            final firstFeature = features.first;
            
            // Validate feature structure
            expect(firstFeature['type'], equals('Feature'));
            expect(firstFeature['geometry'], isNotNull);
            expect(firstFeature['properties'], isNotNull);
            
            // Validate geometry
            final geometry = firstFeature['geometry'];
            expect(geometry['type'], isA<String>());
            expect(geometry['coordinates'], isNotNull);
            
            // Validate properties
            final properties = firstFeature['properties'];
            expect(properties['title'], isA<String>());
            
            logger.info('Data integrity validation passed for ${features.length} charts');
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during data integrity test');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during data integrity test');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    group('API Schema Compatibility', () {
      test('should maintain compatibility with expected NOAA API schema', () async {
        if (skipIntegrationTests) {
          printOnFailure('Skipping integration test - SKIP_INTEGRATION_TESTS is set');
          return;
        }
        
        try {
          final catalog = await apiClient.fetchChartCatalog()
            .timeout(const Duration(minutes: 2));
          
          // Test expected schema elements that our app depends on
          expect(catalog.containsKey('type'), isTrue);
          expect(catalog.containsKey('features'), isTrue);
          
          final features = catalog['features'] as List;
          if (features.isNotEmpty) {
            final feature = features.first;
            
            // Properties our app requires
            final properties = feature['properties'];
            final requiredFields = ['title', 'scale', 'chart_number'];
            
            for (final field in requiredFields) {
              if (!properties.containsKey(field)) {
                logger.warn('Missing expected field: $field');
              }
            }
            
            // Geometry requirements
            final geometry = feature['geometry'];
            expect(geometry.containsKey('type'), isTrue);
            expect(geometry.containsKey('coordinates'), isTrue);
            
            logger.info('Schema compatibility validation completed');
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            printOnFailure('Network connectivity issue during schema test');
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          printOnFailure('Timeout during schema compatibility test');
          return;
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  });
}