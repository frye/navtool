/// Spatial operations utilities for polygon intersection and geographic calculations
library;

import 'dart:math' as math;
import '../models/chart_models.dart';
import '../models/geographic_bounds.dart';

/// Utility class for spatial operations on geographic polygons
class SpatialOperations {
  /// Check if a point is inside a polygon using ray casting algorithm
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) {
      throw ArgumentError('Polygon must have at least 3 vertices');
    }

    // Check if polygon is degenerate (all points collinear)
    if (_isPolygonDegenerate(polygon)) {
      return false; // Degenerate polygon has no area
    }

    int intersections = 0;

    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final vertex1 = polygon[i];
      final vertex2 = polygon[j];

      // Check if point is on the edge first
      if (_isPointOnSegment(point, vertex1, vertex2)) {
        return true;
      }

      if (_rayIntersectsSegment(point, vertex1, vertex2)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  /// Check if polygon is degenerate (all points are collinear)
  static bool _isPolygonDegenerate(List<LatLng> polygon) {
    if (polygon.length < 3) return true;

    const double epsilon = 1e-10;

    // Find the first two distinct points
    int baseIndex = 0;
    int nextIndex = 1;

    while (nextIndex < polygon.length &&
        _arePointsEqual(polygon[baseIndex], polygon[nextIndex], epsilon)) {
      nextIndex++;
    }

    if (nextIndex >= polygon.length) return true; // All points are the same

    // Check if all other points are collinear with the first two
    for (int i = nextIndex + 1; i < polygon.length; i++) {
      if (!_arePointsEqual(polygon[i], polygon[baseIndex], epsilon) &&
          !_arePointsCollinear(
            polygon[baseIndex],
            polygon[nextIndex],
            polygon[i],
            epsilon,
          )) {
        return false; // Found a non-collinear point
      }
    }

    return true; // All points are collinear
  }

  /// Check if two points are equal within epsilon tolerance
  static bool _arePointsEqual(LatLng point1, LatLng point2, double epsilon) {
    return (point1.latitude - point2.latitude).abs() < epsilon &&
        (point1.longitude - point2.longitude).abs() < epsilon;
  }

  /// Check if three points are collinear
  static bool _arePointsCollinear(
    LatLng p1,
    LatLng p2,
    LatLng p3,
    double epsilon,
  ) {
    final crossProduct =
        (p2.latitude - p1.latitude) * (p3.longitude - p1.longitude) -
        (p2.longitude - p1.longitude) * (p3.latitude - p1.latitude);
    return crossProduct.abs() < epsilon;
  }

  /// Check if a point lies on a line segment
  static bool _isPointOnSegment(LatLng point, LatLng vertex1, LatLng vertex2) {
    const double epsilon = 1e-10;

    // Check if point is collinear with the segment
    final crossProduct =
        (point.latitude - vertex1.latitude) *
            (vertex2.longitude - vertex1.longitude) -
        (point.longitude - vertex1.longitude) *
            (vertex2.latitude - vertex1.latitude);

    if (crossProduct.abs() > epsilon) {
      return false; // Not collinear
    }

    // Check if point is within the segment bounds
    final dotProduct =
        (point.longitude - vertex1.longitude) *
            (vertex2.longitude - vertex1.longitude) +
        (point.latitude - vertex1.latitude) *
            (vertex2.latitude - vertex1.latitude);
    final squaredLength =
        (vertex2.longitude - vertex1.longitude) *
            (vertex2.longitude - vertex1.longitude) +
        (vertex2.latitude - vertex1.latitude) *
            (vertex2.latitude - vertex1.latitude);

    return dotProduct >= 0 && dotProduct <= squaredLength;
  }

  /// Check if horizontal ray from point intersects line segment
  static bool _rayIntersectsSegment(
    LatLng point,
    LatLng vertex1,
    LatLng vertex2,
  ) {
    // Check if ray is within y-range of segment
    if (vertex1.latitude > point.latitude ==
        vertex2.latitude > point.latitude) {
      return false;
    }

    // Calculate x-coordinate of intersection
    final intersectionX =
        vertex1.longitude +
        (point.latitude - vertex1.latitude) *
            (vertex2.longitude - vertex1.longitude) /
            (vertex2.latitude - vertex1.latitude);

    return intersectionX > point.longitude;
  }

  /// Check if two polygons intersect
  static bool doPolygonsIntersect(
    List<LatLng> polygon1,
    List<LatLng> polygon2,
  ) {
    // Check if any point of polygon2 is inside polygon1
    for (final point in polygon2) {
      if (isPointInPolygon(point, polygon1)) {
        return true;
      }
    }

    // Check if any point of polygon1 is inside polygon2
    for (final point in polygon1) {
      if (isPointInPolygon(point, polygon2)) {
        return true;
      }
    }

    // Check for edge intersections
    return _doPolygonEdgesIntersect(polygon1, polygon2);
  }

  /// Check if edges of two polygons intersect
  static bool _doPolygonEdgesIntersect(
    List<LatLng> polygon1,
    List<LatLng> polygon2,
  ) {
    for (int i = 0; i < polygon1.length; i++) {
      final p1 = polygon1[i];
      final p2 = polygon1[(i + 1) % polygon1.length];

      for (int j = 0; j < polygon2.length; j++) {
        final q1 = polygon2[j];
        final q2 = polygon2[(j + 1) % polygon2.length];

        if (_lineSegmentsIntersect(p1, p2, q1, q2)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Check if two line segments intersect
  static bool _lineSegmentsIntersect(
    LatLng p1,
    LatLng p2,
    LatLng q1,
    LatLng q2,
  ) {
    final orientation1 = _orientation(p1, p2, q1);
    final orientation2 = _orientation(p1, p2, q2);
    final orientation3 = _orientation(q1, q2, p1);
    final orientation4 = _orientation(q1, q2, p2);

    // General case
    if (orientation1 != orientation2 && orientation3 != orientation4) {
      return true;
    }

    // Special cases for collinear points
    if (orientation1 == 0 && _onSegment(p1, q1, p2)) return true;
    if (orientation2 == 0 && _onSegment(p1, q2, p2)) return true;
    if (orientation3 == 0 && _onSegment(q1, p1, q2)) return true;
    if (orientation4 == 0 && _onSegment(q1, p2, q2)) return true;

    return false;
  }

  /// Find orientation of ordered triplet (p, q, r)
  /// Returns 0 -> colinear, 1 -> clockwise, 2 -> counterclockwise
  static int _orientation(LatLng p, LatLng q, LatLng r) {
    final val =
        (q.latitude - p.latitude) * (r.longitude - q.longitude) -
        (q.longitude - p.longitude) * (r.latitude - q.latitude);

    if (val == 0) return 0; // colinear
    return (val > 0) ? 1 : 2; // clockwise or counterclockwise
  }

  /// Check if point q lies on line segment pr
  static bool _onSegment(LatLng p, LatLng q, LatLng r) {
    return q.longitude <= math.max(p.longitude, r.longitude) &&
        q.longitude >= math.min(p.longitude, r.longitude) &&
        q.latitude <= math.max(p.latitude, r.latitude) &&
        q.latitude >= math.min(p.latitude, r.latitude);
  }

  /// Calculate coverage percentage of polygon2 relative to polygon1
  /// Returns value between 0.0 and 1.0
  static double calculateCoveragePercentage(
    List<LatLng> statePolygon,
    List<LatLng> chartPolygon,
  ) {
    if (!doPolygonsIntersect(statePolygon, chartPolygon)) {
      return 0.0;
    }

    // Simplified coverage calculation using bounding box overlap
    // For production, this could use proper polygon intersection area calculation
    final stateBounds = getPolygonBounds(statePolygon);
    final chartBounds = getPolygonBounds(chartPolygon);

    final intersection = _getBoundsIntersection(stateBounds, chartBounds);
    if (intersection == null) return 0.0;

    final intersectionArea = _getBoundsArea(intersection);
    final chartArea = _getBoundsArea(chartBounds);

    if (chartArea == 0.0) return 0.0;

    return intersectionArea / chartArea;
  }

  /// Get intersection of two bounding boxes
  static GeographicBounds? _getBoundsIntersection(
    GeographicBounds bounds1,
    GeographicBounds bounds2,
  ) {
    final north = math.min(bounds1.north, bounds2.north);
    final south = math.max(bounds1.south, bounds2.south);
    final east = math.min(bounds1.east, bounds2.east);
    final west = math.max(bounds1.west, bounds2.west);

    if (north <= south || east <= west) {
      return null; // No intersection
    }

    return GeographicBounds(north: north, south: south, east: east, west: west);
  }

  /// Calculate area of bounding box in square degrees
  static double _getBoundsArea(GeographicBounds bounds) {
    return (bounds.north - bounds.south) * (bounds.east - bounds.west);
  }

  /// Convert GeographicBounds to polygon (rectangle)
  static List<LatLng> boundsToPolygon(GeographicBounds bounds) {
    return [
      LatLng(bounds.north, bounds.west), // NW
      LatLng(bounds.north, bounds.east), // NE
      LatLng(bounds.south, bounds.east), // SE
      LatLng(bounds.south, bounds.west), // SW
    ];
  }

  /// Get bounding box of a polygon
  static GeographicBounds getPolygonBounds(List<LatLng> polygon) {
    if (polygon.isEmpty) {
      throw ArgumentError('Polygon cannot be empty');
    }

    double north = polygon[0].latitude;
    double south = polygon[0].latitude;
    double east = polygon[0].longitude;
    double west = polygon[0].longitude;

    for (final point in polygon) {
      north = math.max(north, point.latitude);
      south = math.min(south, point.latitude);
      east = math.max(east, point.longitude);
      west = math.min(west, point.longitude);
    }

    return GeographicBounds(north: north, south: south, east: east, west: west);
  }
}
