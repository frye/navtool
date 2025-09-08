/// S-52 Symbol Catalog
/// 
/// Implements IHO S-52 standard symbols for marine chart display
/// Maps S-57 feature types to standardized S-52 presentation symbols
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/models/chart_models.dart';
import 's52_color_tables.dart';

/// S-52 Symbol Catalog for marine chart symbology
class S52SymbolCatalog {
  static final Map<String, S52SymbolDefinition> _symbolsByCode = {};
  static final Map<MaritimeFeatureType, List<S52SymbolDefinition>> _symbolsByFeatureType = {};
  
  /// Initialize the symbol catalog with standard S-52 symbols
  static void initialize() {
    if (_symbolsByCode.isNotEmpty) return; // Already initialized
    
    _registerStandardSymbols();
    _buildFeatureTypeIndex();
  }

  /// Get symbol definition by S-52 symbol code
  static S52SymbolDefinition? getSymbolByCode(String code) {
    initialize();
    return _symbolsByCode[code];
  }

  /// Get symbol definitions for maritime feature type
  static List<S52SymbolDefinition> getSymbolsForFeatureType(MaritimeFeatureType type) {
    initialize();
    return _symbolsByFeatureType[type] ?? [];
  }

  /// Get best symbol for feature based on attributes
  static S52SymbolDefinition? getBestSymbolForFeature(
    MaritimeFeatureType type,
    Map<String, dynamic> attributes,
  ) {
    final symbols = getSymbolsForFeatureType(type);
    if (symbols.isEmpty) return null;

    // For now, return first match - can be enhanced with attribute matching
    return symbols.first;
  }

  /// Register standard S-52 symbols
  static void _registerStandardSymbols() {
    // Navigation Aid Symbols
    _registerSymbol(S52SymbolDefinition(
      code: 'LIGHTS1',
      name: 'Light - Major',
      featureTypes: [MaritimeFeatureType.lighthouse],
      minScale: 0,
      maxScale: double.infinity,
      symbolType: S52SymbolType.point,
      renderFunction: _renderLighthouseSymbol,
      colorTokens: [S52ColorToken.lights, S52ColorToken.chblk],
    ));

    _registerSymbol(S52SymbolDefinition(
      code: 'BEACON1',
      name: 'Beacon - Cardinal North',
      featureTypes: [MaritimeFeatureType.beacon],
      minScale: 0,
      maxScale: 100000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderBeaconSymbol,
      colorTokens: [S52ColorToken.beacons, S52ColorToken.chblk],
    ));

    _registerSymbol(S52SymbolDefinition(
      code: 'BUOY1',
      name: 'Lateral Buoy - Port',
      featureTypes: [MaritimeFeatureType.buoy],
      minScale: 0,
      maxScale: 50000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderBuoySymbol,
      colorTokens: [S52ColorToken.buoys, S52ColorToken.chred],
      attributes: {'CATBOY': '2', 'COLOUR': '3'}, // Port hand, green
    ));

    _registerSymbol(S52SymbolDefinition(
      code: 'BUOY2',
      name: 'Lateral Buoy - Starboard',
      featureTypes: [MaritimeFeatureType.buoy],
      minScale: 0,
      maxScale: 50000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderBuoySymbol,
      colorTokens: [S52ColorToken.buoys, S52ColorToken.chred],
      attributes: {'CATBOY': '1', 'COLOUR': '4'}, // Starboard hand, red
    ));

    _registerSymbol(S52SymbolDefinition(
      code: 'BUOY3',
      name: 'Cardinal Buoy - North',
      featureTypes: [MaritimeFeatureType.buoy],
      minScale: 0,
      maxScale: 50000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderCardinalBuoySymbol,
      colorTokens: [S52ColorToken.buoys, S52ColorToken.chblk, S52ColorToken.chylw],
      attributes: {'CATBOY': '2'}, // Cardinal
    ));

    // Danger and Obstruction Symbols
    _registerSymbol(S52SymbolDefinition(
      code: 'OBSTRN1',
      name: 'Obstruction',
      featureTypes: [MaritimeFeatureType.obstruction],
      minScale: 0,
      maxScale: 100000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderObstructionSymbol,
      colorTokens: [S52ColorToken.obstruction, S52ColorToken.danger],
    ));

    _registerSymbol(S52SymbolDefinition(
      code: 'WRECKS1',
      name: 'Wreck - Dangerous',
      featureTypes: [MaritimeFeatureType.wrecks],
      minScale: 0,
      maxScale: 100000,
      symbolType: S52SymbolType.point,
      renderFunction: _renderWreckSymbol,
      colorTokens: [S52ColorToken.wrecks, S52ColorToken.danger],
    ));
  }

