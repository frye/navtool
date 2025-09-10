/// S-57 to Maritime Feature Adapter
/// Converts S57Feature objects from the parser to MaritimeFeature objects for rendering
library;

import 'package:flutter/material.dart';
import '../models/chart_models.dart';
import '../services/s57/s57_models.dart';

/// Adapter that converts S57Features to MaritimeFeatures for chart rendering
class S57ToMaritimeAdapter {
  
  /// Convert a list of S57Features to MaritimeFeatures
  static List<MaritimeFeature> convertFeatures(List<S57Feature> s57Features) {
    final results = <MaritimeFeature>[];
    
    for (final s57 in s57Features) {
      final converted = _convertFeature(s57);
      if (converted != null) {
        results.add(converted);
      }
    }
    
    return results;
  }
  
  /// Convert a single S57Feature to MaritimeFeature
  static MaritimeFeature? _convertFeature(S57Feature s57) {
    try {
      return switch (s57.featureType) {
        // Depth and bathymetry features
        S57FeatureType.depthArea => _convertDepthArea(s57),
        S57FeatureType.sounding => _convertSounding(s57),
        S57FeatureType.depthContour => _convertDepthContour(s57),
        
        // Coastline and land features
        S57FeatureType.coastline => _convertCoastline(s57),
        S57FeatureType.shoreline => _convertCoastline(s57), // Alias
        S57FeatureType.landArea => _convertLandArea(s57),
        
        // Navigation aids
        S57FeatureType.lighthouse => _convertLighthouse(s57),
        S57FeatureType.buoy => _convertBuoy(s57),
        S57FeatureType.buoyLateral => _convertBuoy(s57),
        S57FeatureType.buoyCardinal => _convertBuoy(s57),
        S57FeatureType.buoyIsolatedDanger => _convertBuoy(s57),
        S57FeatureType.buoySpecialPurpose => _convertBuoy(s57),
        S57FeatureType.beacon => _convertBeacon(s57),
        S57FeatureType.daymark => _convertDaymark(s57),
        
        // Hazards and obstructions
        S57FeatureType.obstruction => _convertObstruction(s57),
        S57FeatureType.wreck => _convertWreck(s57),
        S57FeatureType.underwater => _convertUnderwater(s57),
        
        // Unknown or unsupported
        S57FeatureType.unknown => null,
      };
    } catch (e) {
      // Log conversion error but don't fail the entire conversion
      print('Warning: Failed to convert S57Feature ${s57.recordId} of type ${s57.featureType}: $e');
      return null;
    }
  }
  
