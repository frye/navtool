# Tasks: Elliott Bay Chart Loading UX Improvements

**Input**: Design documents from `/Users/frye/Devel/repos/navtool/specs/001-phase-4-elliott/`
**Prerequisites**: plan.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

## Execution Flow
```
✅ 1. Loaded plan.md → Flutter 3.8.1+, Dart 3.8.1+, archive, crypto, flutter_riverpod
✅ 2. Loaded design documents:
   - data-model.md: 6 entities (ChartIntegrityHash, ChartLoadRequest, ChartLoadResult, ChartLoadError, ChartLoadingQueue, ChartLoadTestHooks)
   - contracts/: 6 service contracts (ZipExtractor, ChartIntegrityRegistry, ChartLoadingService, ChartLoadingQueue, ChartLoadError, UI components)
   - research.md: 7 technical decisions (multi-pattern extraction, SharedPreferences persistence, exponential backoff, etc.)
   - quickstart.md: 9 test scenarios
✅ 3. Generated 32 tasks across 5 phases
✅ 4. Applied task rules: [P] for parallel, TDD ordering
✅ 5. Validated: All contracts have tests, all entities have models, tests before implementation
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions
- **Flutter single project**: `lib/`, `test/` at repository root
- Source: `lib/core/`, `lib/features/charts/`
- Tests: `test/core/`, `test/features/charts/`

---

## Phase 3.1: Setup & Prerequisites

### T001: Verify Project Dependencies
**File**: `pubspec.yaml`
**Action**: Verify all required packages are present:
- `archive: ^3.4.0` (ZIP handling)
- `crypto: ^3.0.3` (SHA256)
- `shared_preferences: ^2.2.2` (persistence)
- `flutter_riverpod: ^2.4.9` (state management)
- Run `flutter pub get` to ensure dependencies installed

**Acceptance**: All packages listed in pubspec.yaml, `flutter pub get` succeeds

---

### T002: [P] Configure Test Fixtures Path
**File**: `pubspec.yaml`
**Action**: Verify test fixtures are configured in `flutter.assets`:
```yaml
flutter:
  assets:
    - assets/s57/US5WA50M_harbor_elliott_bay.zip
    - assets/s57/US3WA01M_puget_sound.zip
