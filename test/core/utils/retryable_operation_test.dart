import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/models/retry_policy.dart';
import 'package:navtool/core/utils/retryable_operation.dart';
import 'dart:io';

void main() {
  group('RetryableOperation Tests', () {
    group('execute', () {
      test('should succeed on first attempt when operation succeeds', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          return 'success';
        }
        
        // Act
        final result = await RetryableOperation.execute(operation);
        
        // Assert
        expect(result, 'success');
        expect(callCount, 1);
      });

      test('should retry on retryable errors and eventually succeed', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          if (callCount < 3) {
            throw NetworkConnectivityException();
          }
          return 'success after retries';
        }
        
        const policy = RetryPolicy(
          maxRetries: 5,
          initialDelay: Duration(milliseconds: 10),
          useJitter: false,
        );
        
        // Act
        final result = await RetryableOperation.execute(
          operation,
          policy: policy,
        );
        
        // Assert
        expect(result, 'success after retries');
        expect(callCount, 3);
      });

      test('should not retry on non-retryable errors', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          throw ChartNotAvailableException('US5CA52M');
        }
        
        const policy = RetryPolicy(
          maxRetries: 5,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act & Assert
        expect(
          () => RetryableOperation.execute(operation, policy: policy),
          throwsA(isA<ChartNotAvailableException>()),
        );
        
        // Wait a bit to ensure no retries happen
        await Future.delayed(const Duration(milliseconds: 50));
        expect(callCount, 1);
      });

      test('should respect maximum retry limit', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          throw NetworkConnectivityException();
        }
        
        const policy = RetryPolicy(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 10),
          useJitter: false,
        );
        
        // Act & Assert
        expect(
          () => RetryableOperation.execute(operation, policy: policy),
          throwsA(isA<NetworkConnectivityException>()),
        );
        
        // Wait for all retries to complete
        await Future.delayed(const Duration(milliseconds: 100));
        expect(callCount, 3); // Initial attempt + 2 retries
      });

      test('should use custom shouldRetry function when provided', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          throw const SocketException('Custom error');
        }
        
        // Custom shouldRetry that prevents retrying SocketException
        bool customShouldRetry(dynamic error) {
          return false; // Never retry
        }
        
        const policy = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act & Assert
        expect(
          () => RetryableOperation.execute(
            operation,
            policy: policy,
            shouldRetry: customShouldRetry,
          ),
          throwsA(isA<SocketException>()),
        );
        
        await Future.delayed(const Duration(milliseconds: 50));
        expect(callCount, 1); // Should not retry
      });

      test('should use default retry policy when none provided', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          if (callCount < 2) {
            throw NetworkConnectivityException();
          }
          return 'success';
        }
        
        // Act
        final result = await RetryableOperation.execute(operation);
        
        // Assert
        expect(result, 'success');
        expect(callCount, 2);
      });

      test('should apply exponential backoff delays between retries', () async {
        // Arrange
        final startTime = DateTime.now();
        final attemptTimes = <DateTime>[];
        
        var callCount = 0;
        Future<String> operation() async {
          attemptTimes.add(DateTime.now());
          callCount++;
          if (callCount < 3) {
            throw NetworkConnectivityException();
          }
          return 'success';
        }
        
        const policy = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 100),
          backoffMultiplier: 2.0,
          useJitter: false,
        );
        
        // Act
        await RetryableOperation.execute(operation, policy: policy);
        
        // Assert
        expect(attemptTimes.length, 3);
        
        // Check delays between attempts (allowing for some timing variance)
        final delay1 = attemptTimes[1].difference(attemptTimes[0]);
        final delay2 = attemptTimes[2].difference(attemptTimes[1]);
        
        expect(delay1.inMilliseconds, greaterThanOrEqualTo(80)); // ~100ms with tolerance
        expect(delay1.inMilliseconds, lessThanOrEqualTo(150));
        
        expect(delay2.inMilliseconds, greaterThanOrEqualTo(150)); // ~200ms with tolerance
        expect(delay2.inMilliseconds, lessThanOrEqualTo(300));
      });

      test('should handle operations that return void', () async {
        // Arrange
        var callCount = 0;
        var sideEffect = '';
        
        Future<void> operation() async {
          callCount++;
          if (callCount < 2) {
            throw NetworkConnectivityException();
          }
          sideEffect = 'completed';
        }
        
        const policy = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act
        await RetryableOperation.execute(operation, policy: policy);
        
        // Assert
        expect(callCount, 2);
        expect(sideEffect, 'completed');
      });

      test('should handle operations that return complex objects', () async {
        // Arrange
        var callCount = 0;
        
        Future<Map<String, dynamic>> operation() async {
          callCount++;
          if (callCount < 2) {
            throw RateLimitExceededException();
          }
          return {
            'status': 'success',
            'data': [1, 2, 3],
            'timestamp': DateTime.now().toIso8601String(),
          };
        }
        
        const policy = RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act
        final result = await RetryableOperation.execute(operation, policy: policy);
        
        // Assert
        expect(callCount, 2);
        expect(result['status'], 'success');
        expect(result['data'], [1, 2, 3]);
        expect(result['timestamp'], isA<String>());
      });

      test('should propagate the original error after max retries', () async {
        // Arrange
        final originalError = NetworkConnectivityException('Specific network error');
        
        Future<String> operation() async {
          throw originalError;
        }
        
        const policy = RetryPolicy(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act & Assert
        try {
          await RetryableOperation.execute(operation, policy: policy);
          fail('Expected exception to be thrown');
        } catch (error) {
          expect(error, same(originalError));
        }
      });
    });

    group('Error Classification', () {
      test('should correctly identify retryable NOAA exceptions', () {
        // Arrange & Act & Assert
        expect(
          RetryableOperation.isRetryable(NetworkConnectivityException()),
          isTrue,
        );
        expect(
          RetryableOperation.isRetryable(RateLimitExceededException()),
          isTrue,
        );
        expect(
          RetryableOperation.isRetryable(NoaaServiceUnavailableException()),
          isTrue,
        );
        expect(
          RetryableOperation.isRetryable(
            ChartDownloadException('US5CA52M', 'Network error')
          ),
          isTrue,
        );
      });

      test('should correctly identify non-retryable NOAA exceptions', () {
        // Arrange & Act & Assert
        expect(
          RetryableOperation.isRetryable(ChartNotAvailableException('US5CA52M')),
          isFalse,
        );
        expect(
          RetryableOperation.isRetryable(
            ChartDownloadException('US5CA52M', 'Corrupted', isRetryable: false)
          ),
          isFalse,
        );
      });

      test('should handle non-NOAA exceptions using error classifier', () {
        // Arrange & Act & Assert
        expect(
          RetryableOperation.isRetryable(const SocketException('Network unreachable')),
          isTrue,
        );
        expect(
          RetryableOperation.isRetryable(Exception('Unknown error')),
          isFalse,
        );
      });
    });

    group('Metrics and Logging', () {
      test('should track retry attempts in operation result', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          if (callCount < 3) {
            throw NetworkConnectivityException();
          }
          return 'success';
        }
        
        const policy = RetryPolicy(
          maxRetries: 5,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act
        final result = await RetryableOperation.executeWithMetrics(
          operation,
          policy: policy,
        );
        
        // Assert
        expect(result.value, 'success');
        expect(result.totalAttempts, 3);
        expect(result.retryCount, 2);
        expect(result.totalDuration, greaterThan(Duration.zero));
        expect(result.errors.length, 2);
        expect(result.errors.every((e) => e is NetworkConnectivityException), isTrue);
      });

      test('should track successful operation on first attempt', () async {
        // Arrange
        Future<int> operation() async {
          await Future.delayed(const Duration(milliseconds: 1)); // Ensure some duration
          return 42;
        }
        
        // Act
        final result = await RetryableOperation.executeWithMetrics(operation);
        
        // Assert
        expect(result.value, 42);
        expect(result.totalAttempts, 1);
        expect(result.retryCount, 0);
        expect(result.errors, isEmpty);
        expect(result.totalDuration, greaterThan(Duration.zero));
      });

      test('should track failed operation that exhausts retries', () async {
        // Arrange
        final testError = NetworkConnectivityException();
        Future<String> operation() async {
          throw testError;
        }
        
        const policy = RetryPolicy(
          maxRetries: 2,
          initialDelay: Duration(milliseconds: 10),
        );
        
        // Act & Assert
        try {
          await RetryableOperation.executeWithMetrics(operation, policy: policy);
          fail('Expected exception');
        } catch (error) {
          expect(error, isA<RetryExhaustedException>());
          final retryError = error as RetryExhaustedException;
          expect(retryError.totalAttempts, 3);
          expect(retryError.retryCount, 2);
          expect(retryError.errors.length, 3);
          expect(retryError.lastError, same(testError));
        }
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle null operation gracefully', () {
        // Act & Assert
        expect(
          () => RetryableOperation.execute(() => null as dynamic),
          throwsA(isA<TypeError>()),
        );
      });

      test('should handle operation that throws immediately', () async {
        // Arrange
        Future<String> operation() async {
          throw ChartNotAvailableException('US5CA52M');
        }
        
        // Act & Assert
        expect(
          () => RetryableOperation.execute(operation),
          throwsA(isA<ChartNotAvailableException>()),
        );
      });

      test('should handle policy with zero max retries', () async {
        // Arrange
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          throw NetworkConnectivityException();
        }
        
        const policy = RetryPolicy(maxRetries: 0);
        
        // Act & Assert
        expect(
          () => RetryableOperation.execute(operation, policy: policy),
          throwsA(isA<NetworkConnectivityException>()),
        );
        
        await Future.delayed(const Duration(milliseconds: 20));
        expect(callCount, 1); // Only initial attempt, no retries
      });
    });
  });
}