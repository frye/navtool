import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/logging/app_logger.dart';

void main() {
  group('AppError Tests', () {
    test('AppError should be created with message and type', () {
      // Arrange
      const message = 'Test error message';
      const type = AppErrorType.network;
      final error = Exception('Original error');

      // Act
      final appError = AppError(
        message: message,
        type: type,
        originalError: error,
      );

      // Assert
      expect(appError.message, equals(message));
      expect(appError.type, equals(type));
      expect(appError.originalError, equals(error));
      expect(appError.timestamp, isA<DateTime>());
    });

    test('AppError should have correct string representation', () {
      // Arrange
      const message = 'Test error';
      const type = AppErrorType.validation;
      final appError = AppError(message: message, type: type);

      // Act
      final errorString = appError.toString();

      // Assert
      expect(errorString, contains(message));
      expect(errorString, contains('validation'));
    });

    test('AppError should categorize different error types', () {
      // Arrange & Act & Assert
      expect(AppErrorType.network.isRetryable, isTrue);
      expect(AppErrorType.storage.isRetryable, isTrue);
      expect(AppErrorType.validation.isRetryable, isFalse);
      expect(AppErrorType.permission.isRetryable, isFalse);
      expect(AppErrorType.parsing.isRetryable, isFalse);
      expect(AppErrorType.unknown.isRetryable, isFalse);
    });

    test('AppError should have correct severity levels', () {
      // Arrange & Act & Assert
      expect(AppErrorType.network.severity, equals(ErrorSeverity.medium));
      expect(AppErrorType.storage.severity, equals(ErrorSeverity.high));
      expect(AppErrorType.validation.severity, equals(ErrorSeverity.low));
      expect(AppErrorType.permission.severity, equals(ErrorSeverity.high));
      expect(AppErrorType.parsing.severity, equals(ErrorSeverity.medium));
      expect(AppErrorType.unknown.severity, equals(ErrorSeverity.high));
    });
  });

  group('ErrorHandler Tests', () {
    late ErrorHandler errorHandler;
    late MockLogger mockLogger;

    setUp(() {
      mockLogger = MockLogger();
      errorHandler = ErrorHandler(logger: mockLogger);
    });

    test('ErrorHandler should handle AppError correctly', () {
      // Arrange
      final appError = AppError(
        message: 'Test error',
        type: AppErrorType.network,
      );

      // Act
      errorHandler.handleError(appError);

      // Assert
      expect(mockLogger.loggedErrors, hasLength(1));
      expect(mockLogger.loggedErrors.first.message, equals('Test error'));
    });

    test('ErrorHandler should convert Exception to AppError', () {
      // Arrange
      final exception = Exception('Test exception');

      // Act
      errorHandler.handleError(exception);

      // Assert
      expect(mockLogger.loggedErrors, hasLength(1));
      expect(mockLogger.loggedErrors.first.type, equals(AppErrorType.unknown));
      expect(mockLogger.loggedErrors.first.originalError, equals(exception));
    });

    test('ErrorHandler should handle network errors with retry', () {
      // Arrange
      final networkError = AppError(
        message: 'Network timeout',
        type: AppErrorType.network,
      );

      // Act
      final result = errorHandler.shouldRetry(networkError);

      // Assert
      expect(result, isTrue);
    });

    test('ErrorHandler should not retry validation errors', () {
      // Arrange
      final validationError = AppError(
        message: 'Invalid input',
        type: AppErrorType.validation,
      );

      // Act
      final result = errorHandler.shouldRetry(validationError);

      // Assert
      expect(result, isFalse);
    });

    test('ErrorHandler should format user-friendly messages', () {
      // Arrange
      final networkError = AppError(
        message: 'HTTP 500 Internal Server Error',
        type: AppErrorType.network,
      );

      // Act
      final userMessage = errorHandler.getUserMessage(networkError);

      // Assert
      expect(userMessage, contains('network'));
      expect(userMessage, isNot(contains('HTTP 500')));
    });
  });

  group('AppLogger Tests', () {
    late MockAppLogger logger;

    setUp(() {
      logger = MockAppLogger();
    });

    test('AppLogger should log different levels correctly', () {
      // Arrange
      const message = 'Test log message';

      // Act
      logger.debug(message);
      logger.info(message);
      logger.warning(message);
      logger.error(message);

      // Assert
      expect(logger.logEntries, hasLength(4));
      expect(logger.logEntries[0].level, equals(LogLevel.debug));
      expect(logger.logEntries[1].level, equals(LogLevel.info));
      expect(logger.logEntries[2].level, equals(LogLevel.warning));
      expect(logger.logEntries[3].level, equals(LogLevel.error));
    });

    test('AppLogger should include timestamp and context', () {
      // Arrange
      const message = 'Test message';
      const context = 'TestClass';

      // Act
      logger.info(message, context: context);

      // Assert
      final entry = logger.logEntries.first;
      expect(entry.message, equals(message));
      expect(entry.context, equals(context));
      expect(entry.timestamp, isA<DateTime>());
    });

    test('AppLogger should handle exceptions in log entries', () {
      // Arrange
      const message = 'Error occurred';
      final exception = Exception('Test exception');

      // Act
      logger.error(message, exception: exception);

      // Assert
      final entry = logger.logEntries.first;
      expect(entry.message, equals(message));
      expect(entry.exception, equals(exception));
      expect(entry.level, equals(LogLevel.error));
    });

    test('AppLogger should filter logs by minimum level', () {
      // Arrange
      logger.setMinimumLevel(LogLevel.warning);

      // Act
      logger.debug('Debug message');
      logger.info('Info message');
      logger.warning('Warning message');
      logger.error('Error message');

      // Assert
      expect(logger.logEntries, hasLength(2));
      expect(logger.logEntries[0].level, equals(LogLevel.warning));
      expect(logger.logEntries[1].level, equals(LogLevel.error));
    });
  });

  group('Error Recovery Tests', () {
    test('Error recovery should provide retry strategies', () {
      // Arrange
      final networkError = AppError(
        message: 'Connection timeout',
        type: AppErrorType.network,
      );

      // Act
      final strategy = ErrorRecoveryStrategy.forError(networkError);

      // Assert
      expect(strategy.shouldRetry, isTrue);
      expect(strategy.maxRetries, greaterThan(0));
      expect(strategy.delayBetweenRetries, greaterThan(Duration.zero));
    });

    test('Error recovery should provide user actions', () {
      // Arrange
      final permissionError = AppError(
        message: 'Location permission denied',
        type: AppErrorType.permission,
      );

      // Act
      final strategy = ErrorRecoveryStrategy.forError(permissionError);

      // Assert
      expect(strategy.userActions, isNotEmpty);
      expect(strategy.userActions.first.title, contains('Permission'));
    });
  });
}

