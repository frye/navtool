import 'dart:collection';
import '../utils/priority_rate_limiter.dart';

/// Individual priority metrics
class PriorityMetrics {
  PriorityMetrics({
    this.totalRequests = 0,
    this.rejectedRequests = 0,
    this.totalWaitTime = Duration.zero,
    this.waitTimeCount = 0,
  });

  int totalRequests;
  int rejectedRequests;
  Duration totalWaitTime;
  int waitTimeCount;

  int get acceptedRequests => totalRequests - rejectedRequests;
  double get successRate => totalRequests > 0 ? acceptedRequests / totalRequests : 1.0;
  Duration get averageWaitTime => waitTimeCount > 0 
      ? Duration(microseconds: totalWaitTime.inMicroseconds ~/ waitTimeCount)
      : Duration.zero;

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'acceptedRequests': acceptedRequests,
    'rejectedRequests': rejectedRequests,
    'successRate': successRate,
    'averageWaitTimeMs': averageWaitTime.inMilliseconds,
    'totalWaitTimeMs': totalWaitTime.inMilliseconds,
    'waitTimeCount': waitTimeCount,
  };

  void reset() {
    totalRequests = 0;
    rejectedRequests = 0;
    totalWaitTime = Duration.zero;
    waitTimeCount = 0;
  }
}

/// Metrics report containing comprehensive rate limiting statistics
class MetricsReport {
  const MetricsReport(this._data);
  
  final Map<String, dynamic> _data;
  
  int get totalRequests => _data['totalRequests'] ?? 0;
  double get successRate => _data['successRate'] ?? 1.0;
  Duration get averageWaitTime => Duration(milliseconds: _data['averageWaitTimeMs'] ?? 0);
  Map<String, dynamic> get priorityBreakdown => _data['priorityBreakdown'] ?? {};
  
  bool containsKey(String key) => _data.containsKey(key);
  dynamic operator [](String key) => _data[key];
}

/// Comprehensive rate limiting metrics collection and analysis
/// 
/// Tracks detailed statistics for rate limiter performance including
/// request counts, wait times, success rates, and priority-specific metrics.
/// Provides insights for optimization and monitoring.
class RateLimitMetrics {
  /// Creates metrics collector with specified measurement window
  RateLimitMetrics({
    this.measurementWindow = const Duration(seconds: 60),
  });

  /// Time window for rate calculation
  final Duration measurementWindow;

  /// Total request counters
  int _totalRequests = 0;
  int _rejectedRequests = 0;

  /// Wait time tracking
  Duration _totalWaitTime = Duration.zero;
  int _waitTimeCount = 0;

  /// Request timestamps for rate calculation
  final Queue<DateTime> _requestTimestamps = Queue<DateTime>();

  /// Priority-specific metrics
  final Map<RequestPriority, PriorityMetrics> _priorityMetrics = {
    RequestPriority.critical: PriorityMetrics(),
    RequestPriority.high: PriorityMetrics(),
    RequestPriority.normal: PriorityMetrics(),
    RequestPriority.low: PriorityMetrics(),
  };

  /// Total number of requests recorded
  int get totalRequests => _totalRequests;

  /// Number of rejected requests
  int get rejectedRequests => _rejectedRequests;

  /// Number of accepted requests
  int get acceptedRequests => _totalRequests - _rejectedRequests;

  /// Success rate (0.0 to 1.0)
  double get successRate => _totalRequests > 0 ? acceptedRequests / _totalRequests : 1.0;

  /// Current request rate within measurement window
  double get currentRequestRate {
    _cleanupOldTimestamps();
    if (_requestTimestamps.isEmpty) return 0.0;
    
    final windowSeconds = measurementWindow.inMilliseconds / 1000.0;
    return _requestTimestamps.length / windowSeconds;
  }

