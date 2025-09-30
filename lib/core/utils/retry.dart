/// Simple exponential backoff retry helper for transient operations.
/// Not tightly coupled to Futures that throw; caller orchestrates attempts.
class RetryBackoff {
  final int maxAttempts;
  final Duration baseDelay; // initial delay
  final Duration maxDelay;

  const RetryBackoff({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 15),
  });

  /// Compute delay for attempt number (1-based).
  Duration delayFor(int attempt) {
    if (attempt <= 1) return baseDelay;
    final ms = baseDelay.inMilliseconds * (1 << (attempt - 1));
    final capped = ms > maxDelay.inMilliseconds ? maxDelay.inMilliseconds : ms;
    return Duration(milliseconds: capped);
  }
}