  /// Convert depth area (DEPARE) to AreaFeature
  static AreaFeature _convertDepthArea(S57Feature s57) {
    final minDepth = s57.attributes['DRVAL1'] as double? ?? 0.0;
    final maxDepth = s57.attributes['DRVAL2'] as double? ?? minDepth;
    
    // Calculate center position from coordinates
    final position = _calculateCenterPosition(s57.coordinates);
    
    // Convert S57Coordinates to LatLng coordinates for area rings
    final rings = _convertToAreaRings(s57.coordinates);
    
    // Determine fill color based on depth
    final fillColor = _getDepthAreaColor(minDepth, maxDepth);
    
    return AreaFeature(
      id: 'depare_${s57.recordId}',
      type: MaritimeFeatureType.depthArea,
      position: position,
      coordinates: rings,
      fillColor: fillColor,
      strokeColor: fillColor.withOpacity(0.8),
      attributes: {
        'depth_min': minDepth,
        'depth_max': maxDepth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert sounding (SOUNDG) to PointFeature
  static PointFeature _convertSounding(S57Feature s57) {
    final depth = s57.attributes['VALSOU'] as double? ?? 0.0;
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    return PointFeature(
      id: 'sounding_${s57.recordId}',
      type: MaritimeFeatureType.soundings,
      position: position,
      label: _formatDepthLabel(depth),
      attributes: {
        'depth': depth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert depth contour (DEPCNT) to DepthContour (which extends LineFeature)
  static DepthContour _convertDepthContour(S57Feature s57) {
    final depth = s57.attributes['VALDCO'] as double? ?? 0.0;
    
    // Convert S57Coordinates to LatLng
    final coordinates = s57.coordinates
        .map((coord) => LatLng(coord.latitude, coord.longitude))
        .toList();
    
    return DepthContour(
      id: 'depthcontour_${s57.recordId}',
      coordinates: coordinates,
      depth: depth,
      attributes: {
        'depth': depth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert coastline (COALNE) to LineFeature
  static LineFeature _convertCoastline(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    // Convert S57Coordinates to LatLng
    final coordinates = s57.coordinates
        .map((coord) => LatLng(coord.latitude, coord.longitude))
        .toList();
    
    return LineFeature(
      id: 'coastline_${s57.recordId}',
      type: MaritimeFeatureType.shoreline,
      position: position,
      coordinates: coordinates,
      width: 2.0,
      attributes: {
        'category': _safeStringFromAttribute(s57.attributes['CATCOA']) ?? 'unknown',
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,  
        ...s57.attributes,
      },
    );
  }
  
  /// Convert land area (LNDARE) to AreaFeature  
  static AreaFeature _convertLandArea(S57Feature s57) {
    final position = _calculateCenterPosition(s57.coordinates);
    final rings = _convertToAreaRings(s57.coordinates);
    
    return AreaFeature(
      id: 'landarea_${s57.recordId}',
      type: MaritimeFeatureType.landArea,
      position: position,
      coordinates: rings,
      fillColor: const Color(0xFFF5F5DC), // Beige for land
      strokeColor: Colors.black,
      attributes: {
        'category': _safeStringFromAttribute(s57.attributes['CATLND']) ?? 'unknown',
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert lighthouse (LIGHTS) to PointFeature
  static PointFeature _convertLighthouse(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    // Handle potential type conversion errors gracefully
    final character = _safeStringFromAttribute(s57.attributes['LITCHR']) ?? 'F';
    final range = (s57.attributes['VALNMR'] is double) 
        ? s57.attributes['VALNMR'] as double
        : (s57.attributes['VALNMR'] is int)
            ? (s57.attributes['VALNMR'] as int).toDouble()
            : 10.0; // Default value
    final color = _safeStringFromAttribute(s57.attributes['COLOUR']) ?? 'white';
    
    return PointFeature(
      id: 'lighthouse_${s57.recordId}',
      type: MaritimeFeatureType.lighthouse,
      position: position,
      label: s57.label ?? _generateLighthouseLabel(character, range),
      attributes: {
        'character': character,
        'range': range,
        'color': color,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert buoy (BOYLAT, BOYCAR, etc.) to PointFeature
  static PointFeature _convertBuoy(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    // Handle potential type conversions gracefully
    final shape = _safeStringFromAttribute(s57.attributes['BOYSHP']) ?? 'cylindrical';
    final color = _safeStringFromAttribute(s57.attributes['COLOUR']) ?? 'red';
    final category = _safeStringFromAttribute(s57.attributes['CATBOY']) ?? 'lateral';
    
    return PointFeature(
      id: 'buoy_${s57.recordId}',
      type: MaritimeFeatureType.buoy,
      position: position,
      label: s57.label ?? _generateBuoyLabel(category, color),
      attributes: {
        'buoyShape': shape,
        'color': color,
        'category': category,
        'topmark': _safeStringFromAttribute(s57.attributes['TOPMAR']),
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert beacon (BCNCAR) to PointFeature
  static PointFeature _convertBeacon(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    final category = _safeStringFromAttribute(s57.attributes['CATBCN']) ?? 'unknown';
    final color = _safeStringFromAttribute(s57.attributes['COLOUR']) ?? 'black';
    
    return PointFeature(
      id: 'beacon_${s57.recordId}',
      type: MaritimeFeatureType.beacon,
      position: position,
      label: s57.label ?? _generateBeaconLabel(category),
      attributes: {
        'category': category,
        'color': color,
        'topmark': _safeStringFromAttribute(s57.attributes['TOPMAR']),
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert daymark (DAYMAR) to PointFeature
  static PointFeature _convertDaymark(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    final category = _safeStringFromAttribute(s57.attributes['CATDAM']) ?? 'unknown';
    final color = _safeStringFromAttribute(s57.attributes['COLOUR']) ?? 'white';
    
    return PointFeature(
      id: 'daymark_${s57.recordId}',
      type: MaritimeFeatureType.daymark,
      position: position,
      label: s57.label ?? 'Daymark',
      attributes: {
        'category': category,
        'color': color,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert obstruction (OBSTRN) to PointFeature
  static PointFeature _convertObstruction(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    final category = _safeStringFromAttribute(s57.attributes['CATOBS']) ?? 'unknown';
    final depth = s57.attributes['VALSOU'] as double?;
    
    return PointFeature(
      id: 'obstruction_${s57.recordId}',
      type: MaritimeFeatureType.obstruction,
      position: position,
      label: s57.label ?? _generateObstructionLabel(category, depth),
      attributes: {
        'category': category,
        'depth': depth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert wreck (WRECKS) to PointFeature
  static PointFeature _convertWreck(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    final category = _safeStringFromAttribute(s57.attributes['CATWRK']) ?? 'unknown';
    final depth = s57.attributes['VALSOU'] as double?;
    
    return PointFeature(
      id: 'wreck_${s57.recordId}',
      type: MaritimeFeatureType.wrecks,
      position: position,
      label: s57.label ?? _generateWreckLabel(category, depth),
      attributes: {
        'category': category,
        'depth': depth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  /// Convert underwater rock (UWTROC) to PointFeature
  static PointFeature _convertUnderwater(S57Feature s57) {
    final position = s57.coordinates.isNotEmpty 
        ? LatLng(s57.coordinates.first.latitude, s57.coordinates.first.longitude)
        : const LatLng(0, 0);
    
    final depth = s57.attributes['VALSOU'] as double?;
    
    return PointFeature(
      id: 'underwater_${s57.recordId}',
      type: MaritimeFeatureType.rocks,
      position: position,
      label: s57.label ?? _generateRockLabel(depth),
      attributes: {
        'depth': depth,
        'original_s57_code': s57.featureType.code,
        'original_s57_acronym': s57.featureType.acronym,
        ...s57.attributes,
      },
    );
  }
  
  // ===== Helper Methods =====
  
  /// Calculate center position from a list of coordinates
  static LatLng _calculateCenterPosition(List<S57Coordinate> coordinates) {
    if (coordinates.isEmpty) return const LatLng(0, 0);
    if (coordinates.length == 1) {
      return LatLng(coordinates.first.latitude, coordinates.first.longitude);
    }
    
    double totalLat = 0;
    double totalLng = 0;
    
    for (final coord in coordinates) {
      totalLat += coord.latitude;
      totalLng += coord.longitude;
    }
    
    return LatLng(totalLat / coordinates.length, totalLng / coordinates.length);
  }
  
  /// Convert S57 coordinates to area rings for AreaFeature
  static List<List<LatLng>> _convertToAreaRings(List<S57Coordinate> coordinates) {
    if (coordinates.isEmpty) return [];
    
    // For now, assume single ring (outer boundary)
    // TODO: Handle multiple rings for areas with holes
    final ring = coordinates
        .map((coord) => LatLng(coord.latitude, coord.longitude))
        .toList();
    
    return [ring];
  }
  
  /// Get appropriate color for depth area based on depth range
  static Color _getDepthAreaColor(double minDepth, double maxDepth) {
    final avgDepth = (minDepth + maxDepth) / 2;
    
    if (avgDepth < 2) {
      return Colors.red.withOpacity(0.3); // Very shallow - danger
    } else if (avgDepth < 5) {
      return Colors.orange.withOpacity(0.3); // Shallow
    } else if (avgDepth < 10) {
      return Colors.yellow.withOpacity(0.3); // Moderate shallow
    } else if (avgDepth < 20) {
      return Colors.lightBlue.withOpacity(0.3); // Moderate depth
    } else {
      return Colors.blue.withOpacity(0.3); // Deep water
    }
  }
  
  /// Format depth value for display
  static String _formatDepthLabel(double depth) {
    if (depth == depth.roundToDouble()) {
      return '${depth.round()}m';
    } else {
      return '${depth.toStringAsFixed(1)}m';
    }
  }
  
  /// Generate lighthouse label from characteristics
  static String _generateLighthouseLabel(String character, double range) {
    return 'Lt $character ${range.round()}M';
  }
  
  /// Generate buoy label from attributes
  static String _generateBuoyLabel(String category, String color) {
    final categoryShort = switch (category.toLowerCase()) {
      'port' => 'P',
      'starboard' => 'S', 
      'cardinal' => 'Card',
      'isolated_danger' => 'ID',
      'special_purpose' => 'SP',
      _ => category,
    };
    return '$categoryShort $color';
  }
  
  /// Generate beacon label
  static String _generateBeaconLabel(String category) {
    return switch (category.toLowerCase()) {
      'north' => 'N Card Bcn',
      'south' => 'S Card Bcn',
      'east' => 'E Card Bcn',
      'west' => 'W Card Bcn',
      _ => 'Beacon',
    };
  }
  
  /// Generate obstruction label
  static String _generateObstructionLabel(String category, double? depth) {
    final depthStr = depth != null ? ' ${_formatDepthLabel(depth)}' : '';
    return 'Obstr$depthStr';
  }
  
  /// Generate wreck label
  static String _generateWreckLabel(String category, double? depth) {
    final depthStr = depth != null ? ' ${_formatDepthLabel(depth)}' : '';
    return 'Wreck$depthStr';
  }
  
  /// Generate rock label
  static String _generateRockLabel(double? depth) {
    final depthStr = depth != null ? ' ${_formatDepthLabel(depth)}' : '';
    return 'Rock$depthStr';
  }
  
  /// Safely convert attribute to string, handling various data types
  static String? _safeStringFromAttribute(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double) return value.toString();
    return value.toString();
  }
}