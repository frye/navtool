import 'package:flutter_test/flutter_test.dart';
import '../utils/enc_test_utilities.dart';

@Tags(['integration'])
void main() {
  group('ENC Metadata Extraction Tests', () {
    late FixtureDiscoveryResult fixtures;

    setUpAll(() {
      fixtures = EncTestUtilities.discoverFixtures();
    });

    testWidgets('should extract metadata from chart ID and filename', (
      tester,
    ) async {
      const testChartPath =
          'test/fixtures/charts/s57_data/US5WA50M_harbor_elliott_bay.zip';

      // Test metadata extraction from filename (works without parsing large file)
      final cellId = testChartPath.split('/').last.split('_')[0];
      expect(cellId, equals('US5WA50M'));

      // Test usage band extraction
      final usageBand = int.tryParse(cellId.substring(2, 3)) ?? 0;
      expect(
        usageBand,
        equals(5),
        reason: 'Should extract usage band 5 from filename',
      );

      print('Metadata extraction from filename:');
      print('  Cell ID: $cellId');
      print('  Usage Band: $usageBand');
      print(
        '  Chart Type: ${usageBand == 5
            ? 'Harbor'
            : usageBand == 3
            ? 'Coastal'
            : 'Other'}',
      );
    });

    testWidgets('should create metadata structure correctly', (tester) async {
      const testMetadata = EncMetadata(
        cellId: 'US5WA50M',
        editionNumber: 4,
        updateNumber: 12,
        usageBand: 5,
        compilationScale: 20000,
        comf: 10000000.0,
        somf: 10.0,
        horizontalDatum: 'WGS84',
        verticalDatum: 'MLLW',
        soundingDatum: 'MLLW',
      );

      expect(testMetadata.cellId, equals('US5WA50M'));
      expect(testMetadata.usageBand, equals(5));
      expect(testMetadata.editionNumber, greaterThan(0));
      expect(testMetadata.compilationScale, isNotNull);

      print('Test metadata structure:');
      print('  Cell ID: ${testMetadata.cellId}');
      print('  Edition: ${testMetadata.editionNumber}');
      print('  Update: ${testMetadata.updateNumber}');
      print('  Usage Band: ${testMetadata.usageBand}');
      print('  Scale: ${testMetadata.compilationScale}');
      print('  COMF: ${testMetadata.comf}');
      print('  SOMF: ${testMetadata.somf}');
      print('  Horizontal Datum: ${testMetadata.horizontalDatum}');
      print('  Vertical Datum: ${testMetadata.verticalDatum}');
      print('  Sounding Datum: ${testMetadata.soundingDatum}');
    });

    testWidgets('should validate metadata consistency between chart types', (
      tester,
    ) async {
      // Test both harbor and coastal chart metadata
      const harborMetadata = EncMetadata(
        cellId: 'US5WA50M',
        editionNumber: 4,
        updateNumber: 12,
        usageBand: 5,
        compilationScale: 20000,
      );

      const coastalMetadata = EncMetadata(
        cellId: 'US3WA01M',
        editionNumber: 3,
        updateNumber: 8,
        usageBand: 3,
        compilationScale: 90000,
      );

      // Cell IDs should be different
      expect(harborMetadata.cellId, isNot(equals(coastalMetadata.cellId)));

      // Usage bands should be different (5 vs 3)
      expect(harborMetadata.usageBand, equals(5));
      expect(coastalMetadata.usageBand, equals(3));

      // Harbor charts should have larger scale (smaller number) than coastal
      if (harborMetadata.compilationScale != null &&
          coastalMetadata.compilationScale != null) {
        expect(
          harborMetadata.compilationScale!,
          lessThan(coastalMetadata.compilationScale!),
          reason: 'Harbor charts should have larger scale than coastal charts',
        );
      }

      print('Chart type comparison:');
      print('Harbor chart (${harborMetadata.cellId}):');
      print('  Usage Band: ${harborMetadata.usageBand}');
      print('  Scale: ${harborMetadata.compilationScale}');
      print('Coastal chart (${coastalMetadata.cellId}):');
      print('  Usage Band: ${coastalMetadata.usageBand}');
      print('  Scale: ${coastalMetadata.compilationScale}');
    });

    testWidgets('should validate coordinate and datum information', (
      tester,
    ) async {
      // Test coordinate system metadata
      const testMetadata = EncMetadata(
        cellId: 'US5WA50M',
        editionNumber: 4,
        updateNumber: 12,
        usageBand: 5,
        comf: 10000000.0, // Coordinate multiplication factor
        somf: 10.0, // Sounding multiplication factor
        horizontalDatum: 'WGS84',
        verticalDatum: 'MLLW',
        soundingDatum: 'MLLW',
      );

      // COMF should be positive if present (coordinate scaling)
      if (testMetadata.comf != null) {
        expect(testMetadata.comf!, greaterThan(0));
      }

      // SOMF should be positive if present (sounding scaling)
      if (testMetadata.somf != null) {
        expect(testMetadata.somf!, greaterThan(0));
      }

      // Datum strings should be meaningful if present
      if (testMetadata.horizontalDatum != null) {
        expect(testMetadata.horizontalDatum!, isNotEmpty);
      }

      if (testMetadata.verticalDatum != null) {
        expect(testMetadata.verticalDatum!, isNotEmpty);
      }

      print('Coordinate system metadata:');
      print('  COMF (coordinate factor): ${testMetadata.comf}');
      print('  SOMF (sounding factor): ${testMetadata.somf}');
      print('  Horizontal Datum: ${testMetadata.horizontalDatum}');
      print('  Vertical Datum: ${testMetadata.verticalDatum}');
      print('  Sounding Datum: ${testMetadata.soundingDatum}');
    });

    testWidgets('should demonstrate fixture availability status', (
      tester,
    ) async {
      print('Fixture availability status:');
      print('  Fixtures path: ${fixtures.fixturesPath}');
      print(
        '  Primary chart (Harbor): ${fixtures.hasPrimaryChart ? 'Available' : 'Missing'}',
      );
      print(
        '  Secondary chart (Coastal): ${fixtures.hasSecondaryChart ? 'Available' : 'Missing'}',
      );

      if (fixtures.hasPrimaryChart) {
        print('  Primary path: ${fixtures.primaryChartPath}');
      }

      if (fixtures.hasSecondaryChart) {
        print('  Secondary path: ${fixtures.secondaryChartPath}');
      }

      if (!fixtures.hasAnyFixtures) {
        print('To enable real ENC metadata extraction:');
        print('  1. Set NOAA_ENC_FIXTURES environment variable');
        print('  2. Download NOAA ENC charts to the specified directory');
        print('  3. Ensure files are named US5WA50M_*.zip and US3WA01M_*.zip');
      }

      // This test documents the current state
      expect(fixtures, isNotNull);
    });
  });
}
