import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/services/noaa/noaa_api_client_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/utils/rate_limiter.dart';

/// Test implementation of AppLogger for testing
class _TestLogger implements AppLogger {
  @override
  void debug(String message, {String? context, Object? exception}) => print('[DEBUG] $message');
  
  @override
  void info(String message, {String? context, Object? exception}) => print('[INFO] $message');
  
  @override
  void warning(String message, {String? context, Object? exception}) => print('[WARN] $message');
  
  @override
  void error(String message, {String? context, Object? exception}) => 
      print('[ERROR] $message${exception != null ? ' | $exception' : ''}');
      
  @override
  void logError(dynamic error) => print('[ERROR] $error');
}

/// Test implementation of HttpClientService
class _TestHttpClientService implements HttpClientService {
  final Dio _dio;
  final AppLogger _logger;
  
  _TestHttpClientService(this._dio, this._logger);

  @override
  Dio get client => _dio;

  @override
  Future<Response> get(String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get(url, 
        queryParameters: queryParameters, 
        options: options,
        cancelToken: cancelToken
      );
    } catch (e) {
      _logger.error('HTTP GET failed', exception: e);
      rethrow;
    }
  }

  @override
  Future<Response> post(String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post(url, 
        data: data,
        queryParameters: queryParameters, 
        options: options,
        cancelToken: cancelToken
      );
    } catch (e) {
      _logger.error('HTTP POST failed', exception: e);
      rethrow;
    }
  }

  @override
  Future<void> downloadFile(String url, String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    int? resumeFrom,
  }) async {
    try {
      await _dio.download(url, savePath, 
        cancelToken: cancelToken, 
        onReceiveProgress: onReceiveProgress,
        queryParameters: queryParameters
      );
    } catch (e) {
      _logger.error('File download failed', exception: e);
      rethrow;
    }
  }

  @override
  void configureNoaaEndpoints() {
    // Test implementation - no-op
  }

  @override
  void configureCertificatePinning() {
    // Test implementation - no-op
  }

  @override
  void dispose() {
    _dio.close();
  }
}

/// DEPRECATED: Real NOAA endpoint integration tests.
/// 
/// These tests have been moved to integration_test/noaa_real_endpoint_test.dart
/// which uses IntegrationTestWidgetsFlutterBinding to allow real network requests.
/// 
/// This file is kept temporarily for backward compatibility but will be removed.
/// All tests here are skipped and redirect to the new implementation.
/// 
/// For fast mock-based development testing, see:
/// test/core/services/noaa_api_client_mock_test.dart
/// 
/// For real network integration testing, see:
/// integration_test/noaa_real_endpoint_test.dart
@Tags(['deprecated', 'skip'])
void main() {
  group('DEPRECATED: NOAA Real Endpoint Integration Tests', () {
    test('Tests moved to integration_test directory', () {
      printOnFailure('DEPRECATED: These tests have been moved to integration_test/noaa_real_endpoint_test.dart');
      printOnFailure('For mock-based unit tests, use test/core/services/noaa_api_client_mock_test.dart');
      printOnFailure('For real network integration tests, use integration_test/noaa_real_endpoint_test.dart');
      
      // This test always passes to indicate the migration is complete
      expect(true, isTrue, reason: 'Tests successfully migrated to new structure');
    });
  });
}