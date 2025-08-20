# Integration Test Directory

This directory contains integration tests that require real network connectivity and actual device/platform capabilities.

## Test Types

- **Real Network Tests**: Tests that connect to actual NOAA API endpoints
- **End-to-End Tests**: Complete workflow testing with real dependencies
- **Device-Specific Tests**: Platform-specific functionality validation

## Running Integration Tests

```bash
# Run all integration tests on a real device
flutter test integration_test/

# Run specific integration test file
flutter test integration_test/noaa_real_endpoint_test.dart

# Skip integration tests during CI
SKIP_INTEGRATION_TESTS=true flutter test integration_test/
```

## Requirements

- Real device or emulator (not just `flutter test`)
- Network connectivity for NOAA API tests
- Appropriate permissions for platform features