/// Sequential FIFO queue for chart loading operations (Phase 4)
/// Ensures one chart loads at a time with position tracking and deduplication
library;

import 'dart:async';
import 'dart:collection';

import 'package:navtool/features/charts/services/chart_loading_service.dart';

/// Entry in the chart loading queue
class ChartQueueEntry {
  final String chartId;
  final Completer<ChartLoadResult> _completer;
  int _position;

  ChartQueueEntry(this.chartId, this._position)
      : _completer = Completer<ChartLoadResult>();

  /// Queue position (0 = currently processing)
  int get position => _position;

  /// Future that completes when chart finishes loading
  Future<ChartLoadResult> get future => _completer.future;

  /// Update position as queue advances
  void _updatePosition(int newPosition) {
    _position = newPosition;
  }

  /// Complete with result
  void _complete(ChartLoadResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  /// Complete with error
  void _completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}

/// Queue status snapshot
class ChartLoadingQueueStatus {
  final String? currentChartId;
  final int queueLength;
  final List<String> pendingChartIds;
  final bool isProcessing;

  const ChartLoadingQueueStatus({
    required this.currentChartId,
    required this.queueLength,
    required this.pendingChartIds,
    required this.isProcessing,
  });
}

/// FIFO queue for sequential chart loading
class ChartLoadingQueue {
  final ChartLoadingService loadingService;
  final Queue<ChartQueueEntry> _queue = Queue<ChartQueueEntry>();
  final Map<String, ChartQueueEntry> _entryMap = {};
  ChartQueueEntry? _currentEntry;
  bool _isProcessing = false;
  bool _isDisposed = false;

  ChartLoadingQueue({required this.loadingService});

  /// Number of charts in queue (including currently processing)
  int get length => _queue.length;

  /// Whether queue is currently processing a chart
  bool get isProcessing => _isProcessing;

  /// Chart ID currently being processed (null if idle)
  String? get currentChartId => _currentEntry?.chartId;

  /// Check if chart is in queue
  bool contains(String chartId) => _entryMap.containsKey(chartId);

  /// Enqueue a chart for loading
  /// Returns entry for tracking position and awaiting completion
  /// Deduplicates: returns existing entry if chart already queued
  ChartQueueEntry enqueue(String chartId) {
    if (_isDisposed) {
      throw StateError('Cannot enqueue after dispose');
    }

    // Deduplicate: return existing entry if chart already in queue
    if (_entryMap.containsKey(chartId)) {
      return _entryMap[chartId]!;
    }

    // Create new entry
    final position = _queue.length;
    final entry = ChartQueueEntry(chartId, position);
    
    _queue.add(entry);
    _entryMap[chartId] = entry;

    // Start processing if idle
    if (!_isProcessing) {
      _startProcessing();
    }

    return entry;
  }

  /// Cancel a pending chart (not currently processing)
  void cancel(String chartId) {
    final entry = _entryMap[chartId];
    if (entry == null) return;

    // Can't cancel currently processing chart
    if (entry == _currentEntry) return;

    // Remove from queue and map
    _queue.remove(entry);
    _entryMap.remove(chartId);

    // Update positions
    _updatePositions();

    // Complete with cancellation error
    entry._completeError(
      StateError('Chart load cancelled'),
      StackTrace.current,
    );
  }

  /// Clear all pending charts (keep current processing)
  void clear() {
    // Cancel all except current
    final toCancel = _queue.where((e) => e != _currentEntry).toList();
    for (final entry in toCancel) {
      _queue.remove(entry);
      _entryMap.remove(entry.chartId);
      entry._completeError(
        StateError('Queue cleared'),
        StackTrace.current,
      );
    }

    // Update positions
    _updatePositions();
  }

  /// Get current queue status
  ChartLoadingQueueStatus getStatus() {
    final pendingIds = _queue
        .where((e) => e != _currentEntry)
        .map((e) => e.chartId)
        .toList();

    return ChartLoadingQueueStatus(
      currentChartId: _currentEntry?.chartId,
      queueLength: _queue.length,
      pendingChartIds: pendingIds,
      isProcessing: _isProcessing,
    );
  }

  /// Dispose queue (cancels pending charts)
  void dispose() {
    _isDisposed = true;
    clear();
    _queue.clear();
    _entryMap.clear();
    _currentEntry = null;
    _isProcessing = false;
  }

  /// Start processing queue
  Future<void> _startProcessing() async {
    if (_isProcessing) return;

    _isProcessing = true;

    while (!_isDisposed) {
      // Check if queue is empty
      if (_queue.isEmpty) {
        break;
      }

      // Get next entry
      final entry = _queue.first;
      _currentEntry = entry;
      final chartId = entry.chartId;

      try {
        // Load chart via service
        final result = await loadingService.loadChart(chartId);

        // Complete entry with result (if not already completed by cancel/clear)
        if (!entry._completer.isCompleted) {
          entry._complete(result);
        }
      } catch (e, stackTrace) {
        // Complete with error (if not already completed by cancel/clear)
        if (!entry._completer.isCompleted) {
          entry._completeError(e, stackTrace);
        }
      } finally {
        // Remove completed entry (check if still first)
        if (_queue.isNotEmpty && _queue.first == entry) {
          _queue.removeFirst();
          _entryMap.remove(chartId);
        }
        _currentEntry = null;

        // Update positions for remaining entries
        _updatePositions();
      }
    }

    _isProcessing = false;
  }

  /// Update positions after queue changes
  void _updatePositions() {
    int position = 0;
    for (final entry in _queue) {
      entry._updatePosition(position);
      position++;
    }
  }
}
