import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/rate_limiter.dart';

void main() {
  group('RateLimiter Tests', () {
    group('Construction and Configuration', () {
      test('should create RateLimiter with default configuration', () {
        // Arrange & Act
        final rateLimiter = RateLimiter();

        // Assert
        expect(rateLimiter.requestsPerSecond, 5);
        expect(rateLimiter.windowSize, const Duration(seconds: 1));
      });

      test('should create RateLimiter with custom configuration', () {
        // Arrange & Act
        final rateLimiter = RateLimiter(
          requestsPerSecond: 10,
          windowSize: const Duration(milliseconds: 500),
        );

        // Assert
        expect(rateLimiter.requestsPerSecond, 10);
        expect(rateLimiter.windowSize, const Duration(milliseconds: 500));
      });

      test('should throw ArgumentError for invalid requests per second', () {
        // Arrange & Act & Assert
        expect(
          () => RateLimiter(requestsPerSecond: 0),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => RateLimiter(requestsPerSecond: -1),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw ArgumentError for invalid window size', () {
        // Arrange & Act & Assert
        expect(
          () => RateLimiter(windowSize: Duration.zero),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => RateLimiter(windowSize: const Duration(milliseconds: -1)),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Sliding Window Algorithm', () {
      test('should allow requests within rate limit', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 2);

        // Act & Assert
        expect(rateLimiter.canMakeRequest(), isTrue);
        await rateLimiter.acquire();

        expect(rateLimiter.canMakeRequest(), isTrue);
        await rateLimiter.acquire();

        // Should still be within window since 2 req/sec allowed
        expect(rateLimiter.canMakeRequest(), isFalse);
      });

      test('should enforce rate limit across sliding window', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 1);

        // Act
        await rateLimiter.acquire();

        // Assert - should not allow another request immediately
        expect(rateLimiter.canMakeRequest(), isFalse);

        // Wait for window to slide
        await Future.delayed(const Duration(milliseconds: 1100));

        // Should allow request after window slides
        expect(rateLimiter.canMakeRequest(), isTrue);
      });

      test('should handle burst requests correctly', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 3);
        final results = <bool>[];

        // Act - attempt 5 rapid requests
        for (int i = 0; i < 5; i++) {
          results.add(rateLimiter.canMakeRequest());
          if (results.last) {
            await rateLimiter.acquire();
          }
        }

        // Assert - only first 3 should succeed
        expect(results, [true, true, true, false, false]);
      });

      test('should accurately track request times in sliding window', () async {
        // Arrange
        final rateLimiter = RateLimiter(
          requestsPerSecond: 2,
          windowSize: const Duration(milliseconds: 500),
        );

        // Act - make requests with delays
        await rateLimiter.acquire();
        await Future.delayed(const Duration(milliseconds: 100));

        await rateLimiter.acquire();
        expect(rateLimiter.canMakeRequest(), isFalse);

        // Wait for first request to fall out of window
        await Future.delayed(const Duration(milliseconds: 450));

        // Assert - should allow new request as window slides
        expect(rateLimiter.canMakeRequest(), isTrue);
      });
    });

    group('Wait Time Calculation', () {
      test('should return zero wait time when under limit', () {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 5);

        // Act
        final waitTime = rateLimiter.getWaitTime();

        // Assert
        expect(waitTime, Duration.zero);
      });

      test('should calculate correct wait time when at limit', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 1);

        // Act - consume the allowed request
        await rateLimiter.acquire();
        final waitTime = rateLimiter.getWaitTime();

        // Assert - should need to wait for window to slide
        expect(waitTime.inMilliseconds, greaterThan(0));
        expect(waitTime.inMilliseconds, lessThanOrEqualTo(1000));
      });

      test('should calculate decreasing wait time as window slides', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 1);
        await rateLimiter.acquire();

        // Act
        final initialWaitTime = rateLimiter.getWaitTime();
        await Future.delayed(const Duration(milliseconds: 200));
        final laterWaitTime = rateLimiter.getWaitTime();

        // Assert
        expect(
          laterWaitTime.inMilliseconds,
          lessThan(initialWaitTime.inMilliseconds),
        );
      });
    });

    group('Rate Limit Status', () {
      test('should provide accurate status when under limit', () {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 5);

        // Act
        final status = rateLimiter.getStatus();

        // Assert
        expect(status.requestsInWindow, 0);
        expect(status.requestsPerSecond, 5);
        expect(status.isAtLimit, isFalse);
        expect(status.windowStart, isNotNull);
        expect(status.nextAvailableTime, isNull);
      });

      test('should provide accurate status when at limit', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 2);

        // Act
        await rateLimiter.acquire();
        await rateLimiter.acquire();
        final status = rateLimiter.getStatus();

        // Assert
        expect(status.requestsInWindow, 2);
        expect(status.requestsPerSecond, 2);
        expect(status.isAtLimit, isTrue);
        expect(status.nextAvailableTime, isNotNull);
      });

      test('should update status as window slides', () async {
        // Arrange
        final rateLimiter = RateLimiter(
          requestsPerSecond: 1,
          windowSize: const Duration(milliseconds: 500),
        );

        // Act
        await rateLimiter.acquire();
        final statusAtLimit = rateLimiter.getStatus();

        await Future.delayed(const Duration(milliseconds: 600));
        final statusAfterWindow = rateLimiter.getStatus();

        // Assert
        expect(statusAtLimit.isAtLimit, isTrue);
        expect(statusAfterWindow.isAtLimit, isFalse);
        expect(statusAfterWindow.requestsInWindow, 0);
      });
    });

    group('Concurrent Access', () {
      test('should handle concurrent acquire calls safely', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 3);

        // Act - simulate concurrent requests
        final futures = List.generate(5, (index) => rateLimiter.acquire());

        // Wait for all to complete (some will wait due to rate limiting)
        await Future.wait(futures.cast<Future<void>>());

        // Assert - rate limiter should still be consistent
        final status = rateLimiter.getStatus();
        expect(status.requestsInWindow, lessThanOrEqualTo(3));
      });

      test('should handle rapid canMakeRequest calls', () {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 2);

        // Act - rapid calls to canMakeRequest
        final results = List.generate(
          10,
          (index) => rateLimiter.canMakeRequest(),
        );

        // Assert - should consistently return same result
        expect(results.every((result) => result == results.first), isTrue);
      });
    });

    group('Edge Cases', () {
      test('should handle system clock changes gracefully', () async {
        // Arrange
        final rateLimiter = RateLimiter(requestsPerSecond: 1);

        // Act - this tests that the implementation doesn't break with timing issues
        await rateLimiter.acquire();

        // Assert - should not throw or enter invalid state
        expect(() => rateLimiter.canMakeRequest(), returnsNormally);
        expect(() => rateLimiter.getWaitTime(), returnsNormally);
        expect(() => rateLimiter.getStatus(), returnsNormally);
      });

      test('should handle very high rate limits', () {
        // Arrange & Act
        final rateLimiter = RateLimiter(requestsPerSecond: 1000);

        // Assert - should handle large numbers without issues
        expect(rateLimiter.canMakeRequest(), isTrue);
        expect(rateLimiter.getWaitTime(), Duration.zero);
      });

      test('should handle very small time windows', () {
        // Arrange & Act
        final rateLimiter = RateLimiter(
          requestsPerSecond: 1,
          windowSize: const Duration(milliseconds: 1),
        );

        // Assert - should not break with small windows
        expect(() => rateLimiter.canMakeRequest(), returnsNormally);
      });
    });
  });
}
