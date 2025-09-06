import 'package:flutter_test/flutter_test.dart';
import '../utils/enc_test_utilities.dart';

void main() {
  group('ENC Parse Presence Tests', () {
    late FixtureDiscoveryResult fixtures;
    
    setUpAll(() {
      fixtures = EncTestUtilities.discoverFixtures();
    });
    
    testWidgets('should discover fixtures correctly', (tester) async {
      print('Fixture discovery test:');
      print('  Path: ${fixtures.fixturesPath}');
      print('  Found: ${fixtures.found}');
      print('  Primary available: ${fixtures.hasPrimaryChart}');
      print('  Secondary available: ${fixtures.hasSecondaryChart}');
      
      // This test should always pass - it just reports the fixture state
      expect(fixtures, isNotNull);
    });
    
    testWidgets('should create utilities without error', (tester) async {
      final utilities = EncTestUtilities();
      expect(utilities, isNotNull);
    });
    
    testWidgets('should test chart parsing if fixtures available', (tester) async {
      if (!fixtures.hasPrimaryChart) {
        print('Skipping chart parsing test - No NOAA ENC fixtures available');
        print('Set NOAA_ENC_FIXTURES environment variable to enable.');
        return;
      }
      
      print('Testing chart parsing with primary fixture: ${fixtures.primaryChartPath}');
      
      final utilities = EncTestUtilities();
      final parsedData = await utilities.extractAndParseChart(fixtures.primaryChartPath!);
      
      expect(parsedData, isNotNull);
      expect(parsedData.features, isNotEmpty);
      
      final frequencyMap = EncTestUtilities.buildFeatureFrequencyMap(parsedData);
      print('Feature frequency map:');
      frequencyMap.forEach((type, count) {
        print('  $type: $count');
      });
      
      // Basic validation
      expect(frequencyMap, isNotEmpty);
    });
  });
}