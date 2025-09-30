# Research & Technical Decisions: Elliott Bay Chart Loading UX

**Feature**: Phase 4 Elliott Bay Chart Loading UX Improvements  
**Date**: 2025-09-29

## Research Areas

### 1. NOAA ENC ZIP Archive Layouts

**Decision**: Support multiple common NOAA ZIP layouts with path pattern fallback strategy

**Rationale**:
- NOAA ENC charts come in various ZIP structures:
  - Flat root: `chartId.000` directly in ZIP root
  - ENC_ROOT structure: `ENC_ROOT/chartId/chartId.000`
  - Nested structure: `chartId/chartId.000`
- Case variations exist (`ENC_ROOT` vs `enc_root`, `.000` vs `.000`)
- Current ZipExtractor returns null for nested layouts (blocking issue)

**Implementation Approach**:
```dart
// Try multiple path patterns in order:
1. Exact match: "{chartId}.000" (root)
2. ENC_ROOT pattern: "ENC_ROOT/{chartId}/{chartId}.000"
3. Nested pattern: "{chartId}/{chartId}.000"
4. Case-insensitive variations of above
5. Recursive search as fallback
```

**Alternatives Considered**:
- Single fixed path: Rejected - breaks with real NOAA downloads
- Recursive search only: Rejected - slow for large ZIPs
- User configuration: Rejected - poor UX for marine environment

**Test Validation**:
- Unit test with real US5WA50M_harbor_elliott_bay.zip fixture
- Verify extraction of 411KB .000 cell file
- Test all known NOAA layout variations

---

### 2. Integrity Hash Storage & First-Load Capture

**Decision**: SharedPreferences with JSON serialization for hash registry persistence

**Rationale**:
- Lightweight for chart ID → SHA256 hash mapping (< 1KB per 100 charts)
- Synchronous access for chart loading pipeline
- Already used in NavTool for settings (consistent pattern)
- No database overhead for simple key-value storage
- Offline-first compatible

**Schema**:
```dart
// SharedPreferences key: "chart_integrity_hashes"
{
  "US5WA50M": "a1b2c3d4...",  // SHA256 hex string
  "US3WA01M": "e5f6g7h8...",
  ...
}
```

**First-Load Behavior**:
1. Extract chart data bytes from ZIP
2. Compute SHA256 hash
3. Check registry for existing hash
4. If not found: Store hash, mark as first load in UI
5. If found: Compare, fail if mismatch

**Alternatives Considered**:
- SQLite database: Rejected - overkill for simple map, slower synchronous access
- File-based JSON: Rejected - SharedPreferences handles cross-platform file paths
- In-memory only: Rejected - hashes lost on app restart (defeats integrity purpose)
- NOAA API hash source: Rejected - requires network, violates offline-first

---

### 3. Exponential Backoff Retry Strategy

**Decision**: 4 retries with exponential backoff (100ms, 200ms, 400ms, 800ms)

**Rationale**:
- Transient failures typically resolve within 1-2 seconds
- Total retry time: 1.5 seconds max (100+200+400+800=1500ms)
- Exponential prevents resource thrashing under contention
- 4 attempts balances responsiveness vs. persistence
- Standard pattern in distributed systems and mobile apps

**Implementation**:
```dart
int attempt = 0;
const maxRetries = 4;
while (attempt < maxRetries) {
  try {
    return await parseChart(data);
  } catch (e) {
    if (isTransient(e) && attempt < maxRetries - 1) {
      await Future.delayed(Duration(milliseconds: 100 * pow(2, attempt)));
      attempt++;
    } else {
      throw ChartLoadError.parsingFailed(retries: attempt);
    }
  }
}
```

**Alternatives Considered**:
- Linear backoff: Rejected - doesn't adapt to contention
- Jittered backoff: Rejected - complexity not needed for single-user app
- Infinite retries: Rejected - violates FR-009 (infinite loop prevention)
- Immediate retry: Rejected - amplifies resource contention

**Test Validation**:
- Widget test with failParsingAttempts=2, fastRetry=true flag
- Assert 3 attempts made (initial + 2 retries)
- Verify exponential timing with mockable timer

---

### 4. Progress Indicator Timing (500ms Threshold)

**Decision**: 500ms configurable constant before showing loading overlay

**Rationale**:
- Fast operations (< 500ms) don't need progress indicator (avoid flicker)
- Marine users expect responsive feedback for longer operations
- 500ms is perceptual threshold for "instantaneous" vs "working"
- Configurable constant allows adjustment without code changes
- Standard UX pattern (iOS HIG: 500ms, Material Design: 400ms)

