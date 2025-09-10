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
      MaritimeFeatureType.buoy => true, // Always visible for Elliott Bay testing
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
       
  /// Constructor with explicit position calculation
  const DepthContour.withPosition({
    required super.id,
    required super.position,
    required super.coordinates,
    required this.depth,
    super.attributes,
  }) : super(
         type: MaritimeFeatureType.depthContour,
       );

  @override
  bool isVisibleAtScale(ChartScale scale) {
    // Show different depth contours based on scale
    final depthInt = depth.round();
    
    // For Elliott Bay testing, make depth contours more visible
    return switch (scale) {
      ChartScale.overview => depthInt % 50 == 0, // 50m intervals
      ChartScale.general => depthInt % 20 == 0, // 20m intervals
      ChartScale.coastal => depthInt % 10 == 0, // 10m intervals  
      ChartScale.approach => depthInt % 5 == 0, // 5m intervals
      ChartScale.harbour => true, // All contours visible
      ChartScale.berthing => true, // All contours visible
    };
  }

  @override
  int get renderPriority => 5;
}

/// Chart tile/cell management for optimal rendering
class ChartTile {
  final String id;
  final LatLngBounds bounds;
  final int zoomLevel;
  final List<MaritimeFeature> features;
  final ChartScale scale;
  final DateTime lastUpdated;

  const ChartTile({
    required this.id,
    required this.bounds,
    required this.zoomLevel,
    required this.features,
    required this.scale,
    required this.lastUpdated,
  });

  /// Check if tile should be rendered at given zoom level
  bool shouldRenderAtZoom(double zoom) {
    return (zoom >= zoomLevel - 1) && (zoom <= zoomLevel + 2);
  }

  /// Get visible features at current scale
  List<MaritimeFeature> getVisibleFeatures() {
    return features.where((feature) => feature.isVisibleAtScale(scale)).toList();
  }

  /// Get feature count by type
  Map<MaritimeFeatureType, int> getFeatureCountsByType() {
    final counts = <MaritimeFeatureType, int>{};
    for (final feature in features) {
      counts[feature.type] = (counts[feature.type] ?? 0) + 1;
    }
    return counts;
  }
}

/// Chart cell management for S-57 ENC data
class ChartCell {
  final String cellName;
  final LatLngBounds bounds;
  final int edition;
  final int updateNumber;
  final String producer;
  final DateTime issueDate;
  final ChartScale nativeScale;
  final List<ChartTile> tiles;

  const ChartCell({
    required this.cellName,
    required this.bounds,
    required this.edition,
    required this.updateNumber,
    required this.producer,
    required this.issueDate,
    required this.nativeScale,
    required this.tiles,
  });

  /// Create tiles for this cell based on feature density
  static List<ChartTile> createTilesForCell({
    required String cellName,
    required LatLngBounds bounds,
    required List<MaritimeFeature> features,
    required ChartScale scale,
    int maxFeaturesPerTile = 1000,
  }) {
    final tiles = <ChartTile>[];
    
    // Simple quadtree-style subdivision if too many features
    if (features.length <= maxFeaturesPerTile) {
      tiles.add(ChartTile(
        id: '${cellName}_0',
        bounds: bounds,
        zoomLevel: _scaleToZoomLevel(scale),
        features: features,
        scale: scale,
        lastUpdated: DateTime.now(),
      ));
    } else {
      // Subdivide into quadrants
      final centerLat = (bounds.north + bounds.south) / 2;
      final centerLon = (bounds.east + bounds.west) / 2;
      
      final quadrants = [
        LatLngBounds(
          north: bounds.north,
          south: centerLat,
          east: centerLon,
          west: bounds.west,
        ), // NW
        LatLngBounds(
          north: bounds.north,
          south: centerLat,
          east: bounds.east,
          west: centerLon,
        ), // NE
        LatLngBounds(
          north: centerLat,
          south: bounds.south,
          east: centerLon,
          west: bounds.west,
        ), // SW
        LatLngBounds(
          north: centerLat,
          south: bounds.south,
          east: bounds.east,
          west: centerLon,
        ), // SE
      ];
      
      for (int i = 0; i < quadrants.length; i++) {
        final quadrantFeatures = features
            .where((f) => quadrants[i].contains(f.position))
            .toList();
            
        if (quadrantFeatures.isNotEmpty) {
          tiles.add(ChartTile(
            id: '${cellName}_$i',
            bounds: quadrants[i],
            zoomLevel: _scaleToZoomLevel(scale),
            features: quadrantFeatures,
            scale: scale,
            lastUpdated: DateTime.now(),
          ));
        }
      }
    }
    
    return tiles;
  }

