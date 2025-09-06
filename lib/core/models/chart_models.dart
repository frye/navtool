/// Maritime chart data models for marine navigation
library;

import 'dart:ui';

/// Represents geographical coordinates in decimal degrees
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

/// Represents a bounding box with north, south, east, west bounds
class LatLngBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const LatLngBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  /// Check if a coordinate is within these bounds
  bool contains(LatLng point) {
    return point.latitude >= south &&
        point.latitude <= north &&
        point.longitude >= west &&
        point.longitude <= east;
  }

  /// Get the center point of the bounds
  LatLng get center => LatLng((north + south) / 2, (east + west) / 2);

  @override
  String toString() => 'LatLngBounds(N:$north, S:$south, E:$east, W:$west)';
}

/// Chart scale levels for different zoom ranges
enum ChartScale {
  overview(1000000, 'Overview'),
  general(500000, 'General'),
  coastal(100000, 'Coastal'),
  approach(50000, 'Approach'),
  harbour(25000, 'Harbour'),
  berthing(10000, 'Berthing');

  const ChartScale(this.scale, this.label);
  final int scale;
  final String label;

  /// Get chart scale based on zoom level
  static ChartScale fromZoom(double zoom) {
    if (zoom <= 8) return ChartScale.overview;
    if (zoom <= 10) return ChartScale.general;
    if (zoom <= 12) return ChartScale.coastal;
    if (zoom <= 14) return ChartScale.approach;
    if (zoom <= 16) return ChartScale.harbour;
    return ChartScale.berthing;
  }
}

/// Types of maritime features that can be rendered
enum MaritimeFeatureType {
  // Depth and bathymetry
  depthContour,
  depthArea,
  soundings,

  // Navigation aids
  lighthouse,
  beacon,
  buoy,
  daymark,

  // Coastline and land
  shoreline,
  landArea,
  rocks,
  wrecks,

  // Marine areas
  anchorage,
  restrictedArea,
  trafficSeparation,

  // Hazards
  obstruction,
  cable,
  pipeline,
}

/// Base class for all maritime chart features
abstract class MaritimeFeature {
  final String id;
  final MaritimeFeatureType type;
  final LatLng position;
  final Map<String, dynamic> attributes;

  const MaritimeFeature({
    required this.id,
    required this.type,
    required this.position,
    this.attributes = const {},
  });

  /// Check if this feature should be visible at the given scale
  bool isVisibleAtScale(ChartScale scale);

  /// Get the rendering priority (higher = render on top)
  int get renderPriority;
}

/// Point feature for lighthouses, buoys, etc.
class PointFeature extends MaritimeFeature {
  final String? label;
  final double? heading;

  const PointFeature({
    required super.id,
    required super.type,
    required super.position,
    super.attributes,
    this.label,
    this.heading,
  });

  @override
  bool isVisibleAtScale(ChartScale scale) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => true, // Always visible
      MaritimeFeatureType.beacon => scale.scale <= 100000,
      MaritimeFeatureType.buoy => scale.scale <= 50000,
      MaritimeFeatureType.daymark => scale.scale <= 25000,
      _ => true,
    };
  }

  @override
  int get renderPriority => switch (type) {
    MaritimeFeatureType.lighthouse => 100,
    MaritimeFeatureType.beacon => 90,
    MaritimeFeatureType.buoy => 80,
    MaritimeFeatureType.daymark => 70,
    _ => 50,
  };
}

/// Line feature for shorelines, cables, etc.
class LineFeature extends MaritimeFeature {
  final List<LatLng> coordinates;
  final double? width;

  const LineFeature({
    required super.id,
    required super.type,
    required super.position,
    required this.coordinates,
    super.attributes,
    this.width,
  });

  @override
  bool isVisibleAtScale(ChartScale scale) {
    return switch (type) {
      MaritimeFeatureType.shoreline => true,
      MaritimeFeatureType.cable => scale.scale <= 100000,
      MaritimeFeatureType.pipeline => scale.scale <= 100000,
      _ => true,
    };
  }

  @override
  int get renderPriority => switch (type) {
    MaritimeFeatureType.shoreline => 10,
    MaritimeFeatureType.cable => 30,
    MaritimeFeatureType.pipeline => 30,
    _ => 20,
  };
}

/// Area feature for land masses, anchorages, etc.
class AreaFeature extends MaritimeFeature {
  final List<List<LatLng>> coordinates;
  final Color? fillColor;
  final Color? strokeColor;

  const AreaFeature({
    required super.id,
    required super.type,
    required super.position,
    required this.coordinates,
    super.attributes,
    this.fillColor,
    this.strokeColor,
  });

  @override
  bool isVisibleAtScale(ChartScale scale) {
    return switch (type) {
      MaritimeFeatureType.landArea => true,
      MaritimeFeatureType.anchorage => scale.scale <= 100000,
      MaritimeFeatureType.restrictedArea => scale.scale <= 100000,
      MaritimeFeatureType.trafficSeparation => scale.scale <= 500000,
      _ => true,
    };
  }

  @override
  int get renderPriority => switch (type) {
    MaritimeFeatureType.landArea => 0,
    MaritimeFeatureType.anchorage => 40,
    MaritimeFeatureType.restrictedArea => 35,
    MaritimeFeatureType.trafficSeparation => 30,
    _ => 20,
  };
}

/// Depth contour feature
class DepthContour extends LineFeature {
  final double depth;

  const DepthContour({
    required super.id,
    required super.coordinates,
    required this.depth,
    super.attributes,
  }) : super(
         type: MaritimeFeatureType.depthContour,
         position: const LatLng(0, 0), // Will be calculated from coordinates
       );

  @override
  bool isVisibleAtScale(ChartScale scale) {
    // Show different depth contours based on scale
    final depthInt = depth.round();
    return switch (scale) {
      ChartScale.overview => depthInt % 100 == 0, // 100m intervals
      ChartScale.general => depthInt % 50 == 0, // 50m intervals
      ChartScale.coastal => depthInt % 20 == 0, // 20m intervals
      ChartScale.approach => depthInt % 10 == 0, // 10m intervals
      ChartScale.harbour => depthInt % 5 == 0, // 5m intervals
      ChartScale.berthing => true, // All contours visible
    };
  }

  @override
  int get renderPriority => 5;
}