**Implementation**:
```dart
// lib/core/config/chart_loading_config.dart
class ChartLoadingConfig {
  static const progressIndicatorDelay = Duration(milliseconds: 500);
  // Easy to change before compilation
}

// Usage in loading service
Future<void> loadChart(String chartId) async {
  final timer = Timer(ChartLoadingConfig.progressIndicatorDelay, () {
    showProgressIndicator();
  });
  try {
    await _actualLoadLogic(chartId);
  } finally {
    timer.cancel();
  }
}
```

**Alternatives Considered**:
- Immediate indicator: Rejected - causes flicker for fast loads
- 1 second threshold: Rejected - too long for desktop UX
- No indicator: Rejected - violates FR-019 (progress feedback required)
- Adaptive timing: Rejected - complexity not justified

---

### 5. Sequential Queue Processing vs Concurrent Loading

**Decision**: Sequential queue with FIFO processing (one chart at a time)

**Rationale**:
- Simplifies resource management (memory, file handles, CPU)
- Prevents integrity verification race conditions
- Ensures predictable performance for marine safety-critical operations
- Reduces peak memory usage (one chart ZIP in memory at a time)
- Clear queue status feedback to user (position in queue)

**Implementation**:
```dart
class ChartLoadingQueue {
  final Queue<ChartLoadRequest> _queue = Queue();
  bool _isProcessing = false;

  Future<void> enqueue(ChartLoadRequest request) async {
    _queue.add(request);
    _updateQueueStatus(); // FR-027: Display queue position
    if (!_isProcessing) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    _isProcessing = true;
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      await _loadSingleChart(request);
    }
    _isProcessing = false;
  }
}
```

**Alternatives Considered**:
- Unlimited concurrent: Rejected - memory exhaustion risk with large ZIPs
- Fixed concurrency (N=2): Rejected - adds complexity, marginal benefit
- Priority queue: Rejected - FIFO is predictable for user expectations
- Cancellation support: Deferred - not in Phase 4 scope

**Performance Impact**:
- Typical chart load: 1-2 seconds (ZIP extract + parse + integrity)
- Queue of 5 charts: 5-10 seconds total (acceptable for batch operations)
- Single chart responsive: < 500ms to show progress

---

### 6. Observability: Dual Logging Levels

**Decision**: Minimal logging by default, comprehensive in debug mode (--debug flag)

**Rationale**:
- Production logs clean for user (error type + chart ID only)
- Debug mode for troubleshooting (stack traces, hash values, file paths)
- Follows standard Flutter logging patterns (debugPrint, kDebugMode)
- Reduces log noise for marine users
- Enables developer diagnostics without performance impact

**Implementation**:
```dart
class ChartLogger {
  static bool debugMode = false; // Set by --debug launch flag

  static void logError(ChartLoadError error) {
    // Minimal: Always logged
    print('[CHART] Error loading ${error.chartId}: ${error.type}');
    
    if (debugMode) {
      // Comprehensive: Debug only
      print('[CHART DEBUG] Stack trace: ${error.stackTrace}');
      print('[CHART DEBUG] File path: ${error.filePath}');
      print('[CHART DEBUG] Expected hash: ${error.expectedHash}');
      print('[CHART DEBUG] Actual hash: ${error.actualHash}');
      print('[CHART DEBUG] System state: ${_captureSystemState()}');
    }
  }
}
```

**Log Levels**:
- **Minimal**: Error type, chart ID, timestamp
- **Debug**: Above + stack traces, file paths, hash values, extraction details, retry counts, system memory/CPU

**Alternatives Considered**:
- Single verbose level: Rejected - too noisy for production
- Multiple levels (info/warn/error/debug): Rejected - over-engineering for this feature
- Remote logging: Deferred - not in Phase 4 scope
- Structured JSON logs: Deferred - file logging not in scope

---

### 7. Error Message Patterns & Troubleshooting Guidance

**Decision**: ChartLoadError enum with mapped troubleshooting suggestions

**Rationale**:
- Structured error types enable clear, actionable UI messages
- Maps to FR-020, FR-021 (specific messages + troubleshooting)
- Marine users need guidance, not technical jargon
- Enum ensures exhaustive error handling

**Error Types & Messages**:
```dart
enum ChartLoadErrorType {
  integrityMismatch,  // "Chart data integrity verification failed"
  parsingFailed,      // "Unable to parse chart file"
  extractionFailed,   // "Cannot extract chart from ZIP archive"
  fileNotFound,       // "Chart file not found"
}

Map<ChartLoadErrorType, String> troubleshootingGuidance = {
  integrityMismatch: "Chart file may be corrupted. Try re-downloading from NOAA.",
  parsingFailed: "Chart format may be unsupported. Verify S-57 edition 3.1.",
  extractionFailed: "ZIP archive may be corrupt. Check file integrity.",
  fileNotFound: "Chart ID not found in archive. Verify correct file.",
};
```

