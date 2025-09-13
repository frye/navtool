/// Coordinate transformation utilities for marine chart rendering
library;

import 'dart:math' as math;
import 'dart:ui';
import '../models/chart_models.dart';

/// Handles coordinate transformations between geographic and screen coordinates
class CoordinateTransform {
  final double _zoom;
  final LatLng _center;
  final Size _screenSize;
  final double _pixelsPerDegree;
  double _rotation = 0.0;
  double _magneticDeclination = 0.0;
  String _projectionType = 'mercator';

  CoordinateTransform({
    required double zoom,
    required LatLng center,
    required Size screenSize,
  }) : _zoom = zoom,
       _center = center,
       _screenSize = screenSize,
       _pixelsPerDegree = _calculatePixelsPerDegree(zoom, center.latitude);

  /// Calculate pixels per degree at given zoom and latitude
  static double _calculatePixelsPerDegree(double zoom, double latitude) {
    // Base pixels per degree at equator for zoom level 0
    const double basePixelsPerDegree = 256.0 / 360.0;

    // Adjust for latitude (Mercator projection)
    final double latitudeAdjustment =
        1.0 / math.cos(latitude * math.pi / 180.0);

    // Scale by zoom level (each zoom level doubles the scale)
    final double zoomScale = math.pow(2, zoom).toDouble();

    return basePixelsPerDegree * zoomScale * latitudeAdjustment;
  }

  /// Convert geographic coordinates to screen coordinates
  Offset latLngToScreen(LatLng latLng) {
    final double deltaLng = latLng.longitude - _center.longitude;
    final double deltaLat = latLng.latitude - _center.latitude;

    final double x = _screenSize.width / 2 + (deltaLng * _pixelsPerDegree);
    final double y = _screenSize.height / 2 - (deltaLat * _pixelsPerDegree);

    return Offset(x, y);
  }

  /// Convert screen coordinates to geographic coordinates
  LatLng screenToLatLng(Offset screen) {
    final double deltaX = screen.dx - _screenSize.width / 2;
    final double deltaY = screen.dy - _screenSize.height / 2;

    final double lng = _center.longitude + (deltaX / _pixelsPerDegree);
    final double lat = _center.latitude - (deltaY / _pixelsPerDegree);

    return LatLng(lat, lng);
  }

  /// Get the visible bounds of the current view
  LatLngBounds get visibleBounds {
    final LatLng topLeft = screenToLatLng(const Offset(0, 0));
    final LatLng bottomRight = screenToLatLng(
      Offset(_screenSize.width, _screenSize.height),
    );

    return LatLngBounds(
      north: topLeft.latitude,
      south: bottomRight.latitude,
      east: bottomRight.longitude,
      west: topLeft.longitude,
    );
  }

  /// Calculate the distance in meters between two geographic coordinates
  static double distanceInMeters(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final double lat1Rad = point1.latitude * math.pi / 180;
    final double lat2Rad = point2.latitude * math.pi / 180;
    final double deltaLatRad =
        (point2.latitude - point1.latitude) * math.pi / 180;
    final double deltaLngRad =
        (point2.longitude - point1.longitude) * math.pi / 180;

    final double a =
        math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLngRad / 2) *
            math.sin(deltaLngRad / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Calculate bearing from point1 to point2 in degrees
  static double bearing(LatLng point1, LatLng point2) {
    final double lat1Rad = point1.latitude * math.pi / 180;
    final double lat2Rad = point2.latitude * math.pi / 180;
    final double deltaLngRad =
        (point2.longitude - point1.longitude) * math.pi / 180;

    final double y = math.sin(deltaLngRad) * math.cos(lat2Rad);
    final double x =
        math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLngRad);

    final double bearingRad = math.atan2(y, x);
    final double bearingDeg = (bearingRad * 180 / math.pi + 360) % 360;

    return bearingDeg;
  }

  /// Convert meters to pixels at the current location and zoom level
  double metersToPixels(double meters) {
    // Use the current center latitude for the calculation
    const double earthCircumference = 2 * math.pi * 6378137; // WGS84 Earth radius
    final double metersPerDegree = earthCircumference / 360.0 * math.cos(_center.latitude * math.pi / 180);
    final double degreesPerMeter = 1.0 / metersPerDegree;
    return meters * degreesPerMeter * _pixelsPerDegree;
  }

  /// Get the scale factor for the current zoom level
  double get scaleFactor => math.pow(2, _zoom).toDouble();

  /// Get the current chart scale based on zoom level
  ChartScale get chartScale => ChartScale.fromZoom(_zoom);

