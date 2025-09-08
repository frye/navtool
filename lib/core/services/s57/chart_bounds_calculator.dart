import 'dart:math';
import '../../models/chart_models.dart';
import 's57_models.dart';

/// Advanced chart bounds and scale calculations for marine navigation
class ChartBoundsCalculator {
  /// Calculate optimal chart bounds from features with padding
  static LatLngBounds calculateOptimalBounds(
    List<MaritimeFeature> features, {
    double paddingPercent = 0.1,
  }) {
    if (features.isEmpty) {
      throw ArgumentError('Cannot calculate bounds from empty feature list');
    }

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLon = 180.0;
    double maxLon = -180.0;

    // Calculate raw bounds from all features
    for (final feature in features) {
      final pos = feature.position;
      minLat = min(minLat, pos.latitude);
      maxLat = max(maxLat, pos.latitude);
      minLon = min(minLon, pos.longitude);
      maxLon = max(maxLon, pos.longitude);

      // For line and area features, check all coordinates
      if (feature is LineFeature) {
        for (final coord in feature.coordinates) {
          minLat = min(minLat, coord.latitude);
          maxLat = max(maxLat, coord.latitude);
          minLon = min(minLon, coord.longitude);
          maxLon = max(maxLon, coord.longitude);
        }
      } else if (feature is AreaFeature) {
        for (final ring in feature.coordinates) {
          for (final coord in ring) {
            minLat = min(minLat, coord.latitude);
            maxLat = max(maxLat, coord.latitude);
            minLon = min(minLon, coord.longitude);
            maxLon = max(maxLon, coord.longitude);
          }
        }
      }
    }

    // Add padding
    final latRange = maxLat - minLat;
    final lonRange = maxLon - minLon;
    final latPadding = latRange * paddingPercent;
    final lonPadding = lonRange * paddingPercent;

    return LatLngBounds(
      north: maxLat + latPadding,
      south: minLat - latPadding,
      east: maxLon + lonPadding,
      west: minLon - lonPadding,
    );
  }

  /// Calculate bounds from S-57 features
  static S57Bounds calculateS57Bounds(List<S57Feature> features) {
    if (features.isEmpty) {
      throw ArgumentError('Cannot calculate bounds from empty feature list');
    }

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLon = 180.0;
    double maxLon = -180.0;

    for (final feature in features) {
      for (final coord in feature.coordinates) {
        minLat = min(minLat, coord.latitude);
        maxLat = max(maxLat, coord.latitude);
        minLon = min(minLon, coord.longitude);
        maxLon = max(maxLon, coord.longitude);
      }
    }

    return S57Bounds(north: maxLat, south: minLat, east: maxLon, west: minLon);
  }

  /// Calculate chart density (features per square degree)
  static double calculateFeatureDensity(
    List<MaritimeFeature> features,
    LatLngBounds bounds,
  ) {
    final area = (bounds.north - bounds.south) * (bounds.east - bounds.west);
    return area > 0 ? features.length / area : 0.0;
  }

  /// Determine optimal chart scale based on feature density and area
  static ChartScale determineOptimalScale({
    required LatLngBounds bounds,
    required List<MaritimeFeature> features,
    required double viewportSizeDegrees,
  }) {
    final area = (bounds.north - bounds.south) * (bounds.east - bounds.west);
    final density = features.length / area;
    
    // Consider viewport size for scale determination
    final avgDimension = sqrt(area);
    
    // Determine scale based on multiple factors
    if (avgDimension > 5.0 || density < 10) {
      return ChartScale.overview;
    } else if (avgDimension > 2.0 || density < 50) {
      return ChartScale.general;
    } else if (avgDimension > 0.5 || density < 200) {
      return ChartScale.coastal;
    } else if (avgDimension > 0.1 || density < 500) {
      return ChartScale.approach;
    } else if (avgDimension > 0.05 || density < 1000) {
      return ChartScale.harbour;
    } else {
      return ChartScale.berthing;
    }
  }