**User Actions** (FR-012):
- Retry button: Re-attempt same operation
- Dismiss button: Close error, return to chart browser
- Copy error details: For bug reports (debug mode only)

**Alternatives Considered**:
- Generic error messages: Rejected - poor UX for troubleshooting
- Multi-step wizards: Rejected - too complex for marine environment
- Auto-recovery attempts: Rejected - user should control retry
- Error codes: Rejected - not user-friendly

---

## Testing Strategy

### Unit Tests
- **ZipExtractor**: Real NOAA ZIP fixture, all layout patterns, case variations
- **ChartIntegrityRegistry**: First-load capture, hash persistence, mismatch detection
- **ChartLoadingQueue**: FIFO ordering, status updates, sequential processing
- **Retry Logic**: Exponential backoff timing, max attempts, transient detection

### Widget Tests (Existing, Enhanced)
- **chart_integrity_mismatch_test.dart**: Force integrity mismatch, verify error UI
- **chart_transient_retry_test.dart**: Inject transient failure, verify retry sequence
- Both tests use ChartLoadTestHooks for deterministic fault injection

### Integration Tests (Existing Pipeline)
- Real NOAA ENC ZIP → extract → hash → parse → SENC → render
- Validates end-to-end with authentic Elliott Bay chart data

---

## Dependencies & Compatibility

### Existing Dependencies
- ✅ `archive` package: ZIP extraction (already in pubspec.yaml)
- ✅ `crypto` package: SHA256 hashing (Dart SDK built-in)
- ✅ `shared_preferences`: Persistence (already in pubspec.yaml)
- ✅ `flutter_riverpod`: State management (already used)

### New Dependencies
- ❌ None required - all functionality within existing packages

### Platform Compatibility
- ✅ Desktop (Linux, Windows, macOS): Primary target
- ✅ iOS: Secondary target (all dependencies compatible)
- ✅ Offline operation: No network dependencies

---

## Performance Benchmarks

**Target Performance** (from FR and spec):
- Progress indicator: < 500ms
- ZIP extraction: < 2s for 400KB chart (US5WA50M)
- SHA256 computation: < 100ms for 400KB data
- Total load time: < 3s (extraction + hash + parse + verify)
- Retry backoff total: < 1.5s (100+200+400+800ms)

**Measured Baselines** (from issue #203):
- Elliott Bay ZIP: 147KB compressed → 411KB .000 file
- Current extraction: Works for flat layout, fails for nested
- Current parsing: Works when data available

**Success Criteria**:
- All NOAA ZIP layouts extract successfully
- Integrity verification adds < 200ms overhead
- Retry logic completes within 5s for worst case (4 retries)

---

## Risk Assessment

### Low Risk
- ✅ ZIP extraction patterns: Well-tested approach, real fixtures available
- ✅ SHA256 computation: Standard crypto library
- ✅ Retry logic: Common pattern, well-understood

### Medium Risk
- ⚠️ First-load UX: User confusion about "no hash to verify" message
  - **Mitigation**: Clear messaging, "First time loading this chart"
- ⚠️ Queue status display: Layout integration with existing UI
  - **Mitigation**: Leverage existing loading overlay infrastructure

### High Risk
- ❌ None identified

---

## Implementation Notes

### File Modification Summary
- **lib/core/utils/zip_extractor.dart**: Add multi-pattern extraction
- **lib/core/services/chart_integrity_registry.dart**: Add first-load capture + persistence
- **lib/features/charts/services/chart_loading_service.dart**: Add retry logic + queue
- **lib/features/charts/screens/chart_browser_screen.dart**: Add retry/dismiss UI
- **test/core/utils/zip_extractor_test.dart**: Add NOAA layout tests
- **test/core/services/chart_integrity_registry_test.dart**: New file, unit tests

### Test Infrastructure
- Existing: ChartLoadTestHooks, widget test framework, real fixtures
- New: Unit tests for registry, enhanced ZipExtractor tests

### Configuration
- New constant: ChartLoadingConfig.progressIndicatorDelay (500ms)
- Easy to adjust before compilation (FR-019a requirement)

---

## Conclusion

All technical unknowns resolved. No NEEDS CLARIFICATION markers remain. Design aligns with NavTool constitution (safety-critical, offline-first, dual testing, authentic data). Ready to proceed to Phase 1: Design & Contracts.

**Key Decisions Summary**:
1. Multi-pattern ZIP extraction with fallback
2. SharedPreferences for hash persistence with first-load capture
3. Exponential backoff (100ms, 200ms, 400ms, 800ms) for 4 retries
4. 500ms configurable progress indicator threshold
5. Sequential FIFO queue processing
6. Dual logging (minimal/debug) with --debug flag
7. Structured error types with troubleshooting guidance

All decisions validated against constitutional principles and marine safety requirements.
