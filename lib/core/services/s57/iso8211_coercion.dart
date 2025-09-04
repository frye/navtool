/// Attribute coercion utilities for ISO 8211 field data
/// 
/// Provides basic type detection and conversion for raw field bytes,
/// supporting the minimal attribute coercion layer required for
/// later semantic decoding in S-57 catalog integration.

import 'dart:convert';
import 'dart:typed_data';

/// Coerce a raw string value to appropriate type (int, double, or string)
/// 
/// Attempts to parse as integer first, then double, falling back to trimmed string.
/// Returns the original string if empty.
Object coerceValue(String raw) {
  if (raw.isEmpty) return raw;
  
  // Try integer parsing first
  final intVal = int.tryParse(raw);
  if (intVal != null) return intVal;
  
  // Try double parsing
  final doubleVal = double.tryParse(raw);
  if (doubleVal != null) return doubleVal;
  
  // Return trimmed string
  return raw.trim();
}

/// Split raw field bytes on subfield delimiters and coerce each part
/// 
/// Handles ISO 8211 subfield delimiter (0x1F) splitting and applies
/// type coercion to each resulting substring.
List<Object> splitAndCoerce(List<int> bytes) {
  // Convert bytes to string using ASCII
  final raw = String.fromCharCodes(bytes);
  
  // Split on subfield delimiter (0x1F)
  final parts = raw.split('\u001F');
  
  // Coerce each part to appropriate type
  return parts.map(coerceValue).toList();
}

/// Coerce raw field bytes to a single value
/// 
/// For fields without subfield delimiters, converts the entire
/// byte array to a string and applies type coercion.
Object coerceFieldValue(List<int> bytes) {
  if (bytes.isEmpty) return '';
  
  final raw = String.fromCharCodes(bytes);
  return coerceValue(raw);
}

/// Extract and coerce multiple values from structured field data
/// 
/// For more complex field structures, this utility helps extract
/// multiple typed values from a single field's raw bytes.
Map<String, Object> extractStructuredValues(List<int> bytes, List<String> fieldNames) {
  final parts = splitAndCoerce(bytes);
  final result = <String, Object>{};
  
  for (int i = 0; i < fieldNames.length && i < parts.length; i++) {
    result[fieldNames[i]] = parts[i];
  }
  
  return result;
}

/// Utility class for common S-57 field coercion patterns
class S57FieldCoercion {
  /// Coerce coordinate values (typically stored as scaled integers)
  static double? coerceCoordinate(List<int> bytes, {double scale = 10000000.0}) {
    if (bytes.length < 4) return null;
    
    try {
      final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
      final rawValue = byteData.getInt32(0, Endian.little);
      return rawValue / scale;
    } catch (e) {
      return null;
    }
  }
  
  /// Coerce depth values (typically scaled integers in centimeters to meters)
  static double? coerceDepth(List<int> bytes, {double scale = 100.0}) {
    if (bytes.length < 4) return null;
    
    try {
      final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
      final rawValue = byteData.getInt32(0, Endian.little);
      return rawValue / scale;
    } catch (e) {
      return null;
    }
  }
  
  /// Coerce record identifier fields (typically unsigned integers)
  static int? coerceRecordId(List<int> bytes) {
    if (bytes.isEmpty) return null;
    
    try {
      // Try binary parsing first for efficiency
      if (bytes.length == 4) {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        return byteData.getUint32(0, Endian.little);
      } else if (bytes.length == 2) {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        return byteData.getUint16(0, Endian.little);
      } else if (bytes.length == 1) {
        return bytes[0];
      }
      
      // Fall back to string parsing
      final str = String.fromCharCodes(bytes).trim();
      return int.tryParse(str);
    } catch (e) {
      return null;
    }
  }
  
  /// Coerce attribute values with S-57 specific handling
  static Object coerceAttributeValue(List<int> bytes) {
    if (bytes.isEmpty) return '';
    
    // For single byte values, return as integer
    if (bytes.length == 1) {
      return bytes[0];
    }
    
    // For 2-byte values, try as unsigned short
    if (bytes.length == 2) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        return byteData.getUint16(0, Endian.little);
      } catch (e) {
        // Fall through to string handling
      }
    }
    
    // For 4-byte values, try as signed integer
    if (bytes.length == 4) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        return byteData.getInt32(0, Endian.little);
      } catch (e) {
        // Fall through to string handling
      }
    }
    
    // Default to string coercion with subfield splitting
    return splitAndCoerce(bytes);
  }
}