  /// Register a symbol definition
  static void _registerSymbol(S52SymbolDefinition symbol) {
    _symbolsByCode[symbol.code] = symbol;
  }

  /// Build index by feature type
  static void _buildFeatureTypeIndex() {
    for (final symbol in _symbolsByCode.values) {
      for (final featureType in symbol.featureTypes) {
        _symbolsByFeatureType.putIfAbsent(featureType, () => []).add(symbol);
      }
    }
  }

  // Symbol rendering functions
  static void _renderLighthouseSymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    final paint = Paint()
      ..color = colorTable.getColor(S52ColorToken.lights)
      ..style = PaintingStyle.fill;

    // Draw lighthouse base (circle)
    canvas.drawCircle(position, size * 0.4, paint);

    // Draw lighthouse tower (rectangle)
    final towerRect = Rect.fromCenter(
      center: position.translate(0, -size * 0.3),
      width: size * 0.3,
      height: size * 0.6,
    );
    canvas.drawRect(towerRect, paint);

    // Draw light beam indicators
    final beamPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chylw).withAlpha(150)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      final angle = (i * 45) * (3.14159 / 180);
      final beamEnd = position + Offset(
        (size * 0.8) * cos(angle),
        (size * 0.8) * sin(angle),
      );
      canvas.drawLine(position, beamEnd, beamPaint..strokeWidth = 2);
    }
  }

  static void _renderBeaconSymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    final paint = Paint()
      ..color = colorTable.getColor(S52ColorToken.beacons)
      ..style = PaintingStyle.fill;

    // Draw beacon base
    canvas.drawCircle(position, size * 0.3, paint);

    // Draw beacon structure (triangle)
    final path = Path();
    path.moveTo(position.dx, position.dy - size * 0.6);
    path.lineTo(position.dx - size * 0.25, position.dy + size * 0.3);
    path.lineTo(position.dx + size * 0.25, position.dy + size * 0.3);
    path.close();

    canvas.drawPath(path, paint);

    // Draw topmark based on cardinal direction
    final topmarkPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chblk)
      ..style = PaintingStyle.fill;

    // North cardinal - two cones pointing up
    final topmark1 = Path();
    topmark1.moveTo(position.dx, position.dy - size * 0.8);
    topmark1.lineTo(position.dx - size * 0.1, position.dy - size * 0.6);
    topmark1.lineTo(position.dx + size * 0.1, position.dy - size * 0.6);
    topmark1.close();

    canvas.drawPath(topmark1, topmarkPaint);
  }

  static void _renderBuoySymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    // Determine buoy color from attributes
    final colorValue = attributes['COLOUR'] as String?;
    final isPortHand = colorValue == '3'; // Green = port hand
    
    final paint = Paint()
      ..color = isPortHand 
          ? colorTable.getColor(S52ColorToken.chgrn)
          : colorTable.getColor(S52ColorToken.chred)
      ..style = PaintingStyle.fill;

    // Draw buoy body (cylinder)
    canvas.drawCircle(position, size * 0.4, paint);

    // Draw waterline
    final waterPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.depare2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawLine(
      position.translate(-size * 0.5, size * 0.2),
      position.translate(size * 0.5, size * 0.2),
      waterPaint,
    );

    // Draw topmark (if lateral)
    if (attributes['CATBOY'] == '1' || attributes['CATBOY'] == '2') {
      final topmarkPaint = Paint()
        ..color = colorTable.getColor(S52ColorToken.chblk)
        ..style = PaintingStyle.fill;

      if (isPortHand) {
        // Cylindrical topmark
        canvas.drawRect(
          Rect.fromCenter(
            center: position.translate(0, -size * 0.5),
            width: size * 0.2,
            height: size * 0.3,
          ),
          topmarkPaint,
        );
      } else {
        // Conical topmark
        final topmark = Path();
        topmark.moveTo(position.dx, position.dy - size * 0.7);
        topmark.lineTo(position.dx - size * 0.1, position.dy - size * 0.4);
        topmark.lineTo(position.dx + size * 0.1, position.dy - size * 0.4);
        topmark.close();
        canvas.drawPath(topmark, topmarkPaint);
      }
    }
  }

  static void _renderCardinalBuoySymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    // Cardinal buoys are black and yellow
    final paint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chblk)
      ..style = PaintingStyle.fill;

    // Draw lower half (black)
    final lowerPath = Path();
    lowerPath.addArc(
      Rect.fromCenter(center: position, width: size * 0.8, height: size * 0.8),
      0, 
      3.14159, // π radians (180 degrees)
    );
    lowerPath.close();
    canvas.drawPath(lowerPath, paint);

    // Draw upper half (yellow)
    final yellowPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chylw)
      ..style = PaintingStyle.fill;

    final upperPath = Path();
    upperPath.addArc(
      Rect.fromCenter(center: position, width: size * 0.8, height: size * 0.8),
      3.14159, // π radians
      3.14159, // π radians (180 degrees)
    );
    upperPath.close();
    canvas.drawPath(upperPath, yellowPaint);

    // Draw cardinal topmarks (two cones pointing up for North)
    final topmarkPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chblk)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 2; i++) {
      final yOffset = -size * (0.6 + i * 0.15);
      final topmark = Path();
      topmark.moveTo(position.dx, position.dy + yOffset - size * 0.1);
      topmark.lineTo(position.dx - size * 0.08, position.dy + yOffset + size * 0.05);
      topmark.lineTo(position.dx + size * 0.08, position.dy + yOffset + size * 0.05);
      topmark.close();
      canvas.drawPath(topmark, topmarkPaint);
    }
  }

  static void _renderObstructionSymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    final paint = Paint()
      ..color = colorTable.getColor(S52ColorToken.obstruction)
      ..style = PaintingStyle.fill;

    // Draw obstruction as cross
    final strokePaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.danger)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Horizontal line
    canvas.drawLine(
      position.translate(-size * 0.4, 0),
      position.translate(size * 0.4, 0),
      strokePaint,
    );

    // Vertical line
    canvas.drawLine(
      position.translate(0, -size * 0.4),
      position.translate(0, size * 0.4),
      strokePaint,
    );

    // Center dot
    canvas.drawCircle(position, size * 0.1, paint);
  }

  static void _renderWreckSymbol(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) {
    final paint = Paint()
      ..color = colorTable.getColor(S52ColorToken.wrecks)
      ..style = PaintingStyle.fill;

    // Draw hull outline
    final hull = Path();
    hull.moveTo(position.dx - size * 0.4, position.dy);
    hull.quadraticBezierTo(
      position.dx - size * 0.3, position.dy - size * 0.2,
      position.dx, position.dy - size * 0.1,
    );
    hull.quadraticBezierTo(
      position.dx + size * 0.3, position.dy - size * 0.2,
      position.dx + size * 0.4, position.dy,
    );
    hull.lineTo(position.dx + size * 0.3, position.dy + size * 0.2);
    hull.lineTo(position.dx - size * 0.3, position.dy + size * 0.2);
    hull.close();

    canvas.drawPath(hull, paint);

    // Draw masts (broken)
    final mastPaint = Paint()
      ..color = colorTable.getColor(S52ColorToken.chblk)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Broken mast
    canvas.drawLine(
      position.translate(-size * 0.2, -size * 0.1),
      position.translate(-size * 0.15, -size * 0.35),
      mastPaint,
    );
    
    canvas.drawLine(
      position.translate(-size * 0.1, -size * 0.3),
      position.translate(size * 0.1, -size * 0.2),
      mastPaint,
    );
  }
}

