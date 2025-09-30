/// Structured error taxonomy for chart loading pipeline (extract → parse → convert → render)
/// Provides user-facing guidance and classification to support troubleshooting UI
import 'package:flutter/foundation.dart';

@immutable
class ChartLoadError implements Exception {
  final ChartLoadErrorType type;
  final String message; // concise summary
  final String? detail; // optional technical detail
  final Object? originalError;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic>? context; // stage specific context (file path, counts, etc.)

  ChartLoadError._({
    required this.type,
    required this.message,
    this.detail,
    this.originalError,
    this.stackTrace,
    DateTime? timestamp,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChartLoadError.extraction(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.extraction, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.parsing(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.parsing, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.conversion(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.conversion, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.integrity(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.integrity, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.dataNotFound(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.dataNotFound, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.cancelled({String message = 'Operation cancelled by user', Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.cancelled, message: message, context: context);
  factory ChartLoadError.unknown(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      ChartLoadError._(type: ChartLoadErrorType.unknown, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.network(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
    ChartLoadError._(type: ChartLoadErrorType.network, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);
  factory ChartLoadError.download(String message, {String? detail, Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
    ChartLoadError._(type: ChartLoadErrorType.download, message: message, detail: detail, originalError: error, stackTrace: stackTrace, context: context);

  bool get isRetryable => type == ChartLoadErrorType.extraction ||
    type == ChartLoadErrorType.parsing ||
    type == ChartLoadErrorType.conversion ||
    type == ChartLoadErrorType.network ||
    type == ChartLoadErrorType.download; // integrity + dataNotFound never retry automatically

  /// High level user suggestions (ordered by priority) for this error type
  List<String> get suggestions {
    final s = <String>[];
    switch (type) {
      case ChartLoadErrorType.extraction:
        s.addAll([
          'Verify the ENC ZIP exists and is not corrupted (try unzip manually).',
          'Ensure the .000 base cell file is present inside the archive.',
          'Re-run tests to regenerate fixture if missing.',
        ]);
        break;
      case ChartLoadErrorType.parsing:
        s.addAll([
          'Check console logs for first parsing error line.',
          'Validate S-57 cell integrity (no truncated records).',
          'Confirm parser version matches expected S-57 edition.',
        ]);
        break;
      case ChartLoadErrorType.conversion:
        s.addAll([
          'Inspect feature type mapping in S57ToMaritimeAdapter.',
          'Log raw S-57 feature count and ensure expected acronyms present.',
          'Verify no unhandled geometry types were dropped.',
        ]);
        break;
      case ChartLoadErrorType.integrity:
        s.addAll([
          'Compare computed SHA256 with known good hash in docs.',
          'Re-download ENC dataset in case of partial/corrupted file.',
        ]);
        break;
      case ChartLoadErrorType.dataNotFound:
        s.addAll([
          'Confirm test fixture path and asset mapping for this chart ID.',
          'Place ENC ZIP under test/fixtures/charts/noaa_enc/.',
          'Run download utility script if available.',
        ]);
        break;
      case ChartLoadErrorType.network:
        s.addAll([
          'Verify internet connectivity or satellite link stability.',
          'Check NOAA API status or rate limiting headers.',
          'Retry with backoff; transient network failures often resolve.',
        ]);
        break;
      case ChartLoadErrorType.download:
        s.addAll([
          'Check disk space and write permissions.',
          'Re-attempt chart download (file may be partial).',
          'Validate target URL and network reachability.',
        ]);
        break;
      case ChartLoadErrorType.cancelled:
        s.add('User cancelled operation – retry if needed.');
        break;
      case ChartLoadErrorType.unknown:
        s.addAll([
          'Check full stack trace in logs.',
          'Validate environment (Flutter version, dependencies).',
        ]);
        break;
    }
    return s;
  }

  @override
  String toString() => 'ChartLoadError(${type.name}): $message';
}

enum ChartLoadErrorType {
  extraction,
  parsing,
  conversion,
  integrity,
  dataNotFound,
  network, // network / connectivity / API failure
  download, // download / storage related
  cancelled,
  unknown;
}
