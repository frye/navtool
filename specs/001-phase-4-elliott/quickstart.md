# Quickstart: Elliott Bay Chart Loading UX Testing

**Feature**: Phase 4 Elliott Bay Chart Loading UX Improvements  
**Date**: 2025-09-29

## Overview

This quickstart guide provides **copy-paste test scenarios** for validating the Elliott Bay chart loading UX improvements. Each scenario maps directly to functional requirements and acceptance criteria from `spec.md`.

All scenarios use **authentic NOAA ENC test data** per Constitution Principle II (Dual Testing Requirement):
- `US5WA50M_harbor_elliott_bay.zip` (Elliott Bay chart, 147KB compressed → 411KB .000 file)
- `US3WA01M_puget_sound.zip` (Puget Sound chart)

---

## Prerequisites

```bash
# Ensure you're on the feature branch
git checkout 001-phase-4-elliott

# Install dependencies (if not already done)
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs

# Verify test fixtures exist
ls -lh assets/s57/US5WA50M_harbor_elliott_bay.zip
ls -lh assets/s57/US3WA01M_puget_sound.zip
```

---

## Scenario 1: Successful Chart Loading (First Load)

**Requirements**: FR-001 (ZIP extraction), FR-002 (integrity capture), FR-019 (progress indicator)

**Test Type**: Widget test

**Steps**:
1. Load Elliott Bay chart from ZIP for the first time
2. Verify progress indicator appears if loading > 500ms
3. Verify chart extracts, hash computed and stored
4. Verify chart renders successfully

**Test Command**:
```bash
flutter test test/features/charts/chart_first_load_test.dart
```

**Expected Outcome**:
- ✅ Chart extracts from `US5WA50M_harbor_elliott_bay.zip`
- ✅ SHA256 hash computed: `a1b2c3...` (64-char hex)
- ✅ Hash stored in SharedPreferences with firstLoadTimestamp
- ✅ Chart renders in UI
- ✅ Progress indicator appears after 500ms if loading slow
- ✅ No error dialogs shown

**Manual Verification**:
```bash
# Run app, load Elliott Bay chart
flutter run -d macos

# In app UI:
1. Navigate to Chart Browser
2. Select "Elliott Bay (US5WA50M)"
3. Tap "Load Chart"
4. Observe:
   - Progress indicator appears if load time > 500ms
   - Chart appears on screen
   - No error messages

# Verify persistence:
# Restart app, load same chart again
# Should match stored hash (Scenario 2)
```

**Widget Test Code Sketch** (for reference):
```dart
testWidgets('Successful chart first load shows progress and chart',
    (WidgetTester tester) async {
  // Arrange: Mock chart load from real fixture
  final zipPath = 'assets/s57/US5WA50M_harbor_elliott_bay.zip';
  final chartId = 'US5WA50M';

  // Act: Trigger chart load
  await tester.pumpWidget(ChartBrowserScreen(initialChart: chartId));
  await tester.tap(find.text('Load Chart'));
  await tester.pump(Duration(milliseconds: 500)); // Check for progress indicator

  // Assert: Progress indicator shown if still loading
  expect(find.byType(ChartLoadingOverlay), findsOneWidget);

  // Wait for load to complete
  await tester.pumpAndSettle();

  // Assert: Chart rendered, no errors
  expect(find.byType(ChartDisplay), findsOneWidget);
  expect(find.byType(ChartLoadErrorDialog), findsNothing);
});
```

---

## Scenario 2: Chart Integrity Verification (Match)

**Requirements**: FR-002 (hash storage), FR-003 (integrity check), FR-004 (match confirmation)

**Test Type**: Unit test

**Steps**:
1. Load chart that has a stored hash (second load)
2. Verify computed hash matches expected hash
3. Verify chart loads successfully without errors

**Test Command**:
```bash
flutter test test/features/charts/chart_integrity_match_test.dart
```

