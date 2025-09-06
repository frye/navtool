import 'dart:math';
import 's57_models.dart';
import 'spatial_index_interface.dart';
import 's57_spatial_index.dart';

/// Configuration for R-tree spatial index
class RTreeConfig {
  final int maxNodeEntries;
  final bool forceLinear;

  const RTreeConfig({this.maxNodeEntries = 16, this.forceLinear = false});
}

/// Bounding box for R-tree entries
class Bounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const Bounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// Create bounds from S57Bounds
  factory Bounds.fromS57(S57Bounds bounds) {
    return Bounds(
      minX: bounds.west,
      minY: bounds.south,
      maxX: bounds.east,
      maxY: bounds.north,
    );
  }

  /// Create bounds from a single point (zero-area)
  factory Bounds.fromPoint(double x, double y) {
    return Bounds(minX: x, minY: y, maxX: x, maxY: y);
  }

  /// Create bounds from feature coordinates
  factory Bounds.fromFeature(S57Feature feature) {
    if (feature.coordinates.isEmpty) {
      throw ArgumentError('Feature must have at least one coordinate');
    }

    double minX = feature.coordinates.first.longitude;
    double minY = feature.coordinates.first.latitude;
    double maxX = minX;
    double maxY = minY;

    for (final coord in feature.coordinates) {
      minX = min(minX, coord.longitude);
      minY = min(minY, coord.latitude);
      maxX = max(maxX, coord.longitude);
      maxY = max(maxY, coord.latitude);
    }

    return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Check if this bounds intersects with another bounds
  bool intersects(Bounds other) {
    return minX <= other.maxX &&
        maxX >= other.minX &&
        minY <= other.maxY &&
        maxY >= other.minY;
  }

  /// Check if this bounds contains a point
  bool containsPoint(double x, double y) {
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  }

  /// Calculate area of bounds
  double get area => (maxX - minX) * (maxY - minY);

  /// Expand bounds to include another bounds
  Bounds expandToInclude(Bounds other) {
    return Bounds(
      minX: min(minX, other.minX),
      minY: min(minY, other.minY),
      maxX: max(maxX, other.maxX),
      maxY: max(maxY, other.maxY),
    );
  }

  /// Convert to S57Bounds
  S57Bounds toS57Bounds() {
    return S57Bounds(north: maxY, south: minY, east: maxX, west: minX);
  }

  @override
  String toString() => 'Bounds($minX, $minY, $maxX, $maxY)';
}

/// Entry in an R-tree node
class RTreeEntry {
  final Bounds mbr;
  final int? featureId;
  final RTreeNode? child;

  const RTreeEntry({required this.mbr, this.featureId, this.child});

  /// Create leaf entry for feature
  factory RTreeEntry.forFeature(int featureId, Bounds bounds) {
    return RTreeEntry(mbr: bounds, featureId: featureId);
  }

  /// Create internal entry for child node
  factory RTreeEntry.forChild(RTreeNode child, Bounds bounds) {
    return RTreeEntry(mbr: bounds, child: child);
  }

  bool get isLeaf => featureId != null;
}

/// Node in an R-tree
class RTreeNode {
  final bool isLeaf;
  final List<RTreeEntry> entries;
  late Bounds mbr;

  RTreeNode({required this.isLeaf, List<RTreeEntry>? entries})
    : entries = entries ?? <RTreeEntry>[] {
    _updateMBR();
  }

  /// Add entry to node
  void addEntry(RTreeEntry entry) {
    entries.add(entry);
    _updateMBR();
  }

  /// Update minimum bounding rectangle from entries
  void _updateMBR() {
    if (entries.isEmpty) {
      mbr = const Bounds(minX: 0, minY: 0, maxX: 0, maxY: 0);
      return;
    }

    double minX = entries.first.mbr.minX;
    double minY = entries.first.mbr.minY;
    double maxX = entries.first.mbr.maxX;
    double maxY = entries.first.mbr.maxY;

    for (final entry in entries.skip(1)) {
      minX = min(minX, entry.mbr.minX);
      minY = min(minY, entry.mbr.minY);
      maxX = max(maxX, entry.mbr.maxX);
      maxY = max(maxY, entry.mbr.maxY);
    }

    mbr = Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}

/// Feature data for R-tree construction
class IndexedFeature {
  final int id;
  final S57Feature feature;
  final Bounds bounds;

