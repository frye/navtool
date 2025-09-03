import 'dart:async';
import 'package:navtool/core/error/noaa_error_classifier.dart';

/// Circuit breaker states
enum CircuitState {
  /// Circuit is closed - requests are allowed through
  closed,
  
  /// Circuit is open - requests are blocked and fail fast
  open,
  
  /// Circuit is half-open - allowing limited requests to test recovery
  halfOpen,
}

/// Exception thrown when circuit breaker is open
class CircuitBreakerOpenException implements Exception {
  const CircuitBreakerOpenException([this.message = 'Circuit breaker is open']);
  
  final String message;
  
  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}

/// Circuit breaker status information
class CircuitBreakerStatus {
  const CircuitBreakerStatus({
    required this.state,
    required this.failureCount,
    required this.successCount,
    required this.failureThreshold,
    required this.timeoutDuration,
    this.lastFailureTime,
    this.nextRetryTime,
  });

  /// Current circuit state
  final CircuitState state;
  
  /// Number of consecutive failures
  final int failureCount;
  
  /// Number of successful operations
  final int successCount;
  
  /// Failure threshold that triggers circuit opening
  final int failureThreshold;
  
  /// Timeout duration before allowing retry in half-open state
  final Duration timeoutDuration;
  
  /// Timestamp of the last failure
  final DateTime? lastFailureTime;
  
  /// When the circuit will next allow a retry attempt
  final DateTime? nextRetryTime;
}

/// Circuit breaker implementation for handling repeated failures
/// 
/// Implements the circuit breaker pattern to prevent cascade failures
/// by temporarily blocking operations when failure threshold is exceeded.
/// Optimized for marine environments with configurable timeouts.
class CircuitBreaker {
  /// Creates a circuit breaker with specified configuration
  /// 
  /// [failureThreshold] Number of consecutive failures before opening circuit
  /// [timeout] How long to wait before attempting recovery
  /// [shouldCountAsFailure] Custom function to determine what counts as failure
  CircuitBreaker({
    required this.failureThreshold,
    required this.timeout,
    this.shouldCountAsFailure,
  }) {
    if (failureThreshold <= 0) {
      throw ArgumentError('Failure threshold must be positive');
    }
    if (timeout.isNegative) {
      throw ArgumentError('Timeout must be non-negative');
    }
    
    _shouldCountAsFailure = shouldCountAsFailure ?? _defaultShouldCountAsFailure;
  }

  /// Failure threshold before opening circuit
  final int failureThreshold;
  
  /// Timeout before allowing retry attempts
  final Duration timeout;
  
  /// Current circuit state
  CircuitState _state = CircuitState.closed;
  
  /// Number of consecutive failures
  int _failureCount = 0;
  
  /// Number of successful operations
  int _successCount = 0;
  
  /// Timestamp of last failure
  DateTime? _lastFailureTime;
  
  /// Function to determine if error should count as failure
  late final bool Function(dynamic) _shouldCountAsFailure;
  
  /// Custom failure classification function
  final bool Function(dynamic)? shouldCountAsFailure;

  /// Current circuit state
  CircuitState get state => _state;
  
  /// Whether circuit is open (blocking requests)
  bool get isOpen => _state == CircuitState.open;
  
  /// Whether circuit is closed (allowing requests)
  bool get isClosed => _state == CircuitState.closed;
  
  /// Whether circuit is half-open (testing recovery)
  bool get isHalfOpen => _state == CircuitState.halfOpen;
  
  /// Current failure count
  int get failureCount => _failureCount;
  
  /// Current success count
  int get successCount => _successCount;
  
  /// Total executions attempted
  int get totalExecutions => _failureCount + _successCount;
  
  /// Current failure rate (0.0 to 1.0)
  double get failureRate {
    final total = totalExecutions;
    return total > 0 ? _failureCount / total : 0.0;
  }
  
  /// Timestamp of last failure
  DateTime? get lastFailureTime => _lastFailureTime;

  /// Executes an operation through the circuit breaker
  /// 
  /// [operation] The operation to execute
  /// 
  /// Returns the result of the operation if successful
  /// Throws [CircuitBreakerOpenException] if circuit is open
  /// Propagates the original exception if operation fails
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check if we should transition from open to half-open
    _updateStateIfNeeded();
    
    // Fail fast if circuit is open
    if (_state == CircuitState.open) {
      throw const CircuitBreakerOpenException();
    }
    
    try {
      final result = await operation();
      _recordSuccess();
      return result;
    } catch (error) {
      if (_shouldCountAsFailure(error)) {
        _recordFailure();
      }
      rethrow;
    }
  }

  /// Records a successful operation
  void recordSuccess() {
    _recordSuccess();
  }

  /// Records a failed operation
  void recordFailure() {
    _recordFailure();
  }

  /// Gets current circuit breaker status
  CircuitBreakerStatus getStatus() {
    _updateStateIfNeeded();
    
    DateTime? nextRetryTime;
    if (_state == CircuitState.open && _lastFailureTime != null) {
      nextRetryTime = _lastFailureTime!.add(timeout);
    }
    
    return CircuitBreakerStatus(
      state: _state,
      failureCount: _failureCount,
      successCount: _successCount,
      failureThreshold: failureThreshold,
      timeoutDuration: timeout,
      lastFailureTime: _lastFailureTime,
      nextRetryTime: nextRetryTime,
    );
  }

  /// Records a successful operation and updates circuit state
  void _recordSuccess() {
    _successCount++;
    
    if (_state == CircuitState.halfOpen) {
      // Successful operation in half-open state closes the circuit
      _state = CircuitState.closed;
      _failureCount = 0; // Reset failure count on recovery
    }
  }

  /// Records a failed operation and updates circuit state
  void _recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_state == CircuitState.halfOpen) {
      // Failure in half-open state reopens the circuit immediately
      _state = CircuitState.open;
    } else if (_state == CircuitState.closed && _failureCount >= failureThreshold) {
      // Threshold exceeded, open the circuit
      _state = CircuitState.open;
    }
  }

  /// Updates circuit state based on timeout if needed
  void _updateStateIfNeeded() {
    if (_state == CircuitState.open && _lastFailureTime != null) {
      final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceLastFailure >= timeout) {
        _state = CircuitState.halfOpen;
      }
    }
  }

  /// Default function to determine if an error should count as failure
  /// 
  /// For circuit breaker purposes, we want to count retryable errors as failures
  /// since repeated retryable failures indicate a systemic issue that needs circuit protection.
  bool _defaultShouldCountAsFailure(dynamic error) {
    // Circuit breakers should count retryable errors as failures
    // This is opposite to retry logic - we want to break the circuit
    // when we see repeated network issues
    return NoaaErrorClassifier.isRetryableError(error);
  }
}