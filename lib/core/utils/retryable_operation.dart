import 'dart:async';
import 'package:navtool/core/error/noaa_error_classifier.dart';
import 'package:navtool/core/models/retry_policy.dart';

/// Exception thrown when retry attempts are exhausted
class RetryExhaustedException implements Exception {
  const RetryExhaustedException({
    required this.totalAttempts,
    required this.retryCount,
    required this.errors,
    required this.lastError,
    required this.totalDuration,
  });

  /// Total number of attempts made (including initial attempt)
  final int totalAttempts;

  /// Number of retry attempts (totalAttempts - 1)
  final int retryCount;

  /// List of all errors encountered during attempts
  final List<dynamic> errors;

  /// The final error that caused the operation to fail
  final dynamic lastError;

  /// Total time spent on all attempts including delays
  final Duration totalDuration;

  @override
  String toString() {
    return 'RetryExhaustedException: Failed after $totalAttempts attempts '
        '($retryCount retries) over ${totalDuration.inSeconds}s. '
        'Last error: $lastError';
  }
}

/// Result of a retryable operation with metrics
class RetryResult<T> {
  const RetryResult({
    required this.value,
    required this.totalAttempts,
    required this.retryCount,
    required this.errors,
    required this.totalDuration,
  });

  /// The successful result value
  final T value;

  /// Total number of attempts made
  final int totalAttempts;

  /// Number of retry attempts
  final int retryCount;

  /// Errors encountered during failed attempts
  final List<dynamic> errors;

  /// Total duration including delays
  final Duration totalDuration;
}

/// Utility class for executing operations with retry logic
///
/// Provides robust retry capabilities with exponential backoff,
/// jitter, and marine environment optimizations.
class RetryableOperation {
  RetryableOperation._(); // Private constructor to prevent instantiation

  /// Default retry policy for general operations
  static const RetryPolicy _defaultPolicy = RetryPolicy.apiRequest;

  /// Executes an operation with retry logic
  ///
  /// [operation] The operation to execute
  /// [policy] Retry policy configuration (defaults to apiRequest policy)
  /// [shouldRetry] Custom function to determine if an error should trigger a retry
  ///
  /// Returns the result of the successful operation
  /// Throws the last encountered error if all retries are exhausted
  static Future<T> execute<T>(
    Future<T> Function() operation, {
    RetryPolicy? policy,
    bool Function(dynamic)? shouldRetry,
  }) async {
    final effectivePolicy = policy ?? _defaultPolicy;
    final effectiveShouldRetry = shouldRetry ?? isRetryable;

    final errors = <dynamic>[];

    for (int attempt = 0; attempt <= effectivePolicy.maxRetries; attempt++) {
      try {
        final result = await operation();
        return result;
      } catch (error) {
        errors.add(error);

        // Don't retry if this is the last attempt
        if (attempt >= effectivePolicy.maxRetries) {
          break;
        }

        // Check if this error should trigger a retry
        if (!effectiveShouldRetry(error)) {
          rethrow; // Don't retry non-retryable errors
        }

        // Calculate and apply delay before next attempt
        final delay = effectivePolicy.calculateDelay(attempt);
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      }
    }

    // All retries exhausted, throw the last error
    throw errors.last;
  }

  /// Executes an operation with retry logic and returns detailed metrics
  ///
  /// Similar to [execute] but returns a [RetryResult] with execution metrics
  /// or throws [RetryExhaustedException] with detailed failure information.
  static Future<RetryResult<T>> executeWithMetrics<T>(
    Future<T> Function() operation, {
    RetryPolicy? policy,
    bool Function(dynamic)? shouldRetry,
  }) async {
    final effectivePolicy = policy ?? _defaultPolicy;
    final effectiveShouldRetry = shouldRetry ?? isRetryable;

    final errors = <dynamic>[];
    final startTime = DateTime.now();

    for (int attempt = 0; attempt <= effectivePolicy.maxRetries; attempt++) {
      try {
        final result = await operation();
        final endTime = DateTime.now();

        return RetryResult<T>(
          value: result,
          totalAttempts: attempt + 1,
          retryCount: attempt,
          errors: List.unmodifiable(errors),
          totalDuration: endTime.difference(startTime),
        );
      } catch (error) {
        errors.add(error);

        // Don't retry if this is the last attempt
        if (attempt >= effectivePolicy.maxRetries) {
          break;
        }

        // Check if this error should trigger a retry
        if (!effectiveShouldRetry(error)) {
          rethrow; // Don't retry non-retryable errors
        }

        // Calculate and apply delay before next attempt
        final delay = effectivePolicy.calculateDelay(attempt);
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      }
    }

    // All retries exhausted
    final endTime = DateTime.now();
    throw RetryExhaustedException(
      totalAttempts: effectivePolicy.maxRetries + 1,
      retryCount: effectivePolicy.maxRetries,
      errors: List.unmodifiable(errors),
      lastError: errors.last,
      totalDuration: endTime.difference(startTime),
    );
  }

  /// Determines if an error is retryable
  ///
  /// Uses the NOAA error classifier to make intelligent retry decisions
  /// based on error types and characteristics.
  static bool isRetryable(dynamic error) {
    return NoaaErrorClassifier.isRetryableError(error);
  }
}
