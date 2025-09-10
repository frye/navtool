import 'package:flutter/foundation.dart';
import '../error/app_error.dart';

/// Log levels for application logging
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// Display name for the log level
  String get displayName {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  /// Whether this level should be shown in production
  bool get showInProduction {
    switch (this) {
      case LogLevel.debug:
        return false;
      case LogLevel.info:
      case LogLevel.warning:
      case LogLevel.error:
        return true;
    }
  }
}

/// Abstract interface for application logging
abstract class AppLogger {
  /// Logs a debug message
  void debug(String message, {String? context, Object? exception});

  /// Logs an info message
  void info(String message, {String? context, Object? exception});

  /// Logs a warning message
  void warning(String message, {String? context, Object? exception});

  /// Logs an error message
  void error(String message, {String? context, Object? exception});

  /// Logs an AppError
  void logError(AppError error);
}

/// Console implementation of AppLogger
class ConsoleLogger implements AppLogger {
  final LogLevel minimumLevel;
  final bool showTimestamp;
  final bool showContext;

  const ConsoleLogger({
    this.minimumLevel = LogLevel.debug,
    this.showTimestamp = true,
    this.showContext = true,
  });

  @override
  void debug(String message, {String? context, Object? exception}) {
    _log(LogLevel.debug, message, context, exception);
  }

  @override
  void info(String message, {String? context, Object? exception}) {
    _log(LogLevel.info, message, context, exception);
  }

  @override
  void warning(String message, {String? context, Object? exception}) {
    _log(LogLevel.warning, message, context, exception);
  }

  @override
  void error(String message, {String? context, Object? exception}) {
    _log(LogLevel.error, message, context, exception);
  }

  @override
  void logError(AppError error) {
    _log(LogLevel.error, error.message, error.type.name, error.originalError);
  }

  void _log(
    LogLevel level,
    String message,
    String? context,
    Object? exception,
  ) {
    // Check if we should log this level
    if (level.index < minimumLevel.index) return;

    // Skip debug logs in production unless explicitly enabled
    if (!kDebugMode && level == LogLevel.debug && !level.showInProduction) {
      return;
    }

    final buffer = StringBuffer();

    // Add timestamp
    if (showTimestamp) {
      final now = DateTime.now();
      buffer.write(
        '[${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}] ',
      );
    }

    // Add level
    buffer.write('[${level.displayName}] ');

    // Add context
    if (showContext && context != null) {
      buffer.write('[$context] ');
    }

    // Add message
    buffer.write(message);

    // Add exception if present
    if (exception != null) {
      buffer.write(' | Exception: $exception');
    }

    // Print to console (this will only show in debug mode or when logging is enabled)
    debugPrint(buffer.toString());
  }
}

/// No-op logger for production when logging is disabled
class NoOpLogger implements AppLogger {
  const NoOpLogger();

  @override
  void debug(String message, {String? context, Object? exception}) {}

  @override
  void info(String message, {String? context, Object? exception}) {}

  @override
  void warning(String message, {String? context, Object? exception}) {}

  @override
  void error(String message, {String? context, Object? exception}) {}

  @override
  void logError(AppError error) {}
}

/// Logger factory for creating appropriate logger instances
class LoggerFactory {
  /// Creates a logger based on the current build mode and configuration
  static AppLogger create({
    LogLevel minimumLevel = LogLevel.info,
    bool enableInProduction = false,
  }) {
    if (kDebugMode || enableInProduction) {
      return ConsoleLogger(
        minimumLevel: minimumLevel,
        showTimestamp: true,
        showContext: true,
      );
    } else {
      return const NoOpLogger();
    }
  }
}

/// Global logger instance
final AppLogger logger = LoggerFactory.create();
