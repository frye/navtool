import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/priority_rate_limiter.dart';

void main() {
  group('PriorityRateLimiter Tests', () {
    group('Construction and Basic Functionality', () {
      test('should create PriorityRateLimiter with default configuration', () {
        // Arrange & Act
        final rateLimiter = PriorityRateLimiter();
        
        // Assert
        expect(rateLimiter.requestsPerSecond, 5);
        expect(rateLimiter.windowSize, const Duration(seconds: 1));
      });

      test('should extend base RateLimiter functionality', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        
        // Act & Assert
        expect(rateLimiter.canMakeRequest(), isTrue);
        expect(rateLimiter.getWaitTime(), Duration.zero);
        expect(rateLimiter.getStatus(), isNotNull);
      });
    });

    group('Priority Request Handling', () {
      test('should handle critical priority requests first', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 1);
        final completionOrder = <RequestPriority>[];
        
        // Fill the rate limit
        await rateLimiter.acquire();
        
        // Act - queue requests with different priorities
        final futures = [
          rateLimiter.acquireWithPriority(RequestPriority.low).then((_) => 
              completionOrder.add(RequestPriority.low)),
          rateLimiter.acquireWithPriority(RequestPriority.critical).then((_) => 
              completionOrder.add(RequestPriority.critical)),
          rateLimiter.acquireWithPriority(RequestPriority.normal).then((_) => 
              completionOrder.add(RequestPriority.normal)),
          rateLimiter.acquireWithPriority(RequestPriority.high).then((_) => 
              completionOrder.add(RequestPriority.high)),
        ];
        
        await Future.wait(futures.cast<Future<void>>());
        
        // Assert - critical should complete first, then high, normal, low
        expect(completionOrder.first, RequestPriority.critical);
        expect(completionOrder.indexOf(RequestPriority.high), 
               lessThan(completionOrder.indexOf(RequestPriority.normal)));
        expect(completionOrder.indexOf(RequestPriority.normal), 
               lessThan(completionOrder.indexOf(RequestPriority.low)));
      });

      test('should process same priority requests in FIFO order', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 1);
        final completionOrder = <int>[];
        
        // Fill the rate limit
        await rateLimiter.acquire();
        
        // Act - queue multiple normal priority requests
        final futures = List.generate(3, (index) =>
          rateLimiter.acquireWithPriority(RequestPriority.normal).then((_) => 
              completionOrder.add(index))
        );
        
        await Future.wait(futures.cast<Future<void>>());
        
        // Assert - should complete in order: 0, 1, 2
        expect(completionOrder, [0, 1, 2]);
      });

      test('should handle mixed priority levels correctly', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 2);
        final results = <String>[];
        
        // Fill the rate limit
        await rateLimiter.acquire();
        await rateLimiter.acquire();
        
        // Act - queue requests with mixed priorities
        final futures = [
          rateLimiter.acquireWithPriority(RequestPriority.low).then((_) => 
              results.add('low1')),
          rateLimiter.acquireWithPriority(RequestPriority.high).then((_) => 
              results.add('high1')),
          rateLimiter.acquireWithPriority(RequestPriority.critical).then((_) => 
              results.add('critical1')),
          rateLimiter.acquireWithPriority(RequestPriority.normal).then((_) => 
              results.add('normal1')),
          rateLimiter.acquireWithPriority(RequestPriority.high).then((_) => 
              results.add('high2')),
        ];
        
        await Future.wait(futures.cast<Future<void>>());
        
        // Assert - should process in priority order
        expect(results.indexOf('critical1'), 0);
        expect(results.indexOf('high1'), lessThan(results.indexOf('normal1')));
        expect(results.indexOf('high2'), lessThan(results.indexOf('normal1')));
        expect(results.indexOf('normal1'), lessThan(results.indexOf('low1')));
      });
    });

    group('Capacity Reservation', () {
      test('should reserve capacity for critical requests', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        
        // Act - reserve capacity for critical requests
        rateLimiter.reserveCapacity(RequestPriority.critical, 2);
        
        // Fill remaining capacity with normal requests
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        // Assert - should reject additional normal requests but allow critical
        expect(rateLimiter.canMakeRequest(priority: RequestPriority.normal), isFalse);
        expect(rateLimiter.canMakeRequest(priority: RequestPriority.critical), isTrue);
      });

      test('should handle capacity reservation limits', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 5);
        
        // Act & Assert - should not allow over-reservation
        expect(
          () => rateLimiter.reserveCapacity(RequestPriority.critical, 6),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should update available capacity correctly', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 4);
        
        // Act - reserve capacity and make requests
        rateLimiter.reserveCapacity(RequestPriority.high, 2);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        await rateLimiter.acquireWithPriority(RequestPriority.high);
        
        // Assert - check remaining capacity
        expect(rateLimiter.getAvailableCapacity(RequestPriority.normal), 0);
        expect(rateLimiter.getAvailableCapacity(RequestPriority.high), 1);
        expect(rateLimiter.getAvailableCapacity(RequestPriority.critical), 1);
      });

      test('should release reserved capacity when window slides', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(
          requestsPerSecond: 2,
          windowSize: const Duration(milliseconds: 500),
        );
        
        // Act - reserve and use capacity
        rateLimiter.reserveCapacity(RequestPriority.critical, 1);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        // Wait for window to slide
        await Future.delayed(const Duration(milliseconds: 600));
        
        // Assert - should have full capacity available again
        expect(rateLimiter.getAvailableCapacity(RequestPriority.normal), 2);
        expect(rateLimiter.getAvailableCapacity(RequestPriority.critical), 2);
      });
    });

    group('Priority Status and Metrics', () {
      test('should provide priority-specific status information', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        
        // Act - make requests with different priorities
        await rateLimiter.acquireWithPriority(RequestPriority.critical);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        final status = rateLimiter.getPriorityStatus();
        
        // Assert
        expect(status.criticalRequestsInWindow, 1);
        expect(status.highRequestsInWindow, 0);
        expect(status.normalRequestsInWindow, 1);
        expect(status.lowRequestsInWindow, 0);
        expect(status.totalRequestsInWindow, 2);
      });

      test('should track queue lengths by priority', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 1);
        
        // Fill rate limit
        await rateLimiter.acquire();
        
        // Act - queue requests
        final futures = [
          rateLimiter.acquireWithPriority(RequestPriority.critical),
          rateLimiter.acquireWithPriority(RequestPriority.high),
          rateLimiter.acquireWithPriority(RequestPriority.normal),
          rateLimiter.acquireWithPriority(RequestPriority.low),
        ];
        
        final queueStatus = rateLimiter.getQueueStatus();
        
        // Assert
        expect(queueStatus.criticalQueueLength, 1);
        expect(queueStatus.highQueueLength, 1);
        expect(queueStatus.normalQueueLength, 1);
        expect(queueStatus.lowQueueLength, 1);
        expect(queueStatus.totalQueueLength, 4);
        
        // Cleanup
        await Future.wait(futures.cast<Future<void>>());
      });

      test('should calculate priority-based wait times', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 1);
        
        // Fill rate limit with low priority
        await rateLimiter.acquireWithPriority(RequestPriority.low);
        
        // Act - queue different priority requests
        final criticalFuture = rateLimiter.acquireWithPriority(RequestPriority.critical);
        final normalFuture = rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        // Check wait times
        final criticalWaitTime = rateLimiter.getWaitTime(priority: RequestPriority.critical);
        final normalWaitTime = rateLimiter.getWaitTime(priority: RequestPriority.normal);
        
        // Assert - critical should have shorter wait time
        expect(criticalWaitTime.inMilliseconds, lessThan(normalWaitTime.inMilliseconds));
        
        // Cleanup
        await Future.wait([criticalFuture, normalFuture].cast<Future<void>>());
      });
    });

    group('Integration with Base RateLimiter', () {
      test('should maintain sliding window behavior with priorities', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(
          requestsPerSecond: 2,
          windowSize: const Duration(milliseconds: 500),
        );
        
        // Act - use up capacity with different priorities
        await rateLimiter.acquireWithPriority(RequestPriority.critical);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        // Check that limit is reached
        expect(rateLimiter.canMakeRequest(), isFalse);
        
        // Wait for window to slide
        await Future.delayed(const Duration(milliseconds: 600));
        
        // Assert - should allow requests again
        expect(rateLimiter.canMakeRequest(), isTrue);
      });

      test('should handle priority and non-priority requests together', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        
        // Act - mix priority and non-priority requests
        await rateLimiter.acquire(); // Non-priority
        await rateLimiter.acquireWithPriority(RequestPriority.high);
        await rateLimiter.acquireWithPriority(RequestPriority.normal);
        
        // Assert - should track all requests in window
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, 3);
        expect(rateLimiter.canMakeRequest(), isFalse);
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle invalid priority gracefully', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter();
        
        // Act & Assert - should handle null or invalid priority
        expect(() => rateLimiter.canMakeRequest(priority: null), returnsNormally);
        expect(() => rateLimiter.getWaitTime(priority: null), returnsNormally);
      });

      test('should handle concurrent priority requests safely', () async {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 2);
        
        // Act - simulate concurrent high-priority requests
        final futures = List.generate(5, (index) => 
          rateLimiter.acquireWithPriority(RequestPriority.critical)
        );
        
        // Wait for all to complete
        await Future.wait(futures.cast<Future<void>>());
        
        // Assert - should maintain consistency
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, lessThanOrEqualTo(2));
      });

      test('should handle capacity reservation edge cases', () {
        // Arrange
        final rateLimiter = PriorityRateLimiter(requestsPerSecond: 3);
        
        // Act & Assert - should handle zero and negative reservations
        expect(() => rateLimiter.reserveCapacity(RequestPriority.high, 0), 
               returnsNormally);
        expect(() => rateLimiter.reserveCapacity(RequestPriority.high, -1), 
               throwsA(isA<ArgumentError>()));
      });
    });
  });
}