  /// Get the appropriate line width for features at current scale
  double getLineWidthForScale(double baseWidth) {
    final double scale = scaleFactor;
    return math.max(1.0, baseWidth * scale / 1000);
  }

  /// Get the appropriate symbol size for features at current scale
  double getSymbolSizeForScale(double baseSize) {
    final double scale = scaleFactor;
    return math.max(8.0, baseSize * scale / 1000);
  }

  /// Check if a feature is visible in the current viewport
  bool isFeatureVisible(MaritimeFeature feature) {
    final bounds = visibleBounds;

    if (feature is PointFeature) {
      return bounds.contains(feature.position);
    } else if (feature is LineFeature) {
      // Check if any point of the line is visible
      return feature.coordinates.any((coord) => bounds.contains(coord));
    } else if (feature is AreaFeature) {
      // Check if any point of the area is visible
      return feature.coordinates
          .expand((ring) => ring)
          .any((coord) => bounds.contains(coord));
    }

    return bounds.contains(feature.position);
  }

  /// Create a new transform with updated parameters
  CoordinateTransform copyWith({
    double? zoom,
    LatLng? center,
    Size? screenSize,
  }) {
    return CoordinateTransform(
      zoom: zoom ?? _zoom,
      center: center ?? _center,
      screenSize: screenSize ?? _screenSize,
    );
  }

  /// Getters for current values
  double get zoom => _zoom;
  LatLng get center => _center;
  Size get screenSize => _screenSize;
  double get pixelsPerDegree => _pixelsPerDegree;

  // ===== Enhanced Properties and Methods =====

  /// Get the current rotation angle in degrees
  double get rotation => _rotation;

  /// Set chart rotation
  void setRotation(double degrees) {
    _rotation = degrees % 360.0;
  }

  /// Set magnetic declination for compass correction
  void setMagneticDeclination(double declination) {
    _magneticDeclination = declination;
  }

  /// Convert bearing from magnetic to true
  double magneticToTrue(double magneticBearing) {
    return (magneticBearing + _magneticDeclination) % 360.0;
  }

  /// Convert bearing from true to magnetic
  double trueToMagnetic(double trueBearing) {
    return (trueBearing - _magneticDeclination + 360.0) % 360.0;
  }

  /// Transform coordinates with rotation
  Offset transformWithRotation(Offset point) {
    if (_rotation == 0.0) return point;

    final radians = _rotation * (math.pi / 180.0);
    final cos = math.cos(radians);
    final sin = math.sin(radians);

    final centerX = _screenSize.width / 2;
    final centerY = _screenSize.height / 2;

    // Translate to origin
    final translatedX = point.dx - centerX;
    final translatedY = point.dy - centerY;

    // Apply rotation
    final rotatedX = translatedX * cos - translatedY * sin;
    final rotatedY = translatedX * sin + translatedY * cos;

    // Translate back
    return Offset(rotatedX + centerX, rotatedY + centerY);
  }

  /// High precision coordinate transformation
  Offset latLngToScreenPrecise(LatLng latLng) {
    // Use more precise spherical mercator projection
    const earthRadius = 6378137.0; // WGS84 Earth radius in meters

    final lat = latLng.latitude * (math.pi / 180.0);
    final lng = latLng.longitude * (math.pi / 180.0);

    final x = earthRadius * lng;
    final y = earthRadius * math.log(math.tan(math.pi / 4 + lat / 2));

    // Convert to screen coordinates
    final centerLat = _center.latitude * (math.pi / 180.0);
    final centerLng = _center.longitude * (math.pi / 180.0);

    final centerX = earthRadius * centerLng;
    final centerY =
        earthRadius * math.log(math.tan(math.pi / 4 + centerLat / 2));

    final screenX = _screenSize.width / 2 + (x - centerX) * _zoom / 1000;
    final screenY = _screenSize.height / 2 - (y - centerY) * _zoom / 1000;

    final point = Offset(screenX, screenY);
    return transformWithRotation(point);
  }

  /// Bulk coordinate transformation for performance
  List<Offset> bulkLatLngToScreen(List<LatLng> coordinates) {
    return coordinates.map((coord) => latLngToScreenPrecise(coord)).toList();
  }

  /// Get projection type
  String getProjectionType() {
    return _projectionType;
  }

  /// Set projection type
  void setProjectionType(String type) {
    _projectionType = type;
  }

  /// Convert to nautical miles
  double degreesToNauticalMiles(double degrees) {
    return degrees * 60.0; // 1 degree = 60 nautical miles
  }

