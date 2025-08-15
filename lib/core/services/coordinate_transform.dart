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

  CoordinateTransform({
    required double zoom,
    required LatLng center,
    required Size screenSize,
  })  : _zoom = zoom,
        _center = center,
        _screenSize = screenSize,
        _pixelsPerDegree = _calculatePixelsPerDegree(zoom, center.latitude);

  /// Calculate pixels per degree at given zoom and latitude
  static double _calculatePixelsPerDegree(double zoom, double latitude) {
    // Base pixels per degree at equator for zoom level 0
    const double basePixelsPerDegree = 256.0 / 360.0;
    
    // Adjust for latitude (Mercator projection)
    final double latitudeAdjustment = 1.0 / math.cos(latitude * math.pi / 180.0);
    
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
    final LatLng bottomRight = screenToLatLng(Offset(_screenSize.width, _screenSize.height));
    
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
    final double deltaLatRad = (point2.latitude - point1.latitude) * math.pi / 180;
    final double deltaLngRad = (point2.longitude - point1.longitude) * math.pi / 180;
    
    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Calculate bearing from point1 to point2 in degrees
  static double bearing(LatLng point1, LatLng point2) {
    final double lat1Rad = point1.latitude * math.pi / 180;
    final double lat2Rad = point2.latitude * math.pi / 180;
    final double deltaLngRad = (point2.longitude - point1.longitude) * math.pi / 180;
    
    final double y = math.sin(deltaLngRad) * math.cos(lat2Rad);
    final double x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLngRad);
    
    final double bearingRad = math.atan2(y, x);
    final double bearingDeg = (bearingRad * 180 / math.pi + 360) % 360;
    
    return bearingDeg;
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
