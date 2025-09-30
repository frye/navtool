# Quickstart: Reproduce and Validate Test Fixes

**Purpose**: Step-by-step guide to reproduce the stuck test issue, apply fixes, and validate that tests complete successfully.

## Prerequisites

- Flutter SDK 3.8.1+ installed
- Dart SDK 3.8.1+ installed
- NavTool repository cloned
- Terminal access
- ~15 minutes for full test run

## Part 1: Reproduce the Stuck Test Issue

### Step 1: Navigate to Project
```bash
cd /Users/frye/Devel/repos/navtool  # Or your repository path
git checkout 002-fix-stuck-tests
```

### Step 2: Install Dependencies
```bash
flutter pub get
# Expected: Resolving dependencies... (5-10 minutes)
# Success: Got dependencies!
```

### Step 3: Generate Mocks (Baseline)
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
# Expected: Mock generation completes in 1-5 minutes
# Success: [INFO] Succeeded after XXXms with YYY outputs
```

**If this fails**: See Part 4 for mock generation fixes.

### Step 4: Run Stuck Tests
```bash
flutter test test/features/charts/chart_browser_screen_test.dart --plain-name "should show date filtering controls when enabled"
```

**Expected Behavior (BEFORE FIX)**:
```
00:01 +0: ChartBrowserScreen Tests Enhanced Filtering Tests should show date filtering controls when enabled
[Hangs here indefinitely - no progress]
^C  # User must press Ctrl+C to cancel
```

**Observation**: Test hangs after test name is printed, never shows PASS or FAIL.

### Step 5: Run Next Stuck Test
```bash
flutter test test/features/charts/chart_browser_screen_test.dart --plain-name "should filter charts by scale range"
```

**Expected Behavior (BEFORE FIX)**:
```
00:01 +0: ChartBrowserScreen Tests Enhanced Filtering Tests should filter charts by scale range
[Hangs here indefinitely]
^C  # User must press Ctrl+C
```

### Step 6: Verify Problem
✅ Tests hang and require manual interruption  
✅ No error message indicating root cause  
✅ Other tests in same file may pass  

## Part 2: Apply Test Execution Fixes

### Step 7: Identify Problematic Pump Calls

Open `test/features/charts/chart_browser_screen_test.dart` and find the stuck tests around line 1095-1150:

```dart
testWidgets('should show date filtering controls when enabled', (
  WidgetTester tester,
) async {
  // ... setup code ...
  
  // Enable date filtering
  await tester.tap(find.text('Filter by Update Date'));
  await tester.pumpAndSettle();  // ← THIS HANGS
  
  // Assert
  expect(find.text('Start Date'), findsOneWidget);
});
```

**Problem**: `pumpAndSettle()` waits for all rebuilds to complete, but filter controls trigger continuous updates.

### Step 8: Replace pumpAndSettle() with pumpAndWait()

Change the problematic line:
```dart
// BEFORE:
await tester.pumpAndSettle();

// AFTER:
await pumpAndWait(tester, wait: const Duration(seconds: 1));
```

The `pumpAndWait()` helper is already defined in the test file (line 127-134).

### Step 9: Add Explicit Timeout

Add timeout to test:
```dart
testWidgets(
  'should show date filtering controls when enabled',
  (WidgetTester tester) async {
    // ... test body ...
  },
  timeout: Timeout(Duration(minutes: 2)),  // Add this
);
```

### Step 10: Repeat for Other Stuck Tests

Apply same fix pattern to:
- `should filter charts by scale range` (line ~1165)
- Any test using `pumpAndSettle()` after filter interactions

**Pattern**:
1. Find `await tester.pumpAndSettle()` after filter tap
2. Replace with `await pumpAndWait(tester)`
3. Add explicit timeout to testWidgets()

## Part 3: Validate Test Fixes

### Step 11: Run Fixed Tests Individually
```bash
flutter test test/features/charts/chart_browser_screen_test.dart --plain-name "should show date filtering controls when enabled"
```

**Expected Behavior (AFTER FIX)**:
```
00:01 +0: ChartBrowserScreen Tests Enhanced Filtering Tests should show date filtering controls when enabled
00:03 +1: ChartBrowserScreen Tests Enhanced Filtering Tests should show date filtering controls when enabled [PASS]
```

✅ Test completes in ~2-3 seconds  
✅ Shows [PASS] status  
✅ No hang or timeout

### Step 12: Run Full Test File
```bash
flutter test test/features/charts/chart_browser_screen_test.dart
```

**Expected Behavior**:
```
00:00 +0: loading test/features/charts/chart_browser_screen_test.dart
00:15 +10: ChartBrowserScreen Tests Screen Structure and Layout should create ChartBrowserScreen...
[... many tests ...]
15:00 +2150 ~27: All tests passed!
```

✅ All tests complete within 15 minutes  
✅ No hangs or manual interruptions  
✅ Failure count does not increase (some tests may skip)

### Step 13: Verify Test Behavior Unchanged
```bash
# Run tests before and after fix, compare output
flutter test test/features/charts/chart_browser_screen_test.dart > before.txt  # (Will hang, Ctrl+C after some tests)
# Apply fixes
flutter test test/features/charts/chart_browser_screen_test.dart > after.txt
diff before.txt after.txt
```

**Expected**: Only differences are completion times and previously-stuck tests now pass.  
**Validate**: Same assertions, same test count, no new failures.

## Part 4: Fix Mock Generation (If Needed)

### Step 14: Test Mock Generation
```bash
flutter clean
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
```

**If Successful**:
```
[INFO] Generating build script completed...
[INFO] Running build...
[INFO] Succeeded after 45.2s with 150 outputs
```

### Step 15: If Mock Generation Fails

**Common Error 1**: Dependency conflict
```bash
Error: Could not resolve package dependencies
```
**Fix**:
```bash
flutter pub upgrade
flutter packages pub run build_runner clean
flutter packages pub run build_runner build --delete-conflicting-outputs
```

**Common Error 2**: Invalid @GenerateMocks annotation
```bash
Error: Could not find class 'SomeClass' in @GenerateMocks
```
**Fix**: Open reported test file, verify all classes in @GenerateMocks are importable.

**Common Error 3**: File write error
```bash
Error: Could not write to file 'test/**/*.mocks.dart'
```
**Fix**:
```bash
# Delete build cache
rm -rf .dart_tool/build
# Retry generation
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
```

### Step 16: Validate Generated Mocks
```bash
# Check mocks exist
ls test/features/charts/chart_browser_screen_test.mocks.dart