  /// Average wait time across all requests
  Duration get averageWaitTime => _waitTimeCount > 0 
      ? Duration(microseconds: _totalWaitTime.inMicroseconds ~/ _waitTimeCount)
      : Duration.zero;

  /// Total accumulated wait time
  Duration get totalWaitTime => _totalWaitTime;

  /// Number of wait time measurements
  int get waitTimeCount => _waitTimeCount;

  /// Records a request attempt
  /// 
  /// [accepted] Whether the request was accepted or rejected
  void recordRequest({required bool accepted}) {
    _totalRequests++;
    if (!accepted) {
      _rejectedRequests++;
    } else {
      _requestTimestamps.add(DateTime.now());
    }
    _cleanupOldTimestamps();
  }

  /// Records a priority-specific request attempt
  /// 
  /// [priority] The priority level of the request
  /// [accepted] Whether the request was accepted or rejected
  void recordPriorityRequest(RequestPriority priority, {required bool accepted}) {
    final metrics = _priorityMetrics[priority]!;
    metrics.totalRequests++;
    if (!accepted) {
      metrics.rejectedRequests++;
    }
    
    // Also record in overall metrics
    recordRequest(accepted: accepted);
  }

  /// Records wait time for a request
  /// 
  /// [waitTime] How long the request had to wait
  void recordWaitTime(Duration waitTime) {
    _totalWaitTime += waitTime;
    _waitTimeCount++;
  }

  /// Records priority-specific wait time
  /// 
  /// [priority] The priority level of the request
  /// [waitTime] How long the request had to wait
  void recordPriorityWaitTime(RequestPriority priority, Duration waitTime) {
    final metrics = _priorityMetrics[priority]!;
    metrics.totalWaitTime += waitTime;
    metrics.waitTimeCount++;
    
    // Also record in overall metrics
    recordWaitTime(waitTime);
  }

  /// Gets metrics for specific priority level
  PriorityMetrics getPriorityMetrics(RequestPriority priority) {
    return _priorityMetrics[priority]!;
  }

  /// Gets number of requests in current measurement window
  int getRequestsInWindow() {
    _cleanupOldTimestamps();
    return _requestTimestamps.length;
  }

  /// Generates comprehensive metrics report
  MetricsReport generateReport() {
    _cleanupOldTimestamps();
    
    final priorityBreakdown = <String, Map<String, dynamic>>{};
    for (final entry in _priorityMetrics.entries) {
      priorityBreakdown[entry.key.name] = entry.value.toJson();
    }
    
    final data = {
      'totalRequests': totalRequests,
      'acceptedRequests': acceptedRequests,
      'rejectedRequests': rejectedRequests,
      'successRate': successRate,
      'currentRequestRate': currentRequestRate,
      'averageWaitTimeMs': averageWaitTime.inMilliseconds,
      'totalWaitTimeMs': totalWaitTime.inMilliseconds,
      'waitTimeCount': waitTimeCount,
      'requestsInWindow': getRequestsInWindow(),
      'measurementWindowMs': measurementWindow.inMilliseconds,
      'priorityBreakdown': priorityBreakdown,
    };
    
    return MetricsReport(data);
  }

  /// Exports metrics as JSON
  Map<String, dynamic> toJson() {
    final report = generateReport();
    return report._data;
  }

  /// Resets all metrics to initial state
  void reset() {
    _totalRequests = 0;
    _rejectedRequests = 0;
    _totalWaitTime = Duration.zero;
    _waitTimeCount = 0;
    _requestTimestamps.clear();
    
    for (final metrics in _priorityMetrics.values) {
      metrics.reset();
    }
  }

  /// Removes request timestamps that have fallen out of measurement window
  void _cleanupOldTimestamps() {
    final now = DateTime.now();
    final cutoff = now.subtract(measurementWindow);
    
    while (_requestTimestamps.isNotEmpty && 
           _requestTimestamps.first.isBefore(cutoff)) {
      _requestTimestamps.removeFirst();
    }
  }
}