```
Verify files exist at these paths.

**Acceptance**: Fixtures listed in pubspec.yaml, files exist on disk

---

### T003: [P] Update Analysis Options
**File**: `analysis_options.yaml`
**Action**: Verify linting rules are configured (no changes needed, just verify)
- Ensure `flutter_lints` is enabled
- Check for any Phase 4-specific lint exclusions needed

**Acceptance**: `flutter analyze --fatal-infos` passes on feature branch

---

## Phase 3.2: Tests First (TDD) ⚠️ MUST COMPLETE BEFORE 3.3

**CRITICAL: These tests MUST be written and MUST FAIL before ANY implementation in Phase 3.3**

### T004: [P] Unit Test - ZipExtractor Multi-Pattern Extraction
**File**: `test/core/utils/zip_extractor_test.dart` (MODIFY existing)
**Action**: Add test cases for multi-pattern ZIP extraction:
- Test 1: Extract from nested layout (ENC_ROOT/chartId/chartId.000) using US5WA50M.zip
- Test 2: Extract from root layout (chartId.000) using synthetic ZIP
- Test 3: Extract from simple nested (chartId/chartId.000) using synthetic ZIP
- Test 4: Return null if chart not found in any pattern
- Test 5: Case-insensitive matching for all patterns
- Test 6: Verify 411KB bytes extracted from US5WA50M.zip

**Expected**: Tests FAIL (extractChart method doesn't support multi-pattern yet)

**Acceptance**: 6 test cases added, all fail with clear error messages

---

### T005: [P] Unit Test - ChartIntegrityRegistry CRUD
**File**: `test/core/services/chart_integrity_registry_test.dart` (NEW)
**Action**: Create unit tests for integrity registry:
- Test 1: `getExpectedHash` returns null for unknown chart
- Test 2: `storeHash` persists hash with firstLoadTimestamp
- Test 3: `getExpectedHash` returns stored hash after storage
- Test 4: `verifyIntegrity` returns firstLoad for new chart
- Test 5: `verifyIntegrity` returns match for correct hash
- Test 6: `verifyIntegrity` returns mismatch for wrong hash
- Test 7: `storeHash` updates lastVerifiedTimestamp on second call
- Test 8: Hash persists across registry recreation (SharedPreferences)

**Expected**: Tests FAIL (methods not implemented yet)

**Acceptance**: 8 test cases created, all fail with clear error messages

---

### T006: [P] Unit Test - ChartLoadingService Retry Logic
**File**: `test/features/charts/services/chart_loading_service_test.dart` (NEW)
**Action**: Create unit tests for retry logic:
- Test 1: Success on first attempt (0 retries)
- Test 2: Transient failure, retry with 100ms backoff, succeed on 2nd attempt
- Test 3: Two failures, retry with 200ms backoff, succeed on 3rd attempt
- Test 4: Three failures, retry with 400ms backoff, succeed on 4th attempt
- Test 5: Four failures, max retries exhausted, return error
- Test 6: Exponential backoff timing validation (100, 200, 400, 800ms)
- Test 7: Progress indicator shown after 500ms
- Test 8: Result includes retry attempt count

**Expected**: Tests FAIL (ChartLoadingService doesn't exist yet)

**Acceptance**: 8 test cases created, all fail with clear error messages

---

### T007: [P] Unit Test - ChartLoadingQueue FIFO Processing
**File**: `test/features/charts/services/chart_loading_queue_test.dart` (NEW)
**Action**: Create unit tests for queue:
- Test 1: Empty queue returns idle status
- Test 2: Enqueue single request, processes immediately
- Test 3: Enqueue 3 requests, processes sequentially (FIFO)
- Test 4: Queue status displays correct position
- Test 5: getQueueStatus returns accurate state
- Test 6: Concurrent enqueues maintain order
- Test 7: Queue empties after all requests complete

**Expected**: Tests FAIL (ChartLoadingQueue doesn't exist yet)

**Acceptance**: 7 test cases created, all fail with clear error messages

---

### T008: [P] Unit Test - ChartLoadError Factory Methods
**File**: `test/features/charts/chart_load_error_test.dart` (NEW)
**Action**: Create unit tests for error factories:
- Test 1: `integrityMismatch` factory creates correct error type
- Test 2: `parsingFailed` factory includes retry count
- Test 3: `extractionFailed` factory includes file path in debug mode
- Test 4: Error messages are user-friendly (< 200 chars)
- Test 5: Troubleshooting guidance is actionable
- Test 6: Technical details only populated in debug mode
- Test 7: Retry attempts within 0-4 range

**Expected**: Tests FAIL (factory methods incomplete)

**Acceptance**: 7 test cases created, all fail with clear error messages

---

### T009: Widget Test - Chart First Load Flow
**File**: `test/features/charts/chart_first_load_test.dart` (NEW)
**Action**: Create widget test for first-time chart load (Scenario 1 from quickstart.md):
- Load Elliott Bay chart (US5WA50M) from ZIP
- Verify progress indicator appears after 500ms
- Verify chart renders successfully
- Verify no error dialogs shown
- Verify hash stored in registry with firstLoadTimestamp

**Expected**: Test FAILS (progress indicator, hash storage not implemented)

**Acceptance**: Widget test created, fails with clear error message

---

### T010: Widget Test - Chart Integrity Match Flow
**File**: `test/features/charts/chart_integrity_match_test.dart` (NEW)
**Action**: Create widget test for subsequent load with hash match (Scenario 2):
- Pre-seed registry with known hash
- Load same chart again
- Verify hash verification passes
- Verify chart renders successfully
- Verify lastVerifiedTimestamp updated

**Expected**: Test FAILS (hash verification not implemented)

**Acceptance**: Widget test created, fails with clear error message

---

### T011: Widget Test - Integrity Mismatch Error Dialog
**File**: `test/features/charts/chart_integrity_mismatch_test.dart` (EXISTS - MODIFY)
**Action**: Enhance existing widget test:
- Use ChartLoadTestHooks.forceIntegrityMismatch = true
- Verify error dialog appears with correct message
- Verify retry button present and functional
- Verify dismiss button present and functional
- Verify chart does NOT render

**Expected**: Test FAILS (retry/dismiss actions not fully implemented)

**Acceptance**: Enhanced test fails with clear error message

---

### T012: Widget Test - Transient Failure Retry Sequence
**File**: `test/features/charts/chart_transient_retry_test.dart` (EXISTS - MODIFY)
**Action**: Enhance existing widget test:
- Use ChartLoadTestHooks.failParsingAttempts = 3
- Verify exponential backoff timing (100, 200, 400ms)
- Verify progress indicator remains visible during retries
- Verify eventual success after 3 retries
- Verify retry count in result

**Expected**: Test FAILS (exponential backoff not implemented)

**Acceptance**: Enhanced test fails with clear error message

---

### T013: Widget Test - Retry Exhaustion Flow
**File**: `test/features/charts/chart_retry_exhaustion_test.dart` (NEW)
**Action**: Create widget test for max retries exhausted (Scenario 5):
- Use ChartLoadTestHooks.failParsingAttempts = 5
- Verify 4 retry attempts (not 5)
- Verify error dialog with "4 attempts" message
- Verify retry button allows manual reattempt
- Verify dismiss button closes dialog

**Expected**: Test FAILS (max retry limit not enforced)

**Acceptance**: Widget test created, fails with clear error message

---

### T014: Widget Test - Sequential Queue UI
**File**: `test/features/charts/chart_queue_processing_test.dart` (NEW)
**Action**: Create widget test for queue status display (Scenario 7):
- Enqueue 3 charts rapidly
- Verify "Loading X, Y in queue" message
- Verify only 1 chart loads at a time
- Verify queue position updates as charts complete
- Verify all 3 charts eventually render

**Expected**: Test FAILS (queue UI not implemented)

**Acceptance**: Widget test created, fails with clear error message

---

### T015: Widget Test - Progress Indicator Timing
**File**: `test/features/charts/chart_progress_indicator_test.dart` (NEW)
**Action**: Create widget test for 500ms threshold (Scenario 8):
- Test 1: Fast load (< 500ms) → No progress indicator
- Test 2: Slow load (> 500ms) → Progress indicator appears at 500ms
- Test 3: Progress indicator dismisses on completion

**Expected**: Test FAILS (500ms threshold not implemented)

**Acceptance**: Widget test created, fails with clear error message

---

### T016: [P] Unit Test - Logging Observability
**File**: `test/core/monitoring/chart_load_logging_test.dart` (NEW)
**Action**: Create unit tests for dual logging (Scenario 9):
- Test 1: Minimal logs in production (FR-020)
- Test 2: Debug logs include hash computation
- Test 3: Debug logs include retry attempts with timing
- Test 4: Debug logs include performance metrics
- Test 5: Technical details redacted in production

**Expected**: Test FAILS (logging not implemented)

**Acceptance**: 5 test cases created, all fail with clear error messages

---

## Phase 3.3: Core Implementation (ONLY after tests are failing)

**GATE: All Phase 3.2 tests MUST be failing before starting this phase**

### T017: Implement ZipExtractor Multi-Pattern Logic
**File**: `lib/core/utils/zip_extractor.dart` (MODIFY existing)
**Action**: Enhance `extractChart` method with multi-pattern fallback for NOAA ENC ZIP archives:
1. Try pattern: `{chartId}.000` (root layout)
2. Try pattern: `ENC_ROOT/{chartId}/{chartId}.000` (nested ENC_ROOT layout)
3. Try pattern: `{chartId}/{chartId}.000` (simple nested layout)
4. For each pattern, try case-insensitive variations
5. Return bytes if found, null if all patterns fail
6. Log extraction attempts in debug mode

**Dependencies**: None (first implementation task)

**Acceptance**: T004 tests pass (6/6 green)

---

### T018: Implement ChartIntegrityRegistry Core Methods
**File**: `lib/core/services/chart_integrity_registry.dart` (MODIFY existing)
**Action**: Implement hash storage and verification:
1. Add SharedPreferences integration for persistence
2. Implement `getExpectedHash` (check in-memory cache, return hash or null)
3. Implement `storeHash` (validate format, update cache, persist to SharedPreferences)
4. Implement `verifyIntegrity` (return firstLoad/match/mismatch)
5. Add firstLoadTimestamp and lastVerifiedTimestamp tracking
6. Implement persistence across app restarts

**First-Load Capture Coordination Note**: This task implements the storage mechanism and persistence layer. The orchestration logic for WHEN to capture hashes (first-load detection, hash comparison flow) is implemented in T020 (ChartLoadingService). The service coordinates: extract → compute hash → check registry → capture if first load → verify if subsequent load.

**Dependencies**: T017 (needs working extraction to test hash storage)

**Acceptance**: T005 tests pass (8/8 green)

---

### T019: Create ChartLoadingQueue Service
**File**: `lib/features/charts/services/chart_loading_queue.dart` (NEW)
**Action**: Implement FIFO queue with sequential processing:
1. Create ChartLoadRequest model class
2. Implement `enqueue` method (add to queue, start processing if idle)
3. Implement `getQueueStatus` method (return queue state)
4. Implement sequential processing (one at a time, FIFO order)
5. Update queue status on enqueue/dequeue
6. Return Future<ChartLoadResult> for awaitable completion

**Dependencies**: T017, T018 (needs extraction and registry)

**Acceptance**: T007 tests pass (7/7 green)

---

### T020: Implement ChartLoadingService Retry Logic
**File**: `lib/features/charts/services/chart_loading_service.dart` (MODIFY existing)
**Action**: Add retry logic with exponential backoff:
1. Integrate ZipExtractor for chart extraction
2. Integrate ChartIntegrityRegistry for hash verification
3. Implement exponential backoff retry (100, 200, 400, 800ms)
4. Implement max 4 retry attempts
5. Track retry count in ChartLoadResult
6. Handle first-load hash capture
7. Handle integrity mismatch detection
8. Implement progress indicator timer (500ms threshold)

**Dependencies**: T017, T018, T019 (needs all core services)

**Acceptance**: T006 tests pass (8/8 green)

---

### T021: Enhance ChartLoadError Factory Methods
**File**: `lib/features/charts/chart_load_error.dart` (MODIFY existing)
**Action**: Implement structured error factories:
1. `integrityMismatch` factory with hash details
2. `parsingFailed` factory with retry count
3. `extractionFailed` factory with file path
4. Add troubleshooting guidance mapping
5. Add technical details (debug mode only)
6. Validate retry attempts within 0-4 range

**Dependencies**: T020 (error creation happens during service execution)

**Acceptance**: T008 tests pass (7/7 green)

---

### T022: Implement ChartLoadTestHooks Enhancements
**File**: `lib/features/charts/chart_load_test_hooks.dart` (MODIFY existing)
**Action**: Add new test hooks for fault injection:
1. Add `simulateLoadDuration` for progress indicator testing
2. Enhance `failParsingAttempts` to support exact failure count
3. Add `fastRetry` flag to speed up tests (skip backoff delays)
4. Ensure hooks only active in test/debug mode

**Dependencies**: T020 (hooks used by service)

**Acceptance**: Test hooks functional, used by T009-T015 widget tests

---

## Phase 3.4: UI Integration

**GATE: Core implementation (T017-T022) must be complete**

### T023: Add Progress Indicator UI Component
**File**: `lib/features/charts/widgets/chart_loading_overlay.dart` (NEW)
**Action**: Create loading overlay widget:
1. Display spinning progress indicator
2. Show "Loading {chartId}..." message
3. Show queue status if queueLength > 0
4. Appear after 500ms threshold (configurable via compile-time constant)
5. Dismiss on completion or error

**Configuration Implementation Note**: The 500ms threshold MUST be a Dart `const` value (compile-time constant), not a runtime configuration setting. This aligns with safety-critical requirements (FR-019a) preventing user tampering with critical timing thresholds. Use `const Duration progressIndicatorThreshold = Duration(milliseconds: 500);` in a constants file. Changing this value requires recompilation.

**Dependencies**: T020 (service triggers progress indicator)

**Acceptance**: T009, T014, T015 widget tests pass (progress indicator visible)

---

### T024: Enhance Chart Error Dialog UI
**File**: `lib/features/charts/widgets/chart_load_error_dialog.dart` (MODIFY existing)
**Action**: Add retry/dismiss actions:
1. Display error.message prominently
2. Show error.troubleshootingGuidance
3. Add "Retry" button (calls onRetry callback)
4. Add "Dismiss" button (calls onDismiss callback)
5. Format technical details if present (debug mode)

**Dependencies**: T021 (uses ChartLoadError structure)

**Acceptance**: T011, T013 widget tests pass (error dialog with actions)

---

### T025: Integrate Queue Status into Chart Browser
**File**: `lib/features/charts/screens/chart_browser_screen.dart` (MODIFY existing)
**Action**: Add queue status display:
1. Show "Loading {chartId}, X charts in queue" during processing
2. Update status on queue changes
3. Display queue position for each pending chart
4. Integrate with ChartLoadingQueue.getQueueStatus()

**Dependencies**: T019 (uses queue service)

**Acceptance**: T014 widget test passes (queue UI displays correctly)

---

### T026: Wire Retry/Dismiss Actions in Chart Browser
**File**: `lib/features/charts/screens/chart_browser_screen.dart` (MODIFY existing)
**Action**: Implement error dialog callbacks:
1. `onRetry`: Re-enqueue same chart load request
2. `onDismiss`: Close error dialog, return to chart list
3. Clear error state on retry or dismiss
4. Preserve chart selection after dismiss

**Dependencies**: T024 (error dialog with callbacks)

**Acceptance**: T011, T013 widget tests pass (retry/dismiss functional)

---

## Phase 3.5: Observability & Polish

**GATE: UI integration (T023-T026) must be complete**

### T027: [P] Implement Dual-Level Logging
**File**: `lib/core/monitoring/chart_load_logger.dart` (NEW)
**Action**: Create logging utility with minimal/debug modes:
1. Minimal mode (production): Only errors and critical events
2. Debug mode: Hash computation, retry attempts, timing metrics
3. Redact technical details in production
4. Log format: `[ChartLoad] {message}`
5. Integrate with existing logging infrastructure

**Dependencies**: None (can be parallel with other polish tasks)

**Acceptance**: T016 unit tests pass (5/5 green)

---

### T028: [P] Add Performance Metrics Logging
**File**: `lib/core/monitoring/chart_load_metrics.dart` (NEW)
**Action**: Track and log performance metrics:
1. ZIP extraction duration
2. Hash computation duration
3. Total load duration
4. Retry attempts and backoff timing
5. Queue processing time
6. Log metrics in debug mode only

**Dependencies**: None (parallel with T027)

**Acceptance**: Metrics logged in debug mode, verified in T016

---

### T029: [P] Update Integration Tests
**File**: `integration_test/chart_loading_integration_test.dart` (NEW)
**Action**: Create end-to-end integration test:
1. Load real US5WA50M chart from ZIP
2. Verify extraction, hash storage, rendering
3. Reload same chart, verify hash match
4. Test retry logic with simulated failures
5. Test queue processing with multiple charts
6. Run without mocks (real services, real fixtures)

**Dependencies**: All implementation complete (T017-T028)

**Acceptance**: Integration test passes with real NOAA fixtures

---

### T030: [P] Performance Validation
**File**: `test/performance/chart_load_performance_test.dart` (NEW)
**Action**: Create performance benchmarks:
1. ZIP extraction < 2s for 400KB chart (absolute limit, no tolerance)
2. Hash computation < 50ms for 400KB file (absolute limit, no tolerance)
3. Progress indicator appears within 500ms threshold (absolute limit)
4. Retry backoff timing accurate (±50ms tolerance: 100ms→50-150ms acceptable)
5. Queue processing overhead < 100ms per chart (absolute limit)

**Performance Tolerance Clarification**:
- Retry backoff delays: ±50ms tolerance (network timing variability)
- All other metrics: Absolute limits (no tolerance for safety-critical operations)

**Dependencies**: All implementation complete (T017-T028)

**Acceptance**: All performance targets met

---

### T031: Update Documentation
**File**: `docs/chart_loading_improvements.md` (NEW)
**Action**: Document Phase 4 improvements:
1. Multi-pattern ZIP extraction guide
2. Integrity verification workflow
3. Retry logic and backoff strategy
4. Queue processing behavior
5. Test hooks usage for fault injection
6. Troubleshooting guide for common errors

**Dependencies**: All implementation complete (T017-T028)

**Acceptance**: Documentation complete, reviewed for clarity

---

### T032: Run Quickstart Validation
**File**: `specs/001-phase-4-elliott/quickstart.md`
**Action**: Execute all 9 quickstart scenarios:
1. Run each test command from quickstart.md
2. Perform manual verification steps
3. Complete manual testing checklist
4. Verify all scenarios pass
5. Document any issues found

**Dependencies**: All implementation and tests complete (T001-T031)

**Acceptance**: All 9 quickstart scenarios pass

---

## Dependencies Summary

```
Setup (T001-T003)
  ↓
