/// Geographic coordinate representing a point on Earth.
class GeoPoint {
  final double longitude;
  final double latitude;

  const GeoPoint(this.longitude, this.latitude);

  factory GeoPoint.fromJson(List<dynamic> coords) {
    return GeoPoint(
      (coords[0] as num).toDouble(),
      (coords[1] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'lon': longitude,
        'lat': latitude,
      };

  @override
  String toString() => 'GeoPoint($longitude, $latitude)';
}

/// A bounding box defined by southwest and northeast corners.
class GeoBounds {
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  const GeoBounds({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  double get width => maxLon - minLon;
  double get height => maxLat - minLat;
  double get centerLon => (minLon + maxLon) / 2;
  double get centerLat => (minLat + maxLat) / 2;

  GeoPoint get center => GeoPoint(centerLon, centerLat);

  bool contains(GeoPoint point) {
    return point.longitude >= minLon &&
        point.longitude <= maxLon &&
        point.latitude >= minLat &&
        point.latitude <= maxLat;
  }

  /// Expands bounds to include another point.
  GeoBounds expand(GeoPoint point) {
    return GeoBounds(
      minLon: point.longitude < minLon ? point.longitude : minLon,
      minLat: point.latitude < minLat ? point.latitude : minLat,
      maxLon: point.longitude > maxLon ? point.longitude : maxLon,
      maxLat: point.latitude > maxLat ? point.latitude : maxLat,
    );
  }

  factory GeoBounds.fromPoints(List<GeoPoint> points) {
    if (points.isEmpty) {
      throw ArgumentError('Cannot create bounds from empty point list');
    }

    double minLon = points.first.longitude;
    double minLat = points.first.latitude;
    double maxLon = points.first.longitude;
    double maxLat = points.first.latitude;

    for (final point in points) {
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
    }

    return GeoBounds(
      minLon: minLon,
      minLat: minLat,
      maxLon: maxLon,
      maxLat: maxLat,
    );
  }

  @override
  String toString() => 'GeoBounds($minLon, $minLat, $maxLon, $maxLat)';
}

/// A polygon representing a land mass or coastline feature.
class CoastlinePolygon {
  final List<GeoPoint> exteriorRing;
  final List<List<GeoPoint>> interiorRings; // Holes in the polygon

  const CoastlinePolygon({
    required this.exteriorRing,
    this.interiorRings = const [],
  });

  GeoBounds get bounds => GeoBounds.fromPoints(exteriorRing);
}

/// Collection of coastline data for a region.
class CoastlineData {
  final List<CoastlinePolygon> polygons;
  final GeoBounds bounds;
  final String? name;
  final DateTime? lastUpdated;
  // Optional level-of-detail metadata used to pick the best dataset for a zoom level.
  final int? lodLevel; // 0 = highest detail
  final double? minZoom;
  final double? maxZoom;
  // If true, this is global data (GSHHG) that should use world projection
  final bool isGlobal;

  const CoastlineData({
    required this.polygons,
    required this.bounds,
    this.name,
    this.lastUpdated,
    this.lodLevel,
    this.minZoom,
    this.maxZoom,
    this.isGlobal = false,
  });

  int get polygonCount => polygons.length;
  
  int get totalPoints {
    int count = 0;
    for (final polygon in polygons) {
      count += polygon.exteriorRing.length;
      for (final ring in polygon.interiorRings) {
        count += ring.length;
      }
    }
    return count;
  }

  /// Returns a copy with optional overrides; keeps data immutable.
  CoastlineData copyWith({
    List<CoastlinePolygon>? polygons,
    GeoBounds? bounds,
    String? name,
    DateTime? lastUpdated,
    int? lodLevel,
    double? minZoom,
    double? maxZoom,
    bool? isGlobal,
  }) {
    return CoastlineData(
      polygons: polygons ?? this.polygons,
      bounds: bounds ?? this.bounds,
      name: name ?? this.name,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lodLevel: lodLevel ?? this.lodLevel,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      isGlobal: isGlobal ?? this.isGlobal,
    );
  }

  /// Checks whether this dataset is intended for the given zoom.
  bool supportsZoom(double zoom) {
    final min = minZoom ?? double.negativeInfinity;
    final max = maxZoom ?? double.infinity;
    return zoom >= min && zoom < max;
  }
}
