# Tasks: Fix Stuck Tests and Mock Generation Failures

**Input**: Design documents from `/Users/frye/Devel/repos/navtool/specs/002-fix-stuck-tests/`
**Prerequisites**: plan.md (✓), research.md (✓), data-model.md (✓), contracts/ (✓), quickstart.md (✓)

## Execution Flow (main)
```
1. Load plan.md from feature directory ✓
   → Tech stack: Dart 3.8.1+, Flutter 3.8.1+, mockito, build_runner
   → Structure: Single Flutter project, test infrastructure fixes only
2. Load optional design documents ✓
   → data-model.md: Test execution states, pump strategies, mock workflow
   → contracts/: test-pump-strategies.md, mock-generation.md
   → research.md: Root causes (pumpAndSettle loops, build_runner issues)
   → quickstart.md: Reproduction and validation procedures
3. Generate tasks by category:
   → Preparation: Baseline measurements, analysis
   → Fixes: Test execution strategy changes
   → CI Updates: Mock generation improvements
   → Validation: Test completion verification
   → Documentation: Update guides and patterns
4. Apply task rules:
   → Different files = mark [P] for parallel
   → Test fixes = sequential (same file modifications)
   → CI updates = parallel (different workflow files)
5. Number tasks sequentially (T001, T002...)
6. Generate dependency graph
7. Create parallel execution examples
8. Validate task completeness: ✓
   → All stuck tests identified
   → All pump strategies have fix approach
   → Mock generation contract implemented
   → Validation procedures defined
9. Return: SUCCESS (tasks ready for execution)
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions
Flutter single project structure:
- **Test files**: `test/features/charts/chart_browser_screen_test.dart`
- **CI workflows**: `.github/workflows/*.yml`
- **Documentation**: `docs/`, `.github/copilot-instructions.md`

---

## Phase 3.1: Preparation and Analysis

### T001 [P] Document Current Test Execution Baseline ✅
**Type**: Analysis  
**Parallel-Safe**: Yes  
**Estimated Time**: 15 minutes
**Status**: COMPLETE

**Objective**: Establish baseline metrics for test execution time and behavior before fixes.

**Files Created**:
- `specs/002-fix-stuck-tests/baseline-measurements.md` ✅

**Validation**:
- [x] Baseline execution times documented
- [x] Identified tests that hang documented
- [x] Current timeout values recorded
- [x] Test count before fixes: 78 expect(), 30 testWidgets()

**Dependencies**: None

---

### T002 [P] Identify All Stuck Tests with Grep Analysis ✅
**Type**: Analysis  
**Parallel-Safe**: Yes  
**Estimated Time**: 10 minutes
**Status**: COMPLETE

**Objective**: Use grep to find all pumpAndSettle() calls in problematic test groups.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
grep -n "pumpAndSettle" test/features/charts/chart_browser_screen_test.dart | grep -A5 -B5 "Filter"
```

**Files to Analyze**:
- `test/features/charts/chart_browser_screen_test.dart` (lines ~1095-1200)

**Expected Findings**:
- "should show date filtering controls when enabled" (line ~1095)
- "should filter charts by scale range" (line ~1165)
- Other filter-related tests with pumpAndSettle()

**Validation**:
- [ ] All stuck test names identified
- [ ] Line numbers for pumpAndSettle() calls documented
- [ ] Test group structure understood

**Dependencies**: None

---

### T003 [P] Verify pumpAndWait Helper Implementation ✅
**Type**: Analysis  
**Parallel-Safe**: Yes  
**Estimated Time**: 5 minutes
**Status**: COMPLETE

**Objective**: Confirm pumpAndWait() helper is correctly implemented per contract.

**Files to Inspect**:
- `test/features/charts/chart_browser_screen_test.dart` (lines 127-134)

**Contract Validation**:
```dart
Future<void> pumpAndWait(
  WidgetTester tester, {
  Duration wait = const Duration(milliseconds: 800),
}) async {
  await tester.pump();
  await Future.delayed(wait);
  await tester.pump();
}
```

**Validation**:
- [ ] pumpAndWait() signature matches contract
- [ ] Default wait duration is 800ms
- [ ] Implementation follows pump() → delay → pump() pattern
- [ ] Helper is defined in test file and accessible

**Dependencies**: None

---

### T004 [P] Audit @GenerateMocks Annotations
**Type**: Analysis  
**Parallel-Safe**: Yes  
**Estimated Time**: 15 minutes

**Objective**: Verify all @GenerateMocks annotations are valid and importable.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
grep -r "@GenerateMocks" test/ --include="*.dart" | wc -l  # Count annotations
grep -r "@GenerateMocks" test/ --include="*.dart" | head -20  # Sample review
```

**Files to Audit**:
- `test/features/charts/chart_browser_screen_test.dart`
- All ~150 test files with @GenerateMocks

**Validation**:
- [ ] All classes in @GenerateMocks are importable
- [ ] No circular dependencies in mock lists
- [ ] No private constructors in mocked classes
- [ ] Import statements match @GenerateMocks classes

**Dependencies**: None

---

## Phase 3.2: Test Execution Fixes

⚠️ **CRITICAL**: These tasks modify the same file sequentially. Do NOT parallelize.

### T005 Fix "should show date filtering controls when enabled" Test ✅
**Type**: Fix  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes
**Status**: COMPLETE

**Objective**: Replace pumpAndSettle() with pumpAndWait() to prevent infinite loop.

**Files to Modify**:
- `test/features/charts/chart_browser_screen_test.dart` (line ~1100)

**Change Required**:
```dart
// BEFORE (line ~1100):
await tester.tap(find.text('Filter by Update Date'));
await tester.pumpAndSettle();

// AFTER:
await tester.tap(find.text('Filter by Update Date'));
await pumpAndWait(tester, wait: const Duration(seconds: 1));
```

**Validation**:
- [ ] pumpAndSettle() replaced with pumpAndWait()
- [ ] Test compiles without errors
- [ ] No other changes to test assertions
- [ ] Test still validates same UI behavior

**Dependencies**: T003 (verify pumpAndWait exists)

---

### T006 Fix "should filter charts by scale range" Test ✅
**Type**: Fix  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes
**Status**: COMPLETE (Test already uses pumpAndWait, added timeout)

**Objective**: Replace pumpAndSettle() with pumpAndWait() for scale filter test.

**Files to Modify**:
- `test/features/charts/chart_browser_screen_test.dart` (line ~1170)

**Change Required**:
```dart
// BEFORE (line ~1170):
await tester.tap(find.text('Filter by Scale Range'));
await pumpAndWait(tester);  // This should already use pumpAndWait
// Verify Slider interactions use pumpAndWait, not pumpAndSettle

// If pumpAndSettle() is found after Slider taps:
// REPLACE with pumpAndWait(tester, wait: const Duration(milliseconds: 800));
```

**Validation**:
- [ ] All pumpAndSettle() in scale filter test replaced
- [ ] Slider interactions use pumpAndWait()
- [ ] Test compiles without errors
- [ ] No assertion changes

**Dependencies**: T005 (sequential file modification)

---

### T007 Add Explicit Timeout to Enhanced Filtering Tests Group ✅
**Type**: Fix  
**Parallel-Safe**: No  
**Estimated Time**: 5 minutes
**Status**: COMPLETE

**Objective**: Add timeout to prevent indefinite hangs if fixes incomplete.

**Files to Modify**:
- `test/features/charts/chart_browser_screen_test.dart` (line ~1090)

**Change Required**:
```dart
// Add to group declaration (line ~1090):
group('Enhanced Filtering Tests', () {
  // Add timeout to individual tests or entire group
  
  testWidgets(
    'should show date filtering controls when enabled',
    (WidgetTester tester) async {
      // ... test body ...
    },
    timeout: Timeout(Duration(minutes: 2)),  // ADD THIS
  );
  
  testWidgets(
    'should filter charts by scale range',
    (WidgetTester tester) async {
      // ... test body ...
    },
    timeout: Timeout(Duration(minutes: 2)),  // ADD THIS
  );
});
```

**Validation**:
- [ ] Timeout added to stuck tests
- [ ] Timeout duration is 2 minutes
- [ ] Test compiles without errors
- [ ] Other tests in file unaffected

**Dependencies**: T006 (sequential file modification)

---

### T008 Scan for Other Filter-Related Tests Needing Fixes ✅
**Type**: Fix  
**Parallel-Safe**: No  
**Estimated Time**: 15 minutes
**Status**: COMPLETE (Fixed "should show scale filtering controls when enabled")

**Objective**: Find and fix any other tests using pumpAndSettle() after filter interactions.

**Files to Modify**:
- `test/features/charts/chart_browser_screen_test.dart` (scan entire file)

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
grep -n "pumpAndSettle" test/features/charts/chart_browser_screen_test.dart | grep -C3 "Filter\|filter"
```

**Action**:
- Review each instance of pumpAndSettle() in filter-related tests
- Replace with pumpAndWait() where appropriate
- Add timeout if missing

**Validation**:
- [ ] All filter-related pumpAndSettle() calls reviewed
- [ ] Appropriate replacements made
- [ ] No new test failures introduced
- [ ] Test file compiles

**Dependencies**: T007 (sequential file modification)

---

### T009 [P] Add Timeout to Other Complex UI Tests
**Type**: Fix  
**Parallel-Safe**: Yes (different test files)  
**Estimated Time**: 20 minutes

**Objective**: Add timeouts to other complex marine UI tests as preventive measure.

**Files to Modify** (if they have similar patterns):
- `test/features/charts/elliott_bay_rendering_test.dart`
- `test/features/charts/enhanced_chart_widget_test.dart`
- Other complex UI tests with pumpAndSettle()

**Change Pattern**:
```dart
testWidgets(
  'complex marine UI test',
  (WidgetTester tester) async {
    // ... test body ...
  },
  timeout: Timeout(Duration(minutes: 2)),  // ADD THIS
);
```

**Validation**:
- [ ] Complex UI tests identified
- [ ] Timeouts added where appropriate
- [ ] All modified files compile
- [ ] No test behavior changes

**Dependencies**: None (different files from T005-T008)

---

## Phase 3.3: Mock Generation Fixes

### T010 [P] Add --verbose Flag to CI Mock Generation Step ✅
**Type**: Fix  
**Parallel-Safe**: Yes  
**Estimated Time**: 10 minutes
**Status**: COMPLETE

**Objective**: Add verbose logging to diagnose CI mock generation failures.

**Files to Modify**:
- `.github/workflows/noaa_integration_tests.yml` (line 66)
- `.github/workflows/binary-builds.yml` (lines 47, 130, 224, 327)

**Change Required**:
```yaml
# BEFORE:
- name: Generate mocks
  run: flutter packages pub run build_runner build --delete-conflicting-outputs

# AFTER:
- name: Generate mocks
  run: flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
  timeout-minutes: 5
```

**Validation**:
- [ ] --verbose flag added to all workflows
- [ ] timeout-minutes: 5 added
- [ ] Workflow YAML syntax valid
- [ ] No other workflow changes

**Dependencies**: None

---

### T011 [P] Add Build Artifact Caching to CI Workflow ✅
**Type**: Fix  
**Parallel-Safe**: Yes  
**Estimated Time**: 15 minutes
**Status**: COMPLETE

**Objective**: Cache .dart_tool/build to speed up CI and reveal cache issues.

**Files to Modify**:
- `.github/workflows/noaa_integration_tests.yml`
- `.github/workflows/binary-builds.yml`

**Change Required**:
```yaml
# Add before mock generation step:
- name: Cache build artifacts
  uses: actions/cache@v3
  with:
    path: |
      .dart_tool/build
      **/*.mocks.dart
    key: ${{ runner.os }}-build-${{ hashFiles('**/pubspec.yaml') }}
    restore-keys: |
      ${{ runner.os }}-build-