  /// Get tiles visible in viewport bounds
  List<ChartTile> getTilesInBounds(LatLngBounds viewportBounds) {
    return tiles
        .where((tile) => _boundsIntersect(tile.bounds, viewportBounds))
        .toList();
  }

  /// Check if cell data is current (no updates needed)
  bool get isCurrent => DateTime.now().difference(issueDate).inDays < 30;

  static int _scaleToZoomLevel(ChartScale scale) {
    return switch (scale) {
      ChartScale.overview => 8,
      ChartScale.general => 10,
      ChartScale.coastal => 12,
      ChartScale.approach => 14,
      ChartScale.harbour => 16,
      ChartScale.berthing => 18,
    };
  }

  static bool _boundsIntersect(LatLngBounds a, LatLngBounds b) {
    return a.west <= b.east &&
        a.east >= b.west &&
        a.south <= b.north &&
        a.north >= b.south;
  }
}

/// Chart metadata management
class ChartMetadata {
  final String id;
  final String title;
  final String producer;
  final DateTime issueDate;
  final int edition;
  final int updateNumber;
  final LatLngBounds bounds;
  final ChartScale nativeScale;
  final Map<String, dynamic> attributes;

  const ChartMetadata({
    required this.id,
    required this.title,
    required this.producer,
    required this.issueDate,
    required this.edition,
    required this.updateNumber,
    required this.bounds,
    required this.nativeScale,
    this.attributes = const {},
  });

  /// Create from S-57 chart metadata
  factory ChartMetadata.fromS57({
    required String cellName,
    required String datasetTitle,
    required String producer,
    required DateTime issueDate,
    required int edition,
    required int updateNumber,
    required double north,
    required double south,
    required double east,
    required double west,
    required int compilationScale,
    Map<String, dynamic> additionalAttributes = const {},
  }) {
    return ChartMetadata(
      id: cellName,
      title: datasetTitle,
      producer: producer,
      issueDate: issueDate,
      edition: edition,
      updateNumber: updateNumber,
      bounds: LatLngBounds(
        north: north,
        south: south,
        east: east,
        west: west,
      ),
      nativeScale: _determineScaleFromCompilation(compilationScale),
      attributes: additionalAttributes,
    );
  }

  /// Determine appropriate chart scale from compilation scale
  static ChartScale _determineScaleFromCompilation(int compilationScale) {
    if (compilationScale >= 1000000) return ChartScale.overview;
    if (compilationScale >= 500000) return ChartScale.general;
    if (compilationScale >= 100000) return ChartScale.coastal;
    if (compilationScale >= 50000) return ChartScale.approach;
    if (compilationScale >= 25000) return ChartScale.harbour;
    return ChartScale.berthing;
  }

  /// Check if bounds overlap with another chart
  bool overlaps(ChartMetadata other) {
    return ChartCell._boundsIntersect(bounds, other.bounds);
  }

  /// Calculate coverage percentage of given bounds
  double calculateCoverage(LatLngBounds queryBounds) {
    if (!ChartCell._boundsIntersect(bounds, queryBounds)) return 0.0;

    final intersectNorth = [bounds.north, queryBounds.north].reduce((a, b) => a < b ? a : b);
    final intersectSouth = [bounds.south, queryBounds.south].reduce((a, b) => a > b ? a : b);
    final intersectEast = [bounds.east, queryBounds.east].reduce((a, b) => a < b ? a : b);
    final intersectWest = [bounds.west, queryBounds.west].reduce((a, b) => a > b ? a : b);

    final intersectArea = (intersectNorth - intersectSouth) * (intersectEast - intersectWest);
    final queryArea = (queryBounds.north - queryBounds.south) * (queryBounds.east - queryBounds.west);

    return (intersectArea / queryArea).clamp(0.0, 1.0);
  }
}
