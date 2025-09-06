import 'package:flutter/material.dart';
import 'gps_position.dart';

/// Enum for different waypoint types
enum WaypointType {
  departure,
  intermediate,
  destination,
  landmark,
  hazard,
  anchorage;

  /// Display name for the waypoint type
  String get displayName {
    switch (this) {
      case WaypointType.departure:
        return 'Departure';
      case WaypointType.intermediate:
        return 'Intermediate';
      case WaypointType.destination:
        return 'Destination';
      case WaypointType.landmark:
        return 'Landmark';
      case WaypointType.hazard:
        return 'Hazard';
      case WaypointType.anchorage:
        return 'Anchorage';
    }
  }

  /// Icon data for the waypoint type
  IconData get iconData {
    switch (this) {
      case WaypointType.departure:
        return Icons.play_arrow;
      case WaypointType.intermediate:
        return Icons.radio_button_unchecked;
      case WaypointType.destination:
        return Icons.flag;
      case WaypointType.landmark:
        return Icons.place;
      case WaypointType.hazard:
        return Icons.warning;
      case WaypointType.anchorage:
        return Icons.anchor;
    }
  }

  /// Color for the waypoint type
  Color get color {
    switch (this) {
      case WaypointType.departure:
        return Colors.green;
      case WaypointType.intermediate:
        return Colors.blue;
      case WaypointType.destination:
        return Colors.red;
      case WaypointType.landmark:
        return Colors.purple;
      case WaypointType.hazard:
        return Colors.orange;
      case WaypointType.anchorage:
        return Colors.brown;
    }
  }
}

/// Represents a navigation waypoint
@immutable
class Waypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final WaypointType type;
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Waypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.description,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError('Latitude must be between -90 and 90');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError('Longitude must be between -180 and 180');
    }
  }

  /// Factory constructor that sets createdAt to current time
  factory Waypoint.create({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required WaypointType type,
    String? description,
  }) {
    return Waypoint(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      type: type,
      description: description,
      createdAt: DateTime.now(),
    );
  }

  /// Converts this waypoint to a GPS position
  GpsPosition toPosition() {
    return GpsPosition(
      latitude: latitude,
      longitude: longitude,
      timestamp: updatedAt ?? createdAt,
    );
  }

  /// Calculates distance to another waypoint in meters
  double distanceTo(Waypoint other) {
    return toPosition().distanceTo(other.toPosition());
  }

  /// Calculates bearing to another waypoint in degrees
  double bearingTo(Waypoint other) {
    return toPosition().bearingTo(other.toPosition());
  }

  /// Formats the waypoint position as a coordinate string
  String toCoordinateString() {
    return toPosition().toCoordinateString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Waypoint &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          type == other.type &&
          description == other.description &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      type.hashCode ^
      description.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Waypoint(id: $id, name: $name, '
        'lat: ${latitude.toStringAsFixed(6)}, '
        'lon: ${longitude.toStringAsFixed(6)}, '
        'type: ${type.displayName})';
  }

  /// Creates a copy with optional parameter overrides
  Waypoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    WaypointType? type,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Waypoint(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