  const IndexedFeature({
    required this.id,
    required this.feature,
    required this.bounds,
  });
}

/// R-tree spatial index implementation for S-57 features
class S57SpatialTree implements SpatialIndex {
  final RTreeConfig config;
  final Map<int, S57Feature> _features = {};
  final Map<S57FeatureType, List<S57Feature>> _featuresByType = {};
  RTreeNode? _root;

  S57SpatialTree({RTreeConfig? config})
    : config = config ?? const RTreeConfig();

  /// Create R-tree using bulk load from features
  factory S57SpatialTree.bulkLoad(
    List<S57Feature> features, {
    RTreeConfig? config,
  }) {
    final tree = S57SpatialTree(config: config);
    if (features.isNotEmpty) {
      // Populate feature maps
      for (final feature in features) {
        tree._features[feature.recordId] = feature;
        tree._featuresByType
            .putIfAbsent(feature.featureType, () => [])
            .add(feature);
      }
      tree._bulkLoad(features);
    }
    return tree;
  }

  @override
  void addFeature(S57Feature feature) {
    _features[feature.recordId] = feature;
    _featuresByType.putIfAbsent(feature.featureType, () => []).add(feature);

    // For incremental insert, rebuild if we have a root
    // (Simple implementation - could be optimized with proper R-tree insert)
    if (_root != null) {
      _bulkLoad(_features.values.toList());
    }
  }

  @override
  void addFeatures(List<S57Feature> features) {
    for (final feature in features) {
      _features[feature.recordId] = feature;
      _featuresByType.putIfAbsent(feature.featureType, () => []).add(feature);
    }

    if (features.isNotEmpty) {
      _bulkLoad(_features.values.toList());
    }
  }

  @override
  void clear() {
    _features.clear();
    _featuresByType.clear();
    _root = null;
  }

  @override
  List<S57Feature> queryBounds(S57Bounds bounds) {
    if (_root == null) return [];

    final queryBounds = Bounds.fromS57(bounds);
    final resultIds = <int>[];
    _queryBoundsRecursive(_root!, queryBounds, resultIds);

    return resultIds
        .where((id) => _features.containsKey(id))
        .map((id) => _features[id]!)
        .toList();
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

    // Refine by exact distance for point features
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
    return List.unmodifiable(_features.values);
  }

  @override
  int get featureCount => _features.length;

  @override
  Set<S57FeatureType> get presentFeatureTypes => _featuresByType.keys.toSet();

  @override
  S57Bounds? calculateBounds() {
    if (_features.isEmpty) return null;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLon = 180.0;
    double maxLon = -180.0;

    for (final feature in _features.values) {
      for (final coord in feature.coordinates) {
        minLat = min(minLat, coord.latitude);
        maxLat = max(maxLat, coord.latitude);
        minLon = min(minLon, coord.longitude);
        maxLon = max(maxLon, coord.longitude);
      }
    }

    return S57Bounds(north: maxLat, south: minLat, east: maxLon, west: minLon);
  }

  /// Bulk load features using STR (Sort-Tile-Recursive) algorithm
  void _bulkLoad(List<S57Feature> features) {
    if (features.isEmpty) {
      _root = null;
      return;
    }

    // Create indexed features with MBRs
    final indexedFeatures = <IndexedFeature>[];
    for (final feature in features) {
      indexedFeatures.add(
        IndexedFeature(
          id: feature.recordId,
          feature: feature,
          bounds: Bounds.fromFeature(feature),
        ),
      );
    }

    // Build R-tree using STR
    _root = _strBulkLoad(indexedFeatures);
  }

