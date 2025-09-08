import 'dart:math';
import 's57_models.dart';
import 'spatial_index_interface.dart';

/// Grid-based spatial index for marine chart features
/// Provides O(1) grid cell lookup with configurable resolution
class SpatialGrid implements SpatialIndex {
  final double cellSizeDegrees;
  final S57Bounds bounds;
  final Map<String, List<S57Feature>> _grid = {};
  final Map<S57FeatureType, List<S57Feature>> _featuresByType = {};
  int _featureCount = 0;

  SpatialGrid({
    required this.bounds,
    this.cellSizeDegrees = 0.01, // ~1km at equator
  });

  /// Get grid cell key for coordinates
  String _getCellKey(double lat, double lon) {
    final gridX = ((lon - bounds.west) / cellSizeDegrees).floor();
    final gridY = ((lat - bounds.south) / cellSizeDegrees).floor();
    return '${gridX}_$gridY';
  }

  /// Get all grid keys that intersect with bounds
  List<String> _getBoundsCells(S57Bounds queryBounds) {
    final cells = <String>[];
    
    final startX = ((queryBounds.west - bounds.west) / cellSizeDegrees).floor();
    final endX = ((queryBounds.east - bounds.west) / cellSizeDegrees).floor();
    final startY = ((queryBounds.south - bounds.south) / cellSizeDegrees).floor();
    final endY = ((queryBounds.north - bounds.south) / cellSizeDegrees).floor();
    
    for (int x = startX; x <= endX; x++) {
      for (int y = startY; y <= endY; y++) {
        cells.add('${x}_$y');
      }
    }
    
    return cells;
  }

  @override
  void addFeature(S57Feature feature) {
    // Add to type index
    _featuresByType.putIfAbsent(feature.featureType, () => []).add(feature);
    
    // Add to spatial grid for each coordinate
    for (final coord in feature.coordinates) {
      final cellKey = _getCellKey(coord.latitude, coord.longitude);
      _grid.putIfAbsent(cellKey, () => []).add(feature);
    }
    
    _featureCount++;
  }

  @override
  void addFeatures(List<S57Feature> features) {
    for (final feature in features) {
      addFeature(feature);
    }
  }

  @override
  void clear() {
    _grid.clear();
    _featuresByType.clear();
    _featureCount = 0;
  }

  @override
  List<S57Feature> queryBounds(S57Bounds queryBounds) {
    final results = <S57Feature>{};
    final cells = _getBoundsCells(queryBounds);
    
    for (final cellKey in cells) {
      final cellFeatures = _grid[cellKey];
      if (cellFeatures != null) {
        for (final feature in cellFeatures) {
          if (_featureIntersectsBounds(feature, queryBounds)) {
            results.add(feature);
          }
        }
      }
    }
    
    return results.toList();
  }

  @override
  List<S57Feature> queryPoint(
    double latitude,
    double longitude, {
    double radiusDegrees = 0.01,
  }) {
    final expandedBounds = S57Bounds(
      north: latitude + radiusDegrees,
      south: latitude - radiusDegrees,
      east: longitude + radiusDegrees,
      west: longitude - radiusDegrees,
    );
    
    final candidates = queryBounds(expandedBounds);
    final results = <S57Feature>[];
    
    for (final feature in candidates) {
      for (final coord in feature.coordinates) {
        final distance = _calculateDistance(
          latitude,
          longitude,
          coord.latitude,
          coord.longitude,
        );
        if (distance <= radiusDegrees) {
          results.add(feature);
          break;
        }
      }
    }
    
    return results;
  }

  @override
  List<S57Feature> queryByType(S57FeatureType featureType) {
    return _featuresByType[featureType] ?? [];
  }

