import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';
import 'package:navtool/core/utils/circuit_breaker.dart';
import 'dart:io';

void main() {
  group('CircuitBreaker Tests', () {
    group('Basic Functionality', () {
      test('should start in closed state', () {
        // Arrange & Act
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        // Assert
        expect(circuitBreaker.state, CircuitState.closed);
        expect(circuitBreaker.isOpen, isFalse);
        expect(circuitBreaker.isClosed, isTrue);
        expect(circuitBreaker.isHalfOpen, isFalse);
      });

      test('should execute operation when closed', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          return 'success';
        }
        
        // Act
        final result = await circuitBreaker.execute(operation);
        
        // Assert
        expect(result, 'success');
        expect(callCount, 1);
        expect(circuitBreaker.state, CircuitState.closed);
      });

      test('should record successful executions', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        Future<String> operation() async => 'success';
        
        // Act
        await circuitBreaker.execute(operation);
        await circuitBreaker.execute(operation);
        
        // Assert
        expect(circuitBreaker.successCount, 2);
        expect(circuitBreaker.failureCount, 0);
        expect(circuitBreaker.state, CircuitState.closed);
      });
    });

    group('Failure Handling', () {
      test('should record failures but stay closed under threshold', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        // Act & Assert
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
            fail('Should have thrown NetworkConnectivityException');
          } catch (e) {
            expect(e, isA<NetworkConnectivityException>());
          }
          expect(circuitBreaker.state, CircuitState.closed, reason: 'Circuit should stay closed after ${i+1} failures');
        }
        
        expect(circuitBreaker.failureCount, 2, reason: 'Should have recorded 2 failures');
      });

      test('should open circuit after failure threshold is reached', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        // Act - reach failure threshold
        for (int i = 0; i < 3; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
            fail('Should have thrown NetworkConnectivityException');
          } catch (e) {
            expect(e, isA<NetworkConnectivityException>());
          }
        }
        
        // Assert
        expect(circuitBreaker.state, CircuitState.open);
        expect(circuitBreaker.isOpen, isTrue);
        expect(circuitBreaker.failureCount, 3);
      });

      test('should fail fast when circuit is open', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(seconds: 10),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        // Act & Assert - should fail fast
        var callCount = 0;
        Future<String> operation() async {
          callCount++;
          return 'success';
        }
        
        expect(
          () => circuitBreaker.execute(operation),
          throwsA(isA<CircuitBreakerOpenException>()),
        );
        
        expect(callCount, 0); // Operation should not be called
        expect(circuitBreaker.state, CircuitState.open);
      });

      test('should transition to half-open after timeout', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(milliseconds: 50),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        expect(circuitBreaker.state, CircuitState.open);
        
        // Act - wait for timeout
        await Future.delayed(const Duration(milliseconds: 60));
        
        // Try an operation to trigger state check
        Future<String> operation() async => 'success';
        final result = await circuitBreaker.execute(operation);
        
        // Assert
        expect(result, 'success');
        expect(circuitBreaker.state, CircuitState.closed); // Success closes it
      });
    });

    group('Half-Open State', () {
      test('should close circuit on successful operation in half-open state', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(milliseconds: 50),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        // Wait for timeout to enter half-open
        await Future.delayed(const Duration(milliseconds: 60));
        
        // Act - successful operation in half-open state
        Future<String> successOperation() async => 'recovered';
        final result = await circuitBreaker.execute(successOperation);
        
        // Assert
        expect(result, 'recovered');
        expect(circuitBreaker.state, CircuitState.closed);
        expect(circuitBreaker.failureCount, 0); // Reset on recovery
      });

      test('should reopen circuit on failure in half-open state', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(milliseconds: 50),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        // Wait for timeout to enter half-open
        await Future.delayed(const Duration(milliseconds: 60));
        
        // Act - failure in half-open state
        try {
          await circuitBreaker.execute(failingOperation);
          fail('Should have thrown NetworkConnectivityException');
        } catch (e) {
          expect(e, isA<NetworkConnectivityException>());
        }
        
        // Assert
        expect(circuitBreaker.state, CircuitState.open);
      });
    });

    group('Configuration', () {
      test('should respect custom failure threshold', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 5,
          timeout: const Duration(seconds: 10),
        );
        
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        // Act - 4 failures should keep circuit closed
        for (int i = 0; i < 4; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        expect(circuitBreaker.state, CircuitState.closed);
        
        // 5th failure should open circuit
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (_) {}
        
        // Assert
        expect(circuitBreaker.state, CircuitState.open);
      });

      test('should respect custom timeout duration', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 1,
          timeout: const Duration(milliseconds: 100),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (_) {}
        
        expect(circuitBreaker.state, CircuitState.open);
        
        // Act - wait less than timeout
        await Future.delayed(const Duration(milliseconds: 50));
        
        Future<String> operation() async => 'success';
        
        // Should still be open
        expect(
          () => circuitBreaker.execute(operation),
          throwsA(isA<CircuitBreakerOpenException>()),
        );
        
        // Wait for full timeout
        await Future.delayed(const Duration(milliseconds: 60));
        
        // Should allow operation now
        final result = await circuitBreaker.execute(operation);
        expect(result, 'success');
      });
    });

    group('Error Filtering', () {
      test('should only count specified errors as failures', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(seconds: 10),
          shouldCountAsFailure: (error) => error is NetworkConnectivityException,
        );
        
        // Act - non-counted error should not affect circuit
        Future<String> nonCountedError() async {
          throw ChartNotAvailableException('US5CA52M');
        }
        
        try {
          await circuitBreaker.execute(nonCountedError);
          fail('Should have thrown ChartNotAvailableException');
        } catch (e) {
          expect(e, isA<ChartNotAvailableException>());
        }
        
        expect(circuitBreaker.failureCount, 0);
        expect(circuitBreaker.state, CircuitState.closed);
        
        // Counted error should affect circuit
        Future<String> countedError() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(countedError);
            fail('Should have thrown NetworkConnectivityException');
          } catch (e) {
            expect(e, isA<NetworkConnectivityException>());
          }
        }
        
        // Assert
        expect(circuitBreaker.failureCount, 2);
        expect(circuitBreaker.state, CircuitState.open);
      });

      test('should use default error filtering when not specified', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(seconds: 10),
        );
        
        // Act - retryable errors should count as failures
        Future<String> retryableError() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(retryableError);
          } catch (_) {}
        }
        
        expect(circuitBreaker.state, CircuitState.open);
        
        // Reset for next test
        final newCircuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(seconds: 10),
        );
        
        // Non-retryable errors should not count as failures
        Future<String> nonRetryableError() async {
          throw ChartNotAvailableException('US5CA52M');
        }
        
        try {
          await newCircuitBreaker.execute(nonRetryableError);
        } catch (_) {}
        
        // Assert
        expect(newCircuitBreaker.failureCount, 0);
        expect(newCircuitBreaker.state, CircuitState.closed);
      });
    });

    group('Metrics and Monitoring', () {
      test('should track execution metrics', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        Future<String> successOperation() async => 'success';
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        // Act
        await circuitBreaker.execute(successOperation);
        await circuitBreaker.execute(successOperation);
        
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (_) {}
        
        // Assert
        expect(circuitBreaker.successCount, 2);
        expect(circuitBreaker.failureCount, 1);
        expect(circuitBreaker.totalExecutions, 3);
        expect(circuitBreaker.failureRate, closeTo(0.333, 0.01));
      });

      test('should track last failure time', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        final beforeFailure = DateTime.now();
        
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        // Act
        try {
          await circuitBreaker.execute(failingOperation);
        } catch (_) {}
        
        final afterFailure = DateTime.now();
        
        // Assert
        expect(circuitBreaker.lastFailureTime, isNotNull);
        expect(circuitBreaker.lastFailureTime!.isAfter(beforeFailure) || 
               circuitBreaker.lastFailureTime!.isAtSameMomentAs(beforeFailure), isTrue);
        expect(circuitBreaker.lastFailureTime!.isBefore(afterFailure) ||
               circuitBreaker.lastFailureTime!.isAtSameMomentAs(afterFailure), isTrue);
      });

      test('should provide circuit breaker status', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(seconds: 10),
        );
        
        // Act - initial status
        var status = circuitBreaker.getStatus();
        
        // Assert
        expect(status.state, CircuitState.closed);
        expect(status.failureCount, 0);
        expect(status.successCount, 0);
        expect(status.failureThreshold, 2);
        expect(status.timeoutDuration, const Duration(seconds: 10));
        expect(status.lastFailureTime, isNull);
        expect(status.nextRetryTime, isNull);
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        status = circuitBreaker.getStatus();
        
        expect(status.state, CircuitState.open);
        expect(status.failureCount, 2);
        expect(status.lastFailureTime, isNotNull);
        expect(status.nextRetryTime, isNotNull);
      });
    });

    group('Edge Cases', () {
      test('should handle null operation gracefully', () {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 3,
          timeout: const Duration(seconds: 10),
        );
        
        // Act & Assert
        expect(
          () => circuitBreaker.execute(() => null as dynamic),
          throwsA(isA<TypeError>()),
        );
      });

      test('should handle zero failure threshold', () {
        // Act & Assert
        expect(
          () => CircuitBreaker(
            failureThreshold: 0,
            timeout: const Duration(seconds: 10),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle negative timeout', () {
        // Act & Assert
        expect(
          () => CircuitBreaker(
            failureThreshold: 3,
            timeout: const Duration(seconds: -1),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should reset metrics when circuit closes after being open', () async {
        // Arrange
        final circuitBreaker = CircuitBreaker(
          failureThreshold: 2,
          timeout: const Duration(milliseconds: 50),
        );
        
        // Open the circuit
        Future<String> failingOperation() async {
          throw NetworkConnectivityException();
        }
        
        for (int i = 0; i < 2; i++) {
          try {
            await circuitBreaker.execute(failingOperation);
          } catch (_) {}
        }
        
        expect(circuitBreaker.failureCount, 2);
        
        // Wait for timeout and recover
        await Future.delayed(const Duration(milliseconds: 60));
        
        Future<String> successOperation() async => 'recovered';
        await circuitBreaker.execute(successOperation);
        
        // Assert
        expect(circuitBreaker.state, CircuitState.closed);
        expect(circuitBreaker.failureCount, 0); // Should be reset
        expect(circuitBreaker.successCount, 1);
      });
    });
  });
}