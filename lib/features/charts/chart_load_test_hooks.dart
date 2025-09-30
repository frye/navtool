/// Test hook utilities for simulating failure conditions in chart loading.
/// These are ONLY intended for widget/unit tests and are no-op by default.
class ChartLoadTestHooks {
  /// When true, forces an integrity mismatch error regardless of real hash.
  static bool forceIntegrityMismatch = false;

  /// Number of initial parsing attempts to fail with a simulated transient parsing error.
  /// Each failed attempt decrements this counter until it reaches zero.
  static int failParsingAttempts = 0;

  /// When true, auto-retry delays are shortened dramatically for faster tests.
  static bool fastRetry = false;

  /// Simulates a specific load duration in milliseconds for testing progress indicators.
  /// When set to > 0, the service will delay for this duration to test timing thresholds.
  /// Default 0 means no artificial delay.
  static int simulateLoadDuration = 0;

  /// Captures the last ChartLoadErrorType.name observed by ChartScreen for deterministic
  /// test assertions (e.g., integrity vs parsing). Null when no error yet.
  static String? lastErrorType;

  /// Reset all test hooks to default state (call in test tearDown).
  static void reset() {
    forceIntegrityMismatch = false;
    failParsingAttempts = 0;
    fastRetry = false;
    simulateLoadDuration = 0;
    lastErrorType = null;
  }
}
