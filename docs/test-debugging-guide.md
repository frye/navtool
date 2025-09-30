# Test Debugging Guide - Widget Test Best Practices

**Date**: September 29, 2025  
**Purpose**: Guide for debugging stuck tests and selecting appropriate pump strategies

## When to Use pumpAndSettle() vs pumpAndWait()

### Use `pumpAndSettle()`
**Good for**:
- Initial widget setup (`await tester.pumpWidget(widget)`)
- Simple animations that complete (dropdown opens/closes)
- Tests without continuous rebuilds
- Widgets with finite animation durations

**Warning Signs it Won't Work**:
- Test hangs indefinitely
- Widgets with Slider components
- Continuous state updates or polling
- Complex filter interactions
- Tests timeout after long delays

### Use `pumpAndWait()`
**Good for**:
- Filter controls that trigger rebuilds
- Slider widgets and range selectors
- Date pickers and complex inputs
- Any widget with continuous updates
- Tests that previously hung with pumpAndSettle()

**Implementation Pattern**:
```dart
// After async operation
await tester.tap(find.text('Filter by Scale Range'));
await pumpAndWait(tester, wait: const Duration(seconds: 1));

// Helper implementation (already in test files)
Future<void> pumpAndWait(
  WidgetTester tester, {
  Duration wait = const Duration(milliseconds: 800),
}) async {
  await tester.pump();
  await Future.delayed(wait);
  await tester.pump();
}
```

### Use Manual `pump()` Pattern
**Good for**:
- Debugging exact frame-by-frame behavior
- Very specific animation timing needs
- Understanding when widgets rebuild

**Implementation**:
```dart
await tester.pump();  // Process one frame
await Future.delayed(const Duration(milliseconds: 200));
await tester.pump();  // Process next frame
```

## Timeout Configuration

### Always Add Timeouts to Complex UI Tests
```dart
testWidgets(
  'complex marine UI test',
  (WidgetTester tester) async {
    // test body
  },
  timeout: Timeout(Duration(minutes: 2)),  // Prevents indefinite hangs
);
```

### Recommended Timeout Values
- **Simple tests**: 30 seconds (default is usually fine)
- **Complex UI with animations**: 2 minutes
- **Marine navigation UI with charts**: 2-5 minutes
- **Integration tests with real APIs**: 15 minutes

## Common Test Hang Patterns

### Pattern 1: Filter Controls with Sliders
**Symptom**: Test hangs after tapping filter button  
**Root Cause**: Slider widgets trigger continuous rebuilds  
**Solution**: Replace pumpAndSettle() with pumpAndWait()

### Pattern 2: Date Pickers
**Symptom**: Test times out after opening date selection  
**Root Cause**: Calendar widgets have complex rebuild cycles  
**Solution**: Use pumpAndWait() with 1-2 second duration

### Pattern 3: Chart Loading
**Symptom**: Test hangs after selecting state/region  
**Root Cause**: Async chart discovery causes multiple rebuilds  
**Solution**: Use pumpAndWait() instead of pumpAndSettle()

### Pattern 4: Dropdown Interactions
**Symptom**: Test completes but sometimes flaky  
**Root Cause**: Animation timing varies  
**Solution**: pumpAndSettle() usually works, but pumpAndWait() more reliable

## Debugging Workflow

### Step 1: Reproduce the Hang
```bash
flutter test test/path/to/test_file.dart --plain-name "exact test name"
# Wait 60 seconds
# Press Ctrl+C if it hangs
```

### Step 2: Identify the Pump Strategy
```bash
# Find pumpAndSettle calls in the test
grep -n "pumpAndSettle" test/path/to/test_file.dart

# Check what actions precede the hang
# Look for: tap(), drag(), enterText()
```

### Step 3: Replace with pumpAndWait()
```dart
// BEFORE:
await tester.tap(find.text('Filter'));
await tester.pumpAndSettle();

// AFTER:
await tester.tap(find.text('Filter'));
await pumpAndWait(tester, wait: const Duration(seconds: 1));
```

### Step 4: Add Timeout Safety
```dart
testWidgets(
  'test that was hanging',
  (tester) async {
    // ... test body ...
  },
  timeout: Timeout(Duration(minutes: 2)),  // ADD THIS
);
```

### Step 5: Verify Fix
```bash
flutter test test/path/to/test_file.dart --plain-name "exact test name"
# Should complete in < 10 seconds
```

## Constitution Principle III Compliance

**CRITICAL**: When fixing stuck tests, you MUST:
- ✅ Preserve all expect() assertions
- ✅ Keep test data unchanged
- ✅ Maintain test behavior validation
- ❌ Never remove assertions to "fix" tests
- ❌ Never skip tests to make them pass
- ❌ Never change test data to avoid edge cases

**Why**: Tests exist for safety-critical marine navigation software. Changing assertions defeats the purpose of testing.

## Troubleshooting

### Test Still Hangs After pumpAndWait()
**Possible Causes**:
1. Widget truly needs more time → Increase wait duration
2. Widget never completes → Check widget implementation for infinite rebuilds
3. Test setup is wrong → Verify mocks and initial state

### Test Fails After Switching to pumpAndWait()
**Possible Causes**:
1. Wait too short → Increase duration
2. Test expects immediate response → Review test expectations
3. Real bug exposed → Investigate widget behavior

### Test Passes Locally But Fails in CI
**Possible Causes**:
1. CI is slower → Increase wait durations for CI
2. Timing differences → Use longer timeouts in CI
3. Mock generation issues → See Mock Generation section below

## Mock Generation Best Practices

### Use --verbose Flag
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
```

### Verify @GenerateMocks Annotations
```dart
// Good: All classes are importable
@GenerateMocks([
  NoaaChartDiscoveryService,
  AppLogger,
])

// Bad: Circular dependencies
@GenerateMocks([
  ServiceA,  // ServiceA imports ServiceB
  ServiceB,  // ServiceB imports ServiceA
])
```

### CI-Specific Issues
- Add caching to speed up builds
- Use verbose logging for diagnostics
- Upload build logs on failure
- Set reasonable timeouts (5 minutes for mock generation)

## Related Documentation
- `contracts/test-pump-strategies.md` - Detailed contract specifications
- `contracts/mock-generation.md` - Build runner best practices
- `quickstart.md` - Step-by-step reproduction guide
- `.github/copilot-instructions.md` - Agent-specific patterns

## References
- Flutter Test Documentation: https://docs.flutter.dev/testing
- Widget Testing Best Practices: https://docs.flutter.dev/cookbook/testing/widget/introduction
- Constitution Principle III: `.specify/memory/constitution.md`
