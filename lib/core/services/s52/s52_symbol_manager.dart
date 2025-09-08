/// S-52 Symbol Asset Management System
/// 
/// Manages loading, caching, and rendering of S-52 compliant maritime symbols
/// Provides efficient symbol lookup and rendering with scale-dependent optimization
library;

import 'package:flutter/material.dart';
import '../../../core/models/chart_models.dart';
import 's52_color_tables.dart';
import 's52_symbol_catalog.dart';

/// S-52 Symbol Manager for efficient symbol asset management
class S52SymbolManager {
  static S52SymbolManager? _instance;
  
  final Map<String, Widget> _symbolCache = {};
  final Map<String, CustomPainter> _painterCache = {};
  S52DisplayMode _currentDisplayMode = S52DisplayMode.day;
  double _currentScale = 50000; // Default coastal scale

  S52SymbolManager._();

  /// Get singleton instance
  static S52SymbolManager get instance {
    _instance ??= S52SymbolManager._();
    return _instance!;
  }

  /// Initialize the symbol manager
  Future<void> initialize() async {
    S52SymbolCatalog.initialize();
    await _preloadCommonSymbols();
  }

  /// Set current display mode
  void setDisplayMode(S52DisplayMode mode) {
    if (_currentDisplayMode != mode) {
      _currentDisplayMode = mode;
      _clearPainterCache(); // Colors changed, invalidate painters
    }
  }

  /// Set current chart scale
  void setScale(double scale) {
    _currentScale = scale;
  }

  /// Get symbol widget for maritime feature
  Widget? getSymbolWidget(
    MaritimeFeature feature,
    double size, {
    S52DisplayMode? displayMode,
  }) {
    final mode = displayMode ?? _currentDisplayMode;
    final cacheKey = '${feature.type.name}_${feature.id}_${size}_${mode.name}';
    
    if (_symbolCache.containsKey(cacheKey)) {
      return _symbolCache[cacheKey];
    }

    final symbolDef = S52SymbolCatalog.getBestSymbolForFeature(
      feature.type,
      feature.attributes,
    );

    if (symbolDef == null) return null;

    final widget = _createSymbolWidget(symbolDef, feature, size, mode);
    _symbolCache[cacheKey] = widget;
    
    return widget;
  }

  /// Get symbol painter for direct canvas rendering
  CustomPainter? getSymbolPainter(
    MaritimeFeature feature,
    double size, {
    S52DisplayMode? displayMode,
  }) {
    final mode = displayMode ?? _currentDisplayMode;
    final cacheKey = '${feature.type.name}_${feature.id}_${size}_${mode.name}_painter';
    
    if (_painterCache.containsKey(cacheKey)) {
      return _painterCache[cacheKey];
    }

    final symbolDef = S52SymbolCatalog.getBestSymbolForFeature(
      feature.type,
      feature.attributes,
    );

    if (symbolDef == null) return null;

    final painter = S52SymbolPainter(
      symbolDefinition: symbolDef,
      feature: feature,
      size: size,
      colorTable: S52ColorTables.getColorTable(mode),
    );
    
    _painterCache[cacheKey] = painter;
    return painter;
  }

  /// Render symbol directly to canvas
  void renderSymbolToCanvas(
    Canvas canvas,
    Offset position,
    MaritimeFeature feature,
    double size, {
    S52DisplayMode? displayMode,
  }) {
    final mode = displayMode ?? _currentDisplayMode;
    final symbolDef = S52SymbolCatalog.getBestSymbolForFeature(
      feature.type,
      feature.attributes,
    );

    if (symbolDef == null) return;

    // Check scale visibility
    if (!symbolDef.isVisibleAtScale(_currentScale)) return;

    final colorTable = S52ColorTables.getColorTable(mode);
    symbolDef.renderFunction(
      canvas,
      position,
      size,
      colorTable,
      feature.attributes,
    );
  }

  /// Get symbols visible at current scale
  List<S52SymbolDefinition> getVisibleSymbols() {
    // Access symbols through public getter
    S52SymbolCatalog.initialize();
    final allSymbols = <S52SymbolDefinition>[];
    
    // Get all symbols by feature type (this is a workaround for private access)
    for (final featureType in MaritimeFeatureType.values) {
      allSymbols.addAll(S52SymbolCatalog.getSymbolsForFeatureType(featureType));
    }
    
    return allSymbols
        .where((symbol) => symbol.isVisibleAtScale(_currentScale))
        .toSet() // Remove duplicates
        .toList();
  }