  /// Calculate intersection bounds between two chart bounds
  static LatLngBounds? calculateIntersection(
    LatLngBounds bounds1,
    LatLngBounds bounds2,
  ) {
    final west = max(bounds1.west, bounds2.west);
    final east = min(bounds1.east, bounds2.east);
    final south = max(bounds1.south, bounds2.south);
    final north = min(bounds1.north, bounds2.north);

    if (west >= east || south >= north) {
      return null; // No intersection
    }

    return LatLngBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  /// Calculate union bounds of multiple chart bounds
  static LatLngBounds calculateUnion(List<LatLngBounds> boundsList) {
    if (boundsList.isEmpty) {
      throw ArgumentError('Cannot calculate union of empty bounds list');
    }

    double minLat = boundsList.first.south;
    double maxLat = boundsList.first.north;
    double minLon = boundsList.first.west;
    double maxLon = boundsList.first.east;

    for (final bounds in boundsList.skip(1)) {
      minLat = min(minLat, bounds.south);
      maxLat = max(maxLat, bounds.north);
      minLon = min(minLon, bounds.west);
      maxLon = max(maxLon, bounds.east);
    }

    return LatLngBounds(
      north: maxLat,
      south: minLat,
      east: maxLon,
      west: minLon,
    );
  }

  /// Convert between coordinate systems (degrees to meters at given latitude)
  static double degreesToMeters(double degrees, double latitude) {
    const earthRadius = 6378137.0; // Earth radius in meters
    final latRadians = latitude * pi / 180;
    return degrees * pi / 180 * earthRadius * cos(latRadians);
  }

  /// Convert meters to degrees at given latitude
  static double metersToDegrees(double meters, double latitude) {
    const earthRadius = 6378137.0; // Earth radius in meters
    final latRadians = latitude * pi / 180;
    return meters / (pi / 180 * earthRadius * cos(latRadians));
  }

  /// Calculate distance between two points using Haversine formula
  static double calculateDistance(LatLng point1, LatLng point2) {
    const R = 6371000; // Earth's radius in meters
    final lat1Rad = point1.latitude * pi / 180;
    final lat2Rad = point2.latitude * pi / 180;
    final deltaLatRad = (point2.latitude - point1.latitude) * pi / 180;
    final deltaLonRad = (point2.longitude - point1.longitude) * pi / 180;

    final a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLonRad / 2) * sin(deltaLonRad / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  /// Calculate bearing between two points
  static double calculateBearing(LatLng from, LatLng to) {
    final lat1Rad = from.latitude * pi / 180;
    final lat2Rad = to.latitude * pi / 180;
    final deltaLonRad = (to.longitude - from.longitude) * pi / 180;

    final y = sin(deltaLonRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(deltaLonRad);

    final bearingRad = atan2(y, x);
    return (bearingRad * 180 / pi + 360) % 360; // Bearing in degrees
  }
}

/// Scale calculation utilities for marine charts
class ScaleCalculator {
  /// Calculate scale ratio from chart bounds and display size
  static double calculateScaleRatio({
    required LatLngBounds chartBounds,
    required double displayWidthPixels,
    required double displayHeightPixels,
    double dpi = 96.0,
  }) {
    // Calculate chart dimensions in degrees
    final chartWidthDegrees = chartBounds.east - chartBounds.west;
    final chartHeightDegrees = chartBounds.north - chartBounds.south;

    // Calculate display dimensions in meters (approximate)
    final centerLat = (chartBounds.north + chartBounds.south) / 2;
    final chartWidthMeters = ChartBoundsCalculator.degreesToMeters(
      chartWidthDegrees,
      centerLat,
    );
    final chartHeightMeters = ChartBoundsCalculator.degreesToMeters(
      chartHeightDegrees,
      centerLat,
    );

    // Calculate display dimensions in meters
    final displayWidthMeters = displayWidthPixels / dpi * 0.0254; // pixels to meters
    final displayHeightMeters = displayHeightPixels / dpi * 0.0254;

    // Calculate scale ratios for both dimensions
    final scaleX = chartWidthMeters / displayWidthMeters;
    final scaleY = chartHeightMeters / displayHeightMeters;

    // Return the maximum scale (most conservative)
    return max(scaleX, scaleY);
  }

  /// Convert scale ratio to natural scale notation (1:XXXX)
  static int scaleRatioToNaturalScale(double scaleRatio) {
    return scaleRatio.round();
  }

  /// Determine appropriate ChartScale enum from natural scale
  static ChartScale naturalScaleToChartScale(int naturalScale) {
    if (naturalScale >= 1000000) return ChartScale.overview;
    if (naturalScale >= 500000) return ChartScale.general;
    if (naturalScale >= 100000) return ChartScale.coastal;
    if (naturalScale >= 50000) return ChartScale.approach;
    if (naturalScale >= 25000) return ChartScale.harbour;
    return ChartScale.berthing;
  }

  /// Calculate recommended zoom level for given scale
  static double scaleToZoomLevel(ChartScale scale) {
    return switch (scale) {
      ChartScale.overview => 8.0,
      ChartScale.general => 10.0,
      ChartScale.coastal => 12.0,
      ChartScale.approach => 14.0,
      ChartScale.harbour => 16.0,
      ChartScale.berthing => 18.0,
    };
  }

  /// Calculate scale-appropriate feature visibility thresholds
  static Map<MaritimeFeatureType, double> getFeatureVisibilityThresholds(
    ChartScale scale,
  ) {
    return switch (scale) {
      ChartScale.overview => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
      },
      ChartScale.general => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.beacon: 0.8,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
        MaritimeFeatureType.anchorage: 0.7,
      },
      ChartScale.coastal => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.beacon: 1.0,
        MaritimeFeatureType.buoy: 0.8,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
        MaritimeFeatureType.anchorage: 1.0,
        MaritimeFeatureType.depthContour: 0.6,
      },
      ChartScale.approach => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.beacon: 1.0,
        MaritimeFeatureType.buoy: 1.0,
        MaritimeFeatureType.daymark: 0.8,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
        MaritimeFeatureType.anchorage: 1.0,
        MaritimeFeatureType.depthContour: 1.0,
        MaritimeFeatureType.soundings: 0.7,
      },
      ChartScale.harbour => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.beacon: 1.0,
        MaritimeFeatureType.buoy: 1.0,
        MaritimeFeatureType.daymark: 1.0,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
        MaritimeFeatureType.anchorage: 1.0,
        MaritimeFeatureType.depthContour: 1.0,
        MaritimeFeatureType.soundings: 1.0,
        MaritimeFeatureType.obstruction: 0.9,
      },
      ChartScale.berthing => {
        MaritimeFeatureType.lighthouse: 1.0,
        MaritimeFeatureType.beacon: 1.0,
        MaritimeFeatureType.buoy: 1.0,
        MaritimeFeatureType.daymark: 1.0,
        MaritimeFeatureType.landArea: 1.0,
        MaritimeFeatureType.shoreline: 1.0,
        MaritimeFeatureType.anchorage: 1.0,
        MaritimeFeatureType.depthContour: 1.0,
        MaritimeFeatureType.soundings: 1.0,
        MaritimeFeatureType.obstruction: 1.0,
        MaritimeFeatureType.cable: 1.0,
        MaritimeFeatureType.pipeline: 1.0,
      },
    };
  }
}