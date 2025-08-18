import 'dart:collection';
import 'rate_limiter.dart';

/// Request priority levels for priority-based rate limiting
enum RequestPriority { 
  critical, 
  high, 
  normal, 
  low 
}

/// Status information for priority-specific metrics
class PriorityStatus {
  const PriorityStatus({
    required this.criticalRequestsInWindow,
    required this.highRequestsInWindow,
    required this.normalRequestsInWindow,
    required this.lowRequestsInWindow,
  });

  final int criticalRequestsInWindow;
  final int highRequestsInWindow;
  final int normalRequestsInWindow;
  final int lowRequestsInWindow;
  
  int get totalRequestsInWindow => 
      criticalRequestsInWindow + highRequestsInWindow + 
      normalRequestsInWindow + lowRequestsInWindow;
}

/// Queue status information for priority-based queues
class QueueStatus {
  const QueueStatus({
    required this.criticalQueueLength,
    required this.highQueueLength,
    required this.normalQueueLength,
    required this.lowQueueLength,
  });

  final int criticalQueueLength;
  final int highQueueLength;
  final int normalQueueLength;
  final int lowQueueLength;
  
  int get totalQueueLength => 
      criticalQueueLength + highQueueLength + 
      normalQueueLength + lowQueueLength;
}

/// Priority-aware rate limiter that extends basic rate limiting
/// 
/// Provides priority-based request handling where higher priority
/// requests are processed first. Supports capacity reservation
/// for critical requests and detailed priority metrics.
class PriorityRateLimiter extends RateLimiter {
  /// Creates a priority rate limiter with specified configuration
  PriorityRateLimiter({
    super.requestsPerSecond,
    super.windowSize,
  });

  /// Priority-based request queues
  final Map<RequestPriority, Queue<_PriorityRequest>> _priorityQueues = {
    RequestPriority.critical: Queue<_PriorityRequest>(),
    RequestPriority.high: Queue<_PriorityRequest>(),
    RequestPriority.normal: Queue<_PriorityRequest>(),
    RequestPriority.low: Queue<_PriorityRequest>(),
  };

  /// Reserved capacity for each priority level
  final Map<RequestPriority, int> _reservedCapacity = {
    RequestPriority.critical: 0,
    RequestPriority.high: 0,
    RequestPriority.normal: 0,
    RequestPriority.low: 0,
  };

  /// Track requests by priority for metrics
  final Queue<_TimestampedPriorityRequest> _priorityRequestTimes = Queue();

  /// Acquires permission to make a request with specified priority
  /// 
  /// Higher priority requests are processed before lower priority ones.
  /// Blocks until request can be made within rate limits and priority order.
  Future<void> acquireWithPriority(RequestPriority priority) async {
    final request = _PriorityRequest(priority);
    _priorityQueues[priority]!.add(request);
    
    try {
      // Wait for our turn based on priority
      while (!_canProcessRequest(priority, request)) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      // Remove from queue now that we can process
      _priorityQueues[priority]!.remove(request);
      
      // Wait for rate limit if needed
      while (!canMakeRequest(priority: priority)) {
        final waitTime = getWaitTime(priority: priority);
        if (waitTime > Duration.zero) {
          await Future.delayed(waitTime);
        }
      }
      
      // Record the request
      final now = DateTime.now();
      super.requestTimes.add(now);
      _priorityRequestTimes.add(_TimestampedPriorityRequest(priority, now));
      super.cleanupOldRequests();
      _cleanupOldPriorityRequests();
      
      request.complete();
    } catch (e) {
      // Ensure request is removed from queue on error
      _priorityQueues[priority]!.remove(request);
      rethrow;
    }
  }

  /// Checks if a request can be made with specified priority
  /// 
  /// Considers both rate limits and priority-based capacity reservation.
  @override
  bool canMakeRequest({RequestPriority? priority}) {
    super.cleanupOldRequests();
    _cleanupOldPriorityRequests();
    
    if (priority == null) {
      return super.canMakeRequest();
    }
    
    final availableCapacity = getAvailableCapacity(priority);
    return availableCapacity > 0;
  }

  /// Calculates wait time for requests with specified priority
  /// 
  /// Higher priority requests may have shorter wait times.
  @override
  Duration getWaitTime({RequestPriority? priority}) {
    if (priority == null) {
      return super.getWaitTime();
    }
    
    super.cleanupOldRequests();
    _cleanupOldPriorityRequests();
    
    if (canMakeRequest(priority: priority)) {
      return Duration.zero;
    }
    
    // Calculate wait time considering priority queue position
    final queuePosition = _getQueuePosition(priority);
    final baseWaitTime = super.getWaitTime();
    
    // Higher priority requests wait less time
    final priorityMultiplier = _getPriorityMultiplier(priority);
    final adjustedWait = Duration(
      milliseconds: (baseWaitTime.inMilliseconds * priorityMultiplier).round(),
    );
    
    // Add queue delay based on position
    final queueDelay = Duration(milliseconds: queuePosition * 100);
    
    return adjustedWait + queueDelay;
  }

