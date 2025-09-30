# Phase 0: Research - Test Hang and Mock Generation Failures

**Status**: Complete  
**Date**: September 29, 2025

## Problem Analysis

### Issue 1: Test Hangs in chart_browser_screen_test.dart

**Symptoms**:
- Tests get stuck after "should show date filtering controls when enabled"
- Never completes "should filter charts by scale range"
- Requires manual Ctrl+C interruption

**Research Findings**:

#### Root Cause Analysis
1. **Infinite pumpAndSettle() Loops**
   - Decision: pumpAndSettle() waits for all animations and microtasks to complete
   - Problem: If widgets continuously rebuild or animations never settle, test hangs
   - Evidence: Tests with complex filtering UI contain pumpAndSettle() calls after tap actions
   
2. **Missing UI State Changes**
   - Decision: Tests assume UI updates complete instantly after tap()
   - Problem: Asynchronous state updates (Riverpod providers, Future operations) may not complete before pumpAndSettle()
   - Evidence: Filter controls trigger async chart discovery operations

3. **Slider Interactions**
   - Decision: Scale filtering tests use Slider widgets
   - Problem: Slider animations and state updates can be complex, causing pumpAndSettle() to wait indefinitely
   - Evidence: "Filter by Scale Range" test shows Slider widgets in expectations

#### Flutter Test Best Practices Research

**Decision**: Use pump() with explicit durations instead of pumpAndSettle() for complex UIs
- **Rationale**: 
  - pumpAndSettle() is convenient but fragile with continuous animations
  - pump() with explicit Duration allows fine-grained control
  - Recommended pattern: pump() → Future.delayed() → pump() for async operations
- **Alternatives Considered**:
  - Increase pumpAndSettle() timeout: Doesn't fix root cause, just delays timeout
  - Mock all async operations: Removes test realism for marine UI complexity
  - Disable animations: Could hide real UI timing issues

**Decision**: Use pumpAndWait() helper pattern for async operations
- **Rationale**:
  - Already defined in test file (line 127-134)
  - Provides consistent wait behavior across tests
  - Allows tuning wait duration for marine UI complexity
- **Current Implementation**: 800ms default wait (increased from 500ms)
- **Recommended**: Use pumpAndWait() instead of pumpAndSettle() for filter interactions

**Decision**: Implement test-specific timeouts with skipFrames
- **Rationale**:
  - Some operations genuinely need time (chart discovery, UI layout)
  - skipFrames: true in pumpAndSettle() skips animation frames
  - Prevents infinite loops while allowing legitimate delays
- **Pattern**: `await tester.pumpAndSettle(timeout, EnginePhase.sendSemanticsUpdate);`

### Issue 2: Mock Generation Failures in CI

**Symptoms**:
- GitHub Actions workflows fail during build_runner step
- Error: "flutter packages pub run build_runner build --delete-conflicting-outputs"
- Local mock generation may succeed but CI fails

**Research Findings**:

#### Root Cause Analysis
1. **build_runner Version Compatibility**
   - Decision: Current version is build_runner ^2.4.12
   - Problem: May have compatibility issues with Dart 3.8.1+ or Flutter 3.8.1+
   - Evidence: Version constraint is caret (^) which allows minor updates

2. **Dependency Conflicts**
   - Decision: 150+ test files use @GenerateMocks annotations
   - Problem: Circular dependencies or missing type definitions can block generation
   - Evidence: Multiple test files import generated .mocks.dart files

3. **CI Environment Differences**
   - Decision: GitHub Actions runs on Linux, macOS, Windows runners
   - Problem: Path differences, permissions, or Dart SDK cache issues
   - Evidence: build_runner creates generated files in project directory

#### Build Runner Best Practices Research

**Decision**: Use --delete-conflicting-outputs flag consistently
- **Rationale**: Prevents stale generated code from blocking regeneration
- **Current Implementation**: Already used in CI workflows
- **Verification**: Check all workflows use consistent flag

**Decision**: Run build_runner with --verbose for diagnostics
- **Rationale**: Provides detailed error messages for CI failures
- **Implementation**: Add to CI workflow for mock generation step
- **Pattern**: `flutter packages pub run build_runner build --delete-conflicting-outputs --verbose`

**Decision**: Verify mockito @GenerateMocks annotations
- **Rationale**: Invalid annotations cause build_runner failures
- **Common Issues**:
  - Missing class imports in @GenerateMocks list
  - Circular mock dependencies
  - Mocking classes with private constructors
- **Verification Strategy**: Run build_runner locally with each test file

**Decision**: Add build_runner cache to CI artifacts
- **Rationale**: Speeds up subsequent runs, reveals cache-related issues
- **Implementation**: Cache .dart_tool/build directory in CI
- **Trade-off**: Slightly larger CI storage vs faster builds

## Technical Decisions Summary

### Test Execution Strategy
1. Replace pumpAndSettle() with pumpAndWait() for filter interactions
2. Use explicit pump() + Future.delayed() for complex async operations
3. Add skipFrames: true to remaining pumpAndSettle() calls
4. Increase test-specific timeouts where marine UI complexity requires it
5. Preserve all test assertions and behaviors (Constitution Principle III)

### Mock Generation Strategy
1. Add --verbose flag to build_runner commands in CI
2. Verify all @GenerateMocks annotations are valid
3. Run build_runner clean before build in CI
4. Add detailed error reporting for mock generation failures
5. Cache .dart_tool/build directory for faster CI runs

### Validation Strategy
1. Run full test suite locally after fixes
2. Verify all tests complete within 15 minutes
3. Ensure mock generation succeeds in CI
4. No test behavior changes (same assertions, same coverage)
5. Manual validation: Run stuck tests individually to confirm fix

## Dependencies & Tools

### Flutter Test Framework
- **Version**: Flutter SDK 3.8.1+ (from flutter_test)
- **Key Classes**: WidgetTester, pump(), pumpAndSettle(), pumpAndWait()
- **Documentation**: https://docs.flutter.dev/testing/overview

### Mockito & build_runner
- **Versions**: mockito ^5.4.4, build_runner ^2.4.12
- **Code Generation**: @GenerateMocks annotation → .mocks.dart files
- **Documentation**: https://pub.dev/packages/mockito

### GitHub Actions
- **Workflows**: .github/workflows/noaa_integration_tests.yml, binary-builds.yml
- **Build Step**: flutter packages pub run build_runner build
- **Timeout**: 15 minutes for test execution, 5 minutes for mock generation

## Risks & Mitigations

### Risk: Test behavior changes break existing validations
- **Mitigation**: Preserve all test assertions, only modify wait patterns
- **Verification**: Compare test output before/after fixes

### Risk: Mock generation still fails in CI after local fixes
- **Mitigation**: Add verbose logging, test on all platforms (Linux, macOS, Windows)
- **Verification**: Run CI workflows on test branch before merge

### Risk: Performance regression from slower test execution
- **Mitigation**: Use minimal necessary wait durations, profile test execution time
- **Verification**: Test suite must complete within 15 minutes (current timeout)

### Risk: False sense of reliability if tests pass due to increased timeouts
- **Mitigation**: Only increase timeouts where marine UI legitimately requires time
- **Verification**: Manual validation that UI actually completes within timeout

## Next Steps (Phase 1)

1. Create data-model.md documenting test execution states and mock generation workflow
2. Generate contracts/ for test helper patterns and mock generation commands
3. Create quickstart.md with reproduction steps and validation procedures
4. Update .github/copilot-instructions.md with test debugging patterns
5. Phase 2 task generation for systematic fixes
