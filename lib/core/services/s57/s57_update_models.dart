/// S-57 Update Processing Models
///
/// Data models for handling sequential S-57 update files (.001, .002, etc.)
/// Implements RUIN (Insert/Delete/Modify) operations with version tracking

import 's57_models.dart';

/// Feature with version tracking for update processing
class FeatureVersioned {
  final S57Feature feature;
  int version; // increment on modify

  FeatureVersioned({required this.feature, required this.version});

  /// Update the feature with new data (for modify operations)
  void updateFeature(S57Feature newFeature, int newVersion) {
    // Create updated feature with same recordId but new data
    final updatedFeature = S57Feature(
      recordId: feature.recordId,
      featureType: newFeature.featureType,
      geometryType: newFeature.geometryType,
      coordinates: newFeature.coordinates,
      attributes: {
        ...feature.attributes,
        ...newFeature.attributes,
      }, // Merge attributes
      label: newFeature.label,
    );

    // Replace the feature reference (this requires recreating the object)
    throw UnsupportedError(
      'FeatureVersioned.updateFeature requires recreating the wrapper object',
    );
  }

  @override
  String toString() =>
      'FeatureVersioned(feature: ${feature.recordId}, version: $version)';
}

/// RUIN operation types
enum RuinOperation {
  insert('I'),
  delete('D'),
  modify('M');

  const RuinOperation(this.code);
  final String code;

  static RuinOperation fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'I':
        return RuinOperation.insert;
      case 'D':
        return RuinOperation.delete;
      case 'M':
        return RuinOperation.modify;
      default:
        throw ArgumentError('Unknown RUIN operation: $code');
    }
  }

  static RuinOperation fromInt(int code) {
    switch (code) {
      case 1:
        return RuinOperation.insert;
      case 2:
        return RuinOperation.delete;
      case 3:
        return RuinOperation.modify;
      default:
        throw ArgumentError('Unknown RUIN operation code: $code');
    }
  }
}

/// RUIN record from update file
class RuinRecord {
  final String foid; // Feature Object Identifier
  final RuinOperation operation;
  final S57Feature? feature; // null for delete operations
  final Map<String, dynamic> rawData; // Raw field data for debugging

  const RuinRecord({
    required this.foid,
    required this.operation,
    this.feature,
    required this.rawData,
  });

  @override
  String toString() =>
      'RuinRecord(foid: $foid, operation: ${operation.code}, hasFeature: ${feature != null})';
}

/// Update dataset representing a single update file (.001, .002, etc.)
class UpdateDataset {
  final String name; // e.g., "SAMPLE.001"
  final int rver; // Record version from RVER field
  final String? baseCellName; // DSID cell name for integrity check
  final List<RuinRecord> records;

  const UpdateDataset({
    required this.name,
    required this.rver,
    this.baseCellName,
    required this.records,
  });

  /// Get the update sequence number from filename (e.g., 1 from "SAMPLE.001")
  int get sequenceNumber {
    final parts = name.split('.');
    if (parts.length >= 2) {
      try {
        return int.parse(parts.last);
      } catch (e) {
        return 0;
      }
    }
    return 0;
  }

  @override
  String toString() =>
      'UpdateDataset(name: $name, rver: $rver, records: ${records.length})';
}

/// Summary of applied updates
class UpdateSummary {
  int inserted = 0;
  int modified = 0;
  int deleted = 0;
  int finalRver = 0;
  final List<String> applied = [];
  final List<String> warnings = [];

  UpdateSummary();

  /// Add a warning message
  void addWarning(String message) {
    warnings.add(message);
  }

  /// Reset counters
  void reset() {
    inserted = 0;
    modified = 0;
    deleted = 0;
    finalRver = 0;
    applied.clear();
    warnings.clear();
  }

  Map<String, dynamic> toMap() {
    return {
      'inserted': inserted,
      'modified': modified,
      'deleted': deleted,
      'finalRver': finalRver,
      'applied': applied,
      'warnings': warnings,
    };
  }

  @override
  String toString() {
    return 'UpdateSummary(inserted: $inserted, modified: $modified, deleted: $deleted, '
        'finalRver: $finalRver, applied: $applied, warnings: ${warnings.length})';
  }
}

/// Feature store with FOID-based indexing for update processing
class FeatureStore {
  final Map<String, FeatureVersioned> _features = {};

  /// Add or update a feature
  void put(String foid, FeatureVersioned versionedFeature) {
    _features[foid] = versionedFeature;
  }

  /// Get feature by FOID
  FeatureVersioned? get(String foid) {
    return _features[foid];
  }

  /// Check if feature exists
  bool contains(String foid) {
    return _features.containsKey(foid);
  }

  /// Remove feature by FOID
  bool remove(String foid) {
    return _features.remove(foid) != null;
  }

  /// Insert new feature (must not exist)
  bool insert(String foid, FeatureVersioned versionedFeature) {
    if (_features.containsKey(foid)) {
      return false; // Already exists
    }
    _features[foid] = versionedFeature;
    return true;
  }

  /// Get all features
  List<FeatureVersioned> get allFeatures => _features.values.toList();

  /// Get all FOIDs
  Set<String> get allFoids => _features.keys.toSet();

  /// Clear all features
  void clear() {
    _features.clear();
  }

  /// Get feature count
  int get count => _features.length;

  @override
  String toString() => 'FeatureStore(count: ${_features.length})';
}

/// FOID (Feature Object Identifier) helper for creating consistent identifiers
class FoidHelper {
  /// Create FOID string from FOID record components
  static String createFoid(int agency, int featureId, int subdivision) {
    return '${agency}_${featureId}_$subdivision';
  }

  /// Create FOID string from FOID map
  static String createFoidFromMap(Map<String, dynamic> foidData) {
    final agency = foidData['agency'] as int? ?? 0;
    final featureId = foidData['feature_id'] as int? ?? 0;
    final subdivision = foidData['subdivision'] as int? ?? 0;
    return createFoid(agency, featureId, subdivision);
  }

  /// Parse FOID string back to components
  static Map<String, int> parseFoid(String foid) {
    final parts = foid.split('_');
    if (parts.length == 3) {
      try {
        return {
          'agency': int.parse(parts[0]),
          'feature_id': int.parse(parts[1]),
          'subdivision': int.parse(parts[2]),
        };
      } catch (e) {
        // Fall back to simple parsing
      }
    }

    // Fallback: treat entire string as feature_id
    try {
      final id = int.parse(foid);
      return {'agency': 0, 'feature_id': id, 'subdivision': 0};
    } catch (e) {
      return {'agency': 0, 'feature_id': foid.hashCode, 'subdivision': 0};
    }
  }
}