  /// Reserves capacity for specific priority level
  /// 
  /// Prevents lower priority requests from using reserved capacity.
  /// [priority] The priority level to reserve capacity for
  /// [requests] Number of requests to reserve (must not exceed total capacity)
  void reserveCapacity(RequestPriority priority, int requests) {
    if (requests < 0) {
      throw ArgumentError('Reserved requests must be non-negative');
    }
    
    final totalReserved = _reservedCapacity.values.fold(0, (sum, val) => sum + val);
    final newTotal = totalReserved - _reservedCapacity[priority]! + requests;
    
    if (newTotal > requestsPerSecond) {
      throw ArgumentError('Cannot reserve more capacity than total limit');
    }
    
    _reservedCapacity[priority] = requests;
  }

  /// Gets available capacity for specified priority level
  /// 
  /// Considers both current usage and reserved capacity.
  int getAvailableCapacity(RequestPriority priority) {
    super.cleanupOldRequests();
    _cleanupOldPriorityRequests();
    
    final currentRequests = super.requestTimes.length;
    final totalCapacity = requestsPerSecond;
    
    // For now, simplified logic - reserved capacity subtracts from total
    int reservedByOthers = 0;
    for (final entry in _reservedCapacity.entries) {
      if (entry.key != priority) {
        reservedByOthers += entry.value;
      }
    }
    
    final availableToThisPriority = totalCapacity - reservedByOthers;
    final remainingCapacity = availableToThisPriority - currentRequests;
    
    return remainingCapacity > 0 ? remainingCapacity : 0;
  }

  /// Gets priority-specific status information
  PriorityStatus getPriorityStatus() {
    _cleanupOldPriorityRequests();
    
    final counts = <RequestPriority, int>{
      RequestPriority.critical: 0,
      RequestPriority.high: 0,
      RequestPriority.normal: 0,
      RequestPriority.low: 0,
    };
    
    for (final request in _priorityRequestTimes) {
      counts[request.priority] = counts[request.priority]! + 1;
    }
    
    return PriorityStatus(
      criticalRequestsInWindow: counts[RequestPriority.critical]!,
      highRequestsInWindow: counts[RequestPriority.high]!,
      normalRequestsInWindow: counts[RequestPriority.normal]!,
      lowRequestsInWindow: counts[RequestPriority.low]!,
    );
  }

  /// Gets current queue status for all priority levels
  QueueStatus getQueueStatus() {
    return QueueStatus(
      criticalQueueLength: _priorityQueues[RequestPriority.critical]!.length,
      highQueueLength: _priorityQueues[RequestPriority.high]!.length,
      normalQueueLength: _priorityQueues[RequestPriority.normal]!.length,
      lowQueueLength: _priorityQueues[RequestPriority.low]!.length,
    );
  }

  /// Checks if a specific request can be processed based on priority order
  bool _canProcessRequest(RequestPriority priority, _PriorityRequest request) {
    // Check if any higher priority requests are waiting
    for (final p in RequestPriority.values) {
      if (_getPriorityValue(p) > _getPriorityValue(priority)) {
        if (_priorityQueues[p]!.isNotEmpty) {
          return false; // Higher priority request is waiting
        }
      }
    }
    
    // Check if this is the first request in its priority queue
    final queue = _priorityQueues[priority]!;
    return queue.isNotEmpty && queue.first == request;
  }

  /// Gets the position of priority requests in the overall queue
  int _getQueuePosition(RequestPriority priority) {
    int position = 0;
    
    // Count higher priority requests first
    for (final p in RequestPriority.values) {
      if (_getPriorityValue(p) > _getPriorityValue(priority)) {
        position += _priorityQueues[p]!.length;
      }
      if (p == priority) break;
    }
    
    return position;
  }

  /// Gets numeric value for priority comparison (higher = more important)
  int _getPriorityValue(RequestPriority priority) {
    switch (priority) {
      case RequestPriority.critical: return 4;
      case RequestPriority.high: return 3;
      case RequestPriority.normal: return 2;
      case RequestPriority.low: return 1;
    }
  }

  /// Gets priority-based wait time multiplier
  double _getPriorityMultiplier(RequestPriority priority) {
    switch (priority) {
      case RequestPriority.critical: return 0.25; // Wait 1/4 as long
      case RequestPriority.high: return 0.5;      // Wait 1/2 as long
      case RequestPriority.normal: return 1.0;    // Wait normal time
      case RequestPriority.low: return 1.5;       // Wait 1.5x as long
    }
  }

  /// Removes old priority request timestamps that have fallen out of window
  void _cleanupOldPriorityRequests() {
    final now = DateTime.now();
    final cutoff = now.subtract(windowSize);
    
    while (_priorityRequestTimes.isNotEmpty && 
           _priorityRequestTimes.first.timestamp.isBefore(cutoff)) {
      _priorityRequestTimes.removeFirst();
    }
  }
}

/// Internal class representing a priority request
class _PriorityRequest {
  _PriorityRequest(this.priority);
  
  final RequestPriority priority;
  bool _completed = false;
  
  void complete() => _completed = true;
  bool get isCompleted => _completed;
}

/// Internal class for tracking timestamped priority requests
class _TimestampedPriorityRequest {
  const _TimestampedPriorityRequest(this.priority, this.timestamp);
  
  final RequestPriority priority;
  final DateTime timestamp;
}