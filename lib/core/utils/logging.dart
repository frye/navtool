/// Simple application logging utility to replace direct print usage.
/// Uses dart:developer log so that messages can be filtered in Observatory / DevTools.
import 'dart:developer' as developer;

class AppLogger {
  static const String _name = 'navtool';

  static void debug(String message) {
    developer.log(message, name: _name, level: 500); // FINE
  }

  static void info(String message) {
    developer.log(message, name: _name, level: 800); // INFO
  }

  static void warning(String message) {
    developer.log(message, name: _name, level: 900); // WARNING
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: _name, level: 1000, error: error, stackTrace: stackTrace); // SEVERE
  }

  /// Structured event logging helper (serializes lightweight map inline)
  static void event(String event, {Map<String, dynamic>? data, int level = 800}) {
    final payload = data == null ? '' : ' data=' + data.toString();
    developer.log('[EVENT] ' + event + payload, name: _name, level: level);
  }
}
