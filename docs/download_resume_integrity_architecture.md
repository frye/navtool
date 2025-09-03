# Resumable Download & Integrity Architecture

Updated: 2025-09-03 (Phase 2 Complete)

This document consolidates Phase 2 implementation details into a cohesive architectural reference for the NavTool chart download pipeline.

---
## Goals
Provide robust, interruption-tolerant, integrity-verified chart downloads optimized for constrained / intermittent marine networks.

Key objectives:
1. Safe atomic writes (no corrupt finals on crash/interruption).
2. Efficient resume using HTTP Range where available.
3. Accurate partial byte accounting and recovery metadata.
4. Adaptive retry with jitter to reduce burst congestion.
5. Early rejection of obviously too-large downloads (best-effort heuristic).
6. Structured failure diagnostics for analytics and UX adaptation.
7. Automated cleanup of stale or invalid resume state.

---
## Data Model Additions
`ResumeData` fields:
- `downloadedBytes`: Authoritative on-disk partial length (normalized by sweep).
- `supportsRange`: Sticky capability flag determined by probe (`GET` with `Range: bytes=0-0`).
- `attempts`: Incremented each time progress persistence occurs or on explicit error save.
- `lastErrorCode`: Integer from `DownloadErrorCode` (see below) capturing the most recent classified failure.

`DownloadErrorCode` constants (stable integer codes):
| Code | Name | Meaning |
|------|------|---------|
| 1 | checksumMismatch | Final integrity verification failed (expected != actual SHA-256). |
| 2 | insufficientDiskSpace | Heuristic preflight rejected due to projected aggregate size. |
| 3 | networkTimeout | Dio/AppError timeout condition. |
| 4 | network | Generic network failure (non-timeout). |
| 5 | storage | Local IO / filesystem failure. |
| 6 | rangeNotSupported | Reserved (not currently emitted; future explicit fallback marker). |
| 99 | unknown | Unclassified / fallback case. |

---
## Pipeline Overview
1. Queue admission (`addToQueue`) with priority ordering.
2. Slot scheduling enforces `maxConcurrentDownloads` and network suitability probe.
3. Start path (`downloadChart`):
   - Disk space heuristic HEAD → optional early abort.
   - Atomic write target `<name>.part`.
   - `_downloadWithRetry` orchestrates up to 3 attempts, exponential (2^n) + 0–500ms jitter.
   - Checksum verification (if provided) before rename.
   - On success: rename `temp.part` → final file.
4. Failure path classification: compute partial bytes length, map error, persist resume entry with `lastErrorCode`.
5. Resume path (`resumeDownload`):
   - Validate existing `.part` size vs. stored `downloadedBytes` (mismatch → reset).
   - Probe range support (if unknown or changed) and record.
   - If resumable + partial > 0 → `_appendResumeStream` with `Range: bytes=<offset>-` streaming append.
   - Else fallback full `downloadFile` (optionally with native range support via Dio).
6. Completion: final rename, progress to 1.0, optional notification.
7. Stale sweep (`_sweepStaleResumeEntries`) executed after persistent state load to normalize or purge invalid entries.

---
## Integrity Handling
- Integrity guard executed pre-rename ensures we never leave a corrupt final file.
- On checksum mismatch: `.part` is deleted, error classified as `checksumMismatch`, resume metadata records 0 bytes (no on-disk partial remains).
- Future extensions (Phase 3 candidates):
  - Chunk-level rolling hash for mid-stream verification.
  - Opportunistic multi-part validation for early corruption detection.

---
## Disk Space Heuristic
Because Dart lacks a portable free-space API, heuristic prevents extreme cases:
- HEAD `content-length` + sum(existing `.part`) + 5MB buffer must remain < 5GB.
- If any value indeterminate → allow (fail-open to avoid false negatives).
- Classification on rejection → `insufficientDiskSpace`.

---
## Error Classification Logic
`_classifyErrorCode` precedence:
1. Message pattern (checksum, insufficient disk, timeout) within `AppError` subtype.
2. `AppError.type` mapping (network/storage).
3. Dio exception type fallback (timeouts vs generic network).
4. Filesystem exception → storage.
5. Default unknown.

Resume data updated via `_saveResumeDataWithError` ensuring `attempts` increments and classification persisted.

---
## Persistence Schema (`.download_state.json`)
```
{
  "downloads": { "<chartId>": { status, progress, totalBytes, downloadedBytes, lastUpdated } },
  "resumeData": { "<chartId>": { originalUrl, downloadedBytes, lastAttempt, checksum, supportsRange, attempts, lastErrorCode } },
  "queue": [ { chartId, url, priority, addedAt, expectedChecksum } ]
}
```

Sweep may mutate `resumeData` or remove entries; mutations are persisted opportunistically.

---
## Testing Summary
Implemented suites:
- Feature: range probe, append resume, retry jitter, disk space heuristic.
- Cleanup: orphan removal, mismatch normalization, completed final removal, zero-length purge.
- Integrity: checksum mismatch eliminates artifacts & sets code.
- Classification: checksum mismatch, insufficient disk space, network timeout, generic network.

Edge cases validated:
- Range 200 fallback to full restart.
- Resume size mismatch triggers reset.
- Multiple retries increment attempts.

Future test opportunities:
- Storage write failure classification (simulate FileSystemException).
- Persistence of error code across process restart scenario.
- Range unsupported explicit code emission once implemented.

