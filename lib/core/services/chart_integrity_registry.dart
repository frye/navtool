// Simple in-memory registry of expected ENC dataset hashes (Phase 1)
// Future: persist to storage or fetch from authoritative manifest.
import 'dart:collection';

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

  void seed(Map<String, String> entries) {
  entries.forEach((id, hash) => _records[id] = ChartIntegrityRecord(chartId: id, expectedSha256: hash));
  }

  void upsert(String chartId, String expectedSha256) {
    _records[chartId] = ChartIntegrityRecord(chartId: chartId, expectedSha256: expectedSha256);
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