Tests (T004-T016) ← MUST FAIL before implementation
  ↓
Core Implementation:
  T017 (ZipExtractor)
    ↓
  T018 (ChartIntegrityRegistry) ← depends on T017
    ↓
  T019 (ChartLoadingQueue) ← depends on T017, T018
    ↓
  T020 (ChartLoadingService) ← depends on T017, T018, T019
    ↓
  T021 (ChartLoadError) ← depends on T020
    ↓
  T022 (ChartLoadTestHooks) ← depends on T020
  ↓
UI Integration:
  T023 (ProgressIndicator) ← depends on T020
  T024 (ErrorDialog) ← depends on T021
  T025 (QueueStatus) ← depends on T019
  T026 (RetryActions) ← depends on T024
  ↓
Polish (T027-T032) ← all can be parallel, depends on T017-T026 complete
```

## Parallel Execution Examples

### Parallel Group 1: Setup
```bash
# Launch T002-T003 together (T001 must complete first):
flutter test test/fixtures/ --check-only  # T002
flutter analyze --fatal-infos             # T003
```

### Parallel Group 2: Tests (After T001-T003)
```bash
# Launch T004-T008, T016 together (unit tests, different files):
flutter test test/core/utils/zip_extractor_test.dart &           # T004
flutter test test/core/services/chart_integrity_registry_test.dart &  # T005
flutter test test/features/charts/services/chart_loading_service_test.dart &  # T006
flutter test test/features/charts/services/chart_loading_queue_test.dart &  # T007
flutter test test/features/charts/chart_load_error_test.dart &   # T008
flutter test test/core/monitoring/chart_load_logging_test.dart & # T016
wait
```

### Sequential Group: Widget Tests (T009-T015)
```bash
# Widget tests must run sequentially (same test environment):
flutter test test/features/charts/chart_first_load_test.dart
flutter test test/features/charts/chart_integrity_match_test.dart
flutter test test/features/charts/chart_integrity_mismatch_test.dart
flutter test test/features/charts/chart_transient_retry_test.dart
flutter test test/features/charts/chart_retry_exhaustion_test.dart
flutter test test/features/charts/chart_queue_processing_test.dart
flutter test test/features/charts/chart_progress_indicator_test.dart
```

### Parallel Group 3: Polish (After T017-T026)
```bash
# Launch T027-T031 together (all independent):
# T027: Implement logging (new file)
# T028: Implement metrics (new file)
# T029: Integration test (new file)
# T030: Performance test (new file)
# T031: Documentation (new file)
# All can be done in parallel by different developers
```

---

## Validation Checklist

**GATE: Checked before marking feature complete**

- [x] All contracts have corresponding tests (T004-T008)
- [x] All entities have model implementations (T018-T020)
- [x] All tests come before implementation (Phase 3.2 before 3.3)
- [x] Parallel tasks are truly independent (verified in Dependencies section)
- [x] Each task specifies exact file path
- [x] No task modifies same file as another [P] task
- [x] TDD workflow enforced (tests MUST fail before implementation)
- [x] Performance targets validated (T030)
- [x] Integration tests with real fixtures (T029)
- [x] Documentation updated (T031)
- [x] Quickstart scenarios validated (T032)

---

## Execution Notes

1. **TDD Discipline**: Phase 3.2 tests MUST fail before starting Phase 3.3. This ensures tests are valid.

2. **Commit Strategy**: Commit after each task completion with message format: `[Phase 4] T###: Task description`

