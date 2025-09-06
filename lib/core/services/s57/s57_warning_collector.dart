/// S-57 Warning Collection and Strict Mode Enforcement
/// 
/// Manages warning accumulation, threshold checking, and strict mode
/// exception handling for S-57 parsing operations.

import 's57_parse_warnings.dart';

/// Exception thrown when strict mode escalates warnings to errors
class S57StrictModeException implements Exception {
  final S57ParseWarning triggeredBy;
  final List<S57ParseWarning> allWarnings;

  const S57StrictModeException(this.triggeredBy, this.allWarnings);

  @override
  String toString() => 'S57StrictModeException: ${triggeredBy.message} '
      '(${allWarnings.length} total warnings)';
}

/// Warning collection service with strict mode enforcement
/// 
/// Accumulates warnings during parsing and enforces strict mode policies
/// including error escalation and threshold checking.
class S57WarningCollector {
  final S57ParseOptions _options;
  final S57ParseLogger _logger;
  final List<S57ParseWarning> _warnings = [];
  
  S57WarningCollector({
    S57ParseOptions? options,
    S57ParseLogger? logger,
  }) : _options = options ?? const S57ParseOptions(),
       _logger = logger ?? const S57NoOpLogger();

  /// Get all collected warnings (immutable copy)
  List<S57ParseWarning> get warnings => List.unmodifiable(_warnings);

  /// Get warning count by severity
  int get errorCount => _warnings.where((w) => w.severity == S57WarningSeverity.error).length;
  int get warningCount => _warnings.where((w) => w.severity == S57WarningSeverity.warning).length;
  int get infoCount => _warnings.where((w) => w.severity == S57WarningSeverity.info).length;

  /// Total warning count
  int get totalWarnings => _warnings.length;

  /// Check if any error-level warnings exist
  bool get hasErrors => errorCount > 0;

  /// Check if warning threshold is exceeded
  bool get isThresholdExceeded {
    final maxWarnings = _options.maxWarnings;
    return maxWarnings != null && totalWarnings > maxWarnings;
  }

  /// Add a warning with automatic strict mode checking
  /// 
  /// Throws [S57StrictModeException] if strict mode is enabled and:
  /// - Warning has error severity, OR
  /// - Warning count exceeds maxWarnings threshold
  void warn(
    String code,
    S57WarningSeverity severity,
    String message, {
    String? recordId,
    String? featureId,
  }) {
    final warning = S57ParseWarning(
      code: code,
      message: message,
      severity: severity,
      recordId: recordId,
      featureId: featureId,
    );

    _warnings.add(warning);
    _logger.onWarning(warning);

    // Check strict mode conditions
    if (_options.strictMode) {
      // Check warning threshold first (takes precedence)
      if (isThresholdExceeded) {
        final thresholdWarning = S57ParseWarning(
          code: 'MAX_WARNINGS_EXCEEDED',
          message: 'Maximum warning threshold (${_options.maxWarnings}) exceeded',
          severity: S57WarningSeverity.error,
        );
        _warnings.add(thresholdWarning);
        throw S57StrictModeException(thresholdWarning, warnings);
      }

      // Escalate error-severity warnings to exceptions
      if (severity == S57WarningSeverity.error) {
        throw S57StrictModeException(warning, warnings);
      }
    }
  }

  /// Convenience method for error-level warnings
  void error(
    String code,
    String message, {
    String? recordId,
    String? featureId,
  }) => warn(code, S57WarningSeverity.error, message, 
            recordId: recordId, featureId: featureId);

  /// Convenience method for warning-level warnings
  void warning(
    String code,
    String message, {
    String? recordId,
    String? featureId,
  }) => warn(code, S57WarningSeverity.warning, message, 
            recordId: recordId, featureId: featureId);

  /// Convenience method for info-level warnings
  void info(
    String code,
    String message, {
    String? recordId,
    String? featureId,
  }) => warn(code, S57WarningSeverity.info, message, 
            recordId: recordId, featureId: featureId);

  /// Clear all warnings
  void clear() {
    _warnings.clear();
  }

  /// Get warnings filtered by severity
  List<S57ParseWarning> getWarningsBySeverity(S57WarningSeverity severity) {
    return _warnings.where((w) => w.severity == severity).toList();
  }

  /// Get warnings filtered by code
  List<S57ParseWarning> getWarningsByCode(String code) {
    return _warnings.where((w) => w.code == code).toList();
  }

  /// Start file processing (notify logger)
  void startFile(String path) {
    _logger.onStartFile(path);
  }

  /// Finish file processing (notify logger)
  void finishFile(String path) {
    _logger.onFinishFile(path, warnings: warnings);
  }

  /// Create a summary report of all warnings
  Map<String, dynamic> createSummaryReport() {
    final warningsByCode = <String, int>{};
    final warningsBySeverity = <String, int>{
      'error': 0,
      'warning': 0,
      'info': 0,
    };

    for (final warning in _warnings) {
      warningsByCode[warning.code] = (warningsByCode[warning.code] ?? 0) + 1;
      warningsBySeverity[warning.severity.name] = 
          (warningsBySeverity[warning.severity.name] ?? 0) + 1;
    }

    return {
      'totalWarnings': totalWarnings,
      'warningsBySeverity': warningsBySeverity,
      'warningsByCode': warningsByCode,
      'hasErrors': hasErrors,
      'isThresholdExceeded': isThresholdExceeded,
      'maxWarnings': _options.maxWarnings,
      'strictMode': _options.strictMode,
    };
  }
}