  /// Preload commonly used symbols
  Future<void> _preloadCommonSymbols() async {
    final commonFeatureTypes = [
      MaritimeFeatureType.lighthouse,
      MaritimeFeatureType.beacon,
      MaritimeFeatureType.buoy,
      MaritimeFeatureType.obstruction,
      MaritimeFeatureType.wrecks,
    ];

    for (final featureType in commonFeatureTypes) {
      for (final mode in S52DisplayMode.values) {
        // Create sample features for preloading
        final sampleFeature = PointFeature(
          id: 'sample_${featureType.name}',
          type: featureType,
          position: const LatLng(0, 0),
          attributes: _getDefaultAttributesForFeatureType(featureType),
        );

        // Preload standard sizes
        for (final size in [12.0, 16.0, 24.0, 32.0]) {
          getSymbolWidget(sampleFeature, size, displayMode: mode);
          getSymbolPainter(sampleFeature, size, displayMode: mode);
        }
      }
    }
  }

  /// Get default attributes for feature type (for preloading)
  Map<String, dynamic> _getDefaultAttributesForFeatureType(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.buoy => {'CATBOY': '1', 'COLOUR': '3'}, // Port lateral
      MaritimeFeatureType.beacon => {'CATCRD': '1'}, // North cardinal
      _ => <String, dynamic>{},
    };
  }

  /// Create symbol widget from definition
  Widget _createSymbolWidget(
    S52SymbolDefinition symbolDef,
    MaritimeFeature feature,
    double size,
    S52DisplayMode mode,
  ) {
    return CustomPaint(
      size: Size(size * 2, size * 2), // Allow for symbol overhang
      painter: S52SymbolPainter(
        symbolDefinition: symbolDef,
        feature: feature,
        size: size,
        colorTable: S52ColorTables.getColorTable(mode),
      ),
    );
  }

  /// Clear painter cache (when colors change)
  void _clearPainterCache() {
    _painterCache.clear();
  }

  /// Clear all caches
  void clearCache() {
    _symbolCache.clear();
    _painterCache.clear();
  }

  /// Get cache statistics
  Map<String, int> getCacheStats() {
    return {
      'symbolWidgets': _symbolCache.length,
      'painters': _painterCache.length,
      'totalCached': _symbolCache.length + _painterCache.length,
    };
  }

  /// Optimize cache by removing least recently used symbols
  void optimizeCache({int maxSymbols = 500, int maxPainters = 200}) {
    // Simple implementation: clear cache if it gets too large
    // More sophisticated LRU implementation could be added later
    if (_symbolCache.length > maxSymbols) {
      final keysToRemove = _symbolCache.keys.take(_symbolCache.length - maxSymbols).toList();
      for (final key in keysToRemove) {
        _symbolCache.remove(key);
      }
    }

    if (_painterCache.length > maxPainters) {
      final keysToRemove = _painterCache.keys.take(_painterCache.length - maxPainters).toList();
      for (final key in keysToRemove) {
        _painterCache.remove(key);
      }
    }
  }
}

/// Custom painter for S-52 symbols
class S52SymbolPainter extends CustomPainter {
  final S52SymbolDefinition symbolDefinition;
  final MaritimeFeature feature;
  final double size;
  final S52ColorTable colorTable;

  const S52SymbolPainter({
    required this.symbolDefinition,
    required this.feature,
    required this.size,
    required this.colorTable,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    
    // Render the symbol centered in the canvas
    symbolDefinition.renderFunction(
      canvas,
      center,
      size,
      colorTable,
      feature.attributes,
    );
  }

  @override
  bool shouldRepaint(S52SymbolPainter oldDelegate) {
    return symbolDefinition != oldDelegate.symbolDefinition ||
           feature != oldDelegate.feature ||
           size != oldDelegate.size ||
           colorTable != oldDelegate.colorTable;
  }

  @override
  bool hitTest(Offset position) {
    // Simple circular hit test
    final center = Offset(size, size);
    final distance = (position - center).distance;
    return distance <= size;
  }
}

/// Symbol rendering context with scale and visibility information
class S52RenderingContext {
  final S52DisplayMode displayMode;
  final double scale;
  final double zoom;
  final bool showLabels;
  final Set<MaritimeFeatureType> visibleLayers;

  const S52RenderingContext({
    required this.displayMode,
    required this.scale,
    required this.zoom,
    this.showLabels = true,
    this.visibleLayers = const {},
  });

  /// Check if feature type should be rendered
  bool shouldRenderFeatureType(MaritimeFeatureType type) {
    return visibleLayers.isEmpty || visibleLayers.contains(type);
  }

  /// Get appropriate symbol size for current zoom
  double getSymbolSize(MaritimeFeatureType type) {
    final baseSize = switch (type) {
      MaritimeFeatureType.lighthouse => 20.0,
      MaritimeFeatureType.beacon => 16.0,
      MaritimeFeatureType.buoy => 14.0,
      MaritimeFeatureType.daymark => 12.0,
      _ => 10.0,
    };

    // Scale with zoom level
    final zoomFactor = (zoom / 12.0).clamp(0.5, 2.5);
    return baseSize * zoomFactor;
  }
}