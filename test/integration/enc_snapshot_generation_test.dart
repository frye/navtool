import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../utils/enc_test_utilities.dart';

@Tags(['integration'])
void main() {
  group('ENC Snapshot Generation Tests', () {
    testWidgets('should demonstrate snapshot generation workflow', (
      tester,
    ) async {
      if (!EncTestUtilities.isSnapshotGenerationAllowed) {
        print(
          'Skipping snapshot generation tests - set ALLOW_SNAPSHOT_GEN=1 to enable',
        );
        return;
      }

      const testMetadata = EncMetadata(
        cellId: 'TEST_GENERATION',
        editionNumber: 5,
        updateNumber: 2,
        usageBand: 5,
        compilationScale: 25000,
      );

      final testFrequencies = {
        'DEPARE': 125,
        'COALNE': 8,
        'LIGHTS': 4,
        'SOUNDG': 750,
        'WRECKS': 3,
        'BCNCAR': 2,
      };

      const testChartId = 'TEST_GENERATION';
      final testSnapshotFile = File(
        'test/fixtures/golden/${testChartId.toLowerCase()}_freq.json',
      );

      // Clean up any existing test snapshot
      if (testSnapshotFile.existsSync()) {
        await testSnapshotFile.delete();
      }

      print('Generating test snapshot:');
      print('  Chart ID: $testChartId');
      print('  Edition: ${testMetadata.editionNumber}');
      print('  Update: ${testMetadata.updateNumber}');
      print('  Features: ${testFrequencies.length}');

      // Generate snapshot
      await EncTestUtilities.generateSnapshot(
        testChartId,
        testMetadata,
        testFrequencies,
      );

      // Verify file was created
      expect(
        testSnapshotFile.existsSync(),
        isTrue,
        reason: 'Snapshot file should be created',
      );

      // Verify file content is valid JSON
      final content = await testSnapshotFile.readAsString();
      expect(content, isNotEmpty, reason: 'Snapshot file should not be empty');
      expect(
        content.contains(testChartId),
        isTrue,
        reason: 'Snapshot should contain chart ID',
      );

      print('  Generated file: ${testSnapshotFile.path}');
      print('  File size: ${content.length} characters');

      // Load and verify the generated snapshot
      final loadedSnapshot = await EncTestUtilities.loadSnapshot(testChartId);
      expect(
        loadedSnapshot,
        isNotNull,
        reason: 'Should be able to load generated snapshot',
      );

      expect(loadedSnapshot!.cellId, equals(testChartId));
      expect(loadedSnapshot.edition, equals(testMetadata.editionNumber));
      expect(loadedSnapshot.update, equals(testMetadata.updateNumber));
      expect(loadedSnapshot.featureFrequency, equals(testFrequencies));

      print('  Verified snapshot content:');
      print('    Cell ID: ${loadedSnapshot.cellId}');
      print('    Edition: ${loadedSnapshot.edition}');
      print('    Update: ${loadedSnapshot.update}');
      print('    Feature count: ${loadedSnapshot.featureFrequency.length}');

      // Clean up test snapshot
      await testSnapshotFile.delete();
    });

    testWidgets('should create properly formatted JSON output', (tester) async {
      if (!EncTestUtilities.isSnapshotGenerationAllowed) {
        print('Skipping JSON format test - set ALLOW_SNAPSHOT_GEN=1 to enable');
        return;
      }

      const testMetadata = EncMetadata(
        cellId: 'JSON_FORMAT_TEST',
        editionNumber: 1,
        updateNumber: 0,
        usageBand: 3,
      );

      final testFrequencies = {'DEPARE': 50, 'COALNE': 5};

      const testChartId = 'JSON_FORMAT_TEST';
      final testSnapshotFile = File(
        'test/fixtures/golden/${testChartId.toLowerCase()}_freq.json',
      );

      // Clean up
      if (testSnapshotFile.existsSync()) {
        await testSnapshotFile.delete();
      }

      // Generate snapshot
      await EncTestUtilities.generateSnapshot(
        testChartId,
        testMetadata,
        testFrequencies,
      );

      // Check JSON format
      final content = await testSnapshotFile.readAsString();

      print('Generated JSON content:');
      print(content);

      // Should be properly formatted (indented)
      expect(
        content.contains('\n'),
        isTrue,
        reason: 'JSON should be formatted with newlines',
      );
      expect(content.contains('  '), isTrue, reason: 'JSON should be indented');

      // Should contain expected fields
      expect(content.contains('"cellId"'), isTrue);
      expect(content.contains('"edition"'), isTrue);
      expect(content.contains('"update"'), isTrue);
      expect(content.contains('"featureFrequency"'), isTrue);

      // Clean up
      await testSnapshotFile.delete();
    });

    testWidgets('should handle directory creation if needed', (tester) async {
      if (!EncTestUtilities.isSnapshotGenerationAllowed) {
        print(
          'Skipping directory creation test - set ALLOW_SNAPSHOT_GEN=1 to enable',
        );
        return;
      }

      // The generateSnapshot method should create the golden directory if it doesn't exist
      // This is automatically handled by File.parent.create(recursive: true)

      const testMetadata = EncMetadata(
        cellId: 'DIR_TEST',
        editionNumber: 1,
        updateNumber: 0,
        usageBand: 5,
      );

      final testFrequencies = {'DEPARE': 1};

      // This should succeed even if golden directory structure needs creation
      await EncTestUtilities.generateSnapshot(
        'DIR_TEST',
        testMetadata,
        testFrequencies,
      );

      final testFile = File('test/fixtures/golden/dir_test_freq.json');
      expect(testFile.existsSync(), isTrue);

      print('Directory creation test passed');

      // Clean up
      await testFile.delete();
    });

    testWidgets('should demonstrate snapshot generation disabled behavior', (
      tester,
    ) async {
      if (EncTestUtilities.isSnapshotGenerationAllowed) {
        print(
          'Skipping disabled behavior test - ALLOW_SNAPSHOT_GEN is currently enabled',
        );
        return;
      }

      print('Snapshot generation is disabled');
      print('Environment variable ALLOW_SNAPSHOT_GEN is not set to 1');
      print('This is the expected behavior for normal test runs');
      print(
        'Snapshots should only be generated during development/maintenance',
      );

      expect(EncTestUtilities.isSnapshotGenerationAllowed, isFalse);
    });

    testWidgets('should generate example golden snapshots when enabled', (
      tester,
    ) async {
      if (!EncTestUtilities.isSnapshotGenerationAllowed) {
        print(
          'Skipping snapshot generation - set ALLOW_SNAPSHOT_GEN=1 to enable',
        );
        print('This test would generate example golden snapshots for:');
        print('  - US5WA50M (Harbor chart)');
        print('  - US3WA01M (Coastal chart)');
        return;
      }

      print('Generating example golden snapshots...');

      // Generate example snapshots for both charts
      await EncTestUtilities.createExampleSnapshots();

      // Verify snapshots were created
      final primarySnapshot = await EncTestUtilities.loadSnapshot(
        EncTestUtilities.primaryChartId,
      );
      final secondarySnapshot = await EncTestUtilities.loadSnapshot(
        EncTestUtilities.secondaryChartId,
      );

      expect(
        primarySnapshot,
        isNotNull,
        reason: 'Primary chart snapshot should be generated',
      );
      expect(
        secondarySnapshot,
        isNotNull,
        reason: 'Secondary chart snapshot should be generated',
      );

      print('✓ Generated snapshots for both charts');
      print(
        '  Primary: ${primarySnapshot!.cellId} (${primarySnapshot.featureFrequency.length} feature types)',
      );
      print(
        '  Secondary: ${secondarySnapshot!.cellId} (${secondarySnapshot.featureFrequency.length} feature types)',
      );
    });
    testWidgets('should validate snapshot comparison logic when enabled', (
      tester,
    ) async {
      if (!EncTestUtilities.isSnapshotGenerationAllowed) {
        print(
          'Skipping comparison validation test - set ALLOW_SNAPSHOT_GEN=1 to enable',
        );
        return;
      }

      const testMetadata = EncMetadata(
        cellId: 'COMPARISON_TEST',
        editionNumber: 1,
        updateNumber: 0,
        usageBand: 5,
      );

      final originalFrequencies = {'DEPARE': 100, 'COALNE': 10, 'LIGHTS': 5};

      const testChartId = 'COMPARISON_TEST';
      final testSnapshotFile = File(
        'test/fixtures/golden/${testChartId.toLowerCase()}_freq.json',
      );

      if (testSnapshotFile.existsSync()) {
        await testSnapshotFile.delete();
      }

      await EncTestUtilities.generateSnapshot(
        testChartId,
        testMetadata,
        originalFrequencies,
      );
      final snapshot = await EncTestUtilities.loadSnapshot(testChartId);
      expect(snapshot, isNotNull);

      final identicalComparison = EncTestUtilities.compareWithSnapshot(
        originalFrequencies,
        snapshot!,
        tolerancePercent: 10.0,
      );
      expect(identicalComparison.isSuccess, isTrue);
      expect(identicalComparison.featuresOutOfTolerance, equals(0));
      print('Generated snapshot comparison validation passed');

      await testSnapshotFile.delete();
    });
  });
}
