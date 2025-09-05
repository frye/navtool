/// S-57 Object Catalog models and services
/// 
/// Provides authoritative S-57 object class and attribute definitions
/// based on IHO S-57 Object Catalogue Edition 3.1

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// S-57 attribute data types
enum S57AttrType {
  float,
  int,
  string,
  enumType,
}

/// S-57 object class definition
class S57ObjectClass {
  final int code;
  final String acronym;
  final String name;

  const S57ObjectClass({
    required this.code,
    required this.acronym,
    required this.name,
  });

  factory S57ObjectClass.fromJson(Map<String, dynamic> json) {
    return S57ObjectClass(
      code: json['code'] as int,
      acronym: json['acronym'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'acronym': acronym,
      'name': name,
    };
  }

  @override
  String toString() => 'S57ObjectClass(code: $code, acronym: $acronym, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is S57ObjectClass &&
           other.code == code &&
           other.acronym == acronym &&
           other.name == name;
  }

  @override
  int get hashCode => Object.hash(code, acronym, name);
}

/// S-57 attribute definition
class S57AttributeDef {
  final String acronym;
  final S57AttrType type;
  final String name;
  final Map<String, String>? domain;

  const S57AttributeDef({
    required this.acronym,
    required this.type,
    required this.name,
    this.domain,
  });

  factory S57AttributeDef.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = switch (typeStr) {
      'float' => S57AttrType.float,
      'int' => S57AttrType.int,
      'string' => S57AttrType.string,
      'enum' => S57AttrType.enumType,
      _ => throw ArgumentError('Unknown attribute type: $typeStr'),
    };

    Map<String, String>? domain;
    if (json['domain'] != null) {
      final domainJson = json['domain'] as Map<String, dynamic>;
      domain = domainJson.map((k, v) => MapEntry(k, v.toString()));
    }

    return S57AttributeDef(
      acronym: json['acronym'] as String,
      type: type,
      name: json['name'] as String,
      domain: domain,
    );
  }

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      S57AttrType.float => 'float',
      S57AttrType.int => 'int',
      S57AttrType.string => 'string',
      S57AttrType.enumType => 'enum',
    };

    return {
      'acronym': acronym,
      'type': typeStr,
      'name': name,
      if (domain != null) 'domain': domain,
    };
  }

  @override
  String toString() => 'S57AttributeDef(acronym: $acronym, type: $type, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is S57AttributeDef &&
           other.acronym == acronym &&
           other.type == type &&
           other.name == name &&
           _mapEquals(other.domain, domain);
  }

  @override
  int get hashCode => Object.hash(acronym, type, name, domain);

  bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

/// S-57 Object Catalog service
/// 
/// Provides lookup functionality for official S-57 object classes and attributes
/// with fallback handling for unknown codes/acronyms
class S57ObjectCatalog {
  final Map<int, S57ObjectClass> _byCode;
  final Map<String, S57ObjectClass> _byAcronym;
  final Set<int> _warnedUnknownCodes = <int>{};
  final Set<String> _warnedUnknownAcronyms = <String>{};

  S57ObjectCatalog._(this._byCode, this._byAcronym);

  /// Load catalog from asset files
  static Future<S57ObjectCatalog> loadFromAssets() async {
    final objectClassesJson = await rootBundle.loadString('assets/s57/object_classes.json');
    final objectClassesData = jsonDecode(objectClassesJson) as List<dynamic>;
    
    final byCode = <int, S57ObjectClass>{};
    final byAcronym = <String, S57ObjectClass>{};
    
    for (final item in objectClassesData) {
      final objectClass = S57ObjectClass.fromJson(item as Map<String, dynamic>);
      byCode[objectClass.code] = objectClass;
      byAcronym[objectClass.acronym.toUpperCase()] = objectClass;
    }
    
    return S57ObjectCatalog._(byCode, byAcronym);
  }

