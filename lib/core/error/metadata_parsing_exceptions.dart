/// Custom exceptions for NOAA metadata parsing operations
/// 
/// This file defines specific exceptions that can occur during the parsing
/// of NOAA GeoJSON metadata into Chart objects, providing detailed error
/// information for debugging and error handling.

/// Base exception class for metadata parsing errors
class MetadataParsingException implements Exception {
  final String message;
  final Map<String, dynamic>? data;
  
  const MetadataParsingException(this.message, {this.data});
  
  @override
  String toString() => 'MetadataParsingException: $message';
}

/// Exception thrown when chart geometry is invalid or cannot be parsed
class InvalidGeometryException extends MetadataParsingException {
  const InvalidGeometryException(String message, {Map<String, dynamic>? data}) 
    : super(message, data: data);
  
  @override
  String toString() => 'InvalidGeometryException: $message';
}

/// Exception thrown when required NOAA metadata fields are missing
class MissingRequiredFieldException extends MetadataParsingException {
  final String fieldName;
  
  const MissingRequiredFieldException(this.fieldName, {Map<String, dynamic>? data}) 
    : super('Missing required field: $fieldName', data: data);
  
  @override
  String toString() => 'MissingRequiredFieldException: Missing required field: $fieldName';
}

/// Exception thrown when date parsing fails
class DateParsingException extends MetadataParsingException {
  final String dateString;
  
  const DateParsingException(this.dateString, {Map<String, dynamic>? data})
    : super('Failed to parse date: $dateString', data: data);
  
  @override
  String toString() => 'DateParsingException: Failed to parse date: $dateString';
}

/// Exception thrown when chart scale is invalid
class InvalidChartScaleException extends MetadataParsingException {
  final dynamic scale;
  
  const InvalidChartScaleException(this.scale, {Map<String, dynamic>? data})
    : super('Invalid chart scale: $scale', data: data);
  
  @override
  String toString() => 'InvalidChartScaleException: Invalid chart scale: $scale';
}