  /// STR (Sort-Tile-Recursive) bulk load algorithm
  RTreeNode _strBulkLoad(List<IndexedFeature> features) {
    if (features.length <= config.maxNodeEntries) {
      // Create leaf node
      final node = RTreeNode(isLeaf: true);
      for (final indexedFeature in features) {
        node.addEntry(
          RTreeEntry.forFeature(indexedFeature.id, indexedFeature.bounds),
        );
      }
      return node;
    }

    // Calculate number of vertical slices
    final numSlices = (sqrt(features.length / config.maxNodeEntries)).ceil();
    final featuresPerSlice = (features.length / numSlices).ceil();

    // Sort by X coordinate (longitude)
    features.sort((a, b) => a.bounds.minX.compareTo(b.bounds.minX));

    final childNodes = <RTreeNode>[];

    // Create vertical slices
    for (int i = 0; i < numSlices; i++) {
      final start = i * featuresPerSlice;
      final end = min(start + featuresPerSlice, features.length);
      final slice = features.sublist(start, end);

      // Sort slice by Y coordinate (latitude)
      slice.sort((a, b) => a.bounds.minY.compareTo(b.bounds.minY));

      // Group slice into nodes
      for (int j = 0; j < slice.length; j += config.maxNodeEntries) {
        final nodeEnd = min(j + config.maxNodeEntries, slice.length);
        final nodeFeatures = slice.sublist(j, nodeEnd);

        final childNode = _strBulkLoad(nodeFeatures);
        childNodes.add(childNode);
      }
    }

    // Create internal node from child nodes
    final internalNode = RTreeNode(isLeaf: false);
    for (final child in childNodes) {
      internalNode.addEntry(RTreeEntry.forChild(child, child.mbr));
    }

    // If we have too many child nodes, we need to group them into parent nodes
    if (childNodes.length > config.maxNodeEntries) {
      final groupedNodes = <RTreeNode>[];

      // Group child nodes into parent nodes
      for (int i = 0; i < childNodes.length; i += config.maxNodeEntries) {
        final groupEnd = min(i + config.maxNodeEntries, childNodes.length);
        final group = childNodes.sublist(i, groupEnd);

        final parentNode = RTreeNode(isLeaf: false);
        for (final child in group) {
          parentNode.addEntry(RTreeEntry.forChild(child, child.mbr));
        }
        groupedNodes.add(parentNode);
      }

      // If we still have too many nodes, recurse with the groups
      if (groupedNodes.length > config.maxNodeEntries) {
        final parentNode = RTreeNode(isLeaf: false);
        for (final group in groupedNodes) {
          parentNode.addEntry(RTreeEntry.forChild(group, group.mbr));
        }
        return parentNode;
      } else if (groupedNodes.length == 1) {
        return groupedNodes.first;
      } else {
        final parentNode = RTreeNode(isLeaf: false);
        for (final group in groupedNodes) {
          parentNode.addEntry(RTreeEntry.forChild(group, group.mbr));
        }
        return parentNode;
      }
    }

    return internalNode;
  }

  /// Recursive bounds query implementation
  void _queryBoundsRecursive(
    RTreeNode node,
    Bounds queryBounds,
    List<int> results,
  ) {
    for (final entry in node.entries) {
      if (!entry.mbr.intersects(queryBounds)) continue;

      if (node.isLeaf) {
        results.add(entry.featureId!);
      } else {
        _queryBoundsRecursive(entry.child!, queryBounds, results);
      }
    }
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

  /// Calculate approximate distance between two points in degrees
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

  /// Create dummy feature for internal R-tree construction
  S57Feature _createDummyFeature(Bounds bounds) {
    return S57Feature(
      recordId: 0,
      featureType: S57FeatureType.unknown,
      geometryType: S57GeometryType.point,
      coordinates: [
        S57Coordinate(latitude: bounds.minY, longitude: bounds.minX),
      ],
      attributes: const {},
    );
  }
}

/// Factory for creating spatial indexes with fallback logic
class SpatialIndexFactory {
  static const int _linearFallbackThreshold = 200;

  /// Create appropriate spatial index based on feature count and configuration
  static SpatialIndex create(List<S57Feature> features, {RTreeConfig? config}) {
    final effectiveConfig = config ?? const RTreeConfig();

    if (features.length < _linearFallbackThreshold ||
        effectiveConfig.forceLinear) {
      // Use linear implementation for small datasets
      final index = S57SpatialIndex();
      index.addFeatures(features);
      return index;
    } else {
      // Use R-tree for larger datasets
      return S57SpatialTree.bulkLoad(features, config: effectiveConfig);
    }
  }
}
