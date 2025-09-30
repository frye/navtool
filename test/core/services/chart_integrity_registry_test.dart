/// TDD Test Suite for ChartIntegrityRegistry Persistence (T005)
/// Tests MUST FAIL until T018 implementation is complete.
///
/// Requirements Coverage:
/// - FR-002: Maintain registry of expected integrity hashes
/// - FR-002a: First-load capture and persist hash
/// - FR-003: Detect integrity mismatch
/// - R05: Persist first-load hashes
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/chart_integrity_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ChartIntegrityRegistry Legacy Tests (Keep Passing)', () {
    test('ChartIntegrityRegistry seed and compare', () {
      final reg = ChartIntegrityRegistry();
      reg.seed({'US5WA50M': 'DEADBEEF'});

      final match = reg.compare('US5WA50M', 'DEADBEEF');
      expect(match, isNull);

      final mismatch = reg.compare('US5WA50M', 'CAFEBABE');
      expect(mismatch, isNotNull);
      expect(mismatch!.chartId, 'US5WA50M');
    });
  });

  group('ChartIntegrityRegistry Persistence Tests (T005 - MUST FAIL)', () {
    late ChartIntegrityRegistry registry;

    setUp(() async {
      // Reset SharedPreferences for each test
      SharedPreferences.setMockInitialValues({});
      registry = ChartIntegrityRegistry();
      // Clear singleton state - WILL FAIL (method doesn't exist yet)
      await registry.clear();
    });

    test('T005.1: First-load capture stores hash in SharedPreferences', () async {
      // ARRANGE: Chart ID with no existing hash
      const chartId = 'US5WA50M';
      const computedHash = 'abc123def456';

      // ACT: Capture first-load hash - WILL FAIL (method doesn't exist yet)
      await registry.captureFirstLoad(chartId, computedHash);

      // ASSERT: Hash stored in registry
      final record = registry.get(chartId);
      expect(record, isNotNull, reason: 'Should store hash record');
      expect(record!.expectedSha256, equals(computedHash),
          reason: 'Should store correct hash value');

      // ASSERT: Hash persisted to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final persistedHash = prefs.getString('chart_integrity_$chartId');
      expect(persistedHash, equals(computedHash),
          reason: 'Should persist hash to SharedPreferences');
    });

    test('T005.2: Load persisted hashes on initialization', () async {
      // ARRANGE: Pre-populate SharedPreferences with chart hashes
      SharedPreferences.setMockInitialValues({
        'chart_integrity_US5WA50M': 'hash_us5wa50m',
        'chart_integrity_US3WA01M': 'hash_us3wa01m',
      });

      // ACT: Create new registry instance - WILL FAIL (initialize method doesn't exist)
      final newRegistry = ChartIntegrityRegistry();
      await newRegistry.initialize();

      // ASSERT: Should load both hashes
      expect(newRegistry.get('US5WA50M'), isNotNull,
          reason: 'Should load US5WA50M hash from SharedPreferences');
      expect(newRegistry.get('US5WA50M')!.expectedSha256, equals('hash_us5wa50m'));
      
      expect(newRegistry.get('US3WA01M'), isNotNull,
          reason: 'Should load US3WA01M hash from SharedPreferences');
      expect(newRegistry.get('US3WA01M')!.expectedSha256, equals('hash_us3wa01m'));
    });

    test('T005.3: Update existing hash persists to SharedPreferences', () async {
      // ARRANGE: Chart with existing hash
      const chartId = 'US5WA50M';
      const originalHash = 'original_hash_123';
      const updatedHash = 'updated_hash_456';
      
      await registry.captureFirstLoad(chartId, originalHash);

      // ACT: Update hash - existing upsert should work, but persistence will fail
      registry.upsert(chartId, updatedHash);

      // ASSERT: Registry updated
      expect(registry.get(chartId)!.expectedSha256, equals(updatedHash));

      // ASSERT: SharedPreferences updated - WILL FAIL (upsert doesn't persist)
      final prefs = await SharedPreferences.getInstance();
      final persistedHash = prefs.getString('chart_integrity_$chartId');
      expect(persistedHash, equals(updatedHash),
          reason: 'Should persist updated hash to SharedPreferences');
    });

    test('T005.4: Compare returns null when no expectation exists (first load)', () {
      // ARRANGE: Chart ID with no stored hash
      const chartId = 'NEW_CHART';
      const computedHash = 'abc123';

      // ACT: Compare hash (existing method should work)
      final mismatch = registry.compare(chartId, computedHash);

      // ASSERT: Should return null (no expectation, not a mismatch)
      expect(mismatch, isNull,
          reason: 'Should return null for first load (no prior hash)');
    });

    test('T005.5: Compare returns null when hashes match', () async {
      // ARRANGE: Chart with stored hash
      const chartId = 'US5WA50M';
      const expectedHash = 'matching_hash_123';
      
      await registry.captureFirstLoad(chartId, expectedHash);

      // ACT: Compare with matching hash
      final mismatch = registry.compare(chartId, expectedHash);

      // ASSERT: Should return null (match)
      expect(mismatch, isNull, reason: 'Should return null when hashes match');
    });

    test('T005.6: Compare returns IntegrityMismatch when hashes differ', () async {
      // ARRANGE: Chart with stored hash
      const chartId = 'US5WA50M';
      const expectedHash = 'expected_hash_abc';
      const computedHash = 'different_hash_xyz';
      
      await registry.captureFirstLoad(chartId, expectedHash);

      // ACT: Compare with different hash
      final mismatch = registry.compare(chartId, computedHash);

      // ASSERT: Should return mismatch details
      expect(mismatch, isNotNull, reason: 'Should detect hash mismatch');
      expect(mismatch!.chartId, equals(chartId));
      expect(mismatch.expected, equals(expectedHash));
      expect(mismatch.actual, equals(computedHash));
    });

    test('T005.7: Case-insensitive hash comparison', () async {
      // ARRANGE: Chart with lowercase hash
      const chartId = 'US5WA50M';
      const expectedHash = 'abc123def456';  // lowercase
      const computedHash = 'ABC123DEF456';  // uppercase
      
      await registry.captureFirstLoad(chartId, expectedHash);

      // ACT: Compare with uppercase hash
      final mismatch = registry.compare(chartId, computedHash);

      // ASSERT: Should consider them equal (case-insensitive)
      expect(mismatch, isNull,
          reason: 'Should perform case-insensitive hash comparison');
    });

    test('T005.8: Clear removes all persisted hashes', () async {
      // ARRANGE: Multiple charts with stored hashes
      await registry.captureFirstLoad('US5WA50M', 'hash1');
      await registry.captureFirstLoad('US3WA01M', 'hash2');
      await registry.captureFirstLoad('US4CA09M', 'hash3');

      // ACT: Clear registry - WILL FAIL (clear method doesn't exist)
      await registry.clear();

      // ASSERT: Registry empty
      expect(registry.get('US5WA50M'), isNull);
      expect(registry.get('US3WA01M'), isNull);
      expect(registry.get('US4CA09M'), isNull);

      // ASSERT: SharedPreferences cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chart_integrity_US5WA50M'), isNull);
      expect(prefs.getString('chart_integrity_US3WA01M'), isNull);
      expect(prefs.getString('chart_integrity_US4CA09M'), isNull);
    });
  });

  group('ChartIntegrityRegistry Edge Cases (T005 Extended)', () {
    late ChartIntegrityRegistry registry;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      registry = ChartIntegrityRegistry();
      await registry.clear();  // WILL FAIL
    });

    test('T005.9: Handle empty SharedPreferences gracefully', () async {
      // ARRANGE: Completely empty SharedPreferences
      SharedPreferences.setMockInitialValues({});

      // ACT: Initialize registry
      final newRegistry = ChartIntegrityRegistry();
      await newRegistry.initialize();

      // ASSERT: Should not throw, registry empty
      expect(newRegistry.get('US5WA50M'), isNull);
    });

    test('T005.10: Handle corrupted SharedPreferences data gracefully', () async {
      // ARRANGE: Invalid data in SharedPreferences
      SharedPreferences.setMockInitialValues({
        'chart_integrity_US5WA50M': 12345,  // Not a string!
      });

      // ACT: Initialize registry (should handle gracefully)
      final newRegistry = ChartIntegrityRegistry();
      
      // ASSERT: Should not throw
      expect(() async => await newRegistry.initialize(), returnsNormally,
          reason: 'Should handle corrupted SharedPreferences gracefully');
    });
  });
}
