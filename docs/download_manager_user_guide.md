# Download Manager User Guide

Phase 3 introduces a unified Download Manager that centralizes visibility and control over chart downloads.

## Overview
The Download Manager surfaces all active, queued, completed, failed, and paused downloads in one panel. It provides:
- Per-item controls (Pause, Resume, Cancel, Retry)
- Global controls (Pause All, Resume All)
- Real-time progress %, speed, ETA, queue position
- Categorized error reasons (e.g., network, timeout, checksum, storage, unknown)
- Automatic retry after network recovery (initial strategy)
- Metrics & diagnostics export (JSON) via the diagnostics feature

## Opening the Manager
The panel is exposed from the chart browsing interface (Chart Browser). When downloads are in progress (or after opening via the UI action), the reusable widget `DownloadManagerPanel` renders the state.

## Status Indicators
| Status | Meaning | Notes |
|--------|---------|-------|
| queued | Waiting for a free slot | Queue position shown as `(#N in queue)` |
| downloading | Actively transferring data | Shows progress bar, speed & ETA when available |
| paused | User or system paused | Can be resumed (retains partial data) |
| completed | Download finished successfully | Entry can be cleared when batch cleanup added |
| failed | Terminal failure | Retry button available if transient |
| cancelled | User aborted | No retry button |

## Error Categories
Displayed in brackets for failed items: `[network]`, `[timeout]`, `[checksum]`, `[storage]`, `[disk]`, `[unknown]`. These are derived from underlying exceptions in `DownloadServiceImpl`.

## Queue Position
Queued items display their current position `(#1 in queue)`, recalculated whenever the provider state updates. Active items do not show a queue number.

## Speed & ETA
- Speed is computed as instantaneous bytes/sec from the service and presented using adaptive units (B/s, KB/s, MB/s).
- ETA (Estimated Time Remaining) is displayed when total size & speed are both known.

## Automatic Retry (Network Recovery)
When the network transitions from degraded/offline to healthy, failed downloads categorized as transient (e.g., network, timeout) are automatically re-queued. Initial implementation is conservative (no exponential backoff yet). Enhancements (backoff, capped retries, debounce) are optional future work.

## Metrics Collection
`DownloadMetricsCollector` tracks:
- Success count / failure count
- Failures by category
- Retry count
- Average & median duration of completed attempts

A polling provider (`downloadMetricsSnapshotProvider`) yields a snapshot every second for UI or logging surfaces.

## Diagnostics Export
Use `DownloadService.exportDiagnostics()` to produce a JSON string summarizing:
- Recent metrics snapshot
- Current queue / active items
- Failure categories encountered
- Timestamp

This is useful for bug reports or offline analysis.

## Testing
Implemented tests include:
- Metrics aggregation correctness (`download_metrics_collector_test.dart`)
- Auto-retry on simulated network recovery (`download_auto_retry_test.dart`)
- UI state mapping (sections, queue positions, error tags, progress) via `download_manager_panel_test.dart`

## Extensibility Points
| Area | Next Step Ideas |
|------|-----------------|
| Retry policy | Add exponential backoff + max attempts per chart |
| Metrics | Persist snapshots or stream events instead of polling |
| UI | Add filtering (show only failed / only active) |
| Accessibility | Announce state changes via semantics / screen reader labels |
| Offline heuristics | Delay large downloads on metered connections |

## Developer Integration
Embed the panel anywhere with:
```dart
const DownloadManagerPanel()
```
Dependencies required in scope:
- `ProviderScope` with `downloadQueueProvider` & `downloadServiceProvider` wired (default app composition already provides these).

## Troubleshooting
| Symptom | Possible Cause | Suggested Action |
|---------|----------------|------------------|
| Progress bar indeterminate | No bytes yet or size unknown | Wait for headers / size; verify server supports content length |
| Speed remains 0 | Extremely small file or network stalled | Check connectivity; watch retry logs |
| Failed with `[checksum]` | Integrity mismatch | Retry; verify catalog checksum is current |
| No automatic retry occurred | Error classified non-transient | Manually tap Retry; inspect logs for category |

## Logging
Underlying operations log to the shared `AppLogger` (console by default). Enable verbose logging to debug queue transitions, retries, and category derivation.

---
*Download Manager – delivering transparency and control over chart acquisition.*
