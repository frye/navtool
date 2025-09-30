# Data Model: Elliott Bay Chart Loading UX

**Feature**: Phase 4 Elliott Bay Chart Loading UX Improvements  
**Date**: 2025-09-29

## Entities

### 1. ChartIntegrityHash

**Purpose**: Represents a stored SHA256 integrity hash for a chart, used for verification on subsequent loads

**Attributes**:
- `chartId` (String, required): Unique NOAA chart identifier (e.g., "US5WA50M")
- `sha256Hash` (String, required): Hex-encoded SHA256 hash of the chart .000 file (64 characters)
- `firstLoadTimestamp` (DateTime, required): When the hash was first captured
- `lastVerifiedTimestamp` (DateTime, optional): Last successful verification against this hash

**Relationships**:
- One-to-one with Chart entity (external, from existing model)
- Many stored in ChartIntegrityRegistry collection

**Validation Rules**:
- `chartId`: Non-empty, alphanumeric + underscore only
- `sha256Hash`: Exactly 64 hexadecimal characters (256 bits / 4 bits per char)
- `firstLoadTimestamp`: Must be in the past
- `lastVerifiedTimestamp`: Must be >= firstLoadTimestamp if present

**State Transitions**:
```
[New Chart] --> [First Load] --> ChartIntegrityHash created
            |
            v
[Subsequent Load] --> Hash compared --> [Match: Update lastVerifiedTimestamp]
                                   --> [Mismatch: Throw IntegrityError]
```

**Persistence**:
- Stored in SharedPreferences as JSON map: `{ chartId: { hash, firstLoad, lastVerified } }`
- Synchronized on every hash capture/update
- In-memory cache for fast lookup during loading

---

### 2. ChartLoadRequest

**Purpose**: Represents a user request to load a specific chart, queued for sequential processing

**Attributes**:
- `chartId` (String, required): Chart identifier to load
- `zipFilePath` (String, required): Absolute path to ZIP archive containing chart
- `timestamp` (DateTime, required): When request was enqueued
- `priority` (int, optional): Future extension for priority queue (always 0 for Phase 4)

**Relationships**:
- Queued in ChartLoadingQueue (ordered collection)
- Results in ChartLoadResult upon completion

**Validation Rules**:
- `chartId`: Non-empty
- `zipFilePath`: Valid file path, file must exist
- `timestamp`: Automatically set on creation
- `priority`: 0-10 range (Phase 4: always 0)

**State Transitions**:
```
[Enqueued] --> [Processing] --> [Completed]
                           --> [Failed]
           
Queue positions: 1st, 2nd, 3rd, ... (displayed to user per FR-027)
```

---

### 3. ChartLoadResult

**Purpose**: Outcome of a chart loading operation, either success or structured failure

**Attributes**:
- `chartId` (String, required): Chart identifier
- `success` (bool, required): True if load succeeded
- `chartData` (Uint8List, optional): Extracted .000 cell file bytes (if success)
- `error` (ChartLoadError, optional): Structured error information (if failure)
- `loadDurationMs` (int, required): Time taken for operation
- `retryAttempts` (int, required): Number of retries made (0 if succeeded first try)

**Relationships**:
- Created from ChartLoadRequest
- Contains ChartLoadError if failed
- Passed to chart rendering pipeline if successful

**Validation Rules**:
- If `success == true`: `chartData` must be non-null, `error` must be null
- If `success == false`: `error` must be non-null, `chartData` must be null
- `loadDurationMs`: Must be >= 0
- `retryAttempts`: 0-4 range (per FR-009)

**State Transitions**:
```
[Processing] --> [Extract ZIP] --> [Compute Hash] --> [Verify Hash] --> [Success]
                              |                  |                |
                              v                  v                v
                         [ExtractFailed]  [IntegrityMismatch]  [ParsingFailed]
                                          (with retry logic)
```

---

### 4. ChartLoadError

**Purpose**: Structured error information categorizing chart loading failures with troubleshooting guidance

**Attributes**:
- `type` (ChartLoadErrorType enum, required): Category of failure
- `chartId` (String, required): Chart that failed to load
- `message` (String, required): Human-readable error description
- `troubleshootingGuidance` (String, required): Actionable user guidance
- `technicalDetails` (String, optional): Debug-level details (file paths, hashes, stack traces)
- `retryAttempts` (int, required): Number of retries made before failure
- `timestamp` (DateTime, required): When error occurred

**Enum: ChartLoadErrorType**:
- `integrityMismatch`: SHA256 hash doesn't match expected value
- `parsingFailed`: S-57 parser error (transient or permanent)
- `extractionFailed`: ZIP extraction error (file not found, corrupt archive)
- `fileNotFound`: Chart ID not located in ZIP

**Relationships**:
- Contained in ChartLoadResult when success == false
- Maps to user-facing error dialog UI

**Validation Rules**:
- `type`: Must be valid enum value
- `message`: Non-empty, under 200 characters
- `troubleshootingGuidance`: Non-empty, actionable advice
- `technicalDetails`: Populated only if debug mode enabled
- `retryAttempts`: 0-4 range

