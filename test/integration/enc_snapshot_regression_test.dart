import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../utils/enc_test_utilities.dart';

@Tags(['integration'])
void main() {
  group('ENC Snapshot Regression Tests', () {
    testWidgets('should demonstrate snapshot loading and comparison', (tester) async {
      // Create test snapshot data
      const testSnapshot = EncSnapshot(
        cellId: 'TEST_CHART',
        edition: 1,
        update: 0,
        featureFrequency: {
          'DEPARE': 100,
          'COALNE': 10,
          'LIGHTS': 5,
          'SOUNDG': 500,
        },
      );
      
      // Test current frequency data (with small variance)
      final currentFrequencies = {
        'DEPARE': 102,  // +2% change
        'COALNE': 9,    // -10% change  
        'LIGHTS': 5,    // No change
        'SOUNDG': 495,  // -1% change
      };
      
      print('Testing snapshot comparison with tolerance:');
      print('Snapshot frequencies:');
      testSnapshot.featureFrequency.forEach((type, count) {
        print('  $type: $count');
      });
      
      print('Current frequencies:');
      currentFrequencies.forEach((type, count) {
        print('  $type: $count');
      });
      
      // Compare with 10% tolerance
      final comparison = EncTestUtilities.compareWithSnapshot(
        currentFrequencies,
        testSnapshot,
        tolerancePercent: 10.0,
      );
      
      print('Comparison results:');
      print('  Total features checked: ${comparison.totalFeaturesChecked}');
      print('  Features out of tolerance: ${comparison.featuresOutOfTolerance}');
      print('  Has failures: ${comparison.hasFailures}');
      print('  Tolerance: ±${comparison.tolerancePercent}%');
      
      for (final result in comparison.results.values) {
        final status = result.isWithinTolerance ? 'PASS' : 'FAIL';
        print('  ${result.featureType}: ${result.actualCount} vs ${result.expectedCount} '
              '(${result.deltaPercent.toStringAsFixed(1)}%) [$status]');
      }
      
      // Should pass with 10% tolerance
      expect(comparison.isSuccess, isTrue, 
          reason: 'All feature changes should be within 10% tolerance');
    });
    
    testWidgets('should test tolerance boundaries correctly', (tester) async {
      const testSnapshot = EncSnapshot(
        cellId: 'TOLERANCE_TEST',
        edition: 1,
        update: 0,
        featureFrequency: {
          'DEPARE': 100,
        },
      );
      
      // Test exactly at 10% boundary
      final boundaryFrequencies = {'DEPARE': 110}; // Exactly +10%
      
      final boundaryComparison = EncTestUtilities.compareWithSnapshot(
        boundaryFrequencies,
        testSnapshot,
        tolerancePercent: 10.0,
      );
      
      expect(boundaryComparison.isSuccess, isTrue, 
          reason: 'Exactly 10% change should pass with 10% tolerance');
      
      // Test beyond tolerance
      final beyondFrequencies = {'DEPARE': 111}; // +11%
      
      final beyondComparison = EncTestUtilities.compareWithSnapshot(
        beyondFrequencies,
        testSnapshot,
        tolerancePercent: 10.0,
      );
      
      expect(beyondComparison.isSuccess, isFalse, 
          reason: '11% change should fail with 10% tolerance');
      
      print('Tolerance boundary testing:');
      print('  10% change: ${boundaryComparison.isSuccess ? 'PASS' : 'FAIL'}');
      print('  11% change: ${beyondComparison.isSuccess ? 'PASS' : 'FAIL'}');
    });
    
    testWidgets('should handle new feature types with warnings', (tester) async {
      const testSnapshot = EncSnapshot(
        cellId: 'NEW_FEATURES_TEST',
        edition: 1,
        update: 0,
        featureFrequency: {
          'DEPARE': 100,
          'COALNE': 10,
        },
      );
      
      final currentWithNewFeatures = {
        'DEPARE': 100,
        'COALNE': 10,
        'WRECKS': 5,    // New feature type
        'LIGHTS': 2,    // Another new feature type
      };
      
      final comparison = EncTestUtilities.compareWithSnapshot(
        currentWithNewFeatures,
        testSnapshot,
        tolerancePercent: 10.0,
      );
      
      print('New feature types test:');
      print('  Warnings generated: ${comparison.warnings.length}');
      for (final warning in comparison.warnings) {
        print('    WARNING: $warning');
      }
      
      expect(comparison.warnings, isNotEmpty, 
          reason: 'Should warn about new feature types');
      expect(comparison.warnings.any((w) => w.contains('WRECKS')), isTrue,
          reason: 'Should specifically warn about WRECKS');
      expect(comparison.warnings.any((w) => w.contains('LIGHTS')), isTrue,
          reason: 'Should specifically warn about LIGHTS');
    });
    
    testWidgets('should demonstrate snapshot generation process', (tester) async {
      const testMetadata = EncMetadata(
        cellId: 'GENERATED_TEST',
        editionNumber: 2,
        updateNumber: 1,
        usageBand: 5,
      );
      
      final testFrequencies = {
        'DEPARE': 150,
        'COALNE': 12,
        'LIGHTS': 3,
        'SOUNDG': 800,
        'WRECKS': 2,
      };
      
      if (EncTestUtilities.isSnapshotGenerationAllowed) {
        print('Snapshot generation is enabled');
        
        // Clean up any existing test snapshot
        final testSnapshotFile = File('test/fixtures/golden/generated_test_freq.json');
        if (testSnapshotFile.existsSync()) {
          await testSnapshotFile.delete();
        }
        
        // Generate new snapshot
        await EncTestUtilities.generateSnapshot(
          'GENERATED_TEST',
          testMetadata,
          testFrequencies,
        );
        
        // Verify it was created
        expect(testSnapshotFile.existsSync(), isTrue);
        
        // Load and verify content
        final loadedSnapshot = await EncTestUtilities.loadSnapshot('GENERATED_TEST');
        expect(loadedSnapshot, isNotNull);
        expect(loadedSnapshot!.cellId, equals('GENERATED_TEST'));
        expect(loadedSnapshot.featureFrequency, equals(testFrequencies));
        
        print('Generated snapshot successfully:');
        print('  File: ${testSnapshotFile.path}');
        print('  Cell ID: ${loadedSnapshot.cellId}');
        print('  Edition: ${loadedSnapshot.edition}');
        print('  Features: ${loadedSnapshot.featureFrequency.length}');
        
        // Clean up test snapshot
        await testSnapshotFile.delete();
        
      } else {
        print('Snapshot generation disabled (set ALLOW_SNAPSHOT_GEN=1 to enable)');
        print('Would generate snapshot with:');
        print('  Cell ID: ${testMetadata.cellId}');
        print('  Edition: ${testMetadata.editionNumber}');
        print('  Update: ${testMetadata.updateNumber}');
        testFrequencies.forEach((type, count) {
          print('    $type: $count');
        });
      }
    });
    
    testWidgets('should handle missing snapshots appropriately', (tester) async {
      // Try to load a non-existent snapshot
      final missingSnapshot = await EncTestUtilities.loadSnapshot('NONEXISTENT_CHART');
      
      expect(missingSnapshot, isNull, 
          reason: 'Loading non-existent snapshot should return null');
      
      print('Missing snapshot handling:');
      print('  Non-existent snapshot returns: ${missingSnapshot ?? 'null'}');
      print('  This allows tests to detect missing golden files');
    });
  });
}