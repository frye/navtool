/// S-57 Structured Warnings Integration Example
///
/// Demonstrates how to integrate the new structured warning system
/// with existing S-57 parsing code and migrate from ad-hoc warnings.

import 's57_parse_warnings.dart';
import 's57_warning_collector.dart';

/// Example integration with S-57 parser showing migration patterns
class S57ParserIntegrationExample {
  final S57WarningCollector _warnings;

  S57ParserIntegrationExample({
    S57ParseOptions? options,
    S57ParseLogger? logger,
  }) : _warnings = S57WarningCollector(options: options, logger: logger);

  /// Example: ISO 8211 record parsing with structured warnings
  Map<String, dynamic> parseIso8211Record(List<int> recordData) {
    try {
      _warnings.startFile('example-file.000');

      // Validate record length
      if (recordData.length < 24) {
        _warnings.error(
          S57WarningCodes.leaderLenMismatch,
          'Record too short: ${recordData.length} bytes (minimum 24)',
          recordId: 'RECORD_${recordData.hashCode}',
        );
        return {};
      }

      // Parse leader
      final recordLength = _parseRecordLength(recordData);
      if (recordLength != recordData.length) {
        _warnings.error(
          S57WarningCodes.leaderLenMismatch,
          'Leader length $recordLength does not match actual data ${recordData.length}',
          recordId: 'LEADER_CHECK',
        );
      }

      // Parse directory (may generate warnings)
      final directory = _parseDirectory(recordData);

      // Parse fields (may generate field bounds warnings)
      final fields = _parseFields(recordData, directory);

      _warnings.finishFile('example-file.000');

      return {
        'recordLength': recordLength,
        'directory': directory,
        'fields': fields,
        'warnings': _warnings.warnings,
      };
    } on S57StrictModeException catch (e) {
      // In strict mode, parsing stops on first error
      print('Parsing failed in strict mode: ${e.triggeredBy.message}');
      print('Total warnings before failure: ${e.allWarnings.length}');
      rethrow;
    }
  }

  /// Example: S-57 feature validation with structured warnings
  Map<String, dynamic> validateS57Feature(Map<String, dynamic> featureData) {
    final objectCode = featureData['objectCode'] as int?;
    final attributes = featureData['attributes'] as Map<String, dynamic>? ?? {};
    final featureId = featureData['featureId'] as String?;

    // Check for unknown object codes
    if (objectCode == null || !_isKnownObjectCode(objectCode)) {
      _warnings.warning(
        S57WarningCodes.unknownObjCode,
        'Unknown object code $objectCode - feature may not render correctly',
        recordId: 'FEATURE_VALIDATION',
        featureId: featureId,
      );
    }

    // Check required attributes
    final requiredAttrs = _getRequiredAttributes(objectCode);
    for (final requiredAttr in requiredAttrs) {
      if (!attributes.containsKey(requiredAttr) ||
          attributes[requiredAttr] == null) {
        _warnings.warning(
          S57WarningCodes.missingRequiredAttr,
          'Missing required attribute $requiredAttr for object code $objectCode',
          recordId: 'ATTR_VALIDATION',
          featureId: featureId,
        );
      }
    }

    // Validate depth attributes
    if (attributes.containsKey('VALSOU')) {
      final depth = attributes['VALSOU'] as double?;
      if (depth != null && (depth < -100 || depth > 15000)) {
        _warnings.info(
          S57WarningCodes.depthOutOfRange,
          'Depth value ${depth}m outside typical range (-100 to 15000m)',
          featureId: featureId,
        );
      }
    }

    return {
      'isValid': !_warnings.hasErrors,
      'warnings': _warnings.warnings,
      'summary': _warnings.createSummaryReport(),
    };
  }

  /// Example: Geometry processing with structured warnings
  List<Map<String, double>> processGeometry(
    List<List<double>> coordinates,
    String featureId,
  ) {
    if (coordinates.isEmpty) {
      _warnings.warning(
        S57WarningCodes.degenerateEdge,
        'Geometry has no coordinates - cannot process',
        featureId: featureId,
      );
      return [];
    }

    // Check for polygon closure
    if (coordinates.length > 2) {
      final first = coordinates.first;
      final last = coordinates.last;

      if (first[0] != last[0] || first[1] != last[1]) {
        _warnings.info(
          S57WarningCodes.polygonClosedAuto,
          'Polygon auto-closed: added segment from (${last[0]}, ${last[1]}) to (${first[0]}, ${first[1]})',
          featureId: featureId,
        );
        coordinates = [...coordinates, first]; // Auto-close
      }
    }

    // Check for degenerate edges
    if (coordinates.length < 2) {
      _warnings.warning(
        S57WarningCodes.degenerateEdge,
        'Edge has only ${coordinates.length} point(s) - requires at least 2 for line geometry',
        featureId: featureId,
      );
    }

    return coordinates
        .map((coord) => {'longitude': coord[0], 'latitude': coord[1]})
        .toList();
  }

  /// Example migration: Replace old warning pattern with new structured approach
  void _oldWarningPattern() {
    // OLD: Ad-hoc string-based warning
    // print('Warning: Unknown object code 999 in record FRID_001');

    // NEW: Structured warning with proper categorization
    _warnings.warning(
      S57WarningCodes.unknownObjCode,
      'Unknown object code 999 - not found in S-57 catalog',
      recordId: 'FRID_001',
    );
  }

  /// Get current warning statistics
  Map<String, dynamic> getWarningStatistics() =>
      _warnings.createSummaryReport();

  /// Check if parsing can continue (no critical errors)
  bool canContinueParsing() =>
      !_warnings.hasErrors || !_warnings.createSummaryReport()['strictMode'];

  // Helper methods (simplified for example)
  int _parseRecordLength(List<int> data) =>
      int.parse(String.fromCharCodes(data.sublist(0, 5)));

  List<String> _parseDirectory(List<int> data) => [
    'DIR1',
    'DIR2',
  ]; // Simplified

  Map<String, List<int>> _parseFields(List<int> data, List<String> directory) =>
      {
        'FIELD1': [1, 2, 3],
      }; // Simplified

  bool _isKnownObjectCode(int code) =>
      [42, 74, 121].contains(code); // Simplified

  List<String> _getRequiredAttributes(int? objectCode) {
    switch (objectCode) {
      case 42:
        return ['DRVAL1']; // DEPARE
      case 74:
        return ['VALSOU']; // SOUNDG
      default:
        return [];
    }
  }
}

/// Example usage patterns
void demonstrateWarningSystemUsage() {
  // Development mode - permissive
  final devParser = S57ParserIntegrationExample(
    options: const S57ParseOptions.development(),
    logger: const S57ConsoleLogger(verbose: true),
  );

  // Production mode - strict
  final prodParser = S57ParserIntegrationExample(
    options: const S57ParseOptions.production(),
    logger: const S57ConsoleLogger(),
  );

  // Custom configuration
  final customParser = S57ParserIntegrationExample(
    options: const S57ParseOptions(strictMode: true, maxWarnings: 50),
    logger: const S57NoOpLogger(), // Silent
  );

  // Process some example data
  try {
    final result = devParser.parseIso8211Record([1, 2, 3]); // Too short
    print('Dev mode result: ${result['warnings'].length} warnings');
  } catch (e) {
    print('Dev mode should not throw: $e');
  }

  try {
    final result = prodParser.parseIso8211Record([1, 2, 3]); // Too short
    print('Prod mode should have thrown but got: $result');
  } on S57StrictModeException catch (e) {
    print('Prod mode correctly threw: ${e.triggeredBy.code}');
  }
}