---
## Operational Considerations
- All mutation paths persist asynchronously; sudden process termination may lose last few bytes of metadata but not corrupt final files.
- Partial file integrity not verified mid-stream (checksum deferred to completion) to minimize CPU overhead on constrained devices.
- Error codes enable UI decisions (e.g., suggest freeing space, advise connectivity checks).
- Sweep operations normalize mismatched metadata automatically on load to prevent resume failures.
- Structured error classification enables future analytics on failure patterns without increasing coupling.

---
## Phase 2 Completion Summary

**All Phase 2 objectives achieved:**

1. ✅ **Safe atomic writes** - No corrupt finals on crash/interruption via `.part` files
2. ✅ **Efficient resume** - HTTP Range support detection and streaming append  
3. ✅ **Accurate partial accounting** - Normalized byte counts with automatic sweep
4. ✅ **Adaptive retry with jitter** - Exponential backoff with 0-500ms randomization
5. ✅ **Early size rejection** - Best-effort heuristic prevents obviously too-large downloads
6. ✅ **Structured failure diagnostics** - Error codes for analytics and UX adaptation
7. ✅ **Automated cleanup** - Stale/invalid resume state removal

**Ready for production use** in marine environments with intermittent connectivity.

---
## Extension Roadmap (Phase 3 Candidates)
| Feature | Benefit | Notes |
|---------|---------|-------|
| Free disk space native probe | Accurate capacity gating | Platform channel or FFI. |
| Chunk hashing / streaming digest | Earlier corruption detection | Balance CPU vs integrity. |
| Auth / quota error codes | Better end-user guidance | Extend `DownloadErrorCode`. |
| Adaptive concurrency | Optimize throughput vs. reliability | Use rolling failure window heuristics. |
| Backoff strategy tuning | Network friendliness | Consider jitter distribution adjustments. |

---
## Quick Reference
| Component | Method | Responsibility |
|-----------|--------|----------------|
| Range Probe | `_probeRangeSupport` | Detect & persist HTTP range capability. |
| Retry Core | `_downloadWithRetry` | Exponential + jitter attempts. |
| Resume Append | `_appendResumeStream` | Ranged streaming continuation. |
| Integrity | Checksum pre-rename | Prevent corrupt finals. |
| Classification | `_classifyErrorCode` | Map failures → stable codes. |
| Cleanup | `_sweepStaleResumeEntries` | Remove/normalize invalid resume metadata. |
| Persistence | `_savePersistentState` | Serialize downloads, resume data, queue. |

---
## Developer Checklist for New Features
1. Update `DownloadErrorCode` if new error types introduced.
2. Add classification branch in `_classifyErrorCode`.
3. Extend tests (positive + negative cases).
4. Update architecture doc & issue checklist.
5. Confirm CI (tests + analyzer) before merge.

---
## Status
**Phase 2 Complete** - All core mechanics and diagnostics implemented.

### Implementation Checklist (Final Status)
- [x] Extend `ResumeData` with `supportsRange`, `attempts`, `lastErrorCode` fields
- [x] Range support probe (`_probeRangeSupport`)
- [x] Manual append resume streaming (`_appendResumeStream`)
- [x] Exponential retry + jitter inside `_downloadWithRetry`
- [x] Persist actual partial bytes on failure path
- [x] Disk space preflight heuristic (`_hasSufficientDiskSpace`)
- [x] Stale resume cleanup (remove/normalize orphan, mismatch, completed, zero-length scenarios)
- [x] Structured `lastErrorCode` population (checksum_mismatch, insufficient_disk_space, network_timeout, network, storage, unknown)
- [x] Load-time proactive invalid resume sweep (runs after `_loadPersistentState`)
- [x] Unit tests: range probe, append correctness, disk space preflight, checksum mismatch cleanup, jitter, error classification
- [x] Documentation: Architecture and implementation guide consolidated

### Test Coverage Status
All Phase 2 feature tests passing:
- Range probe sets `supportsRange` flag correctly
- Manual append resume reconstructs full file from partial
- Retry jitter ensures multiple attempts with variance
- Disk space heuristic rejects oversized content-length (>5GB aggregate)
- Stale cleanup variants: orphan removal, mismatch normalization, completed final removal, zero-length purge
- Checksum mismatch handling: eliminates artifacts & sets proper error code
- Error code classification: checksum mismatch, insufficient disk space, network timeout, generic network

Test files:
- `test/core/services/download_phase2_features_test.dart` - Core Phase 2 functionality
- `test/core/services/download_resume_cleanup_test.dart` - Stale entry cleanup
- `test/core/services/download_checksum_mismatch_test.dart` - Integrity verification
- `test/core/services/download_error_classification_test.dart` - Error code mapping

### Known Limitations & Future Enhancements
| Area | Current Limitation | Future Enhancement (Phase 3 Candidates) |
|------|-------------------|------------------------------------------|
| Disk Space Check | Heuristic-based (may accept downloads exceeding actual free disk) | Platform channel / FFI disk free space query |
| Integrity Verification | Only checksum on full download completion | Chunk-level rolling hash for mid-stream verification |
| Error Code Coverage | Core network/storage/integrity errors | Auth/quota error codes for enhanced UX guidance |
| Concurrency | Fixed max concurrent downloads | Adaptive concurrency based on rolling failure window |

---
