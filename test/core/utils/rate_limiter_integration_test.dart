import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/monitoring/rate_limit_metrics.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

void main() {
  group('Rate Limiter Integration Tests', () {
    test('should integrate with HTTP client service for NOAA requests', () async {
      // Arrange
      final logger = ConsoleLogger();
      final httpClient = HttpClientService(logger: logger);
      final rateLimiter = RateLimiter(requestsPerSecond: 5); // NOAA recommended limit
      final metrics = RateLimitMetrics();
      
      // Configure for NOAA
      httpClient.configureNoaaEndpoints();
      
      // Act - simulate multiple requests with rate limiting
      final requests = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        requests.add(_makeRateLimitedRequest(rateLimiter, metrics, i));
      }
      
      await Future.wait(requests);
      
      // Assert
      expect(metrics.totalRequests, 10);
      expect(metrics.rejectedRequests, 0); // All should be accepted but rate limited
      expect(metrics.successRate, 1.0);
      
      // Should take time due to rate limiting
      expect(metrics.averageWaitTime.inMilliseconds, greaterThan(0));
      
      final report = metrics.generateReport();
      expect(report.totalRequests, 10);
      expect(report.successRate, 1.0);
    });

    test('should demonstrate rate limiting preventing server overload', () async {
      // Arrange
      final rateLimiter = RateLimiter(requestsPerSecond: 2);
      final metrics = RateLimitMetrics();
      final startTime = DateTime.now();
      
      // Act - make requests that would overload without rate limiting
      final requests = <Future<void>>[];
      for (int i = 0; i < 6; i++) {
        requests.add(_makeRateLimitedRequest(rateLimiter, metrics, i));
      }
      
      await Future.wait(requests);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      // Assert - should take at least 2 seconds for 6 requests at 2 req/sec
      expect(duration.inSeconds, greaterThanOrEqualTo(2));
      expect(metrics.totalRequests, 6);
      expect(metrics.rejectedRequests, 0);
    });

    test('should handle burst traffic gracefully', () async {
      // Arrange
      final rateLimiter = RateLimiter(requestsPerSecond: 3);
      final metrics = RateLimitMetrics();
      
      // Act - simulate burst of requests
      final burstRequests = <Future<void>>[];
      for (int i = 0; i < 3; i++) {
        burstRequests.add(_makeRateLimitedRequest(rateLimiter, metrics, i));
      }
      
      // Wait for burst to complete
      await Future.wait(burstRequests);
      
      // Make additional requests after burst
      final additionalRequests = <Future<void>>[];
      for (int i = 3; i < 6; i++) {
        additionalRequests.add(_makeRateLimitedRequest(rateLimiter, metrics, i));
      }
      
      await Future.wait(additionalRequests);
      
      // Assert
      expect(metrics.totalRequests, 6);
      expect(metrics.rejectedRequests, 0);
      expect(metrics.successRate, 1.0);
    });
  });
}

/// Simulates making a rate-limited request
Future<void> _makeRateLimitedRequest(
  RateLimiter rateLimiter, 
  RateLimitMetrics metrics, 
  int requestId,
) async {
  try {
    // Check if we can make request
    if (!rateLimiter.canMakeRequest()) {
      final waitTime = rateLimiter.getWaitTime();
      metrics.recordWaitTime(waitTime);
    }
    
    // Acquire rate limiting permission
    await rateLimiter.acquire();
    
    // Record successful request
    metrics.recordRequest(accepted: true);
    
    // Simulate actual HTTP request work
    await Future.delayed(const Duration(milliseconds: 10));
    
  } catch (e) {
    // Record failed request
    metrics.recordRequest(accepted: false);
  }
}