  /// Create catalog from object classes (for testing)
  factory S57ObjectCatalog.fromObjectClasses(List<S57ObjectClass> objectClasses) {
    final byCode = <int, S57ObjectClass>{};
    final byAcronym = <String, S57ObjectClass>{};
    
    for (final objectClass in objectClasses) {
      byCode[objectClass.code] = objectClass;
      byAcronym[objectClass.acronym.toUpperCase()] = objectClass;
    }
    
    return S57ObjectCatalog._(byCode, byAcronym);
  }

  /// Lookup object class by code
  S57ObjectClass? byCode(int code) {
    final result = _byCode[code];
    if (result == null && !_warnedUnknownCodes.contains(code)) {
      _warnedUnknownCodes.add(code);
      print('Warning: Unknown S-57 object code: $code');
    }
    return result;
  }

  /// Lookup object class by acronym
  S57ObjectClass? byAcronym(String acronym) {
    final upperAcronym = acronym.toUpperCase();
    final result = _byAcronym[upperAcronym];
    if (result == null && !_warnedUnknownAcronyms.contains(upperAcronym)) {
      _warnedUnknownAcronyms.add(upperAcronym);
      print('Warning: Unknown S-57 object acronym: $acronym');
    }
    return result;
  }

  /// Get all object classes
  List<S57ObjectClass> get allObjectClasses => _byCode.values.toList();

  /// Get number of object classes in catalog
  int get size => _byCode.length;
}

/// S-57 Attribute Catalog service
/// 
/// Provides lookup functionality for S-57 attribute definitions
/// with type coercion and enum domain mapping
class S57AttributeCatalog {
  final Map<String, S57AttributeDef> _byAcronym;
  final Set<String> _warnedUnknownAttributes = <String>{};

  S57AttributeCatalog._(this._byAcronym);

  /// Load catalog from asset files
  static Future<S57AttributeCatalog> loadFromAssets() async {
    final attributesJson = await rootBundle.loadString('assets/s57/attributes.json');
    final attributesData = jsonDecode(attributesJson) as List<dynamic>;
    
    final byAcronym = <String, S57AttributeDef>{};
    
    for (final item in attributesData) {
      final attrDef = S57AttributeDef.fromJson(item as Map<String, dynamic>);
      byAcronym[attrDef.acronym.toUpperCase()] = attrDef;
    }
    
    return S57AttributeCatalog._(byAcronym);
  }

  /// Create catalog from attribute definitions (for testing)
  factory S57AttributeCatalog.fromAttributeDefs(List<S57AttributeDef> attributeDefs) {
    final byAcronym = <String, S57AttributeDef>{};
    
    for (final attrDef in attributeDefs) {
      byAcronym[attrDef.acronym.toUpperCase()] = attrDef;
    }
    
    return S57AttributeCatalog._(byAcronym);
  }

  /// Lookup attribute definition by acronym
  S57AttributeDef? byAcronym(String acronym) {
    final upperAcronym = acronym.toUpperCase();
    final result = _byAcronym[upperAcronym];
    if (result == null && !_warnedUnknownAttributes.contains(upperAcronym)) {
      _warnedUnknownAttributes.add(upperAcronym);
      print('Warning: Unknown S-57 attribute acronym: $acronym');
    }
    return result;
  }

  /// Get all attribute definitions
  List<S57AttributeDef> get allAttributeDefs => _byAcronym.values.toList();

  /// Get number of attribute definitions in catalog
  int get size => _byAcronym.length;

  /// Decode attribute value based on definition
  Object? decodeAttribute(S57AttributeDef? def, List<String> rawValues) {
    if (def == null) {
      // Unknown attribute - pass through as-is
      return rawValues.length == 1 ? rawValues.first : rawValues;
    }

    if (rawValues.isEmpty) return null;

    switch (def.type) {
      case S57AttrType.float:
        return double.tryParse(rawValues.first);
      case S57AttrType.int:
        return int.tryParse(rawValues.first);
      case S57AttrType.string:
        return rawValues.first.trim();
      case S57AttrType.enumType:
        final code = rawValues.first.trim();
        final label = def.domain?[code];
        return {
          'code': code,
          if (label != null) 'label': label,
        };
    }
  }
}