**Expected Outcome**:
- ✅ Computed hash matches stored hash
- ✅ Chart loads successfully
- ✅ `lastVerifiedTimestamp` updated in registry
- ✅ No integrity error shown

**Unit Test Code Sketch**:
```dart
test('Chart integrity verification passes on hash match', () async {
  // Arrange: Store expected hash
  final registry = ChartIntegrityRegistry();
  final chartId = 'US5WA50M';
  final expectedHash = 'a1b2c3d4...'; // Known hash for US5WA50M
  await registry.storeHash(chartId, expectedHash);

  // Act: Load chart, compute hash, verify
  final zipExtractor = ZipExtractor();
  final chartBytes = await zipExtractor.extractChart(
    'assets/s57/US5WA50M_harbor_elliott_bay.zip',
    chartId,
  );
  final computedHash = sha256.convert(chartBytes!).toString();
  final result = registry.verifyIntegrity(chartId, computedHash);

  // Assert: Match result
  expect(result, ChartIntegrityResult.match);
  expect(computedHash, expectedHash);
});
```

---

## Scenario 3: Chart Integrity Mismatch Detection

**Requirements**: FR-004 (mismatch detection), FR-005 (error display), FR-022 (user actions)

**Test Type**: Widget test (existing: `test/features/charts/chart_integrity_mismatch_test.dart`)

**Steps**:
1. Use `ChartLoadTestHooks.forceIntegrityMismatch = true`
2. Load chart with mismatched hash
3. Verify integrity error dialog shown
4. Verify retry/dismiss buttons present

**Test Command**:
```bash
flutter test test/features/charts/chart_integrity_mismatch_test.dart
```

**Expected Outcome**:
- ✅ Integrity mismatch detected (computed ≠ expected)
- ✅ Error dialog appears with:
  - Message: "Chart data integrity verification failed"
  - Troubleshooting guidance: "Try re-downloading from NOAA..."
  - Retry button
  - Dismiss button
- ✅ Chart does NOT load into UI

**Widget Test Code Snippet** (existing file):
```dart
testWidgets('Chart integrity mismatch shows error dialog with retry',
    (WidgetTester tester) async {
  // Arrange: Force mismatch via test hook
  ChartLoadTestHooks.forceIntegrityMismatch = true;

  // Act: Load chart
  await tester.pumpWidget(ChartBrowserScreen(initialChart: 'US5WA50M'));
  await tester.tap(find.text('Load Chart'));
  await tester.pumpAndSettle();

  // Assert: Error dialog with retry/dismiss
  expect(find.byType(ChartLoadErrorDialog), findsOneWidget);
  expect(find.text('Chart data integrity verification failed'), findsOneWidget);
  expect(find.text('Retry'), findsOneWidget);
  expect(find.text('Dismiss'), findsOneWidget);

  // Cleanup
  ChartLoadTestHooks.forceIntegrityMismatch = false;
});
```

**Manual Verification**:
```bash
# Run app with test hooks enabled
flutter run -d macos --dart-define=ENABLE_TEST_HOOKS=true

# In app UI:
1. Navigate to Settings → Developer Options
2. Enable "Force Integrity Mismatch"
3. Go to Chart Browser
4. Load Elliott Bay chart
5. Verify error dialog appears
6. Tap "Retry" → Should still fail (forced mismatch)
7. Tap "Dismiss" → Returns to chart browser
```

---

## Scenario 4: Transient Failure Retry with Exponential Backoff

**Requirements**: FR-007 (retry on transient), FR-008 (exponential backoff), FR-009 (max retries)

**Test Type**: Widget test (existing: `test/features/charts/chart_transient_retry_test.dart`)

**Steps**:
1. Use `ChartLoadTestHooks.failParsingAttempts = 3`
2. Load chart, simulate transient parsing failures
3. Verify retry sequence with exponential backoff
4. Verify eventual success on 4th attempt