**Error Message Mapping** (from FR-020, FR-021):
```dart
Map<ChartLoadErrorType, ErrorInfo> errorMessages = {
  ChartLoadErrorType.integrityMismatch: ErrorInfo(
    message: "Chart data integrity verification failed",
    guidance: "The chart file may be corrupted or modified. Try re-downloading the chart from NOAA.",
  ),
  ChartLoadErrorType.parsingFailed: ErrorInfo(
    message: "Unable to parse chart file",
    guidance: "The chart format may be unsupported. Verify the file is S-57 Edition 3.1 format.",
  ),
  ChartLoadErrorType.extractionFailed: ErrorInfo(
    message: "Cannot extract chart from ZIP archive",
    guidance: "The ZIP file may be corrupt or incomplete. Verify the download completed successfully.",
  ),
  ChartLoadErrorType.fileNotFound: ErrorInfo(
    message: "Chart file not found in archive",
    guidance: "The chart ID may not match the ZIP contents. Verify the correct file for this region.",
  ),
};
```

---

### 5. ChartLoadingQueue

**Purpose**: Manages sequential processing of chart load requests with FIFO ordering

**Attributes**:
- `queuedRequests` (List<ChartLoadRequest>, required): Ordered list of pending requests
- `currentRequest` (ChartLoadRequest, optional): Request being processed (null if idle)
- `isProcessing` (bool, required): Whether queue is actively processing

**Methods** (conceptual, not implementation):
- `enqueue(ChartLoadRequest)`: Add request to end of queue
- `dequeue()`: Remove and return first request
- `getQueuePosition(chartId)`: Return 1-based position in queue (for FR-027)
- `clear()`: Remove all pending requests (for app shutdown)

**Relationships**:
- Contains multiple ChartLoadRequest entities
- Processes requests one at a time (singleton pattern)

**State Transitions**:
```
[Idle] --> enqueue() --> [Processing First Request]
                     --> enqueue() --> [Processing + Queue]
[Processing] --> Request Complete --> dequeue() --> [Processing Next Request]
                                                --> [Idle if queue empty]
```

**Concurrency Rules**:
- Only one request processed at a time (sequential, per FR-026)
- New requests added to end (FIFO)
- Queue status displayed to user (position, per FR-027)

---

### 6. ChartLoadTestHooks (Existing, Enhanced)

**Purpose**: Fault injection for deterministic widget testing

**Attributes** (from existing implementation):
- `forceIntegrityMismatch` (bool): Force hash mismatch error
- `failParsingAttempts` (int): Fail first N parsing attempts (for retry testing)
- `fastRetry` (bool): Reduce retry delays for fast test execution
- `lastErrorType` (ChartLoadErrorType): Captured error type for test assertions

**Usage in Tests**:
```dart
// Widget test for integrity mismatch
ChartLoadTestHooks.forceIntegrityMismatch = true;
await tester.pumpWidget(ChartBrowserScreen());
await tester.tap(find.text('Load Elliott Bay'));
await tester.pumpAndSettle();
expect(find.text('Chart data integrity verification failed'), findsOneWidget);
expect(ChartLoadTestHooks.lastErrorType, equals(ChartLoadErrorType.integrityMismatch));

// Widget test for transient retry
ChartLoadTestHooks.failParsingAttempts = 2;
ChartLoadTestHooks.fastRetry = true;
await tester.pumpWidget(ChartBrowserScreen());
await tester.tap(find.text('Load Elliott Bay'));
await tester.pumpAndSettle();
expect(find.byType(ChartDisplay), findsOneWidget); // Success after retries
```

---

## Relationships Diagram

```
┌─────────────────────────┐
│  ChartLoadRequest       │
│  - chartId              │
│  - zipFilePath          │
│  - timestamp            │
└──────────┬──────────────┘
           │ queued in
           v
┌─────────────────────────┐
│  ChartLoadingQueue      │
│  - queuedRequests[]     │
│  - currentRequest       │
│  - isProcessing         │
└──────────┬──────────────┘
           │ processes to
           v
┌─────────────────────────┐
│  ChartLoadResult        │
│  - success              │
│  - chartData            │
│  - error                │◄──────┐
│  - retryAttempts        │       │ contains (if failed)
└─────────────────────────┘       │
                                  │
┌─────────────────────────┐       │
│  ChartLoadError         │───────┘
│  - type (enum)          │
│  - message              │
│  - troubleshootingGuidance│
│  - technicalDetails     │
└─────────────────────────┘

┌─────────────────────────┐
│  ChartIntegrityHash     │
│  - chartId              │
│  - sha256Hash           │
│  - firstLoadTimestamp   │
│  - lastVerifiedTimestamp│
└──────────┬──────────────┘
           │ stored in
           v
┌─────────────────────────┐
│ ChartIntegrityRegistry  │
│ (SharedPreferences)     │
│  Map<chartId, hash>     │
└─────────────────────────┘
```

---

## Data Flow

