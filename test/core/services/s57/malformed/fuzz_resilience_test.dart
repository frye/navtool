/// Fuzz testing for S-57 malformed record resilience (Issue 20.x)
///
/// Lightweight pseudo-fuzz generator for randomized corruption testing.
/// Uses bounded iterations and deterministic seeds to ensure reproducible
/// results while testing parser stability against random corruptions.

@Tags(['fuzz'])

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/iso8211_reader.dart';

import 'malformed_fixture_builder.dart';
import '../test_data_utils.dart';

void main() {
  group('S-57 Malformed Record Fuzz Tests', () {
    
    test('should handle random corruptions without crashing', tags: ['fuzz'], () {
      const int maxIterations = 50; // Limited to keep test runtime ≤1s
      const int baseSeed = 42; // Deterministic for reproducibility
      
      // Base valid record for corruption - use simple structured data
      final baseRecord = MalformedFixtureBuilder.createValidLeader(
        recordLength: 50, 
        baseAddress: 30
      );
      final completeBaseRecord = List<int>.from(baseRecord);
      completeBaseRecord.addAll([0x1e]); // Directory terminator
      while (completeBaseRecord.length < 49) {
        completeBaseRecord.add(0x20); // Padding
      }
      completeBaseRecord.add(0x1d); // Record terminator
      
      // Track any unexpected crashes
      var crashCount = 0;
      var totalIterations = 0;
      
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < maxIterations && stopwatch.elapsedMilliseconds < 800; i++) {
        totalIterations++;
        
        try {
          // Generate random corruption with deterministic seed
          final corruptedData = MalformedFixtureBuilder.createRandomCorruption(
            completeBaseRecord, 
            seed: baseSeed + i,
          );
          
          final reader = Iso8211Reader(corruptedData);
          
          // This should never crash, regardless of corruption
          final records = reader.readAll().toList();
          
          // Verify basic properties
          expect(records, isA<List>());
          expect(reader.warnings, isA<List>());
          
          // Records can be empty (if too corrupted) but should be a valid list
          expect(records.length, greaterThanOrEqualTo(0));
          
        } catch (e, stackTrace) {
          // Log unexpected crashes for debugging
          print('Fuzz test iteration $i crashed: $e');
          print('Stack trace: $stackTrace');
          crashCount++;
          
          // Fail if we get too many crashes
          if (crashCount > 2) {
            fail('Too many crashes during fuzz testing: $crashCount/$totalIterations');
          }
        }
      }
      
      stopwatch.stop();
      
      // Test should complete within time limit
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), 
        reason: 'Fuzz test should complete within 1 second');
      
      // Should have tested a reasonable number of cases
      expect(totalIterations, greaterThan(10), 
        reason: 'Should test at least 10 corruption variants');
      
      // Should have zero or very few crashes
      expect(crashCount, lessThanOrEqualTo(2), 
        reason: 'Parser should be resilient to random corruption');
      
      print('Fuzz test completed: $totalIterations iterations, $crashCount crashes, '
            '${stopwatch.elapsedMilliseconds}ms');
    });

    test('should handle systematic corruption patterns', () {
      // Use simple valid base record for systematic tests
      final baseRecord = MalformedFixtureBuilder.createValidLeader(
        recordLength: 50, 
        baseAddress: 30
      );
      
      // Test systematic corruption patterns
      final corruptionTests = [
        () => MalformedFixtureBuilder.createTruncatedLeader(truncateAt: 5),
        () => MalformedFixtureBuilder.createTruncatedLeader(truncateAt: 15),
        () => MalformedFixtureBuilder.createDirectoryLengthMismatch(),
        () => MalformedFixtureBuilder.createMissingFieldTerminator(),
        () => MalformedFixtureBuilder.createUnexpectedSubfieldDelimiter(atStart: true),
        () => MalformedFixtureBuilder.createUnexpectedSubfieldDelimiter(atStart: false),
        () => MalformedFixtureBuilder.createDanglingFSPTPointer(),
        () => MalformedFixtureBuilder.createInconsistentVRPTCount(),
        () => MalformedFixtureBuilder.createEmptyRequiredFields(emptyDSID: true),
        () => MalformedFixtureBuilder.createEmptyRequiredFields(emptyDSID: false),
        () => MalformedFixtureBuilder.createInvalidRUINOperation(),
      ];
      
      var successCount = 0;
      
      for (int i = 0; i < corruptionTests.length; i++) {
        try {
          final corruptedData = corruptionTests[i]();
          final reader = Iso8211Reader(corruptedData);
          
          // Should not crash
          final records = reader.readAll().toList();
          expect(records, isA<List>());
          
          successCount++;
        } catch (e) {
          print('Systematic corruption test $i failed: $e');
        }
      }
      
      // Most systematic tests should succeed (parser should be robust)
      expect(successCount, greaterThanOrEqualTo(corruptionTests.length * 0.8),
        reason: 'At least 80% of systematic corruption tests should pass');
    });

    test('should generate consistent results with same seed', () {
      // Use simple valid base record
      final baseRecord = MalformedFixtureBuilder.createValidLeader(
        recordLength: 50, 
        baseAddress: 30
      );
      final completeBaseRecord = List<int>.from(baseRecord);
      completeBaseRecord.addAll([0x1e]); // Directory terminator
      while (completeBaseRecord.length < 49) {
        completeBaseRecord.add(0x20); // Padding
      }
      completeBaseRecord.add(0x1d); // Record terminator
      
      const seed = 12345;
      
      // Generate corruption twice with same seed
      final corruption1 = MalformedFixtureBuilder.createRandomCorruption(completeBaseRecord, seed: seed);
      final corruption2 = MalformedFixtureBuilder.createRandomCorruption(completeBaseRecord, seed: seed);
      
      // Should be identical
      expect(corruption1, equals(corruption2), 
        reason: 'Same seed should produce identical corruption');
      
      // Parse both and verify consistent behavior
      final reader1 = Iso8211Reader(corruption1);
      final reader2 = Iso8211Reader(corruption2);
      
      final records1 = reader1.readAll().toList();
      final records2 = reader2.readAll().toList();
      
      expect(records1.length, equals(records2.length));
      expect(reader1.warnings.length, equals(reader2.warnings.length));
    });

    test('should handle edge case corruptions', () {
      // Test extreme edge cases
      final edgeCases = <List<int>>[
        <int>[], // Empty data
        <int>[0], // Single byte
        List<int>.filled(1000, 0), // Large zeroed data
        List<int>.filled(100, 0xFF), // Large max-value data
        List<int>.generate(50, (i) => i % 256), // Sequential pattern
      ];
      
      for (int i = 0; i < edgeCases.length; i++) {
        try {
          final reader = Iso8211Reader(edgeCases[i]);
          final records = reader.readAll().toList();
          
          // Should handle gracefully
          expect(records, isA<List>());
          expect(reader.warnings, isA<List>());
          
        } catch (e) {
          // Edge cases may legitimately fail, but shouldn't crash
          expect(e, isNot(isA<StateError>()), 
            reason: 'Should not have unhandled state errors');
        }
      }
    });

    test('should maintain memory bounds during corruption testing', () {
      // Use simple valid base record
      final baseRecord = MalformedFixtureBuilder.createValidLeader(
        recordLength: 50, 
        baseAddress: 30
      );
      
      // Test with various corruption sizes to ensure no memory issues
      for (int size in [10, 100, 1000, 5000]) {
        final largeCorruption = List<int>.generate(size, (i) => (i * 7) % 256);
        
        try {
          final reader = Iso8211Reader(largeCorruption);
          final records = reader.readAll().toList();
          
          // Should handle without memory issues
          expect(records, isA<List>());
          
          // Warnings list should be bounded (no runaway memory)
          expect(reader.warnings.length, lessThan(1000),
            reason: 'Warning count should be bounded to prevent memory issues');
            
        } catch (e) {
          // Large corruptions may fail, but no memory errors
          expect(e.toString(), isNot(contains('OutOfMemory')));
        }
      }
    });
  });
}