import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/priority_rate_limiter.dart';

void main() {
  group('PriorityRateLimiter Tests', () {
    group('Basic Functionality', () {
      test('should create priority rate limiter successfully', () {
        // Arrange & Act
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 5);

        // Assert
        expect(rateLimiter, isNotNull);
        expect(rateLimiter.requestsPerSecond, 5);
      });

      test('should handle priority requests', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);

        // Act & Assert - should complete without error
        await rateLimiter.acquireWithPriority(RequestPriority.critical);
        await rateLimiter.acquireWithPriority(RequestPriority.high);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);

        final status = rateLimiter.getPriorityStatus();
        expect(status.totalRequestsInWindow, 3);
      });
    });

    group('Priority Status and Metrics', () {
      test('should provide priority status information', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);

        // Act
        await rateLimiter.acquireWithPriority(RequestPriority.critical);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);

        final status = rateLimiter.getPriorityStatus();

        // Assert
        expect(status.criticalRequestsInWindow, 1);
        expect(status.normalRequestsInWindow, 1);
        expect(status.totalRequestsInWindow, 2);
      });

      test('should provide queue status information', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);

        // Act
        final queueStatus = rateLimiter.getQueueStatus();

        // Assert - verify queue status API works
        expect(queueStatus.totalQueueLength, 0);
        expect(queueStatus.criticalQueueLength, 0);
        expect(queueStatus.highQueueLength, 0);
        expect(queueStatus.normalQueueLength, 0);
        expect(queueStatus.lowQueueLength, 0);
      });
    });

    group('Capacity Reservation', () {
      test('should reserve capacity for specific priorities', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 5);

        // Act & Assert
        expect(
          () => rateLimiter.reserveCapacity(RequestPriority.critical, 2),
          returnsNormally,
        );
        expect(
          () => rateLimiter.reserveCapacity(RequestPriority.high, 1),
          returnsNormally,
        );
      });

      test('should calculate available capacity correctly', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 4);

        // Act
        rateLimiter.reserveCapacity(RequestPriority.high, 2);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        await rateLimiter.acquireWithPriority(RequestPriority.high);

        // Assert - capacity should be reduced appropriately
        expect(rateLimiter.getAvailableCapacity(RequestPriority.normal), 0);
        expect(rateLimiter.getAvailableCapacity(RequestPriority.high), 2);
      });

      test('should handle capacity reservation edge cases', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);

        // Act & Assert
        expect(
          () => rateLimiter.reserveCapacity(RequestPriority.high, 0),
          returnsNormally,
        );
        expect(
          () => rateLimiter.reserveCapacity(RequestPriority.high, -1),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Integration', () {
      test('should work with base rate limiter functionality', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 2);

        // Act
        await rateLimiter.acquire(); // Use base method
        await rateLimiter.acquireWithPriority(
          RequestPriority.critical,
        ); // Use priority method

        // Assert
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, 2);
        expect(rateLimiter.canMakeRequest(), false); // Should be at capacity
      });

      test('should handle mixed request types and priorities', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        final results = <String>[];

        // Act - mix of priority and regular requests
        final futures = [
          rateLimiter
              .acquireWithPriority(RequestPriority.critical)
              .then((_) => results.add('critical')),
          rateLimiter.acquire().then((_) => results.add('regular')),
          rateLimiter
              .acquireWithPriority(RequestPriority.low)
              .then((_) => results.add('low')),
        ];

        await Future.wait(futures);

        // Assert - all requests should complete
        expect(results.length, 3);
        expect(results.contains('critical'), true);
        expect(results.contains('regular'), true);
        expect(results.contains('low'), true);
      });
    });
  });
}
