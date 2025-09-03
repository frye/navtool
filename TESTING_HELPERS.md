# Testing Helpers & Reliability Utilities

This document summarizes the timing, flakiness, and filesystem mitigation helpers introduced during Phases D3 and E.

## Timing & Flakiness

### `waitForCondition<T>` (`test/helpers/flakiness_guard.dart`)
A diagnostic-aware polling utility replacing ad-hoc sleeps and most `waitForPredicate` calls.

Key features:
- Supplier + predicate separation (observe evolving value, then assert condition).
- Bounded timeout with adaptive backoff (light exponential after 5 attempts).
- Optional diagnostic snapshot provider included in failure message.
- Generic return type retains the last or successful value for further assertions.

Usage example:
```dart
await waitForCondition<int>(
  () async => progressEvents.length,
  predicate: (len) => len >= 3,
  timeout: const Duration(seconds: 1),
  diagnosticSnapshot: () async => 'events=${progressEvents.join(',')}',
);
```

### Legacy `waitForPredicate`
Still available in `timing_harness.dart` for simple boolean polling; migrate to `waitForCondition` when richer diagnostics are helpful.

### `FakeTicker`
A logical tick driver included in `timing_harness.dart` (not yet wired into production logic). Future work: integrate with services that can accept an injected clock to eliminate real delays (e.g. backoff retries, network suitability probes).

## Filesystem Mitigation (Phase E)
Enhancements in `DownloadServiceImpl` to reduce flakiness / platform differences:

- `_prepareFinalPath(File finalFile)`: Removes existing file/directory at target path with retry/backoff.
- `_safeRename(File tempFile, String finalPath)`: Retries atomic rename and falls back to copy+delete if rename repeatedly fails (helps on Windows locked-file scenarios).

### Rationale
Previously a direct `tempFile.rename` could sporadically fail on Windows due to filesystem latency or antivirus interference. The new path increases resilience while preserving atomic intent.

### Future Hardening Ideas
- Inject a filesystem adapter to simulate failures deterministically in unit tests.
- Track metrics (rename retries, fallback usages) for telemetry in production builds.

## Migration Status
| Area | Old Pattern | New Pattern | Status |
|------|-------------|-------------|--------|
| Predicate waits | `waitForPredicate` + manual loops | `waitForCondition` | Queue tests migrated; more pending |
| Disposal test | Direct assertions | `waitForCondition` | Done |
| Download flow rename | Direct rename | `_safeRename` + `_prepareFinalPath` | Done |
| Progress tests | Live stream race-prone asserts | Snapshot final progress | Simplified (re-hardening optional) |

## Recommendations
1. Continue replacing remaining `waitForPredicate` usages where added diagnostics would help debugging.
2. Add unit tests specifically targeting failure branches of `_safeRename` via a mockable filesystem abstraction.
3. Consider adopting a virtual clock interface so backoff logic can be tick-driven instead of using `Future.delayed`.
4. Expand progress tests with a controlled stream harness if mid-progress granularity becomes important again.

## Quick Reference
```dart
// Basic success condition
await waitForCondition<bool>(() async => flag, predicate: (v) => v);

// With snapshot diagnostics
await waitForCondition<List<String>>(
  () async => events,
  predicate: (e) => e.contains('DONE'),
  diagnosticSnapshot: () async => 'last=${events.isNotEmpty ? events.last : 'none'}',
);
```

## Logger Verification Best Practices

To reduce brittleness and over-specification in tests that assert logging behavior, use the centralized helpers in `test/helpers/verify_helpers.dart`:

Helpers:
```dart
verifyInfoLogged(mockLogger, 'Chart download completed', expectedContext: 'Download');
verifyWarningLogged(mockLogger, RegExp(r'Failed .* state')); // regex patterns supported
verifyErrorLogged(mockLogger, 'Failed to fix chart discovery cache');
```

Guidelines:
1. Prefer substring or concise RegExp patterns over full message literals (allows minor wording/format changes without breaking tests).
2. Supply `expectedContext` only when the context string is semantically important; otherwise omit it to accept any context.
3. For negative assertions (ensuring something was NOT logged) keep direct `verifyNever` calls – helpers intentionally focus on positive verification.
4. Avoid asserting debug-level logs unless they encode functional behavior (debug logs may be pruned or toggled in production configurations).
5. When adding new log-producing branches, prefer a short stable prefix (e.g. `Checksum verification passed`) so tests can match on that anchor.

Migration Status:
- Applied helpers to: download queue processing (pilot), checksum verification, persistence, NOAA chart discovery cache fix.
- Pending broader rollout: other download service tests, performance tests (may skip – high churn outputs), settings/navigation service tests.

Future Enhancements:
- Add `verifyNeverInfoLogged` style convenience wrappers if negative checks become frequent.
- Introduce a custom matcher for ordered log sequences if ordering becomes significant in behavior tests.

