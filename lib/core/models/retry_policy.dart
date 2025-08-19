/// Configuration for retry behavior with exponential backoff
/// 
/// Defines how retries should be handled for different types of operations
/// in marine environments where network conditions can be challenging.
class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(minutes: 2),
    this.useJitter = true,
    this.jitterRange = 0.1,
  });

  /// Maximum number of retry attempts
  final int maxRetries;
  
  /// Initial delay before first retry
  final Duration initialDelay;
  
  /// Multiplier for exponential backoff (e.g., 2.0 doubles delay each time)
  final double backoffMultiplier;
  
  /// Maximum delay between retries (prevents extremely long waits)
  final Duration maxDelay;
  
  /// Whether to add random jitter to prevent thundering herd
  final bool useJitter;
  
  /// Range of jitter as percentage (0.1 = ±10%)
  final double jitterRange;

  /// Calculates delay for a specific retry attempt
  /// 
  /// [attempt] The retry attempt number (0-based)
  /// Returns the calculated delay with optional jitter
  Duration calculateDelay(int attempt) {
    if (attempt < 0) {
      throw ArgumentError('Attempt must be non-negative');
    }
    
    if (attempt >= maxRetries) {
      throw ArgumentError('Attempt exceeds maximum retries');
    }
    
    // Calculate exponential backoff delay
    final baseDelay = Duration(
      milliseconds: (initialDelay.inMilliseconds * 
                    _pow(backoffMultiplier, attempt)).round(),
    );
    
    // Apply maximum delay limit
    final limitedDelay = baseDelay > maxDelay ? maxDelay : baseDelay;
    
    // Add jitter if enabled
    if (useJitter) {
      return _addJitter(limitedDelay);
    }
    
    return limitedDelay;
  }

  /// Predefined retry policy for chart downloads
  /// 
  /// Conservative policy suitable for large file downloads over
  /// potentially slow marine internet connections.
  static const RetryPolicy chartDownload = RetryPolicy(
    maxRetries: 3,
    initialDelay: Duration(seconds: 2),
    backoffMultiplier: 2.0,
    maxDelay: Duration(minutes: 5),
    useJitter: true,
    jitterRange: 0.15,
  );

  /// Predefined retry policy for API requests
  /// 
  /// More aggressive policy for smaller requests that should
  /// fail fast in marine environments.
  static const RetryPolicy apiRequest = RetryPolicy(
    maxRetries: 5,
    initialDelay: Duration(milliseconds: 500),
    backoffMultiplier: 1.5,
    maxDelay: Duration(seconds: 30),
    useJitter: true,
    jitterRange: 0.1,
  );

  /// Predefined retry policy for critical operations
  /// 
  /// More persistent policy for safety-critical marine operations
  /// that must eventually succeed.
  static const RetryPolicy critical = RetryPolicy(
    maxRetries: 7,
    initialDelay: Duration(seconds: 1),
    backoffMultiplier: 2.0,
    maxDelay: Duration(minutes: 10),
    useJitter: true,
    jitterRange: 0.2,
  );

  /// Calculates power without using dart:math
  double _pow(double base, int exponent) {
    if (exponent == 0) return 1.0;
    if (exponent == 1) return base;
    
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// Adds random jitter to delay to prevent thundering herd
  Duration _addJitter(Duration delay) {
    // Simple pseudo-random jitter using current time
    final now = DateTime.now();
    final seed = now.microsecondsSinceEpoch % 1000;
    final jitterMultiplier = 1.0 + (jitterRange * (seed / 500.0 - 1.0));
    
    final jitteredMilliseconds = (delay.inMilliseconds * jitterMultiplier).round();
    return Duration(milliseconds: jitteredMilliseconds);
  }

  @override
  String toString() {
    return 'RetryPolicy(maxRetries: $maxRetries, '
           'initialDelay: $initialDelay, '
           'backoffMultiplier: $backoffMultiplier, '
           'maxDelay: $maxDelay, '
           'useJitter: $useJitter)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RetryPolicy &&
           other.maxRetries == maxRetries &&
           other.initialDelay == initialDelay &&
           other.backoffMultiplier == backoffMultiplier &&
           other.maxDelay == maxDelay &&
           other.useJitter == useJitter &&
           other.jitterRange == jitterRange;
  }

  @override
  int get hashCode {
    return Object.hash(
      maxRetries,
      initialDelay,
      backoffMultiplier,
      maxDelay,
      useJitter,
      jitterRange,
    );
  }
}