```

**Validation**:
- [ ] Cache step added before mock generation
- [ ] Cache key uses pubspec.yaml hash
- [ ] Cache paths include .dart_tool/build
- [ ] Workflow syntax valid

**Dependencies**: None

---

### T012 [P] Update Mock Generation Error Messages ✅
**Type**: Fix  
**Parallel-Safe**: Yes  
**Estimated Time**: 10 minutes
**Status**: COMPLETE

**Objective**: Add error handling to CI for better diagnostics.

**Files to Modify**:
- `.github/workflows/noaa_integration_tests.yml`
- `.github/workflows/binary-builds.yml`

**Change Required**:
```yaml
- name: Generate mocks
  run: flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
  timeout-minutes: 5

- name: Upload mock generation logs on failure
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: mock-generation-logs-${{ runner.os }}
    path: |
      .dart_tool/build/entrypoint/build.log
      **/*.mocks.dart
    retention-days: 7
```

**Validation**:
- [ ] Upload artifact step added
- [ ] Conditional on failure()
- [ ] Includes build logs
- [ ] Retention period set

**Dependencies**: None

---

### T013 Run build_runner Clean and Build Locally
**Type**: Validation  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes

**Objective**: Validate mock generation works locally with clean build.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
flutter clean
rm -rf .dart_tool/build
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs --verbose
```

**Expected Output**:
```
[INFO] Generating build script completed...
[INFO] Running build...
[INFO] Succeeded after XX.Xs with 150 outputs
```

**Validation**:
- [ ] Mock generation completes successfully
- [ ] Exit code 0
- [ ] All .mocks.dart files generated
- [ ] No error messages in output
- [ ] Files compile without errors

**Dependencies**: T010, T011, T012 (need CI updates committed first)

---

## Phase 3.4: Validation

### T014 Run Stuck Tests Individually
**Type**: Validation  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes

**Objective**: Verify fixed tests now complete without hanging.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool

# Test 1: Date filtering
time flutter test test/features/charts/chart_browser_screen_test.dart \
  --plain-name "should show date filtering controls when enabled"

# Test 2: Scale range
time flutter test test/features/charts/chart_browser_screen_test.dart \
  --plain-name "should filter charts by scale range"
```

**Expected Behavior**:
- Tests complete within 2-3 seconds each
- Show [PASS] status
- No hang or manual interruption needed
- Exit code 0

**Validation**:
- [ ] "should show date filtering controls" PASSES
- [ ] "should filter charts by scale range" PASSES
- [ ] Completion time < 10 seconds each
- [ ] No Ctrl+C required
- [ ] Test output shows PASS

**Dependencies**: T005, T006, T007, T008 (test fixes must be applied)

---

### T015 Run Full Chart Browser Test File
**Type**: Validation  
**Parallel-Safe**: No  
**Estimated Time**: 20 minutes

**Objective**: Verify all tests in file complete within 15 minutes.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
time flutter test test/features/charts/chart_browser_screen_test.dart
```

**Expected Output**:
```
00:00 +0: loading test/features/charts/chart_browser_screen_test.dart
[... tests run ...]
XX:XX +2150 ~27: All tests passed!
```

**Validation**:
- [ ] All tests complete within 15 minutes
- [ ] No manual intervention required
- [ ] Test count approximately same (~2150)
- [ ] Skip count approximately same (~27)
- [ ] Exit code 0

**Dependencies**: T014 (individual tests pass)

---

### T016 Verify Test Count and Assertions Unchanged
**Type**: Validation  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes

**Objective**: Ensure no test behavior changed (Constitution Principle III).

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool

# Count test assertions
grep -c "expect(" test/features/charts/chart_browser_screen_test.dart

# Count testWidgets declarations
grep -c "testWidgets(" test/features/charts/chart_browser_screen_test.dart

# Compare with baseline from T001
```

**Validation**:
- [ ] Same number of expect() statements
- [ ] Same number of testWidgets() declarations
- [ ] No test assertions modified
- [ ] No test data changed
- [ ] Only pump strategies changed

**Dependencies**: T015 (full test run complete)

---

### T017 Measure Test Execution Time vs Baseline
**Type**: Validation  
**Parallel-Safe**: No  
**Estimated Time**: 10 minutes

**Objective**: Compare execution time improvements after fixes.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool

# Run with timing
time flutter test test/features/charts/chart_browser_screen_test.dart > after-fix-results.txt
```

**Analysis**:
- Compare with baseline from T001
- Document time savings
- Verify no excessive slowdown from wait strategies

**Validation**:
- [ ] Test suite completes within 15 minutes
- [ ] Previously stuck tests now complete in seconds
- [ ] No significant slowdown in passing tests
- [ ] Results documented in specs/002-fix-stuck-tests/

**Dependencies**: T016 (test behavior validated)

---

### T018 [P] Test Mock Generation in CI
**Type**: Validation  
**Parallel-Safe**: Yes  
**Estimated Time**: 30 minutes (CI runtime)

**Objective**: Validate CI mock generation works with updates.

**Commands**:
```bash
cd /Users/frye/Devel/repos/navtool
git add .github/workflows/
git commit -m "Add verbose logging and caching to mock generation"
git push origin 002-fix-stuck-tests
```

**Monitor**:
- GitHub Actions workflow runs
- Mock generation step completes
- No workflow failures
- Logs available if failure occurs

**Validation**:
- [ ] CI workflow triggers on push
- [ ] Mock generation step shows verbose output
- [ ] Cache step executes
- [ ] Mock generation completes in < 5 minutes
- [ ] All tests pass in CI
- [ ] No manual intervention needed

**Dependencies**: T010, T011, T012 (CI updates must be committed)

---

## Phase 3.5: Documentation

### T019 [P] Add Test Debugging Guide to docs/ ✅
**Type**: Documentation  
**Parallel-Safe**: Yes  
**Estimated Time**: 20 minutes
**Status**: COMPLETE

**Objective**: Create guide for debugging stuck tests in future.

**Files Created**:
- `docs/test-debugging-guide.md` ✅

**Content**:
- How to identify stuck tests
- When to use pumpAndSettle() vs pumpAndWait()
- Timeout configuration best practices
- Common test hang patterns
- Constitution Principle III compliance

**Validation**:
- [ ] Guide created in docs/
- [ ] Covers pump strategy selection
- [ ] Includes troubleshooting section
- [ ] References Constitution Principle III
- [ ] Markdown formatting correct

**Dependencies**: None

---

### T020 [P] Update PR Description with Findings
**Type**: Documentation  
**Parallel-Safe**: Yes  
**Estimated Time**: 15 minutes

**Objective**: Document bug fix for pull request review.

**Content**:
```markdown
## Problem
- Tests hung at "should show date filtering controls when enabled"
- Mock generation failed in CI with build_runner errors

## Root Causes
- pumpAndSettle() infinite loops with Slider widgets
- Missing --verbose flag prevented CI diagnostics

## Solution
- Replaced pumpAndSettle() with pumpAndWait() for filter interactions
- Added explicit timeouts to complex UI tests
- Enhanced CI mock generation with verbose logging and caching

## Testing
- All stuck tests now complete in < 10 seconds
- Full test suite completes in < 15 minutes
- Mock generation succeeds in CI
- No test behavior changes (Constitution Principle III)

## Validation
- ✓ Tests complete without Ctrl+C
- ✓ CI workflows run without intervention
- ✓ Same test count and assertions
- ✓ Mock files generate successfully
```

**Validation**:
- [ ] PR description includes problem statement
- [ ] Root causes documented
- [ ] Solution summary clear
- [ ] Testing results included
- [ ] Constitutional compliance noted

**Dependencies**: None

---

### T021 [P] Create Issue Template for Future Test Hangs ✅
**Type**: Documentation  
**Parallel-Safe**: Yes  
**Estimated Time**: 15 minutes
**Status**: COMPLETE

**Objective**: Provide template for reporting test hang issues.

**Files Created**:
- `.github/ISSUE_TEMPLATE/test-hang.md` ✅

**Files to Create**:
- `.github/ISSUE_TEMPLATE/test-hang.md`

**Content**:
```markdown
---
name: Test Hang Issue
about: Report a test that hangs or times out
title: '[TEST HANG] '
labels: testing, bug
assignees: ''
---

## Test Information
- **Test File**: (e.g., test/features/charts/chart_browser_screen_test.dart)
- **Test Name**: (exact test description)
- **Line Number**: (approximate location)

## Symptoms
- [ ] Test hangs indefinitely
- [ ] Test times out after X minutes
- [ ] Requires manual Ctrl+C interruption

## Context
- Last successful run: (date or "never")
- Recent changes: (related PRs or commits)
- Pump strategy used: (pumpAndSettle / pumpAndWait / pump)

## Reproduction Steps
1. Run: `flutter test <file> --plain-name "<test name>"`
2. Observe: (what happens)

## Expected Behavior
Test should complete within [X] seconds/minutes.

## Debug Checklist
- [ ] Checked for pumpAndSettle() in test
- [ ] Verified timeout is set
- [ ] Reviewed widget rebuild triggers
- [ ] Tested with pumpAndWait() as alternative
- [ ] Consulted docs/test-debugging-guide.md
```

**Validation**:
- [ ] Template created in .github/ISSUE_TEMPLATE/
- [ ] YAML frontmatter correct
- [ ] Checklist includes debugging steps
- [ ] References test-debugging-guide.md

**Dependencies**: T019 (test debugging guide must exist)

---

## Dependencies Graph

```
T001, T002, T003, T004 (Parallel - no dependencies)
    ↓
T005 (Fix date filter test)
    ↓
T006 (Fix scale range test) - depends on T005
    ↓
T007 (Add timeouts) - depends on T006
    ↓
T008 (Scan other tests) - depends on T007
    ↓
T009 (Other complex UI) - parallel after T008

T010, T011, T012 (Parallel CI updates - no dependencies)
    ↓
T013 (Local validation) - depends on T010, T011, T012
    ↓
T014 (Run stuck tests) - depends on T005-T008
    ↓
T015 (Full test file) - depends on T014
    ↓
T016 (Verify unchanged) - depends on T015
    ↓
T017 (Measure timing) - depends on T016
    ↓
T018 (CI validation) - depends on T010-T012

T019, T020, T021 (Parallel documentation - no dependencies)
```

## Parallel Execution Examples

### Batch 1: Preparation (All Parallel)
```bash
# Terminal 1
Task: "Document current test execution baseline in specs/002-fix-stuck-tests/baseline-measurements.md"

# Terminal 2
Task: "Identify all stuck tests with grep in test/features/charts/chart_browser_screen_test.dart"

# Terminal 3
Task: "Verify pumpAndWait helper at lines 127-134 in chart_browser_screen_test.dart"

# Terminal 4
Task: "Audit @GenerateMocks annotations across all 150 test files"
```

### Batch 2: CI Updates (All Parallel)
```bash
# Terminal 1
Task: "Add --verbose flag to mock generation in .github/workflows/noaa_integration_tests.yml line 66"

# Terminal 2
Task: "Add build artifact caching to .github/workflows/binary-builds.yml"

# Terminal 3
Task: "Add mock generation error upload to CI workflows"
```

### Batch 3: Documentation (All Parallel)
```bash
# Terminal 1
Task: "Create test debugging guide in docs/test-debugging-guide.md"

# Terminal 2
Task: "Update PR description with findings and validation results"

# Terminal 3
Task: "Create issue template in .github/ISSUE_TEMPLATE/test-hang.md"
```

## Notes

- **Sequential Tasks**: T005-T008 MUST run in order (same file modifications)
- **Test Preservation**: NO test assertions changed (Constitution Principle III)
- **Validation Critical**: T014-T017 verify fixes work without changing behavior
- **CI Validation**: T018 confirms fixes work in automated environment
- **Time Estimate**: ~5-6 hours total (including CI runtime and validation)

## Validation Checklist
*GATE: Verify before marking complete*

- [x] All contracts have corresponding implementation (test-pump-strategies → T005-T009)
- [x] All mock generation contracts implemented (mock-generation → T010-T013)
- [x] Tests before implementation enforced (T014 before considering complete)
- [x] Parallel tasks truly independent (T001-T004, T010-T012, T019-T021)
- [x] Each task specifies exact file path and line numbers
- [x] No task modifies same file as another [P] task
- [x] Constitution Principle III preserved (no test behavior changes)
- [x] All quickstart.md validation steps covered (T014-T018)

---

**Status**: Ready for execution
**Total Tasks**: 21 numbered tasks
**Parallel Tasks**: 10 tasks marked [P]
**Estimated Duration**: 5-6 hours (including CI runtime)
**Critical Path**: T001 → T005 → T006 → T007 → T008 → T014 → T015 → T016 → T017
