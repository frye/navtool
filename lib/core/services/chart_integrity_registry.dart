// Chart integrity registry with SharedPreferences persistence (Phase 4)
// Maintains SHA256 hashes for chart verification with first-load capture
import 'dart:collection';
import 'package:shared_preferences/shared_preferences.dart';

class ChartIntegrityRecord {
  final String chartId;
  final String expectedSha256;
  final DateTime timestamp;
  ChartIntegrityRecord({required this.chartId, required this.expectedSha256, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class ChartIntegrityRegistry {
  static final ChartIntegrityRegistry _singleton = ChartIntegrityRegistry._internal();
  factory ChartIntegrityRegistry() => _singleton;
  ChartIntegrityRegistry._internal();

  final Map<String, ChartIntegrityRecord> _records = HashMap();
  static const String _keyPrefix = 'chart_integrity_';

  /// Initialize registry by loading persisted hashes from SharedPreferences
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_keyPrefix)) {
          final chartId = key.substring(_keyPrefix.length);
          final hash = prefs.getString(key);
          
          // Handle corrupted data gracefully
          if (hash is String && hash.isNotEmpty) {
            _records[chartId] = ChartIntegrityRecord(
              chartId: chartId,
              expectedSha256: hash,
            );
          }
        }
      }
    } catch (e) {
      // Gracefully handle SharedPreferences errors
      // In production, log error; in tests, continue
      print('[ChartIntegrityRegistry] Warning: Failed to initialize from SharedPreferences: $e');
    }
  }

  /// Capture first-load hash and persist to SharedPreferences
  Future<void> captureFirstLoad(String chartId, String hash) async {
    // Store in memory
    _records[chartId] = ChartIntegrityRecord(
      chartId: chartId,
      expectedSha256: hash,
    );
    
    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$chartId', hash);
    } catch (e) {
      print('[ChartIntegrityRegistry] Warning: Failed to persist hash for $chartId: $e');
      rethrow;
    }
  }

  /// Clear all stored hashes from memory and SharedPreferences
  Future<void> clear() async {
    // Clear in-memory records
    _records.clear();
    
    // Clear persisted hashes
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_keyPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      print('[ChartIntegrityRegistry] Warning: Failed to clear SharedPreferences: $e');
      rethrow;
    }
  }

  void seed(Map<String, String> entries) {
  entries.forEach((id, hash) => _records[id] = ChartIntegrityRecord(chartId: id, expectedSha256: hash));
  }

  Future<void> upsert(String chartId, String expectedSha256) async {
    _records[chartId] = ChartIntegrityRecord(chartId: chartId, expectedSha256: expectedSha256);
    
    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$chartId', expectedSha256);
    } catch (e) {
      print('[ChartIntegrityRegistry] Warning: Failed to persist hash for $chartId: $e');
    }
  }

  ChartIntegrityRecord? get(String chartId) => _records[chartId];

  /// Compare computed hash with expected; returns null if match or no expectation; else mismatch description
  IntegrityMismatch? compare(String chartId, String computedSha256) {
    final rec = _records[chartId];
    if (rec == null) return null; // No expectation set yet
    if (rec.expectedSha256.toLowerCase() == computedSha256.toLowerCase()) return null;
    return IntegrityMismatch(chartId: chartId, expected: rec.expectedSha256, actual: computedSha256);
  }
}

class IntegrityMismatch {
  final String chartId;
  final String expected;
  final String actual;
  const IntegrityMismatch({required this.chartId, required this.expected, required this.actual});

  Map<String, dynamic> toJson() => {
    'chartId': chartId,
    'expected': expected,
    'actual': actual,
  };
}
