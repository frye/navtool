import 's57_models.dart';

/// Spatial index interface for S-57 chart features
/// Provides unified API for both linear and R-tree implementations
abstract class SpatialIndex {
  /// Add a feature to the spatial index
  void addFeature(S57Feature feature);

  /// Add multiple features to the spatial index
  void addFeatures(List<S57Feature> features);

  /// Clear all features from the index
  void clear();

  /// Query features within a geographic bounds
  List<S57Feature> queryBounds(S57Bounds bounds);

  /// Query features near a specific point (within radius in degrees)
  List<S57Feature> queryPoint(
    double latitude,
    double longitude, {
    double radiusDegrees = 0.01,
  });

  /// Query features by type
  List<S57Feature> queryByType(S57FeatureType featureType);

  /// Query features by types within optional bounds
  List<S57Feature> queryTypes(Set<S57FeatureType> types, {S57Bounds? bounds});

  /// Query navigation aids (buoys, beacons, lighthouses)
  List<S57Feature> queryNavigationAids();

  /// Query depth-related features (contours, areas, soundings)
  List<S57Feature> queryDepthFeatures();

  /// Get all features
  List<S57Feature> getAllFeatures();

  /// Get feature count
  int get featureCount;

  /// Get feature types present in the index
  Set<S57FeatureType> get presentFeatureTypes;

  /// Calculate overall bounds of all features
  S57Bounds? calculateBounds();
}
