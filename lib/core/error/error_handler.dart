import 'package:flutter/foundation.dart';
import 'app_error.dart';
import '../logging/app_logger.dart';

/// User action that can be taken in response to an error
class UserAction {
  final String title;
  final String? description;
  final VoidCallback action;

  UserAction({required this.title, this.description, required this.action});
}

/// Strategy for recovering from errors
@immutable
class ErrorRecoveryStrategy {
  final bool shouldRetry;
  final int maxRetries;
  final Duration delayBetweenRetries;
  final List<UserAction> userActions;

  const ErrorRecoveryStrategy({
    required this.shouldRetry,
    required this.maxRetries,
    required this.delayBetweenRetries,
    required this.userActions,
  });

  /// Creates a recovery strategy based on the error type
  static ErrorRecoveryStrategy forError(AppError error) {
    switch (error.type) {
      case AppErrorType.network:
        return ErrorRecoveryStrategy(
          shouldRetry: true,
          maxRetries: 3,
          delayBetweenRetries: const Duration(seconds: 2),
          userActions: [
            UserAction(
              title: 'Check Connection',
              description: 'Verify your internet connection and try again',
              action: () {},
            ),
          ],
        );
      case AppErrorType.storage:
        return ErrorRecoveryStrategy(
          shouldRetry: true,
          maxRetries: 2,
          delayBetweenRetries: const Duration(seconds: 1),
          userActions: [
            UserAction(
              title: 'Check Storage',
              description: 'Verify available storage space',
              action: () {},
            ),
          ],
        );
      case AppErrorType.permission:
        return ErrorRecoveryStrategy(
          shouldRetry: false,
          maxRetries: 0,
          delayBetweenRetries: Duration.zero,
          userActions: [
            UserAction(
              title: 'Grant Permission',
              description: 'Open settings to grant required permissions',
              action: () {},
            ),
          ],
        );
      case AppErrorType.validation:
      case AppErrorType.parsing:
      case AppErrorType.unknown:
        // Fall through to default behavior
        return const ErrorRecoveryStrategy(
          shouldRetry: false,
          maxRetries: 0,
          delayBetweenRetries: Duration.zero,
          userActions: [],
        );
    }
  }
}

/// Central error handler for the application
class ErrorHandler {
  final AppLogger logger;

  ErrorHandler({required this.logger});

  /// Handles any error, converting it to AppError if necessary
  void handleError(Object error, [StackTrace? stackTrace]) {
    final AppError appError;

    if (error is AppError) {
      appError = error;
    } else {
      appError = AppError.create(
        message: error.toString(),
        type: AppErrorType.unknown,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    logger.logError(appError);
  }

  /// Determines if an error should be retried
  bool shouldRetry(AppError error) {
    return error.isRetryable;
  }

  /// Gets user-friendly error message
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
        return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Gets recovery strategy for an error
  ErrorRecoveryStrategy getRecoveryStrategy(AppError error) {
    return ErrorRecoveryStrategy.forError(error);
  }

  /// Handles errors with automatic retry logic
  Future<T> handleWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        attempts++;

        final appError = error is AppError
            ? error
            : AppError.create(
                message: error.toString(),
                type: AppErrorType.unknown,
                originalError: error,
                stackTrace: stackTrace,
              );

        if (attempts >= maxRetries || !shouldRetry(appError)) {
          handleError(appError, stackTrace);
          rethrow;
        }

        logger.warning(
          'Operation failed, retrying in ${delay.inSeconds}s (attempt $attempts/$maxRetries)',
          context: 'ErrorHandler',
          exception: error,
        );

        await Future.delayed(delay);
      }
    }

    throw AppError.unknown('Maximum retry attempts exceeded');
  }
}

/// Global error handler instance
final ErrorHandler errorHandler = ErrorHandler(logger: logger);