# Verify mocks compile
flutter analyze test/features/charts/chart_browser_screen_test.mocks.dart

# Run tests using mocks
flutter test test/features/charts/chart_browser_screen_test.dart --plain-name "should discover charts when state is selected"
```

✅ Mock files exist  
✅ No analyzer errors  
✅ Tests using mocks pass

## Part 5: CI Validation

### Step 17: Update CI Workflow (If Needed)

Edit `.github/workflows/noaa_integration_tests.yml`:

```yaml
- name: Generate mocks
  run: flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
  timeout-minutes: 5
  
- name: Upload mock generation logs on failure
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: mock-generation-logs
    path: .dart_tool/build/entrypoint/build.log
```

### Step 18: Test CI Locally (Optional)

Using [act](https://github.com/nektos/act):
```bash
# Install act (macOS)
brew install act

# Run CI workflow locally
act -j unit-tests
```

### Step 19: Push and Monitor CI
```bash
git add test/features/charts/chart_browser_screen_test.dart
git commit -m "Fix stuck tests by replacing pumpAndSettle with pumpAndWait for filter interactions"
git push origin 002-fix-stuck-tests
```

Monitor GitHub Actions:
- ✅ Mock generation step completes
- ✅ Unit tests complete without timeout
- ✅ No manual intervention required

## Success Criteria

### Before Fix ❌
- Tests hang after "should show date filtering controls when enabled"
- Manual Ctrl+C required to terminate
- CI mock generation may fail
- Test suite never completes

### After Fix ✅
- All tests complete within 15 minutes
- No manual interruption needed
- Mock generation succeeds in CI
- Test behavior unchanged (same assertions)
- CI workflows run without manual intervention

## Troubleshooting

### Issue: Tests still hang after fix
**Check**: 
- Did you replace all `pumpAndSettle()` calls after filter taps?
- Did you use `pumpAndWait()` instead of `pumpAndSettleWithTimeout()`?
- Is the wait duration long enough (try increasing to 2 seconds)?

### Issue: Tests pass but take very long
**Check**:
- Are you using excessive wait durations?
- Can you reduce `pumpAndWait()` duration to 500ms?
- Profile test execution with `--verbose` flag

### Issue: Mock generation still fails in CI
**Check**:
- Is `build_runner` version compatible with Flutter SDK?
- Are all dependencies in pubspec.yaml up to date?
- Check CI logs with `--verbose` flag for specific error

### Issue: Test behavior changed after fix
**Stop**: This violates Constitution Principle III
**Action**: Revert changes, test behavior must remain identical
**Debug**: Use `pump()` with explicit delays instead of `pumpAndWait()`

## Estimated Time

- Part 1 (Reproduce): 5 minutes
- Part 2 (Apply Fixes): 10 minutes
- Part 3 (Validate): 20 minutes (includes full test run)
- Part 4 (Mock Generation): 5 minutes
- Part 5 (CI Validation): 10 minutes

**Total**: ~50 minutes for complete validation cycle

## Next Steps

After validation:
1. Document findings in PR description
2. Update `.github/copilot-instructions.md` with test debugging patterns
3. Add test execution guide to docs/
4. Merge to main branch after CI passes
5. Monitor for any test regressions

---

**Last Updated**: September 29, 2025  
**Validation Status**: Ready for testing