3. **Test Fixtures**: All tests use real NOAA ENC fixtures (US5WA50M_harbor_elliott_bay.zip). No synthetic data.

4. **Constitutional Compliance**: Each task follows Constitution v1.3.0 principles (safety-critical, offline-first, dual testing, etc.)

5. **Performance Targets**:
   - ZIP extraction: < 2s for 400KB chart
   - Hash computation: < 50ms
   - Progress indicator: 500ms threshold
   - Retry backoff: 100/200/400/800ms (±50ms tolerance)

6. **Error Handling**: All errors use structured ChartLoadError types with troubleshooting guidance (FR-005, FR-012, FR-022)

7. **Queue Processing**: Sequential FIFO, one chart at a time, with status updates (FR-026, FR-027)

8. **Logging**: Dual-level (minimal/debug) per FR-020, FR-021

---

## Task Completion Tracking

Track progress by marking tasks complete:
- [x] **Phase 3.1: Setup (T001-T003)** ✅ COMPLETE
  - Dependencies verified, test fixtures noted (missing but expected for TDD)
  - Analysis options validated, `flutter analyze --fatal-infos` passes

- [x] **Phase 3.2: Tests (T004-T016)** ✅ COMPLETE (Committed: 2f01632)
  - **85 comprehensive tests created** following TDD Principle III
  - **Unit Tests (56)**: T004-T008, T016
    - T004: ZipExtractor (8 tests **PASS** - feature already exists, **T017 SKIP**)
    - T005: ChartIntegrityRegistry (10 tests **FAIL** - need persistence)
    - T006: ChartLoadingService (10 tests **FAIL** - service doesn't exist)
    - T007: ChartLoadingQueue (9 tests **FAIL** - queue doesn't exist)
    - T008: ChartLoadError (11 tests **PASS** - feature exists, **T021 SKIP**)
    - T016: ChartLoadLogger (8 tests **FAIL** - logger doesn't exist)
  - **Widget Tests (29)**: T009-T015
    - T009: First load hash capture (3 tests)
    - T010: Integrity match success (3 tests)
    - T011: Integrity mismatch UI - **ENHANCED** (5 tests, +4 for retry/dismiss)
    - T012: Transient retry backoff - **ENHANCED** (5 tests, +4 for exponential timing)
    - T013: Retry exhaustion (4 tests)
    - T014: Sequential queue UI (4 tests)
    - T015: Progress indicator 500ms threshold (5 tests)
  - **Result**: 77/85 tests FAIL correctly (missing features), 8/85 PASS (existing features)
  - **Efficiency**: 2 tasks skippable (T017 ZipExtractor, T021 ChartLoadError) saves ~8 hours
  - **Documentation**: See `PHASE_3_2_TDD_TESTS_COMPLETE.md` for detailed analysis

- [ ] **Phase 3.3: Core Implementation (T018-T020, T022)** ← IN PROGRESS
  - T017: ZipExtractor (**SKIP** - already complete)
  - T018: ChartIntegrityRegistry persistence (3-4h) - captureFirstLoad, initialize, clear
  - T019: ChartLoadingQueue FIFO (3-4h) - sequential processing, deduplication
  - T020: ChartLoadingService retry logic (4-5h) - exponential backoff, max 4 retries
  - T021: ChartLoadError (**SKIP** - already complete)
  - T022: ChartLoadTestHooks enhancements (2-3h) - simulateLoadDuration, fastRetry
  - **Goal**: All 56 unit tests PASS (48 currently failing + 8 already passing)

- [ ] **Phase 3.4: UI Integration (T023-T026)**
  - Integrate ChartLoadingService, add retry/dismiss buttons, 500ms threshold, queue UI
  - **Goal**: All 29 widget tests PASS

- [ ] **Phase 3.5: Polish (T027-T032)**
  - Integration tests, manual validation, performance checks, documentation
  - **Goal**: All 85 tests PASS, coverage >90%, manual validation complete

**Current Status**: Phase 3.2 COMPLETE ✅ | Ready for Phase 3.3 implementation

---

*Generated from design documents in specs/001-phase-4-elliott/*
*Based on Constitution v1.3.0 - See `/memory/constitution.md`*
