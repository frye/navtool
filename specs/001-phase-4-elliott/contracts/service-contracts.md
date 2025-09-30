# Service Contracts: Elliott Bay Chart Loading UX

**Feature**: Phase 4 Elliott Bay Chart Loading UX Improvements  
**Date**: 2025-09-29

## Overview

This feature involves Flutter services and UI components rather than REST/GraphQL APIs. Contracts are defined as Dart interfaces with method signatures, parameters, return types, and error conditions.

---

## Contract 1: ZipExtractor Service

**File**: `lib/core/utils/zip_extractor.dart`

### Method: `extractChart`

**Purpose**: Extract a chart .000 cell file from a NOAA ENC ZIP archive supporting multiple layout patterns

**Signature**:
```dart
Future<Uint8List?> extractChart(String zipFilePath, String chartId)
```

**Parameters**:
- `zipFilePath` (String, required): Absolute path to ZIP archive
- `chartId` (String, required): NOAA chart identifier (e.g., "US5WA50M")

**Returns**:
- `Uint8List`: Raw bytes of the .000 cell file if found
- `null`: If chart not found in ZIP after all pattern attempts

**Error Conditions**:
- Throws `FileSystemException` if zipFilePath doesn't exist
- Throws `ArchiveException` if ZIP is corrupt/unreadable
- Returns `null` if chartId not found (not an error - handled by caller)

**Behavior**:
1. Open ZIP archive from zipFilePath
2. Try extraction patterns in order:
   - Direct root: `{chartId}.000`
   - ENC_ROOT nested: `ENC_ROOT/{chartId}/{chartId}.000`
   - Simple nested: `{chartId}/{chartId}.000`
   - Case-insensitive variations of above
3. Return bytes if found, null if all patterns fail

**Performance Contract**:
- Must complete within 2 seconds for typical chart ZIPs (< 1MB compressed)
- Memory: Single chart in memory at a time (< 10MB)

**Test Contract** (from FR-013 to FR-018):
- MUST extract from real US5WA50M_harbor_elliott_bay.zip fixture
- MUST handle all known NOAA ZIP layouts
- MUST perform case-insensitive matching
- MUST return 411KB bytes for Elliott Bay chart

---

## Contract 2: ChartIntegrityRegistry Service

**File**: `lib/core/services/chart_integrity_registry.dart`

### Method: `getExpectedHash`

**Purpose**: Retrieve stored SHA256 hash for a chart, if it exists

**Signature**:
```dart
String? getExpectedHash(String chartId)
```

**Parameters**:
- `chartId` (String, required): Chart identifier

**Returns**:
- `String`: 64-character hex SHA256 hash if chart previously loaded
- `null`: If chart never loaded before (first-time load)

**Error Conditions**:
- Never throws (null indicates "not found")

**Behavior**:
- Check in-memory cache first (O(1))
- Return hash if present, null otherwise

---

### Method: `storeHash`

**Purpose**: Capture and persist SHA256 hash for a chart (first-load or update)

**Signature**:
```dart
Future<void> storeHash(String chartId, String sha256Hash)
```

**Parameters**:
- `chartId` (String, required): Chart identifier
- `sha256Hash` (String, required): 64-character hex SHA256 hash

**Returns**:
- `void` (async completion)

**Error Conditions**:
- Throws `FormatException` if sha256Hash not 64 hex characters
- Throws `StorageException` if SharedPreferences write fails

**Behavior**:
1. Validate sha256Hash format (64 hex chars)
2. Update in-memory cache
3. Persist to SharedPreferences ("chart_integrity_hashes" key)
4. Set firstLoadTimestamp if new chart, lastVerifiedTimestamp if existing

**Performance Contract**:
- Must complete within 100ms (synchronous SharedPreferences write)

**Test Contract** (from FR-002, FR-002a):
- MUST persist across app restarts
- MUST capture hash on first load
- MUST update lastVerifiedTimestamp on subsequent loads

---

### Method: `verifyIntegrity`

**Purpose**: Compare computed hash against expected hash for integrity check

**Signature**:
```dart
ChartIntegrityResult verifyIntegrity(String chartId, String computedHash)
```

**Parameters**:
- `chartId` (String, required): Chart identifier
- `computedHash` (String, required): SHA256 hash of loaded chart data

**Returns**:
- `ChartIntegrityResult` enum:
  - `firstLoad`: No expected hash (first time loading this chart)
  - `match`: Computed hash matches expected hash
  - `mismatch`: Computed hash doesn't match expected hash