// Mock implementations for testing
class MockLogger implements AppLogger {
  final List<AppError> loggedErrors = [];

  @override
  void logError(AppError error) {
    loggedErrors.add(error);
  }

  @override
  void debug(String message, {String? context, Object? exception}) {}

  @override
  void info(String message, {String? context, Object? exception}) {}

  @override
  void warning(String message, {String? context, Object? exception}) {}

  @override
  void error(String message, {String? context, Object? exception}) {}
}

class MockAppLogger implements AppLogger {
  final List<LogEntry> logEntries = [];
  LogLevel _minimumLevel = LogLevel.debug;

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
    _log(LogLevel.error, error.message, null, error.originalError);
  }

  void setMinimumLevel(LogLevel level) {
    _minimumLevel = level;
  }

  void _log(LogLevel level, String message, String? context, Object? exception) {
    if (level.index >= _minimumLevel.index) {
      logEntries.add(LogEntry(
        level: level,
        message: message,
        context: context,
        exception: exception,
        timestamp: DateTime.now(),
      ));
    }
  }
}

class LogEntry {
  final LogLevel level;
  final String message;
  final String? context;
  final Object? exception;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.context,
    this.exception,
    required this.timestamp,
  });
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

// Test classes that need to be implemented
abstract class AppLogger {
  void debug(String message, {String? context, Object? exception});
  void info(String message, {String? context, Object? exception});
  void warning(String message, {String? context, Object? exception});
  void error(String message, {String? context, Object? exception});
  void logError(AppError error);
}

class ErrorHandler {
  final AppLogger logger;

  ErrorHandler({required this.logger});

  void handleError(Object error) {
    final appError = error is AppError 
        ? error 
        : AppError(
            message: error.toString(),
            type: AppErrorType.unknown,
            originalError: error,
          );
    
    logger.logError(appError);
  }

  bool shouldRetry(AppError error) {
    return error.type.isRetryable;
  }

  String getUserMessage(AppError error) {
    switch (error.type) {
      case AppErrorType.network:
        return 'A network error occurred. Please check your connection and try again.';
      case AppErrorType.storage:
        return 'Unable to access local storage. Please check available space.';
      case AppErrorType.validation:
        return 'Invalid input provided. Please check your data.';
      case AppErrorType.permission:
        return 'Permission required. Please grant the necessary permissions.';
      case AppErrorType.parsing:
        return 'Unable to process the data. The file may be corrupted.';
      case AppErrorType.unknown:
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}

class ErrorRecoveryStrategy {
  final bool shouldRetry;
  final int maxRetries;
  final Duration delayBetweenRetries;
  final List<UserAction> userActions;

  ErrorRecoveryStrategy({
    required this.shouldRetry,
    required this.maxRetries,
    required this.delayBetweenRetries,
    required this.userActions,
  });

  static ErrorRecoveryStrategy forError(AppError error) {
    switch (error.type) {
      case AppErrorType.network:
        return ErrorRecoveryStrategy(
          shouldRetry: true,
          maxRetries: 3,
          delayBetweenRetries: Duration(seconds: 2),
          userActions: [
            UserAction(title: 'Check Connection', action: () {}),
          ],
        );
      case AppErrorType.permission:
        return ErrorRecoveryStrategy(
          shouldRetry: false,
          maxRetries: 0,
          delayBetweenRetries: Duration.zero,
          userActions: [
            UserAction(title: 'Grant Permission', action: () {}),
          ],
        );
      default:
        return ErrorRecoveryStrategy(
          shouldRetry: false,
          maxRetries: 0,
          delayBetweenRetries: Duration.zero,
          userActions: [],
        );
    }
  }
}

class UserAction {
  final String title;
  final Function action;

  UserAction({required this.title, required this.action});
}
