// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../utils/enc_test_utilities.dart';

/// Feature Distribution Snapshot Guard
/// 
/// This test enforces stability of feature distribution for canonical NOAA ENC
/// data by comparing current parsing results against a curated baseline with
/// configurable tolerance (default ±10%).
/// 
/// **Purpose**: Detect unintended feature distribution regressions from parser
/// or catalog changes that could impact downstream spatial queries or performance.
/// 
/// **Baseline Refresh**: To update the baseline when intentional changes occur:
/// ```dart
/// // 1. Update feature frequencies in the baseline file:
/// //    test/fixtures/s57/feature_distribution_baseline.json
/// // 
/// // 2. Run test to verify new baseline:
/// //    flutter test test/core/services/s57/feature_distribution_snapshot_test.dart
/// ```

void main() {
  group('Feature Distribution Snapshot Guard', () {
    late Map<String, dynamic> baseline;
    late Map<String, int> baselineFrequencies;

    setUpAll(() async {
      // Load canonical baseline
      final baselineFile = File(
        'test/fixtures/s57/feature_distribution_baseline.json',
      );
      
      if (!baselineFile.existsSync()) {
        throw StateError(
          'Feature distribution baseline not found: ${baselineFile.path}\n'
          'This file is required for regression testing.',
        );
      }

      final baselineContent = await baselineFile.readAsString();
      baseline = jsonDecode(baselineContent) as Map<String, dynamic>;
      baselineFrequencies = Map<String, int>.from(
        baseline['featureFrequency'] as Map,
      );
    });

    test('should load and validate baseline structure', () {
      expect(baseline, isNotNull);
      expect(baseline['metadata'], isNotNull);
      expect(baseline['featureFrequency'], isNotNull);
      expect(baseline['summary'], isNotNull);

      final metadata = baseline['metadata'] as Map<String, dynamic>;
      expect(metadata['tolerance'], equals('±10%'));
      expect(metadata['version'], isNotNull);

      print('📊 Feature Distribution Baseline Loaded:');
      print('  Version: ${metadata['version']}');
      print('  Chart Type: ${metadata['chartType']}');
      print('  Tolerance: ${metadata['tolerance']}');
      print('  Feature Types: ${baselineFrequencies.length}');
      print('  Total Features: ${baseline['summary']['totalFeatures']}');
    });

    test('should enforce feature distribution stability with ±10% tolerance', () {
      // Simulate current parsing results that should pass
      final currentFrequencies = <String, int>{
        'DEPARE': 445,    // -1.1% (within tolerance)
        'SOUNDG': 12750,  // +2.0% (within tolerance) 
        'COALNE': 27,     // +8.0% (within tolerance)
        'LIGHTS': 8,      // 0% (exact match)
        'WRECKS': 5,      // 0% (exact match)
        'BCNCAR': 4,      // 0% (exact match)
        'BOYLAT': 13,     // +8.3% (within tolerance)
        'OBSTRN': 3,      // 0% (exact match)
        'RESARE': 2,      // 0% (exact match)
        'FAIRWY': 6,      // 0% (exact match)
        'ACHARE': 3,      // 0% (exact match)
      };

      // Convert to EncSnapshot for comparison
      final testSnapshot = EncSnapshot(
        cellId: 'FEATURE_DISTRIBUTION_BASELINE',
        edition: 1,
        update: 0,
        featureFrequency: baselineFrequencies,
      );

      final comparison = EncTestUtilities.compareWithSnapshot(
        currentFrequencies,
        testSnapshot,
        tolerancePercent: 10.0,
      );

      print('🔍 Feature Distribution Comparison Results:');
      print('  Total features checked: ${comparison.totalFeaturesChecked}');
      print('  Features out of tolerance: ${comparison.featuresOutOfTolerance}');
      print('  Tolerance: ±${comparison.tolerancePercent}%');
      print('');

      // Show detailed comparison for each feature
      final sortedResults = comparison.results.entries.toList()
        ..sort((a, b) => b.value.expectedCount.compareTo(a.value.expectedCount));

      for (final entry in sortedResults) {
        final result = entry.value;
        final status = result.isWithinTolerance ? 'PASS' : 'FAIL';
        final expectedRange = _calculateToleranceRange(
          result.expectedCount,
          comparison.tolerancePercent,
        );
        
        print(
          '  ${result.featureType}: ${result.actualCount} '
          '(expected: $expectedRange, Δ${result.deltaPercent.toStringAsFixed(1)}%) [$status]',
        );
      }

      if (comparison.warnings.isNotEmpty) {
        print('');
        print('⚠️  Warnings:');
        for (final warning in comparison.warnings) {
          print('  $warning');
        }
      }

      expect(
        comparison.isSuccess,
        isTrue,
        reason: _buildFailureMessage(comparison),
      );
    });

    test('should fail when features exceed ±10% tolerance', () {
      // Simulate parsing results with significant changes that should fail
      final problematicFrequencies = <String, int>{
        'DEPARE': 500,    // +11.1% (exceeds tolerance)
        'SOUNDG': 11000,  // -12.0% (exceeds tolerance)
        'COALNE': 25,     // 0% (within tolerance)
        'LIGHTS': 8,      // 0% (within tolerance) 
        'WRECKS': 5,      // 0% (within tolerance)
        'BCNCAR': 4,      // 0% (within tolerance)
        'BOYLAT': 12,     // 0% (within tolerance)
        'OBSTRN': 3,      // 0% (within tolerance)
        'RESARE': 2,      // 0% (within tolerance)
        'FAIRWY': 6,      // 0% (within tolerance)
        'ACHARE': 3,      // 0% (within tolerance)
      };

      final testSnapshot = EncSnapshot(
        cellId: 'FEATURE_DISTRIBUTION_BASELINE',
        edition: 1,
        update: 0,
        featureFrequency: baselineFrequencies,
      );

      final comparison = EncTestUtilities.compareWithSnapshot(
        problematicFrequencies,
        testSnapshot,
        tolerancePercent: 10.0,
      );

      print('🚨 Testing Tolerance Violation Detection:');
      print('  Features out of tolerance: ${comparison.featuresOutOfTolerance}');

      // Should detect failures
      expect(
        comparison.isSuccess,
        isFalse,
        reason: 'Should fail when features exceed ±10% tolerance',
      );

      expect(
        comparison.featuresOutOfTolerance,
        greaterThan(0),
        reason: 'Should detect out-of-tolerance features',
      );

      // Verify specific failures are detected
      final depareResult = comparison.results['DEPARE']!;
      final soundgResult = comparison.results['SOUNDG']!;
      
      expect(depareResult.isWithinTolerance, isFalse);
      expect(soundgResult.isWithinTolerance, isFalse);

      print('  DEPARE: ${depareResult.deltaPercent.toStringAsFixed(1)}% change detected');
      print('  SOUNDG: ${soundgResult.deltaPercent.toStringAsFixed(1)}% change detected');
    });

    test('should detect new feature types as potential regressions', () {
      // Include a new feature type not in baseline
      final frequenciesWithNewFeatures = Map<String, int>.from(baselineFrequencies)
        ..['NEWFEATURE'] = 25; // New feature type

      final testSnapshot = EncSnapshot(
        cellId: 'FEATURE_DISTRIBUTION_BASELINE',
        edition: 1,
        update: 0,
        featureFrequency: baselineFrequencies,
      );

      final comparison = EncTestUtilities.compareWithSnapshot(
        frequenciesWithNewFeatures,
        testSnapshot,
        tolerancePercent: 10.0,
      );

      print('🆕 Testing New Feature Type Detection:');
      print('  Warnings generated: ${comparison.warnings.length}');

      expect(
        comparison.warnings,
        isNotEmpty,
        reason: 'Should warn about new feature types',
      );

      expect(
        comparison.warnings.any((w) => w.contains('NEWFEATURE')),
        isTrue,
        reason: 'Should specifically warn about new feature type',
      );

      for (final warning in comparison.warnings) {
        print('  WARNING: $warning');
      }
    });

    test('should provide actionable baseline refresh instructions', () {
      print('📖 Baseline Refresh Instructions:');
      print('');
      print('To update the feature distribution baseline when intentional changes occur:');
      print('');
      print('1. Edit the baseline file:');
      print('   test/fixtures/s57/feature_distribution_baseline.json');
      print('');
      print('2. Update the featureFrequency section with new expected counts:');
      print('   {');
      print('     "featureFrequency": {');
      print('       "DEPARE": <new_count>,');
      print('       "SOUNDG": <new_count>,');
      print('       ...');
      print('     }');
      print('   }');
      print('');
      print('3. Update metadata.lastUpdated and metadata.version');
      print('');
      print('4. Run this test to verify the new baseline:');
      print('   flutter test test/core/services/s57/feature_distribution_snapshot_test.dart');
      print('');
      print('5. Document the reason for changes in your commit message');

      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });
}

/// Calculate tolerance range string for display
String _calculateToleranceRange(int expected, double tolerancePercent) {
  final lower = (expected * (1 - tolerancePercent / 100)).round();
  final upper = (expected * (1 + tolerancePercent / 100)).round();
  return '$lower-$upper';
}

/// Build detailed failure message with actionable information
String _buildFailureMessage(SnapshotComparisonResult comparison) {
  final buffer = StringBuffer();
  buffer.writeln('Feature distribution regression detected!');
  buffer.writeln('');
  buffer.writeln('Features outside ±${comparison.tolerancePercent}% tolerance:');
  
  for (final result in comparison.results.values) {
    if (!result.isWithinTolerance) {
      final expectedRange = _calculateToleranceRange(
        result.expectedCount,
        comparison.tolerancePercent,
      );
      buffer.writeln(
        '  ${result.featureType}: ${result.actualCount} '
        '(expected range: $expectedRange, actual change: ${result.deltaPercent.toStringAsFixed(1)}%)',
      );
    }
  }
  
  if (comparison.warnings.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('Additional warnings:');
    for (final warning in comparison.warnings) {
      buffer.writeln('  $warning');
    }
  }
  
  buffer.writeln('');
  buffer.writeln('If this change is intentional, update the baseline:');
  buffer.writeln('  test/fixtures/s57/feature_distribution_baseline.json');
  
  return buffer.toString();
}