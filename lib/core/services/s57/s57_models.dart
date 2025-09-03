/// S-57 data models for Electronic Navigational Chart (ENC) parsing
/// Based on IHO S-57 Edition 3.1 specification

import 's57_spatial_index.dart';

/// S-57 feature types for marine navigation
/// Based on IHO S-57 Object Catalogue Edition 3.1
enum S57FeatureType {
  // Navigation aids (official S-57 codes)
  beacon(57, 'BCNCAR'), // Cardinal beacon
  buoyLateral(58, 'BOYLAT'), // Lateral buoy
  buoyCardinal(59, 'BOYCAR'), // Cardinal buoy 
  buoyIsolatedDanger(60, 'BOYINB'), // Isolated danger buoy
  buoySpecialPurpose(61, 'BOYSAW'), // Special purpose buoy
  lighthouse(75, 'LIGHTS'), // Light
  daymark(85, 'DAYMAR'), // Daymark
  
  // Bathymetry (official S-57 codes)
  depthArea(120, 'DEPARE'), // Depth area
  depthContour(121, 'DEPCNT'), // Depth contour
  sounding(127, 'SOUNDG'), // Sounding
  
  // Coastline features (official S-57 codes)
  coastline(30, 'COALNE'), // Coastline
  landArea(71, 'LNDARE'), // Land area
  
  // Obstructions (official S-57 codes)
  obstruction(104, 'OBSTRN'), // Obstruction
  wreck(159, 'WRECKS'), // Wreck
  underwater(158, 'UWTROC'), // Underwater/awash rock
  
  // Unknown/other
  unknown(0, 'UNKNOW'),
  ;
  
  const S57FeatureType(this.code, this.acronym);
  
  /// Official S-57 object class code
  final int code;
  
  /// S-57 object class acronym
  final String acronym;
  
  /// Create from S-57 object class code
  static S57FeatureType fromCode(int code) {
    for (final type in S57FeatureType.values) {
      if (type.code == code) return type;
    }
    return S57FeatureType.unknown;
  }
  
  /// Create from S-57 acronym
  static S57FeatureType fromAcronym(String acronym) {
    for (final type in S57FeatureType.values) {
      if (type.acronym == acronym) return type;
    }
    return S57FeatureType.unknown;
  }
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
      S57FeatureType.buoyLateral => 'buoy_lateral',
      S57FeatureType.buoyCardinal => 'buoy_cardinal',
      S57FeatureType.buoyIsolatedDanger => 'buoy_isolated_danger',
      S57FeatureType.buoySpecialPurpose => 'buoy_special_purpose',
      S57FeatureType.lighthouse => 'lighthouse',
      S57FeatureType.daymark => 'daymark',
      S57FeatureType.depthArea => 'depth_area',
      S57FeatureType.depthContour => 'depth_contour',
      S57FeatureType.sounding => 'sounding',
      S57FeatureType.coastline => 'coastline',
      S57FeatureType.landArea => 'land_area',
      S57FeatureType.obstruction => 'obstruction',
      S57FeatureType.wreck => 'wreck',
      S57FeatureType.underwater => 'underwater_rock',
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