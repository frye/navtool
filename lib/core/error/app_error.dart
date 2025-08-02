import 'package:flutter/foundation.dart';

/// Types of errors that can occur in the application
enum AppErrorType {
  network,
  storage,
  validation,
  permission,
  parsing,
  unknown;

  /// Whether this error type can be retried
  bool get isRetryable {
    switch (this) {
      case AppErrorType.network:
      case AppErrorType.storage:
        return true;
      case AppErrorType.validation:
      case AppErrorType.permission:
      case AppErrorType.parsing:
      case AppErrorType.unknown:
        return false;
    }
  }

  /// Severity level of the error
  ErrorSeverity get severity {
    switch (this) {
      case AppErrorType.network:
      case AppErrorType.parsing:
        return ErrorSeverity.medium;
      case AppErrorType.storage:
      case AppErrorType.permission:
        return ErrorSeverity.high;
      case AppErrorType.validation:
        return ErrorSeverity.low;
      case AppErrorType.unknown:
        return ErrorSeverity.high;
    }
  }
}

/// Severity levels for errors
enum ErrorSeverity {
  low,
  medium,
  high,
  critical;

  /// Display name for the severity
  String get displayName {
    switch (this) {
      case ErrorSeverity.low:
        return 'Low';
      case ErrorSeverity.medium:
        return 'Medium';
      case ErrorSeverity.high:
        return 'High';
      case ErrorSeverity.critical:
        return 'Critical';
    }
  }
}

/// Custom application error class
@immutable
class AppError implements Exception {
  final String message;
  final AppErrorType type;
  final Object? originalError;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic>? context;

  AppError({
    required this.message,
    required this.type,
    this.originalError,
    this.stackTrace,
    DateTime? timestamp,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Factory constructor that sets timestamp to current time
  factory AppError.create({
    required String message,
    required AppErrorType type,
    Object? originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppError(
      message: message,
      type: type,
      originalError: originalError,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
      context: context,
    );
  }

  /// Creates a network error
  factory AppError.network(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AppError.create(
      message: message,
      type: AppErrorType.network,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Creates a storage error
  factory AppError.storage(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AppError.create(
      message: message,
      type: AppErrorType.storage,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Creates a validation error
  factory AppError.validation(String message, {Map<String, dynamic>? context}) {
    return AppError.create(
      message: message,
      type: AppErrorType.validation,
      context: context,
    );
  }

  /// Creates a permission error
  factory AppError.permission(String message, {Object? originalError}) {
    return AppError.create(
      message: message,
      type: AppErrorType.permission,
      originalError: originalError,
    );
  }

  /// Creates a parsing error
  factory AppError.parsing(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AppError.create(
      message: message,
      type: AppErrorType.parsing,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Creates an unknown error
  factory AppError.unknown(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AppError.create(
      message: message,
      type: AppErrorType.unknown,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Gets the severity of this error
  ErrorSeverity get severity => type.severity;

  /// Whether this error can be retried
  bool get isRetryable => type.isRetryable;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('AppError(${type.name}): $message');
    
    if (originalError != null) {
      buffer.write(' [Original: $originalError]');
    }
    
    if (context != null && context!.isNotEmpty) {
      buffer.write(' [Context: $context]');
    }
    
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppError &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          type == other.type &&
          originalError == other.originalError &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      message.hashCode ^
      type.hashCode ^
      originalError.hashCode ^
      timestamp.hashCode;

  /// Creates a copy with optional parameter overrides
  AppError copyWith({
    String? message,
    AppErrorType? type,
    Object? originalError,
    StackTrace? stackTrace,
    DateTime? timestamp,
    Map<String, dynamic>? context,
  }) {
    return AppError(
      message: message ?? this.message,
      type: type ?? this.type,
      originalError: originalError ?? this.originalError,
      stackTrace: stackTrace ?? this.stackTrace,
      timestamp: timestamp ?? this.timestamp,
      context: context ?? this.context,
    );
  }
}
