import 'package:flutter/foundation.dart';

/// Lightweight test logger to replace direct print usage in tests.
/// Uses debugPrint (which is throttled & analyzer-friendly) and can be
/// silenced via the NAVTOOL_SILENT_TEST_LOGS environment variable in the
/// parent process (not inspected here to keep pure Dart). Provide an on/off
/// switch by setting [enabled] during construction.
class TestLogger {
  final bool enabled;
  final String? scope;

  const TestLogger({this.enabled = true, this.scope});

  void _log(String level, String message, [Object? error]) {
    if (!enabled) return;
    final prefix = scope != null ? '[$scope]' : '';
    final err = error != null ? ' | $error' : '';
    debugPrint('[$level]$prefix $message$err');
  }

  void info(String message) => _log('INFO', message);
  void debug(String message) => _log('DEBUG', message);
  void warn(String message) => _log('WARN', message);
  void error(String message, [Object? error]) => _log('ERROR', message, error);
}

/// Global default test logger (opt-in verbose). Individual tests may create
/// their own with a scope for clearer context.
const testLogger = TestLogger();
