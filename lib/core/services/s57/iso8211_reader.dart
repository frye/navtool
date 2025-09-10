/// ISO/IEC 8211 record reader for S-57 ENC files
///
/// Implements a robust, standards-aligned ISO/IEC 8211 record parser that
/// produces validated multi-record structures and gracefully handles
/// malformed records according to the specification.


import 'dart:typed_data';

import 'iso8211_models.dart';
import '../../error/app_error.dart';

/// Iterator-based reader for ISO 8211 records
///
/// Provides a stream-like interface for parsing multiple ISO 8211 records
/// from byte data, with graceful recovery for malformed non-DDR records.
class Iso8211Reader {
  static const int _leaderSize = 24;
  static const int _fieldTerminator = 0x1e;
  static const int _recordTerminator = 0x1d;
  static const int _subfieldDelimiter = 0x1f;

  final Uint8List _data;
  int _position = 0;
  final List<Iso8211Warning> _warnings = [];
  final Set<String> _warningKeys =
      {}; // prevent duplicate warnings (runaway memory)

  /// Create reader for the given byte data
  Iso8211Reader(List<int> data) : _data = Uint8List.fromList(data);

  /// Get all collected warnings
  List<Iso8211Warning> get warnings => List.unmodifiable(_warnings);

  /// Read all records from the data stream
  ///
  /// Returns an iterable of successfully parsed records. Malformed records
  /// (except DDR) are skipped with warnings added to the warnings collection.
  Iterable<Iso8211Record> readAll() sync* {
    _position = 0;
    _warnings.clear();
    _warningKeys.clear();

    bool isFirstRecord = true;

    while (_position < _data.lengthInBytes) {
      final startLoopPos = _position;
      try {
        final record = _readSingleRecord(isFirstRecord);
        if (record != null) {
          yield record;
        }
        isFirstRecord = false;
      } catch (e) {
        if (isFirstRecord) {
          // DDR parsing errors are fatal
          rethrow;
        } else {
          // Non-DDR errors are logged as warnings and we continue
          _addWarning(
            Iso8211WarningCodes.subfieldParse,
            'Skipped malformed record at position $_position: ${e.toString()}',
          );
          _skipToNextRecord();
        }
      }
      // Ensure forward progress to avoid infinite loops on corrupt data
      if (_position <= startLoopPos) {
        _position = startLoopPos + 1;
      }
      // Safety guard: stop if excessive warnings (corrupt file)
      if (_warnings.length > 1000) {
        _addWarning(
          Iso8211WarningCodes.subfieldParse,
          'Aborting parse after 1000 warnings to prevent runaway memory',
        );
        break;
      }
    }
  }

  /// Read a single ISO 8211 record
  Iso8211Record? _readSingleRecord(bool isDDR) {
    // Track start of this potential record so we can recover position on failure
    final recordStart = _position;

    if (_position + _leaderSize > _data.lengthInBytes) {
      if (isDDR) {
        throw AppError(
          message: 'Incomplete leader at position $_position',
          type: AppErrorType.parsing,
        );
      } else {
        _addWarning(
          Iso8211WarningCodes.leaderLengthMismatch,
          'Incomplete leader at position $_position',
        );
        return null;
      }
    }

    // Parse 24-byte leader according to ISO 8211 specification
    final leader = _readLeader();

    // Validate leader fields
    if (!_validateLeader(leader, isDDR)) {
      if (isDDR) {
        throw AppError(
          message: 'Invalid DDR leader at position $recordStart',
          type: AppErrorType.parsing,
        );
      } else {
        // Attempt to fast-forward by declared record length if plausible to reduce warning spam
        final remaining = _data.lengthInBytes - recordStart;
        if (leader.recordLength > _leaderSize &&
            leader.recordLength <= remaining) {
          _position = recordStart + leader.recordLength;
        } else {
          _position = recordStart + 1; // minimal advance
          _skipToNextRecord();
        }
        return null; // Warning already added by _validateLeader
      }
    }

    // Parse directory entries
    final directory = _parseDirectory(leader);
    if (directory == null) {
      if (isDDR) {
        throw AppError(
          message: 'Failed to parse DDR directory at position $recordStart',
          type: AppErrorType.parsing,
        );
      } else {
        // Advance minimally to avoid reprocessing same bytes
        _position = recordStart + 1;
        _skipToNextRecord();
        return null; // Warning already added
      }
    }

    // Extract field data
    final rawFields = _extractFields(leader, directory);

    // Advance to next record
    _position = _position - _leaderSize + leader.recordLength;

    return Iso8211Record(
      recordLength: leader.recordLength,
      baseAddress: leader.baseAddress,
      directory: directory,
      rawFields: rawFields,
    );
  }

