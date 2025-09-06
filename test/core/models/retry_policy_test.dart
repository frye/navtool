import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/retry_policy.dart';

void main() {
  group('RetryPolicy Tests', () {
    group('Constructor and Properties', () {
      test('should create RetryPolicy with default values', () {
        // Arrange & Act
        const policy = RetryPolicy();

        // Assert
        expect(policy.maxRetries, 3);
        expect(policy.initialDelay, const Duration(seconds: 1));
        expect(policy.backoffMultiplier, 2.0);
        expect(policy.maxDelay, const Duration(minutes: 2));
        expect(policy.useJitter, isTrue);
        expect(policy.jitterRange, 0.1);
      });

      test('should create RetryPolicy with custom values', () {
        // Arrange & Act
        const policy = RetryPolicy(
          maxRetries: 5,
          initialDelay: Duration(milliseconds: 500),
          backoffMultiplier: 1.5,
          maxDelay: Duration(seconds: 30),
          useJitter: false,
          jitterRange: 0.2,
        );

        // Assert
        expect(policy.maxRetries, 5);
        expect(policy.initialDelay, const Duration(milliseconds: 500));
        expect(policy.backoffMultiplier, 1.5);
        expect(policy.maxDelay, const Duration(seconds: 30));
        expect(policy.useJitter, isFalse);
        expect(policy.jitterRange, 0.2);
      });
    });

    group('calculateDelay', () {
      test('should calculate exponential backoff delays correctly', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(minutes: 10),
          useJitter: false,
        );

        // Act & Assert
        expect(policy.calculateDelay(0), const Duration(seconds: 1));
        expect(policy.calculateDelay(1), const Duration(seconds: 2));
        expect(policy.calculateDelay(2), const Duration(seconds: 4));
      });

      test('should enforce maximum delay limit', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 5),
          maxRetries: 15, // Allow enough retries to test max delay
          useJitter: false,
        );

        // Act
        final delay = policy.calculateDelay(
          10,
        ); // Would be 1024 seconds without limit

        // Assert
        expect(delay, const Duration(seconds: 5));
      });

      test('should add jitter when enabled', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          useJitter: true,
          jitterRange: 0.1,
        );

        // Act
        final delay1 = policy.calculateDelay(0);
        final delay2 = policy.calculateDelay(0);

        // Assert - delays should be within jitter range of 1 second (±10%)
        expect(delay1.inMilliseconds, greaterThanOrEqualTo(900));
        expect(delay1.inMilliseconds, lessThanOrEqualTo(1100));
        expect(delay2.inMilliseconds, greaterThanOrEqualTo(900));
        expect(delay2.inMilliseconds, lessThanOrEqualTo(1100));

        // Note: Can't guarantee they're different due to time-based pseudo-random
      });

      test('should handle fractional backoff multipliers', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 2),
          backoffMultiplier: 1.5,
          useJitter: false,
        );

        // Act & Assert
        expect(policy.calculateDelay(0), const Duration(seconds: 2));
        expect(policy.calculateDelay(1), const Duration(seconds: 3));
        expect(policy.calculateDelay(2), const Duration(milliseconds: 4500));
      });

      test('should throw ArgumentError for negative attempt', () {
        // Arrange
        const policy = RetryPolicy();

        // Act & Assert
        expect(() => policy.calculateDelay(-1), throwsA(isA<ArgumentError>()));
      });

      test('should throw ArgumentError for attempt exceeding max retries', () {
        // Arrange
        const policy = RetryPolicy(maxRetries: 3);

        // Act & Assert
        expect(() => policy.calculateDelay(3), throwsA(isA<ArgumentError>()));
      });
    });

    group('Predefined Policies', () {
      test('should have correct chartDownload policy configuration', () {
        // Arrange & Act
        const policy = RetryPolicy.chartDownload;

        // Assert
        expect(policy.maxRetries, 3);
        expect(policy.initialDelay, const Duration(seconds: 2));
        expect(policy.backoffMultiplier, 2.0);
        expect(policy.maxDelay, const Duration(minutes: 5));
        expect(policy.useJitter, isTrue);
        expect(policy.jitterRange, 0.15);
      });

      test('should have correct apiRequest policy configuration', () {
        // Arrange & Act
        const policy = RetryPolicy.apiRequest;

        // Assert
        expect(policy.maxRetries, 5);
        expect(policy.initialDelay, const Duration(milliseconds: 500));
        expect(policy.backoffMultiplier, 1.5);
        expect(policy.maxDelay, const Duration(seconds: 30));
        expect(policy.useJitter, isTrue);
        expect(policy.jitterRange, 0.1);
      });

      test('should have correct critical policy configuration', () {
        // Arrange & Act
        const policy = RetryPolicy.critical;

        // Assert
        expect(policy.maxRetries, 7);
        expect(policy.initialDelay, const Duration(seconds: 1));
        expect(policy.backoffMultiplier, 2.0);
        expect(policy.maxDelay, const Duration(minutes: 10));
        expect(policy.useJitter, isTrue);
        expect(policy.jitterRange, 0.2);
      });
    });

    group('Equality and toString', () {
      test('should implement equality correctly', () {
        // Arrange
        const policy1 = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
        );

        const policy2 = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
        );

        const policy3 = RetryPolicy(
          maxRetries: 5,
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
        );

        // Act & Assert
        expect(policy1, equals(policy2));
        expect(policy1, isNot(equals(policy3)));
        expect(policy1.hashCode, equals(policy2.hashCode));
      });

      test('should have informative toString representation', () {
        // Arrange
        const policy = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(minutes: 2),
          useJitter: true,
        );

        // Act
        final stringRep = policy.toString();

        // Assert
        expect(stringRep, contains('RetryPolicy'));
        expect(stringRep, contains('maxRetries: 3'));
        expect(stringRep, contains('backoffMultiplier: 2.0'));
        expect(stringRep, contains('useJitter: true'));
      });
    });

    group('Edge Cases', () {
      test('should handle zero initial delay', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration.zero,
          useJitter: false,
        );

        // Act
        final delay = policy.calculateDelay(0);

        // Assert
        expect(delay, Duration.zero);
      });

      test('should handle backoff multiplier of 1.0 (no growth)', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 2),
          backoffMultiplier: 1.0,
          useJitter: false,
        );

        // Act & Assert
        expect(policy.calculateDelay(0), const Duration(seconds: 2));
        expect(policy.calculateDelay(1), const Duration(seconds: 2));
        expect(policy.calculateDelay(2), const Duration(seconds: 2));
      });

      test('should handle very small jitter range', () {
        // Arrange
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          useJitter: true,
          jitterRange: 0.001, // 0.1%
        );

        // Act
        final delay = policy.calculateDelay(0);

        // Assert
        // Should be very close to 1 second
        expect(delay.inMilliseconds, greaterThanOrEqualTo(999));
        expect(delay.inMilliseconds, lessThanOrEqualTo(1001));
      });
    });
  });
}