**Test Command**:
```bash
flutter test test/features/charts/chart_transient_retry_test.dart
```

**Expected Outcome**:
- ✅ Attempt 1 fails → Retry after 100ms
- ✅ Attempt 2 fails → Retry after 200ms
- ✅ Attempt 3 fails → Retry after 400ms
- ✅ Attempt 4 succeeds → Chart loads
- ✅ Total retries: 3
- ✅ Progress indicator remains visible during retries

**Widget Test Code Snippet** (existing file):
```dart
testWidgets('Transient failure retries with exponential backoff',
    (WidgetTester tester) async {
  // Arrange: Fail first 3 attempts, succeed on 4th
  ChartLoadTestHooks.failParsingAttempts = 3;
  ChartLoadTestHooks.fastRetry = false; // Use real timing

  // Act: Load chart
  final startTime = DateTime.now();
  await tester.pumpWidget(ChartBrowserScreen(initialChart: 'US5WA50M'));
  await tester.tap(find.text('Load Chart'));

  // Assert: Progress indicator during retries
  await tester.pump(Duration(milliseconds: 500));
  expect(find.byType(ChartLoadingOverlay), findsOneWidget);

  // Wait for retry sequence: 100 + 200 + 400 = 700ms + overhead
  await tester.pumpAndSettle();
  final duration = DateTime.now().difference(startTime);

  // Assert: Chart loaded after retries
  expect(find.byType(ChartDisplay), findsOneWidget);
  expect(find.byType(ChartLoadErrorDialog), findsNothing);

  // Verify exponential backoff timing (approximate)
  expect(duration.inMilliseconds, greaterThan(700));
  expect(duration.inMilliseconds, lessThan(2000));

  // Cleanup
  ChartLoadTestHooks.failParsingAttempts = 0;
});
```

---

## Scenario 5: Retry Exhaustion After Max Attempts

**Requirements**: FR-009 (max retries), FR-012 (error after exhaustion), FR-022 (user actions)

**Test Type**: Widget test

**Steps**:
1. Use `ChartLoadTestHooks.failParsingAttempts = 5`
2. Load chart, simulate persistent parsing failures
3. Verify retry sequence exhausted after 4 attempts
4. Verify error dialog shown with retry/dismiss

**Test Command**:
```bash
flutter test test/features/charts/chart_retry_exhaustion_test.dart
```

**Expected Outcome**:
- ✅ Attempts 1-4 fail with exponential backoff
- ✅ No 5th attempt (max 4 retries)
- ✅ Error dialog appears:
  - Message: "Unable to parse chart file"
  - Troubleshooting guidance: "Verify S-57 Edition 3.1 format..."
  - Retry button (allows manual reattempt)
  - Dismiss button
- ✅ Chart does NOT load

**Widget Test Code Sketch**:
```dart
testWidgets('Retry exhaustion shows error after max attempts',
    (WidgetTester tester) async {
  // Arrange: Fail all 5 attempts (only 4 retries allowed)
  ChartLoadTestHooks.failParsingAttempts = 5;
  ChartLoadTestHooks.fastRetry = true; // Speed up test

  // Act: Load chart
  await tester.pumpWidget(ChartBrowserScreen(initialChart: 'US5WA50M'));
  await tester.tap(find.text('Load Chart'));
  await tester.pumpAndSettle();

  // Assert: Error dialog after 4 retries
  expect(find.byType(ChartLoadErrorDialog), findsOneWidget);
  expect(find.text('Unable to parse chart file'), findsOneWidget);
  expect(find.textContaining('4 attempts'), findsOneWidget); // Retry count

  // Assert: Chart not loaded
  expect(find.byType(ChartDisplay), findsNothing);

  // Cleanup
  ChartLoadTestHooks.failParsingAttempts = 0;
});
```

---

## Scenario 6: ZIP Extraction with Multiple Layouts

**Requirements**: FR-013 to FR-018 (multi-pattern extraction)