### First-Time Chart Load (No Hash)
```
1. ChartLoadRequest created → enqueued
2. Queue processes: Extract ZIP → Uint8List chartData
3. Compute SHA256(chartData) → "abc123..."
4. Check ChartIntegrityRegistry[chartId] → not found
5. Store ChartIntegrityHash(chartId, "abc123...", now, null)
6. Return ChartLoadResult(success: true, chartData, retryAttempts: 0)
7. UI shows "First time loading Elliott Bay chart" (informational)
```

### Subsequent Chart Load (Hash Exists, Match)
```
1. ChartLoadRequest created → enqueued
2. Queue processes: Extract ZIP → Uint8List chartData
3. Compute SHA256(chartData) → "abc123..."
4. Check ChartIntegrityRegistry[chartId] → found: "abc123..."
5. Compare: "abc123..." == "abc123..." → MATCH
6. Update lastVerifiedTimestamp = now
7. Return ChartLoadResult(success: true, chartData, retryAttempts: 0)
8. Chart renders normally (no special UI)
```

### Subsequent Chart Load (Hash Exists, Mismatch)
```
1. ChartLoadRequest created → enqueued
2. Queue processes: Extract ZIP → Uint8List chartData
3. Compute SHA256(chartData) → "xyz789..."
4. Check ChartIntegrityRegistry[chartId] → found: "abc123..."
5. Compare: "xyz789..." != "abc123..." → MISMATCH
6. Create ChartLoadError(
     type: integrityMismatch,
     message: "Chart data integrity verification failed",
     guidance: "Try re-downloading from NOAA",
     technicalDetails: "Expected: abc123..., Got: xyz789..." (if debug)
   )
7. Return ChartLoadResult(success: false, error, retryAttempts: 0)
8. UI shows error dialog with Retry/Dismiss buttons
```

### Transient Parser Failure (with Retry)
```
1. ChartLoadRequest created → enqueued
2. Queue processes: Extract ZIP → Uint8List chartData
3. Compute SHA256(chartData) → "abc123..." (match or first load)
4. Parse chartData → throws TransientException
5. Retry logic:
   - Attempt 1: Wait 100ms → retry parse → throws TransientException
   - Attempt 2: Wait 200ms → retry parse → throws TransientException
   - Attempt 3: Wait 400ms → retry parse → SUCCESS
6. Return ChartLoadResult(success: true, chartData, retryAttempts: 3)
7. Chart renders normally (retries transparent to user)
```

### Max Retries Exhausted
```
1-5. Same as above, but all 4 retry attempts fail
6. Create ChartLoadError(
     type: parsingFailed,
     message: "Unable to parse chart file",
     guidance: "Verify S-57 Edition 3.1 format",
     technicalDetails: "Failed after 4 retries" (if debug),
     retryAttempts: 4
   )
7. Return ChartLoadResult(success: false, error, retryAttempts: 4)
8. UI shows error dialog with Retry/Dismiss buttons
```

---

## Persistence Schema

### SharedPreferences Keys

**`chart_integrity_hashes`** (String → JSON):
```json
{
  "US5WA50M": {
    "hash": "a1b2c3d4e5f6...",
    "firstLoad": "2025-09-29T14:30:00.000Z",
    "lastVerified": "2025-09-29T16:45:00.000Z"
  },
  "US3WA01M": {
    "hash": "f6e5d4c3b2a1...",
    "firstLoad": "2025-09-29T15:00:00.000Z",
    "lastVerified": null
  }
}
```

**Access Pattern**:
- Load entire map on app startup (< 1KB for 100 charts)
- In-memory cache for O(1) lookup during chart loading
- Write-through on hash capture/update (synchronous)

---

## Validation Rules Summary

| Entity | Key Validation |
|--------|----------------|
| ChartIntegrityHash | chartId non-empty, sha256Hash exactly 64 hex chars |
| ChartLoadRequest | zipFilePath file exists, chartId non-empty |
| ChartLoadResult | success XOR error (only one set), retryAttempts 0-4 |
| ChartLoadError | type valid enum, message under 200 chars, guidance non-empty |
| ChartLoadingQueue | FIFO order maintained, only one currentRequest |

---

## Performance Considerations

- **ChartIntegrityRegistry**: In-memory cache, O(1) lookup, < 1KB for 100 charts
- **SHA256 Computation**: ~100ms for 400KB file (Elliott Bay chart)
- **Sequential Queue**: Prevents memory exhaustion, predictable performance
- **Retry Logic**: Max 1.5 seconds overhead (100+200+400+800ms)

---

## Testing Strategy

### Unit Test Coverage
- ChartIntegrityHash: Serialization, validation, timestamp logic
- ChartLoadError: Message mapping, enum exhaustiveness
- ChartLoadingQueue: FIFO ordering, status updates, dequeue logic

### Widget Test Coverage (Existing)
- chart_integrity_mismatch_test.dart: Uses ChartLoadTestHooks
- chart_transient_retry_test.dart: Uses ChartLoadTestHooks

### Integration Test Coverage
- End-to-end with real US5WA50M.zip: Extract → Hash → Verify → Parse → Render

---

## Conclusion

Data model supports all 27 functional requirements with clear entity boundaries, validation rules, and state transitions. Aligns with NavTool constitution (offline-first persistence, safety-critical integrity checks, authentic test data). Ready for Phase 1: Contract generation.
