import 'package:flutter/foundation.dart';
import 'gps_position.dart';

/// Represents geographic bounds with north, south, east, and west coordinates
@immutable
class GeographicBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  GeographicBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  }) {
    if (north < south) {
      throw ArgumentError('North must be greater than or equal to south');
    }
    if (east < west) {
      throw ArgumentError('East must be greater than or equal to west');
    }
    if (north < -90 || north > 90) {
      throw ArgumentError('North must be between -90 and 90');
    }
    if (south < -90 || south > 90) {
      throw ArgumentError('South must be between -90 and 90');
    }
    if (east < -180 || east > 180) {
      throw ArgumentError('East must be between -180 and 180');
    }
    if (west < -180 || west > 180) {
      throw ArgumentError('West must be between -180 and 180');
    }
  }

  /// Calculates the center point of the bounds
  ({double latitude, double longitude}) get center => (
    latitude: (north + south) / 2,
    longitude: (east + west) / 2,
  );

  /// Calculates the width (longitude difference) of the bounds
  double get width => east - west;

  /// Calculates the height (latitude difference) of the bounds
  double get height => north - south;

  /// Checks if a point is within these bounds
  /// 
  /// Can be called with either:
  /// - `contains(GpsPosition position)`
  /// - `contains(double latitude, double longitude)`
  bool contains(dynamic latitudeOrPosition, [double? longitude]) {
    double lat, lon;
    
    if (latitudeOrPosition is GpsPosition) {
      lat = latitudeOrPosition.latitude;
      lon = latitudeOrPosition.longitude;
    } else if (latitudeOrPosition is double && longitude != null) {
      lat = latitudeOrPosition;
      lon = longitude;
    } else {
      throw ArgumentError('Invalid arguments. Use contains(GpsPosition) or contains(latitude, longitude)');
    }
    
    return lat >= south && 
           lat <= north && 
           lon >= west && 
           lon <= east;
  }

  /// Calculates the area of the bounds in square degrees
  double get area => height * width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeographicBounds &&
          runtimeType == other.runtimeType &&
          north == other.north &&
          south == other.south &&
          east == other.east &&
          west == other.west;

  @override
  int get hashCode =>
      north.hashCode ^
      south.hashCode ^
      east.hashCode ^
      west.hashCode;

  @override
  String toString() {
    return 'GeographicBounds(north: $north, south: $south, east: $east, west: $west)';
  }

  /// Creates a copy with optional parameter overrides
  GeographicBounds copyWith({
    double? north,
    double? south,
    double? east,
    double? west,
  }) {
    return GeographicBounds(
      north: north ?? this.north,
      south: south ?? this.south,
      east: east ?? this.east,
      west: west ?? this.west,
    );
  }
}