**Test Type**: Unit test

**Steps**:
1. Test extraction from root layout: `{chartId}.000`
2. Test extraction from ENC_ROOT layout: `ENC_ROOT/{chartId}/{chartId}.000`
3. Test extraction from simple nested: `{chartId}/{chartId}.000`
4. Verify fallback logic tries all patterns

**Test Command**:
```bash
flutter test test/core/utils/zip_extractor_test.dart
```

**Expected Outcome**:
- ✅ Extracts from `US5WA50M_harbor_elliott_bay.zip` (nested layout)
- ✅ Extracts from synthetic ZIPs with root/ENC_ROOT layouts
- ✅ Returns 411KB bytes for US5WA50M chart
- ✅ Returns null if chart not found in any pattern

**Unit Test Code Sketch**:
```dart
group('ZipExtractor multi-pattern extraction', () {
  test('Extracts from nested layout (ENC_ROOT/chartId/chartId.000)', () async {
    // Arrange: Real NOAA ZIP with nested layout
    final extractor = ZipExtractor();
    final zipPath = 'assets/s57/US5WA50M_harbor_elliott_bay.zip';
    final chartId = 'US5WA50M';

    // Act: Extract
    final bytes = await extractor.extractChart(zipPath, chartId);

    // Assert: 411KB chart extracted
    expect(bytes, isNotNull);
    expect(bytes!.length, 411000, reason: '411KB .000 file');
  });

  test('Extracts from root layout (chartId.000)', () async {
    // Arrange: Synthetic ZIP with root layout
    final zipPath = await createSyntheticZip(rootLayout: true);
    final extractor = ZipExtractor();

    // Act: Extract
    final bytes = await extractor.extractChart(zipPath, 'TEST123');

    // Assert: Extracted successfully
    expect(bytes, isNotNull);
  });

  test('Returns null if chart not found in any pattern', () async {
    // Arrange: ZIP without target chart
    final extractor = ZipExtractor();
    final zipPath = 'assets/s57/US3WA01M_puget_sound.zip';
    final chartId = 'NONEXISTENT';

    // Act: Extract
    final bytes = await extractor.extractChart(zipPath, chartId);

    // Assert: Null return (not found)
    expect(bytes, isNull);
  });
});
```

---

## Scenario 7: Sequential Queue Processing

**Requirements**: FR-026 (sequential processing), FR-027 (queue status display)

**Test Type**: Widget test

**Steps**:
1. Enqueue 3 chart load requests rapidly
2. Verify only 1 chart loads at a time (sequential)
3. Verify queue status displays "Loading X, Y in queue..."
4. Verify all 3 charts eventually load

**Test Command**:
```bash
flutter test test/features/charts/chart_queue_processing_test.dart
```

**Expected Outcome**:
- ✅ Chart 1 loads, Charts 2-3 queued
- ✅ UI shows "Loading US5WA50M, 2 charts in queue"
- ✅ Chart 2 loads after Chart 1 completes
- ✅ UI updates to "Loading US3WA01M, 1 chart in queue"
- ✅ Chart 3 loads after Chart 2 completes
- ✅ All charts rendered successfully

**Widget Test Code Sketch**:
```dart
testWidgets('Sequential queue processes charts one at a time',
    (WidgetTester tester) async {
  // Arrange: Queue 3 charts
  final queue = ChartLoadingQueue();
  final charts = ['US5WA50M', 'US3WA01M', 'TEST123'];

  // Act: Enqueue all 3 rapidly
  final futures = charts.map((id) => queue.enqueue(
    ChartLoadRequest(chartId: id, zipFilePath: 'assets/s57/$id.zip'),
  )).toList();

  // Assert: Only 1 processing at a time
  await tester.pump(Duration(milliseconds: 100));
  final status1 = queue.getQueueStatus();
  expect(status1.isProcessing, true);
  expect(status1.currentChartId, 'US5WA50M');
  expect(status1.queueLength, 2);

  // UI shows queue status
  expect(find.text('Loading US5WA50M'), findsOneWidget);
  expect(find.text('2 charts in queue'), findsOneWidget);

  // Wait for first to complete
  await tester.pumpAndSettle();
  final status2 = queue.getQueueStatus();
  expect(status2.currentChartId, 'US3WA01M');
  expect(status2.queueLength, 1);

  // Wait for all to complete
  await Future.wait(futures);
  final status3 = queue.getQueueStatus();
  expect(status3.isProcessing, false);
  expect(status3.queueLength, 0);
});
```

