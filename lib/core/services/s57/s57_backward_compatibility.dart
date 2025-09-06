/// S-57 Backward Compatibility Adapter
///
/// Provides mapping between the legacy S57FeatureType enum and
/// the new S57ObjectCatalog system for backward compatibility

import '../s57/s57_models.dart';
import 's57_object_catalog.dart';

/// Backward compatibility adapter for S57FeatureType enum
///
/// Maps legacy enum values to new catalog-based object classes
/// and provides deprecation warnings for legacy usage
class S57BackwardCompatibilityAdapter {
  /// Map legacy S57FeatureType enum values to official S-57 acronyms
  static const Map<S57FeatureType, String> _legacyToAcronymMap = {
    // Navigation aids - map to closest official equivalents
    S57FeatureType.beacon: 'LIGHTS', // Cardinal beacon -> Lights
    S57FeatureType.buoy: 'BOYLAT', // Generic buoy -> Lateral buoy
    S57FeatureType.buoyLateral: 'BOYLAT', // Lateral buoy
    S57FeatureType.buoyCardinal:
        'BOYLAT', // Cardinal buoy -> Lateral buoy for compatibility
    S57FeatureType.buoyIsolatedDanger: 'BOYISD', // Isolated danger buoy
    S57FeatureType.buoySpecialPurpose: 'BOYSPP', // Special purpose buoy
    S57FeatureType.lighthouse: 'LIGHTS', // Light
    S57FeatureType.daymark: 'LIGHTS', // Daymark -> Lights for compatibility
    // Bathymetry
    S57FeatureType.depthArea: 'DEPARE', // Depth area
    S57FeatureType.depthContour:
        'DEPARE', // Depth contour -> Depth area for compatibility
    S57FeatureType.sounding: 'SOUNDG', // Sounding
    // Coastline features
    S57FeatureType.coastline: 'COALNE', // Coastline
    S57FeatureType.shoreline: 'COALNE', // Shoreline alias -> Coastline
    S57FeatureType.landArea: 'LNDARE', // Land area
    // Obstructions
    S57FeatureType.obstruction: 'OBSTRN', // Obstruction
    S57FeatureType.wreck: 'WRECKS', // Wreck
    S57FeatureType.underwater: 'UWTROC', // Underwater/awash rock
    // Unknown
    S57FeatureType.unknown: 'UNKNOW', // Unknown (not in official catalog)
  };

  /// Map official S-57 acronyms back to legacy enum values (for compatibility)
  static const Map<String, S57FeatureType> _acronymToLegacyMap = {
    'LIGHTS': S57FeatureType.lighthouse,
    'BOYLAT': S57FeatureType.buoyLateral,
    'BOYISD': S57FeatureType.buoyIsolatedDanger,
    'BOYSPP': S57FeatureType.buoySpecialPurpose,
    'DEPARE': S57FeatureType.depthArea,
    'SOUNDG': S57FeatureType.sounding,
    'COALNE': S57FeatureType.coastline,
    'LNDARE': S57FeatureType.landArea,
    'OBSTRN': S57FeatureType.obstruction,
    'WRECKS': S57FeatureType.wreck,
    'UWTROC': S57FeatureType.underwater,
    'UNKNOW': S57FeatureType.unknown,
  };

  static final Set<S57FeatureType> _warnedDeprecatedUsage = <S57FeatureType>{};

  /// Convert legacy S57FeatureType to official S-57 acronym
  static String legacyToAcronym(S57FeatureType legacyType) {
    // Emit deprecation warning once per type
    if (!_warnedDeprecatedUsage.contains(legacyType)) {
      _warnedDeprecatedUsage.add(legacyType);
      print(
        'Warning: S57FeatureType.$legacyType is deprecated. '
        'Use S57ObjectCatalog.byAcronym("${_legacyToAcronymMap[legacyType]}") instead.',
      );
    }

    return _legacyToAcronymMap[legacyType] ?? 'UNKNOW';
  }

  /// Convert official S-57 acronym to legacy S57FeatureType
  static S57FeatureType acronymToLegacy(String acronym) {
    return _acronymToLegacyMap[acronym.toUpperCase()] ?? S57FeatureType.unknown;
  }

  /// Get the S57ObjectClass equivalent for a legacy S57FeatureType
  static S57ObjectClass? legacyToObjectClass(
    S57FeatureType legacyType,
    S57ObjectCatalog catalog,
  ) {
    final acronym = legacyToAcronym(legacyType);
    return catalog.byAcronym(acronym);
  }

  /// Check if a legacy S57FeatureType has an official S-57 equivalent
  static bool hasOfficialEquivalent(S57FeatureType legacyType) {
    final acronym = _legacyToAcronymMap[legacyType];
    return acronym != null && acronym != 'UNKNOW';
  }

  /// Get mapping statistics for validation
  static Map<String, int> getMappingStats() {
    return {
      'total_legacy_types': S57FeatureType.values.length,
      'mapped_to_official': _legacyToAcronymMap.length,
      'official_acronyms': _acronymToLegacyMap.length,
      'unknown_mappings': _legacyToAcronymMap.values
          .where((v) => v == 'UNKNOW')
          .length,
    };
  }
}
