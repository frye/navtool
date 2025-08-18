import 'dart:collection';
import 'package:meta/meta.dart';

/// Status information for the rate limiter
class RateLimitStatus {
  const RateLimitStatus({
    required this.requestsInWindow,
    required this.requestsPerSecond,
    required this.windowStart,
    this.nextAvailableTime,
  });

  /// Number of requests in the current window
  final int requestsInWindow;
  
  /// Maximum requests per second allowed
  final int requestsPerSecond;
  
  /// When the current window started
  final DateTime windowStart;
  
  /// When the next request can be made (null if available now)
  final DateTime? nextAvailableTime;
  
  /// Whether the rate limit is currently at maximum capacity
  bool get isAtLimit => requestsInWindow >= requestsPerSecond;
}

/// Core rate limiter implementation using sliding window algorithm
/// 
/// Provides accurate rate limiting by tracking exact request timestamps
/// within a sliding time window. Prevents exceeding configured requests
/// per second while handling burst traffic gracefully.
class RateLimiter {
  /// Creates a rate limiter with specified configuration
  /// 
  /// [requestsPerSecond] must be positive
  /// [windowSize] must be positive duration
  RateLimiter({
    this.requestsPerSecond = 5,
    this.windowSize = const Duration(seconds: 1),
  }) {
    if (requestsPerSecond <= 0) {
      throw ArgumentError('requestsPerSecond must be positive');
    }
    if (windowSize <= Duration.zero) {
      throw ArgumentError('windowSize must be positive');
    }
  }

  /// Maximum requests allowed per second
  final int requestsPerSecond;
  
  /// Time window for rate limiting
  final Duration windowSize;
  
  /// Queue of request timestamps within the current window
  @protected
  final Queue<DateTime> requestTimes = Queue<DateTime>();

  /// Acquires permission to make a request
  /// 
  /// Blocks until a request can be made within rate limits.
  /// Uses sliding window algorithm for accurate timing.
  Future<void> acquire() async {
    while (!canMakeRequest()) {
      final waitTime = getWaitTime();
      if (waitTime > Duration.zero) {
        await Future.delayed(waitTime);
      }
    }
    
    // Record the request
    requestTimes.add(DateTime.now());
    cleanupOldRequests();
  }

  /// Checks if a request can be made immediately
  /// 
  /// Returns true if within rate limits, false otherwise.
  bool canMakeRequest() {
    cleanupOldRequests();
    return requestTimes.length < requestsPerSecond;
  }

  /// Calculates time to wait before next request can be made
  /// 
  /// Returns Duration.zero if request can be made immediately.
  Duration getWaitTime() {
    cleanupOldRequests();
    
    if (requestTimes.length < requestsPerSecond) {
      return Duration.zero;
    }
    
    // Need to wait for the oldest request to fall out of window
    final oldestRequest = requestTimes.first;
    final windowEnd = oldestRequest.add(windowSize);
    final now = DateTime.now();
    
    if (windowEnd.isAfter(now)) {
      return windowEnd.difference(now);
    }
    
    return Duration.zero;
  }

  /// Gets current rate limiter status
  /// 
  /// Provides detailed information about current state including
  /// requests in window, capacity, and next available time.
  RateLimitStatus getStatus() {
    cleanupOldRequests();
    
    final now = DateTime.now();
    final windowStart = requestTimes.isEmpty 
        ? now
        : requestTimes.first;
    
    DateTime? nextAvailableTime;
    if (requestTimes.length >= requestsPerSecond) {
      final oldestRequest = requestTimes.first;
      nextAvailableTime = oldestRequest.add(windowSize);
    }
    
    return RateLimitStatus(
      requestsInWindow: requestTimes.length,
      requestsPerSecond: requestsPerSecond,
      windowStart: windowStart,
      nextAvailableTime: nextAvailableTime,
    );
  }

  /// Removes request timestamps that have fallen out of the window
  @protected
  void cleanupOldRequests() {
    final now = DateTime.now();
    final cutoff = now.subtract(windowSize);
    
    while (requestTimes.isNotEmpty && requestTimes.first.isBefore(cutoff)) {
      requestTimes.removeFirst();
    }
  }
}