**Error Conditions**:
- Never throws (returns result enum)

**Behavior**:
1. Get expected hash from cache
2. If null: return `ChartIntegrityResult.firstLoad`
3. If matches: return `ChartIntegrityResult.match`
4. If differs: return `ChartIntegrityResult.mismatch`

**Test Contract** (from FR-003, FR-004):
- MUST detect mismatches (wrong hash vs expected)
- MUST identify first-load scenario (no expected hash)
- MUST confirm matches (correct hash vs expected)

---

## Contract 3: ChartLoadingService

**File**: `lib/features/charts/services/chart_loading_service.dart`

### Method: `loadChartFromZip`

**Purpose**: Orchestrate chart loading with ZIP extraction, integrity verification, parsing, and retry logic

**Signature**:
```dart
Future<ChartLoadResult> loadChartFromZip(String zipFilePath, String chartId)
```

**Parameters**:
- `zipFilePath` (String, required): Absolute path to ZIP archive
- `chartId` (String, required): NOAA chart identifier

**Returns**:
- `ChartLoadResult` object:
  - If success: `{ success: true, chartData: Uint8List, retryAttempts: int }`
  - If failure: `{ success: false, error: ChartLoadError, retryAttempts: int }`

**Error Conditions**:
- Never throws (errors captured in ChartLoadResult.error)

**Behavior**:
1. Start 500ms timer for progress indicator (FR-019)
2. Extract chart bytes via ZipExtractor
3. If extraction fails: return ChartLoadError.extractionFailed
4. Compute SHA256 hash of bytes
5. Verify integrity via ChartIntegrityRegistry
6. If first load: store hash, show first-load message
7. If mismatch: return ChartLoadError.integrityMismatch
8. If match or first load: parse chart with retry logic
9. On transient parse failure: retry with exponential backoff (FR-007, FR-008)
10. Max 4 retries (FR-009), then return ChartLoadError.parsingFailed
11. On success: return ChartLoadResult with chartData
12. Cancel progress timer on completion

**Performance Contract**:
- Progress indicator shown if loading exceeds 500ms (FR-019)
- Total time < 5s for typical chart (extract + hash + parse + retries)
- Retry backoff: 100ms, 200ms, 400ms, 800ms (FR-008)

**Test Contract** (from FR-007 to FR-012):
- MUST retry on transient failures
- MUST use exponential backoff timing
- MUST limit to 4 retry attempts
- MUST return result with retry count

---

## Contract 4: ChartLoadingQueue Service

**File**: `lib/features/charts/services/chart_loading_queue.dart` (new file)

### Method: `enqueue`

**Purpose**: Add a chart load request to the queue for sequential processing

**Signature**:
```dart
Future<ChartLoadResult> enqueue(ChartLoadRequest request)
```

**Parameters**:
- `request` (ChartLoadRequest): Chart load request object
  - `chartId`: Chart identifier
  - `zipFilePath`: Path to ZIP

**Returns**:
- `ChartLoadResult`: Completion result (awaitable future)

**Error Conditions**:
- Never throws (errors in ChartLoadResult)

**Behavior**:
1. Add request to internal FIFO queue
2. Update queue status UI (FR-027)
3. If not already processing: start processing
4. Return Future that completes when this request finishes

**Performance Contract**:
- Queue operations O(1)
- Status updates within 100ms

**Test Contract** (from FR-026, FR-027):
- MUST process requests sequentially (one at a time)
- MUST maintain FIFO order
- MUST display queue position to user

---

### Method: `getQueueStatus`

**Purpose**: Get current queue state for UI display

**Signature**:
```dart
ChartLoadingQueueStatus getQueueStatus()
```

**Parameters**:
- None

**Returns**:
- `ChartLoadingQueueStatus` object:
  - `isProcessing`: bool
  - `currentChartId`: String? (null if idle)
  - `queuedChartIds`: List<String>
  - `queueLength`: int

**Error Conditions**:
- Never throws

**Behavior**:
- Return snapshot of current queue state
- Used by UI to display "Loading chart X, Y in queue..."

**Test Contract**:
- MUST reflect accurate queue state
- MUST update immediately on enqueue/dequeue

---

## Contract 5: ChartLoadError Factory

**File**: `lib/features/charts/chart_load_error.dart` (existing, enhanced)

