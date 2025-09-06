import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/monitoring/rate_limit_metrics.dart';
import 'package:navtool/core/utils/rate_limiter.dart';
import 'package:navtool/core/utils/priority_rate_limiter.dart';

void main() {
  group('RateLimitMetrics Tests', () {
    group('Basic Metrics Collection', () {
      test('should initialize with zero metrics', () {
        // Arrange & Act
        final metrics = RateLimitMetrics();

        // Assert
        expect(metrics.totalRequests, 0);
        expect(metrics.rejectedRequests, 0);
        expect(metrics.currentRequestRate, 0.0);
        expect(metrics.averageWaitTime, Duration.zero);
        expect(metrics.successRate, 1.0); // 100% when no requests yet
      });

      test('should track total and rejected requests', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act
        metrics.recordRequest(accepted: true);
        metrics.recordRequest(accepted: true);
        metrics.recordRequest(accepted: false);
        metrics.recordRequest(accepted: false);
        metrics.recordRequest(accepted: true);

        // Assert
        expect(metrics.totalRequests, 5);
        expect(metrics.rejectedRequests, 2);
        expect(metrics.acceptedRequests, 3);
        expect(metrics.successRate, 0.6); // 3/5 = 60%
      });

      test('should calculate request rate over time window', () async {
        // Arrange
        final metrics = RateLimitMetrics(
          measurementWindow: const Duration(milliseconds: 500),
        );

        // Act - record requests with timing
        metrics.recordRequest(accepted: true);
        await Future.delayed(const Duration(milliseconds: 100));
        metrics.recordRequest(accepted: true);
        await Future.delayed(const Duration(milliseconds: 100));
        metrics.recordRequest(accepted: true);

        // Assert - should calculate rate based on window
        final rate = metrics.currentRequestRate;
        expect(rate, greaterThan(0.0));
        expect(
          rate,
          lessThanOrEqualTo(6.0),
        ); // 3 requests in 0.5s = 6 req/s max
      });

      test('should track wait times and calculate averages', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act
        metrics.recordWaitTime(const Duration(milliseconds: 100));
        metrics.recordWaitTime(const Duration(milliseconds: 200));
        metrics.recordWaitTime(const Duration(milliseconds: 300));

        // Assert
        expect(metrics.averageWaitTime, const Duration(milliseconds: 200));
        expect(metrics.totalWaitTime, const Duration(milliseconds: 600));
        expect(metrics.waitTimeCount, 3);
      });
    });

    group('Time Window Management', () {
      test('should maintain sliding window for rate calculation', () async {
        // Arrange
        final metrics = RateLimitMetrics(
          measurementWindow: const Duration(milliseconds: 300),
        );

        // Act - record requests, then wait for window to slide
        metrics.recordRequest(accepted: true);
        metrics.recordRequest(accepted: true);

        await Future.delayed(const Duration(milliseconds: 400));

        metrics.recordRequest(accepted: true);

        // Assert - rate should only reflect requests in current window
        final rate = metrics.currentRequestRate;
        expect(rate, lessThan(4.0)); // Should not count old requests
      });

      test('should handle empty time windows', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act - don't record any requests

        // Assert
        expect(metrics.currentRequestRate, 0.0);
        expect(metrics.getRequestsInWindow(), 0);
      });

      test('should clean up old request timestamps', () async {
        // Arrange
        final metrics = RateLimitMetrics(
          measurementWindow: const Duration(milliseconds: 200),
        );

        // Act - record requests then wait for cleanup
        for (int i = 0; i < 10; i++) {
          metrics.recordRequest(accepted: true);
        }

        await Future.delayed(const Duration(milliseconds: 300));

        // Trigger cleanup by getting current rate
        final rate = metrics.currentRequestRate;

        // Assert - old timestamps should be cleaned up
        expect(rate, 0.0); // No requests in current window
        expect(metrics.getRequestsInWindow(), 0);
      });
    });

    group('Integration with RateLimiter', () {
      test('should track RateLimiter metrics accurately', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 2);
        final metrics = RateLimitMetrics();

        // Act - use rate limiter and track metrics
        if (rateLimiter.canMakeRequest()) {
          await rateLimiter.acquire();
          metrics.recordRequest(accepted: true);
        }

        if (rateLimiter.canMakeRequest()) {
          await rateLimiter.acquire();
          metrics.recordRequest(accepted: true);
        }

        // Try to make more requests (should be rejected)
        if (!rateLimiter.canMakeRequest()) {
          metrics.recordRequest(accepted: false);
          metrics.recordWaitTime(rateLimiter.getWaitTime());
        }

        // Assert
        expect(metrics.totalRequests, 3);
        expect(metrics.acceptedRequests, 2);
        expect(metrics.rejectedRequests, 1);
        expect(metrics.averageWaitTime.inMilliseconds, greaterThan(0));
      });

      test('should monitor rate limiter performance over time', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 3);
        final metrics = RateLimitMetrics();

        // Act - simulate burst of requests
        for (int i = 0; i < 10; i++) {
          if (rateLimiter.canMakeRequest()) {
            await rateLimiter.acquire();
            metrics.recordRequest(accepted: true);
          } else {
            metrics.recordRequest(accepted: false);
            metrics.recordWaitTime(rateLimiter.getWaitTime());
          }

          // Small delay between requests
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // Assert - should have mix of accepted and rejected
        expect(metrics.totalRequests, 10);
        expect(metrics.acceptedRequests, lessThan(10));
        expect(metrics.rejectedRequests, greaterThan(0));
        expect(metrics.successRate, lessThan(1.0));
      });
    });

    group('Priority Metrics', () {
      test('should track priority-specific metrics', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act
        metrics.recordPriorityRequest(RequestPriority.critical, accepted: true);
        metrics.recordPriorityRequest(RequestPriority.high, accepted: true);
        metrics.recordPriorityRequest(RequestPriority.normal, accepted: false);
        metrics.recordPriorityRequest(RequestPriority.low, accepted: false);

        // Assert
        expect(
          metrics.getPriorityMetrics(RequestPriority.critical).totalRequests,
          1,
        );
        expect(
          metrics.getPriorityMetrics(RequestPriority.critical).successRate,
          1.0,
        );
        expect(
          metrics.getPriorityMetrics(RequestPriority.normal).successRate,
          0.0,
        );
        expect(
          metrics.getPriorityMetrics(RequestPriority.low).totalRequests,
          1,
        );
      });

      test('should calculate priority-specific wait times', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act
        metrics.recordPriorityWaitTime(
          RequestPriority.critical,
          const Duration(milliseconds: 50),
        );
        metrics.recordPriorityWaitTime(
          RequestPriority.normal,
          const Duration(milliseconds: 200),
        );
        metrics.recordPriorityWaitTime(
          RequestPriority.normal,
          const Duration(milliseconds: 300),
        );

        // Assert
        expect(
          metrics.getPriorityMetrics(RequestPriority.critical).averageWaitTime,
          const Duration(milliseconds: 50),
        );
        expect(
          metrics.getPriorityMetrics(RequestPriority.normal).averageWaitTime,
          const Duration(milliseconds: 250),
        );
      });

      test('should aggregate priority metrics into overall metrics', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act
        metrics.recordPriorityRequest(RequestPriority.critical, accepted: true);
        metrics.recordPriorityRequest(RequestPriority.high, accepted: false);
        metrics.recordPriorityRequest(RequestPriority.normal, accepted: true);

        // Assert
        expect(metrics.totalRequests, 3);
        expect(metrics.acceptedRequests, 2);
        expect(metrics.rejectedRequests, 1);
        expect(metrics.successRate, closeTo(0.67, 0.01)); // 2/3
      });
    });

    group('Metrics Reporting and Export', () {
      test('should generate comprehensive metrics report', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act - record various metrics
        metrics.recordRequest(accepted: true);
        metrics.recordRequest(accepted: false);
        metrics.recordWaitTime(const Duration(milliseconds: 150));
        metrics.recordPriorityRequest(RequestPriority.critical, accepted: true);

        final report = metrics.generateReport();

        // Assert
        expect(report.totalRequests, 3); // 2 regular + 1 priority
        expect(report.successRate, closeTo(0.67, 0.01));
        expect(report.averageWaitTime, const Duration(milliseconds: 150));
        expect(report.containsKey('priorityBreakdown'), isTrue);
      });

      test('should export metrics as JSON', () {
        // Arrange
        final metrics = RateLimitMetrics();
        metrics.recordRequest(accepted: true);
        metrics.recordWaitTime(const Duration(milliseconds: 100));

        // Act
        final json = metrics.toJson();

        // Assert
        expect(json, isA<Map<String, dynamic>>());
        expect(json['totalRequests'], 1);
        expect(json['rejectedRequests'], 0);
        expect(json['averageWaitTimeMs'], 100);
        expect(json['successRate'], 1.0);
      });

      test('should reset metrics when requested', () {
        // Arrange
        final metrics = RateLimitMetrics();
        metrics.recordRequest(accepted: true);
        metrics.recordRequest(accepted: false);
        metrics.recordWaitTime(const Duration(milliseconds: 200));

        // Act
        metrics.reset();

        // Assert
        expect(metrics.totalRequests, 0);
        expect(metrics.rejectedRequests, 0);
        expect(metrics.averageWaitTime, Duration.zero);
        expect(metrics.successRate, 1.0);
      });
    });

    group('Performance and Memory', () {
      test('should handle large numbers of requests efficiently', () {
        // Arrange
        final metrics = RateLimitMetrics();

        // Act - record many requests
        for (int i = 0; i < 1000; i++) {
          metrics.recordRequest(accepted: i % 2 == 0);
          if (i % 10 == 0) {
            metrics.recordWaitTime(Duration(milliseconds: i % 100));
          }
        }

        // Assert - should complete without performance issues
        expect(metrics.totalRequests, 1000);
        expect(metrics.successRate, 0.5); // 50% acceptance rate
        expect(metrics.averageWaitTime.inMilliseconds, greaterThan(0));
      });

      test('should limit memory usage for timestamp tracking', () async {
        // Arrange
        final metrics = RateLimitMetrics(
          measurementWindow: const Duration(milliseconds: 100),
        );

        // Act - record many requests over time
        for (int i = 0; i < 100; i++) {
          metrics.recordRequest(accepted: true);
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // Assert - should not accumulate unlimited timestamps
        expect(
          metrics.getRequestsInWindow(),
          lessThan(20),
        ); // Only recent requests
      });
    });
  });
}
