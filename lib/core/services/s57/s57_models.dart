/// S-57 data models for Electronic Navigational Chart (ENC) parsing
/// Based on IHO S-57 Edition 3.1 specification

/// S-57 feature types for marine navigation
enum S57FeatureType {
  // Navigation aids
  beacon,
  buoy,
  lighthouse,
  daymark,
  
  // Bathymetry
  depthContour,
  depthArea,
  
  // Coastline features
  shoreline,
  landArea,
  
  // Obstructions
  obstruction,
  wreck,
  
  // Unknown/other
  unknown,
}

/// S-57 geometry types
enum S57GeometryType {
  point,
  line,
  area,
}

/// S-57 Feature Record
class S57Feature {
  final int recordId;
  final S57FeatureType featureType;
  final S57GeometryType geometryType;
  final Map<String, dynamic> attributes;
  final List<S57Coordinate> coordinates;
  final String? label;

  const S57Feature({
    required this.recordId,
    required this.featureType,
    required this.geometryType,
    required this.attributes,
    required this.coordinates,
    this.label,
  });

  /// Convert to the format expected by chart rendering
  Map<String, dynamic> toChartFeature() {
    return {
      'id': recordId,
      'type': _featureTypeToString(featureType),
      'geometry_type': _geometryTypeToString(geometryType),
      'coordinates': coordinates.map((c) => {'lat': c.latitude, 'lon': c.longitude}).toList(),
      'attributes': attributes,
      'label': label,
    };
  }

  String _featureTypeToString(S57FeatureType type) {
    return switch (type) {
      S57FeatureType.beacon => 'beacon',
      S57FeatureType.buoy => 'buoy',
      S57FeatureType.lighthouse => 'lighthouse',
      S57FeatureType.daymark => 'daymark',
      S57FeatureType.depthContour => 'depth_contour',
      S57FeatureType.depthArea => 'depth_area',
      S57FeatureType.shoreline => 'shoreline',
      S57FeatureType.landArea => 'land_area',
      S57FeatureType.obstruction => 'obstruction',
      S57FeatureType.wreck => 'wreck',
      S57FeatureType.unknown => 'unknown',
    };
  }

  String _geometryTypeToString(S57GeometryType type) {
    return switch (type) {
      S57GeometryType.point => 'point',
      S57GeometryType.line => 'line',
      S57GeometryType.area => 'area',
    };
  }
}

/// S-57 coordinate with latitude/longitude
class S57Coordinate {
  final double latitude;
  final double longitude;

  const S57Coordinate({
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => 'S57Coordinate(lat: $latitude, lon: $longitude)';
}

/// S-57 Geographic bounds
class S57Bounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const S57Bounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  /// Check if bounds are valid marine navigation coordinates
  bool get isValid {
    return north >= -90 && north <= 90 &&
           south >= -90 && south <= 90 &&
           east >= -180 && east <= 180 &&
           west >= -180 && west <= 180 &&
           north > south && east > west;
  }

  Map<String, double> toMap() {
    return {
      'north': north,
      'south': south,
      'east': east,
      'west': west,
    };
  }
}

/// S-57 Chart metadata from DDR and feature records
class S57ChartMetadata {
  final String producer;
  final String version;
  final DateTime? creationDate;
  final DateTime? updateDate;
  final String? title;
  final int? scale;
  final S57Bounds? bounds;

  const S57ChartMetadata({
    required this.producer,
    required this.version,
    this.creationDate,
    this.updateDate,
    this.title,
    this.scale,
    this.bounds,
  });

  Map<String, dynamic> toMap() {
    return {
      'producer': producer,
      'version': version,
      'creation_date': creationDate?.toIso8601String(),
      'update_date': updateDate?.toIso8601String(),
      'title': title,
      'scale': scale,
      'bounds': bounds?.toMap(),
    };
  }
}

/// S-57 parsed chart data with spatial indexing
class S57ParsedData {
  final S57ChartMetadata metadata;
  final List<S57Feature> features;
  final S57Bounds bounds;
  final S57SpatialIndex spatialIndex;

  const S57ParsedData({
    required this.metadata,
    required this.features,
    required this.bounds,
    required this.spatialIndex,
  });

  /// Convert to the format expected by ChartService
  Map<String, dynamic> toChartServiceFormat() {
    return {
      'metadata': metadata.toMap(),
      'features': features.map((f) => f.toChartFeature()).toList(),
      'bounds': bounds.toMap(),
      'spatial_index': {
        'feature_count': spatialIndex.featureCount,
        'feature_types': spatialIndex.presentFeatureTypes.map((t) => t.toString()).toList(),
      },
    };
  }

  /// Query features near a point using spatial index
  List<S57Feature> queryFeaturesNear(double lat, double lon, {double radiusDegrees = 0.01}) {
    return spatialIndex.queryPoint(lat, lon, radiusDegrees: radiusDegrees);
  }

  /// Query features within bounds using spatial index
  List<S57Feature> queryFeaturesInBounds(S57Bounds queryBounds) {
    return spatialIndex.queryBounds(queryBounds);
  }

  /// Query navigation aids using spatial index
  List<S57Feature> queryNavigationAids() {
    return spatialIndex.queryNavigationAids();
  }

  /// Query depth features using spatial index
  List<S57Feature> queryDepthFeatures() {
    return spatialIndex.queryDepthFeatures();
  }
}