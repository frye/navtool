import 'dart:math';
import 's57_models.dart';
import 'spatial_index_interface.dart';

/// Simple spatial indexing for S-57 chart features
/// Provides efficient queries for marine navigation features
class S57SpatialIndex implements SpatialIndex {
  final List<S57Feature> _features = [];
  final Map<S57FeatureType, List<S57Feature>> _featuresByType = {};
  
  /// Add a feature to the spatial index
  void addFeature(S57Feature feature) {
    _features.add(feature);
    
    // Index by feature type for efficient type-based queries
    _featuresByType.putIfAbsent(feature.featureType, () => []).add(feature);
  }

  /// Add multiple features to the spatial index
  void addFeatures(List<S57Feature> features) {
    for (final feature in features) {
      addFeature(feature);
    }
  }

  /// Clear all features from the index
  void clear() {
    _features.clear();
    _featuresByType.clear();
  }

  /// Query features within a geographic bounds
  List<S57Feature> queryBounds(S57Bounds bounds) {
    final results = <S57Feature>[];
    
    for (final feature in _features) {
      if (_featureIntersectsBounds(feature, bounds)) {
        results.add(feature);
      }
    }
    
    return results;
  }

  /// Query features near a specific point (within radius in degrees)
  List<S57Feature> queryPoint(double latitude, double longitude, 
                               {double radiusDegrees = 0.01}) {
    final results = <S57Feature>[];
    
    for (final feature in _features) {
      if (_featureNearPoint(feature, latitude, longitude, radiusDegrees)) {
        results.add(feature);
      }
    }
    
    return results;
  }

  /// Query features by type
  List<S57Feature> queryByType(S57FeatureType featureType) {
    return _featuresByType[featureType] ?? [];
  }

  /// Query features by types within optional bounds
  @override
  List<S57Feature> queryTypes(Set<S57FeatureType> types, {S57Bounds? bounds}) {
    final results = <S57Feature>[];
    
    for (final type in types) {
      final typedFeatures = queryByType(type);
      if (bounds != null) {
        // Filter by bounds
        for (final feature in typedFeatures) {
          if (_featureIntersectsBounds(feature, bounds)) {
            results.add(feature);
          }
        }
      } else {
        results.addAll(typedFeatures);
      }
    }
    
    return results;
  }

  /// Query navigation aids (buoys, beacons, lighthouses)
  List<S57Feature> queryNavigationAids() {
    final results = <S57Feature>[];
    
    final navTypes = [
      S57FeatureType.buoy,  // Include generic buoy type
      S57FeatureType.buoyLateral,
      S57FeatureType.buoyCardinal,
      S57FeatureType.buoyIsolatedDanger,
      S57FeatureType.buoySpecialPurpose,
      S57FeatureType.beacon,
      S57FeatureType.lighthouse,
      S57FeatureType.daymark,
    ];
    
    for (final type in navTypes) {
      results.addAll(queryByType(type));
    }
    
    return results;
  }

  /// Query depth-related features (contours, areas, soundings)
  List<S57Feature> queryDepthFeatures() {
    final results = <S57Feature>[];
    
    final depthTypes = [
      S57FeatureType.depthContour,
      S57FeatureType.depthArea,
      S57FeatureType.sounding,
    ];
    
    for (final type in depthTypes) {
      results.addAll(queryByType(type));
    }
    
    return results;
  }

  /// Get all features
  List<S57Feature> getAllFeatures() {
    return List.unmodifiable(_features);
  }

  /// Get feature count
  int get featureCount => _features.length;

  /// Get feature types present in the index
  Set<S57FeatureType> get presentFeatureTypes => _featuresByType.keys.toSet();

  /// Calculate overall bounds of all features
  S57Bounds? calculateBounds() {
    if (_features.isEmpty) return null;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLon = 180.0;
    double maxLon = -180.0;

    for (final feature in _features) {
      for (final coord in feature.coordinates) {
        minLat = min(minLat, coord.latitude);
        maxLat = max(maxLat, coord.latitude);
        minLon = min(minLon, coord.longitude);
        maxLon = max(maxLon, coord.longitude);
      }
    }

    return S57Bounds(
      north: maxLat,
      south: minLat,
      east: maxLon,
      west: minLon,
    );
  }

  /// Check if a feature intersects with given bounds
  bool _featureIntersectsBounds(S57Feature feature, S57Bounds bounds) {
    for (final coord in feature.coordinates) {
      if (coord.latitude >= bounds.south &&
          coord.latitude <= bounds.north &&
          coord.longitude >= bounds.west &&
          coord.longitude <= bounds.east) {
        return true;
      }
    }
    return false;
  }

  /// Check if a feature is near a point
  bool _featureNearPoint(S57Feature feature, double lat, double lon, double radius) {
    for (final coord in feature.coordinates) {
      final distance = _calculateDistance(lat, lon, coord.latitude, coord.longitude);
      if (distance <= radius) {
        return true;
      }
    }
    return false;
  }

  /// Calculate approximate distance between two points in degrees
  /// For marine navigation, this provides sufficient accuracy for spatial queries
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;
    return sqrt(dLat * dLat + dLon * dLon);
  }
}

/// Statistics about spatial index performance
class SpatialIndexStats {
  final int totalFeatures;
  final Map<S57FeatureType, int> featureCountsByType;
  final S57Bounds? bounds;
  final DateTime indexTime;

  const SpatialIndexStats({
    required this.totalFeatures,
    required this.featureCountsByType,
    required this.bounds,
    required this.indexTime,
  });

  @override
  String toString() {
    return 'SpatialIndexStats('
           'features: $totalFeatures, '
           'types: ${featureCountsByType.length}, '
           'bounds: $bounds, '
           'indexed: ${indexTime.toIso8601String()}'
           ')';
  }
}