---

## Scenario 8: Progress Indicator Timing

**Requirements**: FR-019 (500ms threshold), FR-019a (configurability)

**Test Type**: Widget test

**Steps**:
1. Load chart that completes < 500ms
2. Verify progress indicator does NOT appear
3. Load chart that completes > 500ms
4. Verify progress indicator appears after 500ms

**Test Command**:
```bash
flutter test test/features/charts/chart_progress_indicator_test.dart
```

**Expected Outcome**:
- ✅ Fast load (< 500ms): No progress indicator
- ✅ Slow load (> 500ms): Progress indicator appears at 500ms mark
- ✅ Progress indicator disappears on completion

**Widget Test Code Sketch**:
```dart
testWidgets('Progress indicator appears only after 500ms threshold',
    (WidgetTester tester) async {
  // Arrange: Mock fast load (200ms)
  ChartLoadTestHooks.simulateLoadDuration = Duration(milliseconds: 200);

  // Act: Load chart
  await tester.pumpWidget(ChartBrowserScreen(initialChart: 'US5WA50M'));
  await tester.tap(find.text('Load Chart'));
  await tester.pump(Duration(milliseconds: 400)); // Check before 500ms

  // Assert: No progress indicator yet
  expect(find.byType(ChartLoadingOverlay), findsNothing);

  // Wait for completion
  await tester.pumpAndSettle();
  expect(find.byType(ChartDisplay), findsOneWidget);

  // --- Slow load scenario ---
  // Arrange: Mock slow load (1000ms)
  ChartLoadTestHooks.simulateLoadDuration = Duration(milliseconds: 1000);

  // Act: Load chart
  await tester.tap(find.text('Load Chart'));
  await tester.pump(Duration(milliseconds: 500)); // Check at 500ms

  // Assert: Progress indicator now visible
  expect(find.byType(ChartLoadingOverlay), findsOneWidget);

  // Wait for completion
  await tester.pumpAndSettle();
  expect(find.byType(ChartLoadingOverlay), findsNothing); // Dismissed
});
```

---

## Scenario 9: Logging and Observability

**Requirements**: FR-020, FR-021 (dual logging), FR-023 to FR-025 (observability)

**Test Type**: Unit test

**Steps**:
1. Enable debug logging mode
2. Perform chart load operation
3. Verify console output contains:
   - Hash computation logs
   - Retry attempt logs
   - Performance timing logs

**Test Command**:
```bash
flutter test test/core/monitoring/chart_load_logging_test.dart --dart-define=LOG_LEVEL=debug
```

**Expected Outcome**:
- ✅ Minimal logs in production (FR-020)
- ✅ Detailed logs in debug mode (FR-021):
  - `[ChartLoad] Computing hash for US5WA50M...`
  - `[ChartLoad] Hash: a1b2c3... (computed in 45ms)`
  - `[ChartLoad] Retry attempt 2/4 (backoff: 200ms)`
  - `[ChartLoad] Chart loaded successfully (total: 1.2s, retries: 2)`