  /// Parse the 24-byte ISO 8211 leader
  _LeaderInfo _readLeader() {
    final startPos = _position;

    // Record length (positions 0-4)
    final recordLength = _parseAsciiInt(_readAscii(5));

    // Interchange level (position 5)
    final interchangeLevel = _readAscii(1);

    // Leader identifier (position 6)
    final leaderIdentifier = _readAscii(1);

    // Field control length (position 7)
    final fieldControlLength = _parseAsciiInt(_readAscii(1));

    // Base address of field area (positions 8-12)
    final baseAddress = _parseAsciiInt(_readAscii(5));

    // Extended character set indicator (positions 13-15)
    final extendedCharSet = _readAscii(3);

    // Size of field length (position 16)
    final sizeOfFieldLength = _parseAsciiInt(_readAscii(1));

    // Size of field position (position 17)
    final sizeOfFieldPosition = _parseAsciiInt(_readAscii(1));

    // Reserved (position 18)
    final reserved = _readAscii(1);

    // Size of field tag (position 19)
    final sizeOfFieldTag = _parseAsciiInt(_readAscii(1));

    // Remaining reserved bytes (positions 20-23)
    final remaining = _readAscii(4);

    return _LeaderInfo(
      recordLength: recordLength,
      interchangeLevel: interchangeLevel,
      leaderIdentifier: leaderIdentifier,
      fieldControlLength: fieldControlLength,
      baseAddress: baseAddress,
      extendedCharSet: extendedCharSet,
      sizeOfFieldLength: sizeOfFieldLength,
      sizeOfFieldPosition: sizeOfFieldPosition,
      reserved: reserved,
      sizeOfFieldTag: sizeOfFieldTag,
      remaining: remaining,
    );
  }

  /// Validate leader fields according to ISO 8211 specification
  bool _validateLeader(_LeaderInfo leader, bool isDDR) {
    // Validate record length
    final currentRecordStart = _position - _leaderSize;
    final remaining = _data.lengthInBytes - currentRecordStart;
    if (leader.recordLength <= _leaderSize || leader.recordLength > remaining) {
      final msg =
          'Invalid record length: ${leader.recordLength} at position $currentRecordStart (remaining=$remaining)';
      if (isDDR) {
        throw AppError(message: msg, type: AppErrorType.parsing);
      } else {
        _addWarning(Iso8211WarningCodes.leaderLengthMismatch, msg);
        return false;
      }
    }

    // Validate base address
    if (leader.baseAddress < _leaderSize ||
        leader.baseAddress >= leader.recordLength) {
      final msg =
          'Invalid base address: ${leader.baseAddress} (must be in [$_leaderSize, ${leader.recordLength - 1}])';
      if (isDDR) {
        throw AppError(message: msg, type: AppErrorType.parsing);
      } else {
        _addWarning(Iso8211WarningCodes.badBaseAddress, msg);
        return false;
      }
    }

    return true;
  }

  /// Parse directory entries from the record
  List<Iso8211DirectoryEntry>? _parseDirectory(_LeaderInfo leader) {
    final directory = <Iso8211DirectoryEntry>[];
    final directoryStart =
        _position - _leaderSize + _leaderSize; // After leader
    final directoryEnd = _position - _leaderSize + leader.baseAddress;

    int dirPos = directoryStart;

    try {
      while (dirPos < directoryEnd) {
        // Check for directory terminator
        if (dirPos < _data.lengthInBytes && _data[dirPos] == _fieldTerminator) {
          dirPos++; // Skip terminator
          break;
        }

        final entrySize =
            leader.sizeOfFieldTag +
            leader.sizeOfFieldLength +
            leader.sizeOfFieldPosition;

        if (dirPos + entrySize > directoryEnd) {
          _addWarning(
            Iso8211WarningCodes.directoryTruncated,
            'Directory entry extends past base address at position $dirPos',
          );
          return null;
        }

        // Read directory entry
        final tag = _readAsciiAt(dirPos, leader.sizeOfFieldTag).trim();
        dirPos += leader.sizeOfFieldTag;

        final length = _parseAsciiInt(
          _readAsciiAt(dirPos, leader.sizeOfFieldLength),
        );
        dirPos += leader.sizeOfFieldLength;

        final position = _parseAsciiInt(
          _readAsciiAt(dirPos, leader.sizeOfFieldPosition),
        );
        dirPos += leader.sizeOfFieldPosition;

        directory.add(Iso8211DirectoryEntry(tag, length, position));
      }
    } catch (e) {
      _addWarning(
        Iso8211WarningCodes.directoryTruncated,
        'Failed to parse directory: ${e.toString()}',
      );
      return null;
    }

    return directory;
  }