  @override
  List<S57Feature> queryTypes(Set<S57FeatureType> types, {S57Bounds? bounds}) {
    final results = <S57Feature>[];
    
    for (final type in types) {
      final typedFeatures = queryByType(type);
      if (bounds != null) {
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

  @override
  List<S57Feature> queryNavigationAids() {
    final navTypes = {
      S57FeatureType.buoy,
      S57FeatureType.buoyLateral,
      S57FeatureType.buoyCardinal,
      S57FeatureType.buoyIsolatedDanger,
      S57FeatureType.buoySpecialPurpose,
      S57FeatureType.beacon,
      S57FeatureType.lighthouse,
      S57FeatureType.daymark,
    };
    
    return queryTypes(navTypes);
  }

  @override
  List<S57Feature> queryDepthFeatures() {
    final depthTypes = {
      S57FeatureType.depthContour,
      S57FeatureType.depthArea,
      S57FeatureType.sounding,
    };
    
    return queryTypes(depthTypes);
  }

  @override
  List<S57Feature> getAllFeatures() {
    final allFeatures = <S57Feature>{};
    for (final cellFeatures in _grid.values) {
      allFeatures.addAll(cellFeatures);
    }
    return allFeatures.toList();
  }

  @override
  int get featureCount => _featureCount;

  @override
  Set<S57FeatureType> get presentFeatureTypes => _featuresByType.keys.toSet();

  @override
  S57Bounds? calculateBounds() {
    if (_featureCount == 0) return null;
    
    double minLat = 90.0;
    double maxLat = -90.0;
    double minLon = 180.0;
    double maxLon = -180.0;
    
    for (final cellFeatures in _grid.values) {
      for (final feature in cellFeatures) {
        for (final coord in feature.coordinates) {
          minLat = min(minLat, coord.latitude);
          maxLat = max(maxLat, coord.latitude);
          minLon = min(minLon, coord.longitude);
          maxLon = max(maxLon, coord.longitude);
        }
      }
    }
    
    return S57Bounds(north: maxLat, south: minLat, east: maxLon, west: minLon);
  }

  /// Get grid statistics for performance analysis
  SpatialGridStats getStats() {
    final cellCounts = <int>[];
    int totalCells = 0;
    int emptyCells = 0;
    
    for (final cellFeatures in _grid.values) {
      totalCells++;
      if (cellFeatures.isEmpty) {
        emptyCells++;
      } else {
        cellCounts.add(cellFeatures.length);
      }
    }
    
    final averageFeaturesPerCell = cellCounts.isNotEmpty 
        ? cellCounts.reduce((a, b) => a + b) / cellCounts.length 
        : 0.0;
    
    return SpatialGridStats(
      totalCells: totalCells,
      emptyCells: emptyCells,
      averageFeaturesPerCell: averageFeaturesPerCell,
      maxFeaturesPerCell: cellCounts.isNotEmpty ? cellCounts.reduce(max) : 0,
      cellSizeDegrees: cellSizeDegrees,
      totalFeatures: _featureCount,
    );
  }

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

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;
    return sqrt(dLat * dLat + dLon * dLon);
  }
}

/// Statistics for spatial grid performance analysis
class SpatialGridStats {
  final int totalCells;
  final int emptyCells;
  final double averageFeaturesPerCell;
  final int maxFeaturesPerCell;
  final double cellSizeDegrees;
  final int totalFeatures;

  const SpatialGridStats({
    required this.totalCells,
    required this.emptyCells,
    required this.averageFeaturesPerCell,
    required this.maxFeaturesPerCell,
    required this.cellSizeDegrees,
    required this.totalFeatures,
  });

  double get cellUtilization => totalCells > 0 
      ? (totalCells - emptyCells) / totalCells 
      : 0.0;

  @override
  String toString() {
    return 'SpatialGridStats('
        'cells: $totalCells, '
        'utilization: ${(cellUtilization * 100).toStringAsFixed(1)}%, '
        'avg features/cell: ${averageFeaturesPerCell.toStringAsFixed(1)}, '
        'max features/cell: $maxFeaturesPerCell, '
        'cell size: ${cellSizeDegrees}°'
        ')';
  }
}