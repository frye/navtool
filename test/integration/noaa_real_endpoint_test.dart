import 'package:flutter_test/flutter_test.dart';

/// DEPRECATED: Real NOAA endpoint integration tests.
///
/// These tests have been migrated to: integration_test/noaa_real_endpoint_test.dart
/// where IntegrationTestWidgetsFlutterBinding is used to allow real network
/// requests. This legacy file remains only to provide a clear migration
/// pointer and will be removed after downstream references are updated.
///
/// DO NOT add new tests here.
/// For mock/unit tests: test/core/services/noaa_api_client_mock_test.dart
/// For real integration tests: integration_test/noaa_real_endpoint_test.dart
@Tags(['deprecated', 'skip'])
void main() {
  group('DEPRECATED: NOAA Real Endpoint Integration Tests', () {
    test('Tests moved to integration_test directory', () {
      printOnFailure(
        'DEPRECATED: These tests have been moved to integration_test/noaa_real_endpoint_test.dart',
      );
      printOnFailure(
        'For mock-based unit tests, use test/core/services/noaa_api_client_mock_test.dart',
      );
      printOnFailure(
        'For real network integration tests, use integration_test/noaa_real_endpoint_test.dart',
      );

      // This test always passes to indicate the migration is complete
      expect(
        true,
        isTrue,
        reason: 'Tests successfully migrated to new structure',
      );
    });
  });
}
