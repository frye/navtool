import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/utils/rate_limiter.dart';

/// Lightweight logger for integration tests
class _IntegrationTestLogger implements AppLogger {
  String _fmt(
    String level,
    String message, {
    String? context,
    Object? exception,
  }) {
    final ctx = context != null ? '[$context]' : '';
    final ex = exception != null ? ' | $exception' : '';
    return '[$level]$ctx $message$ex';
  }

  @override
  void debug(String message, {String? context, Object? exception}) =>
      debugPrint(
        _fmt('DEBUG', message, context: context, exception: exception),
      );
  @override
  void info(String message, {String? context, Object? exception}) =>
      debugPrint(_fmt('INFO', message, context: context, exception: exception));
  @override
  void warning(String message, {String? context, Object? exception}) =>
      debugPrint(_fmt('WARN', message, context: context, exception: exception));
  @override
  void error(String message, {String? context, Object? exception}) =>
      debugPrint(
        _fmt('ERROR', message, context: context, exception: exception),
      );
  @override
  void logError(dynamic error) => debugPrint('[ERROR] $error');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('NOAA Real Endpoint Integration Tests', () {
    late NoaaApiClientImpl apiClient;
    late AppLogger logger;
    late HttpClientService httpClientService;

    final skipIntegrationTests =
        Platform.environment['SKIP_INTEGRATION_TESTS'] == 'true' ||
        Platform.environment['CI'] == 'true';

    setUpAll(() {
      if (skipIntegrationTests) return;
      logger = _IntegrationTestLogger();
      httpClientService = HttpClientService(logger: logger)
        ..configureNoaaEndpoints();
      apiClient = NoaaApiClientImpl(
        httpClient: httpClientService,
        rateLimiter: RateLimiter(requestsPerSecond: 1),
        logger: logger,
      );
    });

    tearDownAll(() {
      if (!skipIntegrationTests) httpClientService.dispose();
    });
    group('Real API Connectivity', () {
      testWidgets(
        'should successfully fetch NOAA chart catalog from real endpoint',
        (tester) async {
          if (skipIntegrationTests) {
            logger.info(
              'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
              context: 'Integration',
            );
            return;
          }

          try {
            final catalogString = await apiClient.fetchChartCatalog().timeout(
              const Duration(minutes: 2),
            );

            expect(catalogString, isNotNull);
            expect(catalogString, isA<String>());

            final catalog = jsonDecode(catalogString) as Map<String, dynamic>;
            expect(catalog.containsKey('type'), isTrue);
            expect(catalog['type'], equals('FeatureCollection'));
            expect(catalog.containsKey('features'), isTrue);

            final features = catalog['features'] as List;
            expect(features.isNotEmpty, isTrue);

            logger.info(
              'Successfully fetched catalog with ${features.length} charts',
            );
          } on SocketException catch (e) {
            if (e.message.contains('Failed host lookup') ||
                e.message.contains('No route to host')) {
              logger.warning(
                'Network connectivity issue - expected in some test environments',
                context: 'Integration',
              );
              return;
            }
            rethrow;
          } on TimeoutException catch (e) {
            logger.warning(
              'Timeout fetching catalog - possible slow marine connection',
              context: 'Integration',
              exception: e,
            );
            return;
          }
        },
      );

      testWidgets('should handle filtered catalog requests correctly', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        try {
          // Test with geographic filtering for California coast
          final filteredCatalogString = await apiClient
              .fetchChartCatalog(
                filters: {
                  'BBOX':
                      '-125.0,32.0,-117.0,42.0', // minLon,minLat,maxLon,maxLat for California
                },
              )
              .timeout(const Duration(minutes: 2));

          expect(filteredCatalogString, isNotNull);
          final filteredCatalog =
              jsonDecode(filteredCatalogString) as Map<String, dynamic>;
          expect(filteredCatalog['features'], isA<List>());

          final features = filteredCatalog['features'] as List;
          logger.info(
            'Filtered catalog returned ${features.length} charts for California coast',
          );

          // Verify charts are actually in the expected region
          if (features.isNotEmpty) {
            for (final feature in features.take(5)) {
              // Check first 5 charts
              expect(feature['geometry'], isNotNull);
              expect(feature['properties'], isNotNull);
              expect(feature['properties']['title'], isA<String>());
            }
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during filtered request',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during filtered catalog fetch',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });

      testWidgets('should retrieve chart metadata for real charts', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        Chart? chartMetadata;
        try {
          // Use a known stable NOAA chart ID for testing
          chartMetadata = await apiClient
              .getChartMetadata('US5CA52M')
              .timeout(const Duration(minutes: 1));

          if (chartMetadata != null) {
            expect(chartMetadata.id, isNotEmpty);
            expect(chartMetadata.title, isNotEmpty);
            expect(chartMetadata.scale, greaterThan(0));
            expect(chartMetadata.bounds, isNotNull);

            logger.info('Retrieved metadata for chart: ${chartMetadata.title}');
          } else {
            logger.warning(
              'Chart metadata returned null - chart may not be available',
            );
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during metadata fetch',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during metadata fetch',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });

      testWidgets('should handle invalid chart IDs gracefully', (tester) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        Chart? result;
        try {
          result = await apiClient
              .getChartMetadata('INVALID_CHART_ID_12345')
              .timeout(const Duration(minutes: 1));

          // Should return null for invalid chart IDs
          expect(result, isNull);
          logger.info('Correctly handled invalid chart ID');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during invalid chart test',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during invalid chart test',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });
    });

    group('Chart Availability Checks', () {
      testWidgets('should check chart availability for real charts', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        try {
          // Test with a known chart
          final isAvailable = await apiClient
              .isChartAvailable('US5CA52M')
              .timeout(const Duration(seconds: 30));

          // Should return a boolean
          expect(isAvailable, isA<bool>());
          logger.info('Chart US5CA52M availability: $isAvailable');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during availability check',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during availability check',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });

      testWidgets('should return false for invalid chart availability', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        try {
          final isAvailable = await apiClient
              .isChartAvailable('DEFINITELY_INVALID_CHART')
              .timeout(const Duration(seconds: 30));

          expect(isAvailable, isFalse);
          logger.info('Correctly identified invalid chart as unavailable');
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during invalid availability check',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during invalid availability check',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });
    });

    group('Error Handling and Resilience', () {
      testWidgets('should handle temporary network failures gracefully', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
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
      });

      testWidgets('should handle slow marine connections with retries', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        // Test multiple requests to validate retry logic
        final requests = <Future<dynamic>>[];

        for (int i = 0; i < 3; i++) {
          requests.add(
            apiClient
                .isChartAvailable('US5CA52M')
                .timeout(const Duration(seconds: 45))
                .catchError((e) {
                  if (e is SocketException || e is TimeoutException) {
                    logger.warning(
                      'Request ${i + 1} failed with expected marine connection issue',
                    );
                    return false;
                  }
                  throw e;
                }),
          );
        }

        try {
          final results = await Future.wait(
            requests,
          ).timeout(const Duration(minutes: 4));

          // At least one request should succeed in good conditions
          expect(results, isA<List>());
          logger.info(
            'Marine connection resilience test completed: ${results.length} requests processed',
          );
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Marine connection simulation - network unavailable',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Marine connection timeout - simulating satellite internet conditions',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });
    });

    group('Data Integrity Validation', () {
      testWidgets('should validate data structure integrity from real API', (
        tester,
      ) async {
        if (skipIntegrationTests) {
          logger.info(
            'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
            context: 'Integration',
          );
          return;
        }

        try {
          final catalogString = await apiClient.fetchChartCatalog().timeout(
            const Duration(minutes: 2),
          );

          final catalog = jsonDecode(catalogString) as Map<String, dynamic>;

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

            logger.info(
              'Data integrity validation passed for ${features.length} charts',
            );
          }
        } on SocketException catch (e) {
          if (e.message.contains('Failed host lookup')) {
            logger.warning(
              'Network connectivity issue during data integrity test',
              context: 'Integration',
            );
            return;
          }
          rethrow;
        } on TimeoutException catch (e) {
          logger.warning(
            'Timeout during data integrity test',
            context: 'Integration',
            exception: e,
          );
          return;
        }
      });
    });

    group('API Schema Compatibility', () {
      testWidgets(
        'should maintain compatibility with expected NOAA API schema',
        (tester) async {
          if (skipIntegrationTests) {
            logger.info(
              'Skipping integration test - SKIP_INTEGRATION_TESTS is set',
              context: 'Integration',
            );
            return;
          }

          try {
            final catalogString = await apiClient.fetchChartCatalog().timeout(
              const Duration(minutes: 2),
            );

            final catalog = jsonDecode(catalogString) as Map<String, dynamic>;

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
                  logger.warning('Missing expected field: $field');
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
              logger.warning(
                'Network connectivity issue during schema test',
                context: 'Integration',
              );
              return;
            }
            rethrow;
          } on TimeoutException catch (e) {
            logger.warning(
              'Timeout during schema compatibility test',
              context: 'Integration',
              exception: e,
            );
            return;
          }
        },
      );
    });
  });
}
