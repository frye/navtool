import 'package:flutter/foundation.dart';
import 'waypoint.dart';
import 'gps_position.dart';

/// Represents a navigation route consisting of multiple waypoints
@immutable
class NavigationRoute {
  final String id;
  final String name;
  final List<Waypoint> waypoints;
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  NavigationRoute({
    required this.id,
    required this.name,
    required this.waypoints,
    this.description,
    DateTime? createdAt,
    this.updatedAt,
    this.isActive = false,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (waypoints.length < 2) {
      throw ArgumentError('Route must have at least 2 waypoints');
    }
  }

  /// Factory constructor that sets createdAt to current time
  factory NavigationRoute.create({
    required String id,
    required String name,
    required List<Waypoint> waypoints,
    String? description,
  }) {
    return NavigationRoute(
      id: id,
      name: name,
      waypoints: waypoints,
      description: description,
      createdAt: DateTime.now(),
    );
  }

  /// Calculates the total distance of the route in meters
  double get totalDistance {
    if (waypoints.length < 2) return 0.0;
    
    double total = 0.0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      total += waypoints[i].distanceTo(waypoints[i + 1]);
    }
    return total;
  }

  /// Gets the departure waypoint (first waypoint)
  Waypoint get departure => waypoints.first;

  /// Gets the destination waypoint (last waypoint)
  Waypoint get destination => waypoints.last;

  /// Gets intermediate waypoints (all except first and last)
  List<Waypoint> get intermediateWaypoints {
    if (waypoints.length <= 2) return [];
    return waypoints.sublist(1, waypoints.length - 1);
  }

  /// Finds the next waypoint in the route based on current position
  Waypoint? getNextWaypoint(GpsPosition currentPosition) {
    if (waypoints.isEmpty) return null;
    
    // Find the closest waypoint that hasn't been reached
    double minDistance = double.infinity;
    Waypoint? nextWaypoint;
    
    for (final waypoint in waypoints) {
      final distance = currentPosition.distanceTo(waypoint.toPosition());
      if (distance < minDistance) {
        minDistance = distance;
        nextWaypoint = waypoint;
      }
    }
    
    return nextWaypoint;
  }

  /// Calculates the remaining distance from current position to destination
  double remainingDistance(GpsPosition currentPosition) {
    final nextWaypoint = getNextWaypoint(currentPosition);
    if (nextWaypoint == null) return 0.0;
    
    double remaining = currentPosition.distanceTo(nextWaypoint.toPosition());
    
    // Add distances between remaining waypoints
    final nextIndex = waypoints.indexOf(nextWaypoint);
    for (int i = nextIndex; i < waypoints.length - 1; i++) {
      remaining += waypoints[i].distanceTo(waypoints[i + 1]);
    }
    
    return remaining;
  }

  /// Gets the bearing from current position to next waypoint
  double? getBearing(GpsPosition currentPosition) {
    final nextWaypoint = getNextWaypoint(currentPosition);
    if (nextWaypoint == null) return null;
    
    return currentPosition.bearingTo(nextWaypoint.toPosition());
  }

  /// Checks if the route contains a specific waypoint
  bool containsWaypoint(String waypointId) {
    return waypoints.any((wp) => wp.id == waypointId);
  }

  /// Gets a waypoint by its ID
  Waypoint? getWaypointById(String waypointId) {
    try {
      return waypoints.firstWhere((wp) => wp.id == waypointId);
    } catch (e) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationRoute &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          listEquals(waypoints, other.waypoints) &&
          description == other.description &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      waypoints.hashCode ^
      description.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      isActive.hashCode;

  @override
  String toString() {
    return 'NavigationRoute(id: $id, name: $name, '
           'waypoints: ${waypoints.length}, '
           'distance: ${(totalDistance / 1000).toStringAsFixed(2)}km, '
           'active: $isActive)';
  }

  /// Creates a copy with optional parameter overrides
  NavigationRoute copyWith({
    String? id,
    String? name,
    List<Waypoint>? waypoints,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return NavigationRoute(
      id: id ?? this.id,
      name: name ?? this.name,
      waypoints: waypoints ?? this.waypoints,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