### Factory: `ChartLoadError.integrityMismatch`

**Purpose**: Create integrity mismatch error with troubleshooting guidance

**Signature**:
```dart
factory ChartLoadError.integrityMismatch({
  required String chartId,
  required String expectedHash,
  required String actualHash,
  required int retryAttempts,
})
```

**Returns**:
- `ChartLoadError` with:
  - `type: ChartLoadErrorType.integrityMismatch`
  - `message: "Chart data integrity verification failed"`
  - `troubleshootingGuidance: "Try re-downloading from NOAA..."`
  - `technicalDetails`: Debug info (if debug mode)

**Test Contract** (from FR-004, FR-005):
- MUST provide user-friendly message
- MUST include actionable troubleshooting guidance

---

### Factory: `ChartLoadError.parsingFailed`

**Purpose**: Create parsing failure error after retry exhaustion

**Signature**:
```dart
factory ChartLoadError.parsingFailed({
  required String chartId,
  required int retryAttempts,
  required dynamic originalException,
})
```

**Returns**:
- `ChartLoadError` with:
  - `type: ChartLoadErrorType.parsingFailed`
  - `message: "Unable to parse chart file"`
  - `troubleshootingGuidance: "Verify S-57 Edition 3.1 format..."`
  - `technicalDetails`: Stack trace (if debug mode)

**Test Contract** (from FR-012):
- MUST include retry attempt count
- MUST provide troubleshooting guidance

---

### Factory: `ChartLoadError.extractionFailed`

**Purpose**: Create ZIP extraction failure error

**Signature**:
```dart
factory ChartLoadError.extractionFailed({
  required String chartId,
  required String zipFilePath,
})
```

**Returns**:
- `ChartLoadError` with:
  - `type: ChartLoadErrorType.extractionFailed`
  - `message: "Cannot extract chart from ZIP archive"`
  - `troubleshootingGuidance: "ZIP file may be corrupt..."`
  - `technicalDetails`: File path (if debug mode)

**Test Contract** (from FR-018):
- MUST provide clear error when chart not found in ZIP
- MUST include troubleshooting guidance

---

## Contract 6: UI Components

**File**: `lib/features/charts/screens/chart_browser_screen.dart`

### Widget: ChartLoadErrorDialog

**Purpose**: Display error with retry/dismiss actions per FR-012, FR-022

**Props**:
```dart
class ChartLoadErrorDialog extends StatelessWidget {
  final ChartLoadError error;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;
}
```

**Behavior**:
- Display error.message prominently
- Show error.troubleshootingGuidance
- Two action buttons: "Retry" and "Dismiss"
- onRetry: Reattempt same chart load
- onDismiss: Close dialog, return to chart browser

**Test Contract**:
- MUST display error message and guidance
- MUST have retry and dismiss buttons
- MUST call callbacks on button press

---

### Widget: ChartLoadingOverlay

**Purpose**: Show progress indicator with queue status per FR-019, FR-027

**Props**:
```dart
class ChartLoadingOverlay extends StatelessWidget {
  final String currentChartId;
  final int queueLength;
}
```

**Behavior**:
- Appear after 500ms if loading not complete (FR-019, FR-019a)
- Show spinning progress indicator
- Display "Loading {currentChartId}..."
- If queueLength > 0: Show "X charts in queue"

**Test Contract**:
- MUST appear within 500ms threshold
- MUST display queue status if queue not empty

---

## Contract Testing Strategy

All contracts will have corresponding unit/widget tests:

1. **ZipExtractor**: Unit test with US5WA50M.zip, verify extraction
2. **ChartIntegrityRegistry**: Unit test hash storage, retrieval, verification
3. **ChartLoadingService**: Mock ZipExtractor/Registry, test retry logic
4. **ChartLoadingQueue**: Unit test FIFO ordering, status updates
5. **ChartLoadError**: Unit test factory methods, message mapping
6. **UI Components**: Widget tests (already exist for integrity/retry scenarios)

---

## Contract Validation

Each contract tested with:
- **Success path**: Happy case with valid inputs
- **Error path**: Invalid inputs, null returns, exceptions
- **Edge cases**: First load, max retries, empty queue, etc.

Tests must FAIL before implementation (TDD per Constitution Principle III).

---

## Conclusion

Service contracts cover all 27 functional requirements with clear interfaces, parameters, return types, and error conditions. Ready for contract test generation in Phase 1.