  /// Convert from nautical miles
  double nauticalMilesToDegrees(double nauticalMiles) {
    return nauticalMiles / 60.0;
  }

  /// Calculate great circle distance
  double calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 3440.065; // Earth radius in nautical miles

    final lat1 = point1.latitude * (math.pi / 180.0);
    final lat2 = point2.latitude * (math.pi / 180.0);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180.0);
    final deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180.0);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Calculate bearing between two points
  double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180.0);
    final lat2 = to.latitude * (math.pi / 180.0);
    final deltaLng = (to.longitude - from.longitude) * (math.pi / 180.0);

    final y = math.sin(deltaLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);

    final bearing = math.atan2(y, x) * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  /// Calculate rhumb line distance
  double calculateRhumbDistance(LatLng point1, LatLng point2) {
    final lat1 = point1.latitude * (math.pi / 180.0);
    final lat2 = point2.latitude * (math.pi / 180.0);
    final deltaLat = lat2 - lat1;
    var deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180.0);

    final deltaPhi = math.log(
      math.tan(lat2 / 2 + math.pi / 4) / math.tan(lat1 / 2 + math.pi / 4),
    );
    final q = deltaLat != 0 ? deltaLat / deltaPhi : math.cos(lat1);

    if (deltaLng.abs() > math.pi) {
      final sign = deltaLng > 0 ? -1 : 1;
      deltaLng = sign * (2 * math.pi - deltaLng.abs());
    }

    final distance = math.sqrt(
      deltaLat * deltaLat + q * q * deltaLng * deltaLng,
    );
    return distance * 180.0 / math.pi * 60.0; // Convert to nautical miles
  }

  /// Calculate rhumb line bearing
  double calculateRhumbBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180.0);
    final lat2 = to.latitude * (math.pi / 180.0);
    var deltaLng = (to.longitude - from.longitude) * (math.pi / 180.0);

    final deltaPhi = math.log(
      math.tan(lat2 / 2 + math.pi / 4) / math.tan(lat1 / 2 + math.pi / 4),
    );

    if (deltaLng.abs() > math.pi) {
      final sign = deltaLng > 0 ? -1 : 1;
      deltaLng = sign * (2 * math.pi - deltaLng.abs());
    }

    final bearing = math.atan2(deltaLng, deltaPhi) * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  /// Check if point is within screen bounds
  bool isPointInBounds(LatLng point) {
    final screenPoint = latLngToScreen(point);
    return screenPoint.dx >= 0 &&
        screenPoint.dx <= _screenSize.width &&
        screenPoint.dy >= 0 &&
        screenPoint.dy <= _screenSize.height;
  }

  /// Get viewport bounds in lat/lng
  LatLngBounds getViewportBounds() {
    final topLeft = screenToLatLng(const Offset(0, 0));
    final bottomRight = screenToLatLng(
      Offset(_screenSize.width, _screenSize.height),
    );

    return LatLngBounds(
      north: topLeft.latitude,
      south: bottomRight.latitude,
      east: bottomRight.longitude,
      west: topLeft.longitude,
    );
  }
}

/// Utilities for coordinate validation and conversion
class CoordinateUtils {
  /// Validate that latitude is within valid range
  static bool isValidLatitude(double latitude) {
    return latitude >= -90.0 && latitude <= 90.0;
  }

  /// Validate that longitude is within valid range
  static bool isValidLongitude(double longitude) {
    return longitude >= -180.0 && longitude <= 180.0;
  }

  /// Normalize longitude to [-180, 180] range
  static double normalizeLongitude(double longitude) {
    while (longitude > 180.0) {
      longitude -= 360.0;
    }
    while (longitude < -180.0) {
      longitude += 360.0;
    }
    return longitude;
  }

  /// Convert degrees to radians
  static double degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  /// Convert radians to degrees
  static double radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }

  /// Format latitude for display
  static String formatLatitude(double latitude) {
    final String direction = latitude >= 0 ? 'N' : 'S';
    final double absLat = latitude.abs();
    final int degrees = absLat.floor();
    final double minutes = (absLat - degrees) * 60;
    return '${degrees.toString().padLeft(2, '0')}°${minutes.toStringAsFixed(3)}\'$direction';
  }

  /// Format longitude for display
  static String formatLongitude(double longitude) {
    final String direction = longitude >= 0 ? 'E' : 'W';
    final double absLng = longitude.abs();
    final int degrees = absLng.floor();
    final double minutes = (absLng - degrees) * 60;
    return '${degrees.toString().padLeft(3, '0')}°${minutes.toStringAsFixed(3)}\'$direction';
  }
}
