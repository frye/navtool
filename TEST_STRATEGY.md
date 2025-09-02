# Testing Strategy for NOAA API Integration

This document outlines the dual testing strategy implemented to fix the 10 failing integration tests that required real network connectivity.

## Problem

The original integration tests in `test/integration/noaa_real_endpoint_test.dart` were failing with HTTP 400 errors because Flutter's `TestWidgetsFlutterBinding` blocks real network requests for security reasons.

## Solution: Dual Testing Strategy

### 1. Integration Tests (`integration_test/`)

**Purpose**: Real network testing with actual NOAA API endpoints
**Location**: `integration_test/noaa_real_endpoint_test.dart`
**Binding**: `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`

**Features**:
- Tests actual NOAA API connectivity
- Validates real data structures and responses
- Handles marine connection scenarios (slow/intermittent networks)
- Uses real timeouts and retry logic
- Requires actual device or emulator

**Running**:
```bash
# Run integration tests on real device
flutter test integration_test/

# Run specific file
flutter test integration_test/noaa_real_endpoint_test.dart
```

### 2. Mock-Based Unit Tests (`test/`)

**Purpose**: Fast development feedback with mocked responses
**Location**: `test/core/services/noaa_api_client_mock_test.dart`
**Binding**: Standard `TestWidgetsFlutterBinding`

**Features**:
- Fast execution (no network calls)
- Predictable test data
- Comprehensive error scenario testing
- Rate limiting validation
- Performance testing with large datasets

**Running**:
```bash
# Run only mock-based unit tests
flutter test --tags=unit

# Run all standard tests (including mocks)
flutter test
```

## Test Organization

### Test Tags

- `@Tags(['unit', 'mock', 'noaa'])` - Mock-based unit tests
- `@Tags(['deprecated', 'skip'])` - Old integration tests (will be removed)
- No special tags - Real integration tests in `integration_test/`

### Environment Variables

- `SKIP_INTEGRATION_TESTS=true` - Skip network-dependent tests
- `CI=true` - Automatically skips integration tests in CI environments

## Test Coverage

### Mock Tests Cover:
1. Chart catalog fetching with various filters
2. Chart metadata retrieval for valid/invalid IDs
3. Chart availability checks
4. Network error handling scenarios
5. Rate limiting behavior
6. Data validation and schema compliance
7. Performance with large datasets

### Integration Tests Cover:
1. Real NOAA API connectivity
2. Actual data structure validation
3. Marine connection resilience
4. API schema compatibility
5. End-to-end workflows
6. Real timeout and retry scenarios

## Benefits

1. **Fast Development**: Mock tests provide immediate feedback
2. **Reliable CI/CD**: Unit tests don't depend on external services
3. **Real Validation**: Integration tests ensure API compatibility
4. **Comprehensive Coverage**: Both success and failure scenarios
5. **Marine-Specific**: Handles unique maritime connectivity challenges

## Migration from Old Tests

The original failing tests in `test/integration/noaa_real_endpoint_test.dart` have been:

1. **Replaced** with a simple deprecation notice
2. **Migrated** to `integration_test/noaa_real_endpoint_test.dart` for real network testing
3. **Supplemented** with comprehensive mock tests in `test/core/services/noaa_api_client_mock_test.dart`

## Running Tests in Different Scenarios

### Local Development
```bash
# Fast feedback during development
flutter test --tags=unit

# Quick smoke test of all unit tests
flutter test test/
```

### Pre-commit Validation
```bash
# Run all tests except integration
flutter test

# Optional: Run integration tests if network available
flutter test integration_test/
```

### CI/CD Pipeline
```bash
# CI automatically skips integration tests
flutter test

# Integration tests can be run in dedicated environments
# with SKIP_INTEGRATION_TESTS=false
```

### Manual API Validation
```bash
# Test against real NOAA APIs
SKIP_INTEGRATION_TESTS=false flutter test integration_test/

# Test specific functionality
flutter test integration_test/noaa_real_endpoint_test.dart
```

## Maintenance

### Adding New Tests

1. **Mock Tests**: Add to `test/core/services/noaa_api_client_mock_test.dart`
   - Fast execution
   - Predictable data
   - Error scenario coverage

2. **Integration Tests**: Add to `integration_test/noaa_real_endpoint_test.dart`
   - Real network validation
   - End-to-end workflows
   - API contract verification

### Download Progress Semantics

All download progress values emitted by services and observed in tests are normalized fractions in the inclusive range [0.0, 1.0].

Rationale:
- Simplifies UI bindings (direct percentage = fraction * 100).
- Avoids historic ambiguity where some mocks emitted 0–100 values.
- Enables consistent mathematical treatment (easing aggregation / averaging).

Guidelines:
- When simulating progress in tests, call progress callbacks with (receivedBytes, totalBytes) so the service normalizes internally.
- Never emit raw percentage integers (e.g., 25, 50, 100) into progress streams—use fractions if constructing synthetic streams directly.
- Assertions should enforce 0 ≤ p ≤ 1 and use helper `expectProgressCloseTo` for approximate comparisons.
- If a future regression introduces values >1, tests SHOULD fail loudly rather than auto-normalize silently.

Example (correct):
```
onReceiveProgress: (received, total) {
   // received: 50, total: 100  -> progress stream emits 0.5
}
```

Example (incorrect – do not use):
```
progressController.add(50); // 50 interpreted incorrectly as 50x completion
```

### Updating Test Data

- **Mock Data**: Update `test/utils/test_fixtures.dart`
- **Real Data**: Tests use actual NOAA chart IDs (e.g., 'US5CA52M')

## Troubleshooting

### Mock Tests Failing
- Check mock setup in test files
- Verify test fixtures are correct
- Ensure proper mockito usage

### Integration Tests Failing
- Check network connectivity
- Verify NOAA API availability
- Review timeout settings for marine conditions
- Check if `SKIP_INTEGRATION_TESTS` is set

### Build Issues
- Regenerate mocks: `flutter packages pub run build_runner build`
- Clean and rebuild: `flutter clean && flutter pub get`

This dual strategy ensures reliable testing while maintaining the ability to validate real-world scenarios critical for marine navigation applications.