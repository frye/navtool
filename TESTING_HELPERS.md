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
Centralized helpers in `test/helpers/verify_helpers.dart` reduce brittle Mockito chains and keep tests resilient to benign wording changes. They accept either substring or `RegExp` patterns and optional context matching.

Available helpers:
```dart
verifyDebugLogged(mockLogger, 'Starting download:');
verifyInfoLogged(mockLogger, RegExp(r'Compression completed:'), expectedContext: 'Compression');
verifyWarningLogged(mockLogger, 'Retry failed');
verifyErrorLogged(mockLogger, 'Failed to import settings');
expectNoErrorLogs(mockLogger); // negative invariant (happy-path tests)
```

Guidelines:
1. Prefer stable prefixes or succinct regex patterns instead of full literal messages.
2. Only assert `expectedContext:` when the context is semantically meaningful (e.g. distinguishes subsystems: `HTTP`, `Compression`).
3. Use `expectNoErrorLogs` in happy-path tests where emitting any error log would indicate regression (added in Phase F, Task F3).
4. Avoid over‑verifying incidental debug logs; focus on logs that confirm side-effects, branch selection, or externally observable behaviors.
5. Do not verify log ordering unless behavior depends on sequence—order-based assertions are usually a smell; prefer independent semantic checks.
6. For multiple log events of same type, use `times:` only when cardinality matters (e.g. exactly one compression completion per operation). Otherwise, omit.

Anti-patterns (avoid):
- Full string equality: `verify(logger.info('Settings imported successfully from backup'))` (brittle to punctuation/wording).
- Count-only assertions without content: `verify(logger.info(any)).called(2)` (allows unrelated messages to satisfy the test).
- Verifying volatile debug traces (e.g., low-level progress ticks) – these churn frequently and add noise.
- Mixing direct `verify()` and helper usage for the same log type within one test (consistency aids readability).

When to introduce a new helper wrapper:
- Repeated triad (start/success/failure) patterns across ≥3 suites.
- Domain-specific context where a dedicated semantic function improves intent (e.g. `verifyChartDownloadStarted`). Delay until a pattern stabilizes.

Negative expectations:
Use `expectNoErrorLogs(mockLogger)` rather than scattering multiple `verifyNever(logger.error(...))` calls. This asserts zero error emissions regardless of message content or context.

Migration Coverage (Phase F Batches 1–4):
- Downloads, persistence, catalog, compression, NOAA metadata/API, settings, HTTP client, filesystem, cache suites now use helpers.
- Pending optional extension: parser success tests (could add `expectNoErrorLogs`) and any future domain modules.

Future Improvements:
- Potential `verifyNoWarningsLogged` sibling if warning silence becomes a public invariant.
- Lightweight ordered group matcher only if a real ordering semantic emerges.

Example pattern vs literal improvement:
```dart
// Before (brittle)
verify(mockLogger.info('Settings reset to marine navigation defaults'));

// After (resilient)
verifyInfoLogged(mockLogger, 'Settings reset to marine navigation defaults');
```

