# Baseline Measurements - Test Execution Analysis

**Date**: September 29, 2025  
**Branch**: 002-fix-stuck-tests

## Test File: test/features/charts/chart_browser_screen_test.dart

### Test Count Baseline
- **expect() statements**: 78
- **testWidgets() declarations**: 30
- **Total file lines**: 1159

### Identified Stuck Tests

Based on grep analysis of pumpAndSettle() calls in filter-related tests:

#### Test 1: "should show date filtering controls when enabled"
- **Location**: Lines 997-1019
- **Problem**: Uses `await tester.pumpAndSettle()` after tapping "Filter by Update Date" (line 1013)
- **Symptom**: Test hangs indefinitely, never completes
- **Root Cause**: Filter controls with date pickers trigger continuous rebuilds

#### Test 2: "should filter charts by scale range"  
- **Location**: Lines 1021-1058
- **Status**: Already uses pumpAndWait() correctly (lines 1033, 1037, 1039, 1051)
- **Note**: This test should NOT hang - it's using the correct pump strategy

#### Test 3: "should show scale filtering controls when enabled"
- **Location**: Lines 970-995
- **Uses**: pumpAndSettleWithTimeout() at line 991
- **Status**: This might work but could be slow or unreliable

### pumpAndSettle() Usage Pattern

Found pumpAndSettle() calls at:
- Line 981: After initial pumpWidget (OK - initial setup)
- Line 985: After dropdown tap (OK - dropdown animation)
- Line 987: After California selection (OK - chart loading)
- Line 991: Using pumpAndSettleWithTimeout for filter UI (RISKY - extended timeout)
- Line 1009: After dropdown tap (OK - dropdown animation)
- Line 1013: **PROBLEM** - After "Filter by Update Date" tap - causes hang
- Line 1015: After California selection (OK - chart loading)

### Verification

#### pumpAndWait() Helper
- **Location**: Lines 127-134
- **Signature**: `Future<void> pumpAndWait(WidgetTester tester, {Duration wait = const Duration(milliseconds: 800)})`
- **Implementation**: ✅ Correct (pump → delay → pump pattern)
- **Default wait**: 800ms (sufficient for marine UI)

#### pumpAndSettleWithTimeout() Helper
- **Location**: Lines 119-124
- **Signature**: `Future<void> pumpAndSettleWithTimeout(WidgetTester tester, {Duration timeout = const Duration(seconds: 15)})`
- **Implementation**: Calls `tester.pumpAndSettle(timeout)`
- **Risk**: Still subject to infinite loops if widgets continuously rebuild

## Required Fixes

### Priority 1: Fix Stuck Test
**Test**: "should show date filtering controls when enabled" (line 1013)
- **Action**: Replace `await tester.pumpAndSettle()` with `await pumpAndWait(tester, wait: const Duration(seconds: 1))`
- **Reason**: Date filter controls cause continuous rebuilds

### Priority 2: Add Timeout Safety
**Test**: "should show date filtering controls when enabled"
- **Action**: Add `timeout: Timeout(Duration(minutes: 2))` to testWidgets declaration
- **Reason**: Prevents indefinite hangs if fix incomplete

### Priority 3: Review pumpAndSettleWithTimeout Usage
**Test**: "should show scale filtering controls when enabled" (line 991)
- **Consider**: Replace with pumpAndWait() for consistency
- **Reason**: More predictable behavior for filter interactions

## Next Steps

1. ✅ Baseline documented
2. Apply fix to line 1013 (T005)
3. Add timeout to test (T007)
4. Scan for other filter-related pumpAndSettle() calls (T008)
5. Run tests to verify fixes (T014)

## Notes

- Test count shows 30 testWidgets which contradicts task plan estimate of ~2150 tests
- This file has 30 test cases, not 2150 individual test executions
- Constitution Principle III: Preserve all 78 expect() statements
