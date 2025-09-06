import 'package:flutter/foundation.dart';
import 'dart:math' as math;

/// Represents a GPS position with latitude, longitude, and timestamp
@immutable
class GpsPosition {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitude;
  final double? accuracy;
  final double? heading;
  final double? speed;

  GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitude,
    this.accuracy,
    this.heading,
    this.speed,
  }) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError('Latitude must be between -90 and 90');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError('Longitude must be between -180 and 180');
    }
    if (altitude != null && altitude! < -1000) {
      throw ArgumentError('Altitude cannot be below -1000m');
    }
    if (accuracy != null && accuracy! < 0) {
      throw ArgumentError('Accuracy must be non-negative');
    }
    if (heading != null && (heading! < 0 || heading! >= 360)) {
      throw ArgumentError('Heading must be between 0 and 360');
    }
    if (speed != null && speed! < 0) {
      throw ArgumentError('Speed must be non-negative');
    }
  }

  /// Calculates the distance to another GPS position in meters using the Haversine formula
  double distanceTo(GpsPosition other) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final double lat1Rad = latitude * math.pi / 180;
    final double lat2Rad = other.latitude * math.pi / 180;
    final double deltaLatRad = (other.latitude - latitude) * math.pi / 180;
    final double deltaLonRad = (other.longitude - longitude) * math.pi / 180;

    final double a =
        math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Calculates the bearing to another GPS position in degrees (0-360)
  double bearingTo(GpsPosition other) {
    final double lat1Rad = latitude * math.pi / 180;
    final double lat2Rad = other.latitude * math.pi / 180;
    final double deltaLonRad = (other.longitude - longitude) * math.pi / 180;

    final double y = math.sin(deltaLonRad) * math.cos(lat2Rad);
    final double x =
        math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLonRad);

    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Returns the age of this position in seconds
  int get ageInSeconds {
    return DateTime.now().difference(timestamp).inSeconds;
  }

  /// Checks if this position is considered fresh (less than specified seconds old)
  bool isFresh({int maxAgeSeconds = 30}) {
    return ageInSeconds <= maxAgeSeconds;
  }

  /// Formats the position as a coordinate string
  String toCoordinateString() {
    final String latDirection = latitude >= 0 ? 'N' : 'S';
    final String lonDirection = longitude >= 0 ? 'E' : 'W';

    final double absLat = latitude.abs();
    final double absLon = longitude.abs();

    final int latDeg = absLat.floor();
    final double latMin = (absLat - latDeg) * 60;

    final int lonDeg = absLon.floor();
    final double lonMin = (absLon - lonDeg) * 60;

    return '${latDeg.toString().padLeft(2, '0')}°${latMin.toStringAsFixed(3)}\'$latDirection '
        '${lonDeg.toString().padLeft(3, '0')}°${lonMin.toStringAsFixed(3)}\'$lonDirection';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsPosition &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          timestamp == other.timestamp &&
          altitude == other.altitude &&
          accuracy == other.accuracy &&
          heading == other.heading &&
          speed == other.speed;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      timestamp.hashCode ^
      altitude.hashCode ^
      accuracy.hashCode ^
      heading.hashCode ^
      speed.hashCode;

  @override
  String toString() {
    return 'GpsPosition(lat: ${latitude.toStringAsFixed(6)}, '
        'lon: ${longitude.toStringAsFixed(6)}, '
        'timestamp: $timestamp)';
  }

  /// Creates a copy with optional parameter overrides
  GpsPosition copyWith({
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    double? altitude,
    double? accuracy,
    double? heading,
    double? speed,
  }) {
    return GpsPosition(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
    );
  }
}