/// S-52 Symbol Definition
class S52SymbolDefinition {
  final String code;
  final String name;
  final List<MaritimeFeatureType> featureTypes;
  final double minScale;
  final double maxScale;
  final S52SymbolType symbolType;
  final List<S52ColorToken> colorTokens;
  final Map<String, String> attributes;
  final void Function(
    Canvas canvas,
    Offset position,
    double size,
    S52ColorTable colorTable,
    Map<String, dynamic> attributes,
  ) renderFunction;

  const S52SymbolDefinition({
    required this.code,
    required this.name,
    required this.featureTypes,
    required this.minScale,
    required this.maxScale,
    required this.symbolType,
    required this.renderFunction,
    this.colorTokens = const [],
    this.attributes = const {},
  });

  /// Check if symbol is visible at given scale
  bool isVisibleAtScale(double scale) {
    return scale >= minScale && scale <= maxScale;
  }

  /// Check if symbol matches feature attributes
  bool matchesAttributes(Map<String, dynamic> featureAttributes) {
    for (final entry in attributes.entries) {
      final featureValue = featureAttributes[entry.key]?.toString();
      if (featureValue != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// Types of S-52 symbols
enum S52SymbolType {
  /// Point symbol (e.g., lighthouse, buoy)
  point,
  
  /// Line symbol (e.g., cable, pipeline)  
  line,
  
  /// Area symbol (e.g., anchorage, restricted area)
  area,
  
  /// Text symbol
  text,
}

// Helper functions for symbol rendering
double cos(double radians) => math.cos(radians);
double sin(double radians) => math.sin(radians);