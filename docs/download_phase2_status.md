# Download Service Phase 2 Status (Resume Semantics & Integrity Hardening)

Updated: 2025-09-01 (Post error code classification & cleanup tests)

## Overview
Phase 2 focuses on robust resumable downloads and integrity safeguards for chart packages under intermittent / high-latency marine network conditions. Core goals:
- Detect & leverage HTTP Range support
- Preserve and append partial downloads safely
- Add adaptive retry with jitter
- Persist richer resume diagnostics (attempt counts, range support, last error code)
- Preflight disk space (best effort heuristic)
- Sweep stale / invalid resume metadata (implemented)
- Provide structured error codes for failure analytics (implemented)

## Current Architecture Additions
- Atomic write pattern: `<name>.zip.part` temp file then rename on success.
- Range Probe: Single byte GET (Range: bytes=0-0) persisted in `ResumeData.supportsRange`.
- Manual Append Path: Stream remaining bytes via ranged GET and append directly to existing `.part` file.
- Retry Strategy: Exponential (2^n) with 0–500ms jitter; attempt count stored.
- Partial Preservation: On failure we record actual current `.part` length instead of last progress callback value.
- Disk Space Heuristic: HEAD content-length + aggregate partial bytes + 5MB buffer gated under 5GB cap.
- Persistence: `.download_state.json` includes `downloads`, `resumeData`, `queue`.
- Stale Resume Sweep: `_sweepStaleResumeEntries` normalizes size mismatches, removes orphans / completed / corrupt zero-length partials.
- Error Classification: `DownloadErrorCode` integer constants persisted in `ResumeData.lastErrorCode` via `_classifyErrorCode`.

## Checklist
- [x] Extend `ResumeData` with `supportsRange`, `attempts`, `lastErrorCode` field placeholders
- [x] Range support probe (`_probeRangeSupport`)
- [x] Manual append resume streaming (`_appendResumeStream`)
- [x] Exponential retry + jitter inside `_downloadWithRetry`
- [x] Persist actual partial bytes on failure path
- [x] Disk space preflight heuristic (`_hasSufficientDiskSpace`)
- [x] Pass initial Phase 2 feature tests (range probe, manual append, jitter, disk space rejection)
- [x] Stale resume cleanup (remove/normalize orphan, mismatch, completed, zero-length scenarios)
- [x] Structured `lastErrorCode` population (checksum_mismatch, insufficient_disk_space, network_timeout, network, storage, unknown)
- [x] Load-time proactive invalid resume sweep (runs after `_loadPersistentState`)
- [x] Additional tests: stale cleanup, error code mapping, checksum mismatch scenario
- [ ] Documentation: Integrate this status into main architecture docs (this doc pending merge / consolidation)

## Open Items / Risks
| Area | Risk | Mitigation Plan |
|------|------|-----------------|
| Large File Handling | Heuristic may accept downloads that exceed actual free disk | Future: platform channel / FFI disk free query |
| Integrity Verification | Only checksum on full download path | Potential Phase 3 partial chunk hashing (deferred) |
| Error Code Evolution | New categories needed later (e.g. auth, quota) | Reserve code space & extend `DownloadErrorCode` enum-like class |

## Near-Term Plan
1. Consolidate this status into broader architecture / downloads documentation (developer guide section: "Resumable Download Pipeline").
2. CI verification (full test + analyzer) and finalize lint cleanups if any.
3. Close Phase 2 issue after docs merged; open follow-up for optional enhancements (partial chunk hashing, free disk query, auth/quota error codes).

## Test Status (Latest)
All current Phase 2 feature tests passing post Windows teardown fix:
- Range probe sets `supportsRange`
- Manual append resume reconstructs full file
- Retry jitter ensures multiple attempts captured
- Disk space heuristic rejects oversized content-length (>5GB aggregate)

Added tests now cover: stale cleanup variants, checksum mismatch handling, error code classification (checksum mismatch, insufficient disk space, timeout, generic network).

Next possible (optional) tests: simulated storage write failure classification, resume after classified failure ensuring code persists across process restart.

## Notes
Sweep implemented post-core stabilization; classification ensures future analytics on failure patterns (e.g., user-facing telemetry) without increasing coupling.
