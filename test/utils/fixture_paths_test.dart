import 'package:flutter_test/flutter_test.dart';
import '../utils/fixture_paths.dart';

/// Test to validate fixture path consistency and availability
/// This helps prevent future path inconsistencies across the test suite.
void main() {
  group('Fixture Path Consistency', () {
    test('should have consistent path constants', () {
      // Validate path structure is logical
      expect(FixturePaths.s57Data, startsWith(FixturePaths.charts));
      expect(FixturePaths.s57EncRoot, startsWith(FixturePaths.s57Data));
      
      // Validate chart paths use consistent base
      expect(FixturePaths.ChartPaths.elliottBayZip, startsWith(FixturePaths.s57Data));
      expect(FixturePaths.ChartPaths.pugetSoundZip, startsWith(FixturePaths.s57Data));
      expect(FixturePaths.ChartPaths.elliottBayS57, startsWith(FixturePaths.s57EncRoot));
      expect(FixturePaths.ChartPaths.pugetSoundS57, startsWith(FixturePaths.s57EncRoot));
    });

    test('should provide fixture validation', () {
      final validation = FixtureUtils.validateChartFixtures();
      
      expect(validation, isA<FixtureValidationResult>());
      expect(validation.basePath, equals(FixturePaths.s57Data));
      expect(validation.statusMessage, isNotEmpty);
      
      if (!validation.allAvailable) {
        print('Missing fixtures: ${validation.missingFixtures}');
        print('Status: ${validation.statusMessage}');
      }
      
      // Log status for CI/debugging
      print('Fixture validation: ${validation.allAvailable ? "PASS" : "PARTIAL"}');
    });

    test('should have correct file extensions', () {
      // ZIP files should end with .zip
      expect(FixturePaths.ChartPaths.elliottBayZip, endsWith('.zip'));
      expect(FixturePaths.ChartPaths.pugetSoundZip, endsWith('.zip'));
      
      // S57 files should end with .000
      expect(FixturePaths.ChartPaths.elliottBayS57, endsWith('.000'));
      expect(FixturePaths.ChartPaths.pugetSoundS57, endsWith('.000'));
    });

    test('should have matching chart IDs in paths', () {
      // Elliott Bay paths should contain US5WA50M
      expect(FixturePaths.ChartPaths.elliottBayZip, contains('US5WA50M'));
      expect(FixturePaths.ChartPaths.elliottBayS57, contains('US5WA50M'));
      
      // Puget Sound paths should contain US3WA01M
      expect(FixturePaths.ChartPaths.pugetSoundZip, contains('US3WA01M'));
      expect(FixturePaths.ChartPaths.pugetSoundS57, contains('US3WA01M'));
    });

    test('should provide utility methods', () {
      // Test absolute path utility
      final absolutePath = FixtureUtils.getAbsolutePath('test/example.txt');
      expect(absolutePath, isNotEmpty);
      expect(absolutePath, endsWith('test/example.txt'));
      
      // Test exists utility (should work even for non-existent files)
      final nonExistentExists = FixtureUtils.exists('non/existent/path.txt');
      expect(nonExistentExists, isFalse);
    });
  });
}