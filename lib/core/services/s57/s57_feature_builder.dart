/// S-57 Feature Builder with Object Catalog Integration
///
/// Builds S-57 features using the new object catalog and attribute services
/// while maintaining backward compatibility with the existing S57Parser

import 's57_models.dart';
import 's57_object_catalog.dart';
import 's57_attribute_validator.dart';
import 's57_backward_compatibility.dart';

/// Enhanced S-57 feature builder with catalog integration
class S57FeatureBuilder {
  final S57ObjectCatalog _objectCatalog;
  final S57AttributeCatalog _attributeCatalog;

  S57FeatureBuilder(this._objectCatalog, this._attributeCatalog);

  /// Build S-57 feature from raw record data with catalog-based validation
  S57Feature? buildFeature({
    required int recordId,
    required int objectCode,
    required Map<String, List<String>> rawAttributes,
    required List<S57Coordinate> coordinates,
  }) {
    // Look up object class in catalog
    final objectClass = _objectCatalog.byCode(objectCode);

    // If object class is unknown, try to map to legacy type for compatibility
    S57FeatureType legacyType;
    if (objectClass != null) {
      legacyType = S57BackwardCompatibilityAdapter.acronymToLegacy(
        objectClass.acronym,
      );
    } else {
      legacyType = S57FeatureType.fromCode(objectCode);
    }

    // If still unknown, return null (feature will be skipped)
    if (legacyType == S57FeatureType.unknown && objectClass == null) {
      return null;
    }

    // Decode attributes using catalog
    final decodedAttributes = _decodeAttributes(rawAttributes);

    // Validate required attributes
    final warnings = S57RequiredAttributeValidator.validateRequired(
      objectClass,
      decodedAttributes,
    );

    // Print warnings (in production, these would go to a proper logger)
    for (final warning in warnings) {
      print('S-57 Validation Warning: ${warning.message}');
    }

    // Determine geometry type based on coordinates
    final geometryType = _determineGeometryType(coordinates);

    // Generate label using object class name or legacy type
    final label = _generateFeatureLabel(
      objectClass,
      legacyType,
      decodedAttributes,
    );

    return S57Feature(
      recordId: recordId,
      featureType: legacyType,
      geometryType: geometryType,
      coordinates: coordinates,
      attributes: decodedAttributes,
      label: label,
    );
  }

  /// Decode raw attributes using attribute catalog
  Map<String, Object?> _decodeAttributes(
    Map<String, List<String>> rawAttributes,
  ) {
    final decoded = <String, Object?>{};

    for (final entry in rawAttributes.entries) {
      final acronym = entry.key;
      final rawValues = entry.value;

      // Look up attribute definition
      final attrDef = _attributeCatalog.byAcronym(acronym);

      // Decode using catalog
      final decodedValue = _attributeCatalog.decodeAttribute(
        attrDef,
        rawValues,
      );
      decoded[acronym] = decodedValue;
    }

    return decoded;
  }

  /// Determine geometry type from coordinates
  S57GeometryType _determineGeometryType(List<S57Coordinate> coordinates) {
    if (coordinates.isEmpty) {
      return S57GeometryType.point; // Default fallback
    }

    if (coordinates.length == 1) {
      return S57GeometryType.point;
    }

    // Check if coordinates form a closed polygon
    if (coordinates.length >= 3 &&
        coordinates.first.latitude == coordinates.last.latitude &&
        coordinates.first.longitude == coordinates.last.longitude) {
      return S57GeometryType.area;
    }

    return S57GeometryType.line;
  }

  /// Generate feature label using object class or legacy type
  String _generateFeatureLabel(
    S57ObjectClass? objectClass,
    S57FeatureType legacyType,
    Map<String, Object?> attributes,
  ) {
    // Use object name from attributes if available
    final objName = attributes['OBJNAM'];
    if (objName is String && objName.isNotEmpty) {
      return objName;
    }

    // Use catalog object class name if available
    if (objectClass != null) {
      return objectClass.name;
    }

    // Fall back to legacy type name
    return _legacyTypeToLabel(legacyType);
  }

  /// Convert legacy feature type to readable label
  String _legacyTypeToLabel(S57FeatureType type) {
    return switch (type) {
      S57FeatureType.beacon => 'Beacon',
      S57FeatureType.buoy => 'Buoy',
      S57FeatureType.buoyLateral => 'Lateral Buoy',
      S57FeatureType.buoyCardinal => 'Cardinal Buoy',
      S57FeatureType.buoyIsolatedDanger => 'Isolated Danger Buoy',
      S57FeatureType.buoySpecialPurpose => 'Special Purpose Buoy',
      S57FeatureType.lighthouse => 'Light',
      S57FeatureType.daymark => 'Daymark',
      S57FeatureType.depthArea => 'Depth Area',
      S57FeatureType.depthContour => 'Depth Contour',
      S57FeatureType.sounding => 'Sounding',
      S57FeatureType.coastline => 'Coastline',
      S57FeatureType.shoreline => 'Shoreline',
      S57FeatureType.landArea => 'Land Area',
      S57FeatureType.shoreConstruction => 'Shore Construction',
      S57FeatureType.builtArea => 'Built Area',
      S57FeatureType.obstruction => 'Obstruction',
      S57FeatureType.wreck => 'Wreck',
      S57FeatureType.underwater => 'Underwater Rock',
      S57FeatureType.unknown => 'Unknown Feature',
    };
  }
}

/// Factory for creating S57FeatureBuilder with loaded catalogs
class S57FeatureBuilderFactory {
  static S57ObjectCatalog? _objectCatalog;
  static S57AttributeCatalog? _attributeCatalog;

  /// Initialize catalogs (call once at startup)
  static Future<void> initialize() async {
    _objectCatalog ??= await S57ObjectCatalog.loadFromAssets();
    _attributeCatalog ??= await S57AttributeCatalog.loadFromAssets();
  }

  /// Create a feature builder with initialized catalogs
  static S57FeatureBuilder create() {
    if (_objectCatalog == null || _attributeCatalog == null) {
      throw StateError(
        'S57FeatureBuilderFactory must be initialized before use. '
        'Call S57FeatureBuilderFactory.initialize() first.',
      );
    }
    return S57FeatureBuilder(_objectCatalog!, _attributeCatalog!);
  }

  /// Create a feature builder with custom catalogs (for testing)
  static S57FeatureBuilder createWithCatalogs(
    S57ObjectCatalog objectCatalog,
    S57AttributeCatalog attributeCatalog,
  ) {
    return S57FeatureBuilder(objectCatalog, attributeCatalog);
  }

  /// Get loaded catalogs (for inspection)
  static S57ObjectCatalog? get objectCatalog => _objectCatalog;
  static S57AttributeCatalog? get attributeCatalog => _attributeCatalog;

  /// Reset catalogs (for testing)
  static void reset() {
    _objectCatalog = null;
    _attributeCatalog = null;
  }
}
