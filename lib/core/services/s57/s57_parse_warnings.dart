/// S-57 Structured Warnings & Strict Mode Diagnostics
///
/// Unified warning model with codes, severities, and contextual identifiers
/// for comprehensive S-57 parsing diagnostics and error handling.

/// Warning severity levels for S-57 parsing
enum S57WarningSeverity {
  /// Informational messages (e.g., auto-corrections)
  info,

  /// Non-critical issues that don't affect parsing (e.g., missing optional data)
  warning,

  /// Critical issues that affect data integrity (e.g., malformed records)
  error,
}

/// Structured warning for S-57 parsing issues
///
/// Provides typed warning information with severity levels and contextual
/// identifiers for comprehensive error tracking and strict mode enforcement.
class S57ParseWarning {
  /// Warning code for categorization (e.g., 'DIR_TRUNCATED')
  final String code;

  /// Human-readable warning message
  final String message;

  /// Severity level determining escalation behavior
  final S57WarningSeverity severity;

  /// Optional record identifier (e.g., tag or record sequence number)
  final String? recordId;

  /// Optional feature identifier (FOID or internal id)
  final String? featureId;

  /// Timestamp when warning was generated
  final DateTime timestamp;

  S57ParseWarning({
    required this.code,
    required this.message,
    required this.severity,
    this.recordId,
    this.featureId,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'S57ParseWarning(${severity.name}): [$code] $message'
      '${recordId != null ? ' (record: $recordId)' : ''}'
      '${featureId != null ? ' (feature: $featureId)' : ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is S57ParseWarning &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          recordId == other.recordId &&
          featureId == other.featureId;

  @override
  int get hashCode => Object.hash(code, message, severity, recordId, featureId);
}

/// Core warning codes for S-57 parsing issues
///
/// Standardized codes matching the specification table for consistent
/// warning categorization across all parsing modules.
class S57WarningCodes {
  // ISO 8211 parsing errors
  static const String leaderLenMismatch = 'LEADER_LEN_MISMATCH';
  static const String badBaseAddr = 'BAD_BASE_ADDR';
  static const String dirTruncated = 'DIR_TRUNCATED';
  static const String fieldBounds = 'FIELD_BOUNDS';
  static const String subfieldParse = 'SUBFIELD_PARSE';
  static const String leaderTruncated = 'LEADER_TRUNCATED';
  static const String fieldLenMismatch = 'FIELD_LEN_MISMATCH';
  static const String missingFieldTerminator = 'MISSING_FIELD_TERM';
  static const String invalidSubfieldDelim = 'INVALID_SUBFIELD_DELIM';
  static const String danglingPointer = 'DANGLING_POINTER';
  static const String coordinateCountMismatch = 'COORD_COUNT_MISMATCH';
  static const String emptyRequiredField = 'EMPTY_REQUIRED_FIELD';
  static const String invalidRUINCode = 'INVALID_RUIN_CODE';

  // S-57 object and attribute validation
  static const String unknownObjCode = 'UNKNOWN_OBJ_CODE';
  static const String missingRequiredAttr = 'MISSING_REQUIRED_ATTR';

  // Geometry validation and processing
  static const String degenerateEdge = 'DEGENERATE_EDGE';
  static const String polygonClosedAuto = 'POLYGON_CLOSED_AUTO';

  // Update processing
  static const String updateGap = 'UPDATE_GAP';
  static const String updateRverMismatch = 'UPDATE_RVER_MISMATCH';
  static const String updateDeleteMissing = 'UPDATE_DELETE_MISSING';
  static const String updateInsertConflict = 'UPDATE_INSERT_CONFLICT';

  // Data sanity checks
  static const String depthOutOfRange = 'DEPTH_OUT_OF_RANGE';
}

/// Configuration options for S-57 parsing behavior
///
/// Controls strict mode enforcement and warning thresholds for
/// different parsing scenarios and environments.
class S57ParseOptions {
  /// Enable strict mode (escalate error-level warnings to exceptions)
  final bool strictMode;

  /// Optional maximum warning threshold (null = no limit)
  final int? maxWarnings;

  const S57ParseOptions({this.strictMode = false, this.maxWarnings});

  /// Create options for development (permissive)
  const S57ParseOptions.development() : this(strictMode: false);

  /// Create options for production (strict)
  const S57ParseOptions.production() : this(strictMode: true, maxWarnings: 100);

  /// Create options for testing (strict with low threshold)
  const S57ParseOptions.testing() : this(strictMode: true, maxWarnings: 10);
}

/// Abstract interface for S-57 parsing event logging
///
/// Pluggable logging interface for integration with UI/CLI systems
/// and custom warning handling strategies.
abstract class S57ParseLogger {
  /// Called when a warning is generated during parsing
  void onWarning(S57ParseWarning warning);

  /// Called when file parsing begins
  void onStartFile(String path);

  /// Called when file parsing completes
  void onFinishFile(String path, {required List<S57ParseWarning> warnings});
}

/// Default no-op logger implementation
///
/// Provides silent logging for scenarios where warning tracking
/// is not required or handled elsewhere.
class S57NoOpLogger implements S57ParseLogger {
  const S57NoOpLogger();

  @override
  void onWarning(S57ParseWarning warning) {
    // No-op implementation
  }

  @override
  void onStartFile(String path) {
    // No-op implementation
  }

  @override
  void onFinishFile(String path, {required List<S57ParseWarning> warnings}) {
    // No-op implementation
  }
}

/// Console logger implementation for CLI applications
///
/// Prints condensed warning information to console with severity-based
/// formatting for development and debugging scenarios.
class S57ConsoleLogger implements S57ParseLogger {
  final bool verbose;

  const S57ConsoleLogger({this.verbose = false});

  @override
  void onWarning(S57ParseWarning warning) {
    final severityPrefix = _getSeverityPrefix(warning.severity);
    final contextSuffix = _getContextSuffix(warning);
    print('$severityPrefix[${warning.code}] ${warning.message}$contextSuffix');
  }

  @override
  void onStartFile(String path) {
    if (verbose) {
      print('Starting S-57 parsing: $path');
    }
  }

  @override
  void onFinishFile(String path, {required List<S57ParseWarning> warnings}) {
    if (verbose || warnings.isNotEmpty) {
      final errorCount = warnings
          .where((w) => w.severity == S57WarningSeverity.error)
          .length;
      final warningCount = warnings
          .where((w) => w.severity == S57WarningSeverity.warning)
          .length;
      final infoCount = warnings
          .where((w) => w.severity == S57WarningSeverity.info)
          .length;

      print(
        'Finished parsing $path: $errorCount errors, $warningCount warnings, $infoCount info',
      );
    }
  }

  String _getSeverityPrefix(S57WarningSeverity severity) {
    switch (severity) {
      case S57WarningSeverity.error:
        return 'ERROR: ';
      case S57WarningSeverity.warning:
        return 'WARN: ';
      case S57WarningSeverity.info:
        return 'INFO: ';
    }
  }

  String _getContextSuffix(S57ParseWarning warning) {
    final parts = <String>[];
    if (warning.recordId != null) parts.add('record:${warning.recordId}');
    if (warning.featureId != null) parts.add('feature:${warning.featureId}');
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }
}
