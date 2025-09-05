/// ISO/IEC 8211 data structures for S-57 ENC parsing
/// Based on ISO/IEC 8211:1994 specification
/// 
/// This module provides the core data structures for parsing ISO 8211 records
/// that form the foundation of S-57 Electronic Navigational Chart files.

import 'dart:typed_data';

/// Directory entry in an ISO 8211 record
/// 
/// Each directory entry contains metadata about a field in the record,
/// including its tag, length, and position within the field area.
class Iso8211DirectoryEntry {
  /// Field tag (typically 4 characters)
  final String tag;
  
  /// Length of field data in bytes (excluding field terminator)
  final int length;
  
  /// Position offset from start of field area
  final int position;

  const Iso8211DirectoryEntry(this.tag, this.length, this.position);

  @override
  String toString() => 'Iso8211DirectoryEntry(tag: $tag, length: $length, position: $position)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Iso8211DirectoryEntry &&
          runtimeType == other.runtimeType &&
          tag == other.tag &&
          length == other.length &&
          position == other.position;

  @override
  int get hashCode => tag.hashCode ^ length.hashCode ^ position.hashCode;
}

/// ISO 8211 record containing directory and field data
/// 
/// Represents a single ISO 8211 record with parsed directory entries
/// and raw field data accessible by tag.
class Iso8211Record {
  /// Total record length from leader
  final int recordLength;
  
  /// Base address of field area from leader
  final int baseAddress;
  
  /// Directory entries for all fields in this record
  final List<Iso8211DirectoryEntry> directory;
  
  /// Raw field data mapped by tag (excluding field terminators)
  final Map<String, List<int>> rawFields;

  const Iso8211Record({
    required this.recordLength,
    required this.baseAddress,
    required this.directory,
    required this.rawFields,
  });

  /// Get raw field data for a specific tag
  List<int>? getFieldData(String tag) => rawFields[tag];

  /// Check if record contains a specific field tag
  bool hasField(String tag) => rawFields.containsKey(tag);

  /// Get all field tags in this record
  Set<String> get fieldTags => rawFields.keys.toSet();

  @override
  String toString() => 'Iso8211Record(recordLength: $recordLength, '
      'baseAddress: $baseAddress, fields: ${fieldTags.length})';
}

/// Warning information for ISO 8211 parsing issues
/// 
/// Temporary warning collection model pending unified diagnostics (Issue #150)
class Iso8211Warning {
  /// Warning code for categorization
  final String code;
  
  /// Human-readable warning message
  final String message;
  
  /// Optional additional context data
  final Map<String, dynamic>? context;

  const Iso8211Warning({
    required this.code,
    required this.message,
    this.context,
  });

  @override
  String toString() => 'Iso8211Warning(code: $code, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Iso8211Warning &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => code.hashCode ^ message.hashCode;
}

/// Warning codes for common ISO 8211 parsing issues
class Iso8211WarningCodes {
  static const String leaderLengthMismatch = 'LEADER_LEN_MISMATCH';
  static const String badBaseAddress = 'BAD_BASE_ADDR';
  static const String directoryTruncated = 'DIR_TRUNCATED';
  static const String fieldBounds = 'FIELD_BOUNDS';
  static const String subfieldParse = 'SUBFIELD_PARSE';
}