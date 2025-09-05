/// S-57 Required Attribute Validation
/// 
/// Provides validation rules for required attributes per object class
/// and generates warnings for missing required attributes

import 's57_object_catalog.dart';

/// Validation warning for missing required attributes
class S57ValidationWarning {
  final String objectAcronym;
  final String missingAttribute;
  final String message;

  const S57ValidationWarning({
    required this.objectAcronym,
    required this.missingAttribute,
    required this.message,
  });

  @override
  String toString() => 'S57ValidationWarning: $message';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is S57ValidationWarning &&
           other.objectAcronym == objectAcronym &&
           other.missingAttribute == missingAttribute &&
           other.message == message;
  }

  @override
  int get hashCode => Object.hash(objectAcronym, missingAttribute, message);
}

/// S-57 Required Attribute Validation Service
/// 
/// Validates that required attributes are present for each object class
/// and generates non-fatal warnings for missing attributes
class S57RequiredAttributeValidator {
  /// Required attribute rules per object class
  static const Map<String, List<String>> _requiredAttributes = {
    'DEPARE': ['DRVAL1'], // DRVAL2 optional but recommended
    'SOUNDG': ['VALSOU'], // QUASOU optional quality annotation
    // 'COALNE': [], // WATLEV optional; if absent no warning (configurable threshold)
    // 'LIGHTS': [], // OBJNAM optional, HEIGHT optional
    'BOYLAT': ['CATBOY'], // COLOUR recommended
    'BOYISD': ['CATBOY'], // COLOUR recommended
    'BOYSPP': ['CATBOY'], // COLOUR recommended
    // 'OBSTRN': [], // No mandatory attributes
    // 'WRECKS': [], // VALSOU optional - provide warning if absent? configurable
  };

  /// Validate required attributes for an object class
  static List<S57ValidationWarning> validateRequired(
    S57ObjectClass? objectClass,
    Map<String, Object?> attributes,
  ) {
    if (objectClass == null) return [];

    final required = _requiredAttributes[objectClass.acronym];
    if (required == null || required.isEmpty) return [];

    final warnings = <S57ValidationWarning>[];

    for (final requiredAttr in required) {
      if (!attributes.containsKey(requiredAttr) || attributes[requiredAttr] == null) {
        warnings.add(S57ValidationWarning(
          objectAcronym: objectClass.acronym,
          missingAttribute: requiredAttr,
          message: 'Missing required attribute $requiredAttr for ${objectClass.acronym} (${objectClass.name})',
        ));
      }
    }

    return warnings;
  }

  /// Get required attributes for an object class
  static List<String> getRequiredAttributes(String objectAcronym) {
    return _requiredAttributes[objectAcronym] ?? [];
  }

  /// Check if an attribute is required for an object class
  static bool isAttributeRequired(String objectAcronym, String attributeAcronym) {
    final required = _requiredAttributes[objectAcronym];
    return required?.contains(attributeAcronym) ?? false;
  }

  /// Get all object classes that have required attribute rules
  static List<String> getObjectClassesWithRequiredAttributes() {
    return _requiredAttributes.keys.toList();
  }
}