**Unit Test Code Sketch**:
```dart
test('Debug logging includes hash, retries, and timing', () async {
  // Arrange: Enable debug logging
  Logger.setLevel(LogLevel.debug);
  final logs = <String>[];
  Logger.onLog = (message) => logs.add(message);

  // Act: Load chart with retries
  ChartLoadTestHooks.failParsingAttempts = 2;
  final service = ChartLoadingService();
  final result = await service.loadChartFromZip(
    'assets/s57/US5WA50M_harbor_elliott_bay.zip',
    'US5WA50M',
  );

  // Assert: Debug logs present
  expect(logs, contains(matches(r'Computing hash for US5WA50M')));
  expect(logs, contains(matches(r'Hash: [a-f0-9]{64}')));
  expect(logs, contains(matches(r'Retry attempt 1/4')));
  expect(logs, contains(matches(r'Retry attempt 2/4')));
  expect(logs, contains(matches(r'Chart loaded successfully \(total: \d+ms, retries: 2\)')));

  // Cleanup
  ChartLoadTestHooks.failParsingAttempts = 0;
});
```

---

## Running All Tests

### Unit + Widget Tests (Fast)
```bash
# Run all chart loading tests
flutter test test/features/charts/ test/core/utils/zip_extractor_test.dart

# Run with coverage
flutter test --coverage test/features/charts/ test/core/utils/zip_extractor_test.dart
```

### Integration Tests (Real Network)
```bash
# Real NOAA API endpoint tests
flutter test integration_test/noaa_real_endpoint_test.dart --timeout=30m
```

### Full Test Suite
```bash
# Use validated test script
./scripts/test.sh validate  # 10-15 minutes
```

---

## Manual Testing Checklist

Use this checklist for manual validation in the app UI:

- [ ] **First Load**: Load Elliott Bay chart, verify no errors, chart appears
- [ ] **Subsequent Load**: Reload same chart, verify hash match, chart appears
- [ ] **Integrity Mismatch**: Enable test hook, verify error dialog with retry/dismiss
- [ ] **Transient Retry**: Enable failure hook, verify retry sequence, eventual success
- [ ] **Retry Exhaustion**: Enable persistent failure hook, verify error after 4 retries
- [ ] **Progress Indicator**: Load slow chart, verify indicator appears after 500ms
- [ ] **Queue Processing**: Load 3 charts rapidly, verify sequential processing, queue status
- [ ] **Error Troubleshooting**: Trigger each error type, verify guidance text helpful
- [ ] **Debug Logging**: Enable debug mode, verify console logs detailed
- [ ] **Persistence**: Load chart, restart app, reload chart, verify hash persisted

---

## Troubleshooting

### Test Failures

**Symptom**: `zip_extractor_test.dart` fails with "Chart not found"  
**Fix**: Verify test fixtures exist in `assets/s57/` directory

**Symptom**: Timing tests fail intermittently  
**Fix**: Use `ChartLoadTestHooks.fastRetry = true` to speed up tests

**Symptom**: Widget tests don't show error dialogs  
**Fix**: Ensure `await tester.pumpAndSettle()` called after triggering load

### Manual Testing Issues

**Symptom**: Charts load instantly, can't see progress indicator  
**Fix**: Enable test hook to simulate slow load: `ChartLoadTestHooks.simulateLoadDuration = Duration(seconds: 2)`

**Symptom**: Error dialogs not appearing  
**Fix**: Check test hooks enabled: `flutter run --dart-define=ENABLE_TEST_HOOKS=true`

---

## Next Steps

After validating all scenarios:

1. ✅ Mark Phase 1 complete in `plan.md`
2. Run `/tasks` command to generate task breakdown
3. Begin implementation following TDD workflow
4. Run `./scripts/test.sh validate` before committing

---

## Conclusion

These 9 scenarios cover all 27 functional requirements with copy-paste test commands, expected outcomes, and troubleshooting guidance. Use this quickstart to validate the Elliott Bay chart loading UX implementation incrementally as you build each component.

**Remember**: Tests must FAIL before implementation (Constitution Principle III). Write the test, watch it fail, implement the fix, watch it pass.