  /// Extract field data according to directory entries
  Map<String, List<int>> _extractFields(
    _LeaderInfo leader,
    List<Iso8211DirectoryEntry> directory,
  ) {
    final fields = <String, List<int>>{};
    final fieldAreaStart = _position - _leaderSize + leader.baseAddress;

    for (final entry in directory) {
      try {
        final fieldStart = fieldAreaStart + entry.position;

        // Validate field bounds
        if (fieldStart >= _data.lengthInBytes) {
          _addWarning(
            Iso8211WarningCodes.fieldBounds,
            'Field ${entry.tag} starts beyond data bounds',
          );
          continue;
        }

        // Find actual field end by scanning for field terminator
        int actualEnd = fieldStart;
        // Allow one extra byte beyond declared length to account for implementations
        // that store length excluding the field terminator (common variance)
        final maxEnd = fieldStart + entry.length + 1;

        while (actualEnd < maxEnd &&
            actualEnd < _data.lengthInBytes &&
            _data[actualEnd] != _fieldTerminator) {
          actualEnd++;
        }

        if (actualEnd > fieldStart) {
          final fieldData = _data.sublist(fieldStart, actualEnd);
          fields[entry.tag] = fieldData;
        }
      } catch (e) {
        _addWarning(
          Iso8211WarningCodes.fieldBounds,
          'Failed to extract field ${entry.tag}: ${e.toString()}',
        );
      }
    }

    return fields;
  }

  /// Read ASCII string at current position and advance
  String _readAscii(int length) {
    if (_position + length > _data.lengthInBytes) {
      throw Exception('Not enough data for ASCII read');
    }

    final bytes = _data.sublist(_position, _position + length);
    _position += length;
    return String.fromCharCodes(bytes);
  }

  /// Read ASCII string at specific position without advancing
  String _readAsciiAt(int position, int length) {
    if (position + length > _data.lengthInBytes) {
      throw Exception('Not enough data for ASCII read at position $position');
    }

    final bytes = _data.sublist(position, position + length);
    return String.fromCharCodes(bytes);
  }

  /// Parse ASCII string as integer
  int _parseAsciiInt(String ascii) {
    final trimmed = ascii.trim();
    if (trimmed.isEmpty) return 0;

    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      throw Exception('Invalid ASCII integer: "$ascii"');
    }

    return parsed;
  }

  /// Add warning to collection
  void _addWarning(
    String code,
    String message, [
    Map<String, dynamic>? context,
  ]) {
    final key = '$code|$message';
    if (_warningKeys.add(key)) {
      _warnings.add(
        Iso8211Warning(code: code, message: message, context: context),
      );
    }
  }

  /// Skip to next record boundary for error recovery
  void _skipToNextRecord() {
    // Scan for next record that starts with a reasonable record length
    while (_position + _leaderSize < _data.lengthInBytes) {
      try {
        final potentialLength = _parseAsciiInt(_readAsciiAt(_position, 5));
        if (potentialLength > _leaderSize &&
            potentialLength <= _data.lengthInBytes - _position &&
            potentialLength < 100000) {
          // Reasonable upper bound
          break;
        }
      } catch (e) {
        // Continue scanning
      }
      _position++;
    }
  }
}

/// Internal leader information structure
class _LeaderInfo {
  final int recordLength;
  final String interchangeLevel;
  final String leaderIdentifier;
  final int fieldControlLength;
  final int baseAddress;
  final String extendedCharSet;
  final int sizeOfFieldLength;
  final int sizeOfFieldPosition;
  final String reserved;
  final int sizeOfFieldTag;
  final String remaining;

  const _LeaderInfo({
    required this.recordLength,
    required this.interchangeLevel,
    required this.leaderIdentifier,
    required this.fieldControlLength,
    required this.baseAddress,
    required this.extendedCharSet,
    required this.sizeOfFieldLength,
    required this.sizeOfFieldPosition,
    required this.reserved,
    required this.sizeOfFieldTag,
    required this.remaining,
  });
}
