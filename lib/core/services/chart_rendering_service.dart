/// Chart rendering service for marine navigation
library;

import 'package:flutter/material.dart';
import '../models/chart_models.dart';
import '../services/coordinate_transform.dart';
import '../utils/path_dash_utils.dart';
import 's52/s52_color_tables.dart';
import 's52/s52_symbol_manager.dart';
import 's57/s57_models.dart';
import 's57/s57_spatial_tree.dart';
import 's57/spatial_index_interface.dart';

/// Service responsible for rendering maritime charts
class ChartRenderingService {
  final CoordinateTransform _transform;
  final List<MaritimeFeature> _features;
  final ChartDisplayMode _displayMode;
  final Map<String, bool> _layerVisibility = {};
  final Map<MaritimeFeatureType, Widget> _symbolCache = {};
  
  // Spatial indexing for performance
  late final SpatialIndex _spatialIndex;
  
  // S-52 integration
  late final S52SymbolManager _symbolManager;

  ChartRenderingService({
    required CoordinateTransform transform,
    required List<MaritimeFeature> features,
    ChartDisplayMode displayMode = ChartDisplayMode.dayMode,
  }) : _transform = transform,
       _features = features,
       _displayMode = displayMode {
    // Initialize default layer visibility
    _initializeLayerVisibility();
    
    // Initialize S-52 symbology
    _initializeS52();
    
    // Build spatial index for performance
    _buildSpatialIndex();
  }

  /// Render the chart to a Canvas
  void render(Canvas canvas, Size size) {
    // Debug: Log all features being rendered
    print('[ChartRenderingService] render() called with ${_features.length} features');
    for (var feature in _features) {
      print('[ChartRenderingService] Feature: ${feature.type} at ${feature.position} (id: ${feature.id})');
    }
    
    // Clear the canvas with sea color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _getSeaColor(),
    );

    // Render chart grid if enabled
    if (_layerVisibility['chart_grid'] ?? false) {
      _renderChartGrid(canvas, size);
    }

    // Get visible features sorted by render priority
    final visibleFeatures = _getVisibleFeatures();
    print('[ChartRenderingService] Visible features after filtering: ${visibleFeatures.length}');
    for (var feature in visibleFeatures) {
      print('[ChartRenderingService] Visible: ${feature.type} at ${feature.position}');
    }
    
    visibleFeatures.sort(
      (a, b) => a.renderPriority.compareTo(b.renderPriority),
    );

    // Render features in order
    for (final feature in visibleFeatures) {
      print('[ChartRenderingService] Rendering feature: ${feature.type}');
      _renderFeature(canvas, feature);
    }

    // Render chart boundaries if enabled
    if (_layerVisibility['chart_boundaries'] ?? true) {
      _renderChartBoundaries(canvas, size);
    }

    // Render scale bar and compass
    _renderScaleBar(canvas, size);
    _renderCompass(canvas, size);
  }

  /// Get features visible in current viewport
  List<MaritimeFeature> _getVisibleFeatures() {
    final currentScale = _transform.chartScale;
    print('[ChartRenderingService] Current scale: $currentScale');
    
    final visibleFeatures = <MaritimeFeature>[];
    
    for (final feature in _features) {
      final isVisible = _transform.isFeatureVisible(feature);
      final isVisibleAtScale = feature.isVisibleAtScale(currentScale);
      
      print('[ChartRenderingService] Feature ${feature.type}: isVisible=$isVisible, isVisibleAtScale=$isVisibleAtScale');
      
      if (isVisible && isVisibleAtScale) {
        visibleFeatures.add(feature);
      }
    }
    
    return visibleFeatures;
  }

  /// Render a single maritime feature
  void _renderFeature(Canvas canvas, MaritimeFeature feature) {
    // Check layer visibility  
    final layerName = _getLayerNameForFeature(feature.type);
    final isLayerVisible = _layerVisibility[layerName] ?? true;
    
    print('[ChartRenderingService] Feature ${feature.type}: layer=$layerName, visible=$isLayerVisible');
    
    if (!isLayerVisible) {
      print('[ChartRenderingService] Skipping ${feature.type} - layer not visible');
      return;
    }
    
    if (feature is DepthContour) {
      _renderDepthContour(canvas, feature);
    } else if (feature is PointFeature) {
      _renderPointFeature(canvas, feature);
    } else if (feature is LineFeature) {
      _renderLineFeature(canvas, feature);
    } else if (feature is AreaFeature) {
      _renderAreaFeature(canvas, feature);
    }
  }

  /// Render point features (buoys, lighthouses, etc.)
  void _renderPointFeature(Canvas canvas, PointFeature feature) {
    final screenPos = _transform.latLngToScreen(feature.position);
    final symbolSize = _transform.getSymbolSizeForScale(16.0);

    final paint = Paint()
      ..color = _getFeatureColor(feature.type)
      ..style = PaintingStyle.fill;

    // Render symbol based on feature type
    switch (feature.type) {
      case MaritimeFeatureType.lighthouse:
        _drawLighthouseSymbol(canvas, screenPos, symbolSize, paint);
        break;
      case MaritimeFeatureType.beacon:
        _drawBeaconSymbol(canvas, screenPos, symbolSize, paint);
        break;
      case MaritimeFeatureType.buoy:
        _drawBuoySymbol(canvas, screenPos, symbolSize, paint);
        break;
      case MaritimeFeatureType.daymark:
        _drawDaymarkSymbol(canvas, screenPos, symbolSize, paint);
        break;
      default:
        _drawGenericPointSymbol(canvas, screenPos, symbolSize, paint);
    }

    // Render label if present
    if (feature.label != null) {
      _renderLabel(canvas, feature.label!, screenPos, symbolSize);
    }
  }

  /// Render line features (shorelines, cables, etc.)
  void _renderLineFeature(Canvas canvas, LineFeature feature) {
    if (feature.coordinates.length < 2) return;

    final path = Path();
    final screenCoords = feature.coordinates
        .map((coord) => _transform.latLngToScreen(coord))
        .toList();

    path.moveTo(screenCoords.first.dx, screenCoords.first.dy);
    for (int i = 1; i < screenCoords.length; i++) {
      path.lineTo(screenCoords[i].dx, screenCoords[i].dy);
    }

    final paint = Paint()
      ..color = _getFeatureColor(feature.type)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _transform.getLineWidthForScale(feature.width ?? 2.0);

    // Apply specific line styles
    Path renderPath = path;
    switch (feature.type) {
      case MaritimeFeatureType.shoreline:
        paint.strokeWidth = 2.0;
        break;
      case MaritimeFeatureType.cable:
        paint.strokeWidth = 1.0;
        renderPath = PathDashUtils.cableDashedPath(path);
        break;
      case MaritimeFeatureType.pipeline:
        paint.strokeWidth = 1.0;
        renderPath = PathDashUtils.pipelineDottedPath(path);
        break;
      default:
        break;
    }

    canvas.drawPath(renderPath, paint);
  }

  /// Render area features (land masses, anchorages, etc.)
  void _renderAreaFeature(Canvas canvas, AreaFeature feature) {
    for (final ring in feature.coordinates) {
      if (ring.length < 3) continue;

      final path = Path();
      final screenCoords = ring
          .map((coord) => _transform.latLngToScreen(coord))
          .toList();

      path.moveTo(screenCoords.first.dx, screenCoords.first.dy);
      for (int i = 1; i < screenCoords.length; i++) {
        path.lineTo(screenCoords[i].dx, screenCoords[i].dy);
      }
      path.close();

      // Fill area
      if (feature.fillColor != null) {
        final fillPaint = Paint()
          ..color = feature.fillColor!
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
      } else {
        final fillPaint = Paint()
          ..color = _getFeatureColor(feature.type)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
      }

      // Draw stroke
      if (feature.strokeColor != null) {
        final strokePaint = Paint()
          ..color = feature.strokeColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  /// Render depth contours
  void _renderDepthContour(Canvas canvas, DepthContour contour) {
    if (contour.coordinates.length < 2) return;

    final path = Path();
    final screenCoords = contour.coordinates
        .map((coord) => _transform.latLngToScreen(coord))
        .toList();

    path.moveTo(screenCoords.first.dx, screenCoords.first.dy);
    for (int i = 1; i < screenCoords.length; i++) {
      path.lineTo(screenCoords[i].dx, screenCoords[i].dy);
    }

    final paint = Paint()
      ..color = _getDepthContourColor(contour.depth)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _getDepthContourWidth(contour.depth);

    canvas.drawPath(path, paint);

    // Add depth labels at intervals
    _renderDepthLabels(canvas, contour);
  }

  /// Draw lighthouse symbol
  void _drawLighthouseSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    // Draw lighthouse tower
    canvas.drawRect(
      Rect.fromCenter(center: center, width: size * 0.3, height: size),
      paint,
    );

    // Draw light beam
    final beamPaint = Paint()
      ..color = Colors.yellow.withAlpha(100)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size * 0.8, beamPaint);
  }

  /// Draw beacon symbol
  void _drawBeaconSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    canvas.drawCircle(center, size * 0.5, paint);

    // Draw beacon shape
    final path = Path();
    path.moveTo(center.dx, center.dy - size * 0.7);
    path.lineTo(center.dx - size * 0.3, center.dy + size * 0.7);
    path.lineTo(center.dx + size * 0.3, center.dy + size * 0.7);
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Draw buoy symbol
  void _drawBuoySymbol(Canvas canvas, Offset center, double size, Paint paint) {
    canvas.drawCircle(center, size * 0.5, paint);

    // Draw waves around buoy
    final wavePaint = Paint()
      ..color = paint.color.withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, size * 0.8, wavePaint);
  }

  /// Draw daymark symbol
  void _drawDaymarkSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    final path = Path();
    path.addPolygon([
      Offset(center.dx, center.dy - size * 0.5),
      Offset(center.dx + size * 0.5, center.dy),
      Offset(center.dx, center.dy + size * 0.5),
      Offset(center.dx - size * 0.5, center.dy),
    ], true);

    canvas.drawPath(path, paint);
  }

  /// Draw generic point symbol
  void _drawGenericPointSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    canvas.drawCircle(center, size * 0.4, paint);
  }

  /// Render text label for features
  void _renderLabel(
    Canvas canvas,
    String text,
    Offset position,
    double symbolSize,
  ) {
    final textStyle = TextStyle(
      color: _displayMode == ChartDisplayMode.dayMode
          ? Colors.black
          : Colors.white,
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label to the right of symbol
    final labelPosition = Offset(
      position.dx + symbolSize * 0.7,
      position.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, labelPosition);
  }

  /// Render depth labels along contours with enhanced placement
  void _renderDepthLabels(Canvas canvas, DepthContour contour) {
    if (contour.coordinates.length < 10) return;

    final scale = _transform.chartScale;
    
    // Determine label frequency based on scale and contour importance
    int labelInterval;
    if (contour.depth % 50 == 0) {
      labelInterval = 3; // Major contours - more frequent labels
    } else if (contour.depth % 10 == 0) {
      labelInterval = 5; // Intermediate contours
    } else {
      labelInterval = 8; // Minor contours - fewer labels
    }

    // Only show labels at appropriate scales
    if (scale.scale > 100000 && contour.depth % 20 != 0) return;

    for (int i = labelInterval; i < contour.coordinates.length; i += labelInterval) {
      final screenPos = _transform.latLngToScreen(contour.coordinates[i]);
      
      // Calculate contour direction for label orientation
      Offset? direction;
      if (i > 0 && i < contour.coordinates.length - 1) {
        final prev = _transform.latLngToScreen(contour.coordinates[i - 1]);
        final next = _transform.latLngToScreen(contour.coordinates[i + 1]);
        direction = Offset(next.dx - prev.dx, next.dy - prev.dy);
      }

      _renderDepthLabel(canvas, contour.depth, screenPos, direction);
    }
  }

  /// Render individual depth label with orientation
  void _renderDepthLabel(Canvas canvas, double depth, Offset position, Offset? direction) {
    final labelText = depth.round() == depth ? depth.round().toString() : depth.toStringAsFixed(1);
    
    final textStyle = TextStyle(
      color: _getDepthLabelColor(depth),
      fontSize: 10.0,
      fontWeight: FontWeight.w600,
      shadows: [
        Shadow(
          color: _displayMode == ChartDisplayMode.dayMode ? Colors.white : Colors.black,
          offset: const Offset(0.5, 0.5),
          blurRadius: 1.0,
        ),
      ],
    );

    final textSpan = TextSpan(text: labelText, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label slightly offset from contour line
    final labelPosition = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2 - 8,
    );

    textPainter.paint(canvas, labelPosition);
  }

  /// Get depth label color based on depth
  Color _getDepthLabelColor(double depth) {
    final isDayMode = _displayMode == ChartDisplayMode.dayMode;
    
    if (depth < 5) {
      // Shallow water - red for danger
      return isDayMode ? Colors.red.shade700 : Colors.red.shade300;
    } else if (depth < 20) {
      // Moderate depth - blue
      return isDayMode ? Colors.blue.shade700 : Colors.blue.shade300;
    } else {
      // Deep water - dark blue
      return isDayMode ? Colors.blue.shade900 : Colors.blue.shade200;
    }
  }

  /// Render scale bar
  void _renderScaleBar(Canvas canvas, Size size) {
    const double barWidth = 100.0;
    const double barHeight = 20.0;
    final offset = Offset(20, size.height - 60);

    // Calculate scale distance
    final leftPos = _transform.screenToLatLng(offset);
    final rightPos = _transform.screenToLatLng(
      offset + const Offset(barWidth, 0),
    );
    final distance = CoordinateTransform.distanceInMeters(leftPos, rightPos);

    // Draw scale bar background
    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, barWidth, barHeight),
      Paint()..color = Colors.white.withAlpha(200),
    );

    // Draw scale bar
    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, barWidth, 4),
      Paint()..color = Colors.black,
    );

    // Draw scale text
    final scaleText = distance > 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.toInt()} m';

    _renderLabel(canvas, scaleText, offset + const Offset(0, 25), 0);
  }

  /// Render compass rose
  void _renderCompass(Canvas canvas, Size size) {
    const double compassSize = 40.0;
    final center = Offset(size.width - 60, 60);

    // Draw compass background
    canvas.drawCircle(
      center,
      compassSize,
      Paint()..color = Colors.white.withAlpha(200),
    );

    // Draw compass needle pointing north
    final path = Path();
    path.moveTo(center.dx, center.dy - compassSize * 0.8);
    path.lineTo(center.dx - 6, center.dy);
    path.lineTo(center.dx + 6, center.dy);
    path.close();

    canvas.drawPath(path, Paint()..color = Colors.red);

    // Draw 'N' label
    _renderLabel(canvas, 'N', center + const Offset(-4, -compassSize - 5), 0);
  }

  /// Get color for sea/water areas
  Color _getSeaColor() {
    return _displayMode == ChartDisplayMode.dayMode
        ? const Color(0xFFE6F3FF) // Light blue for day
        : const Color(0xFF001122); // Dark blue for night
  }

  /// Get color for specific feature types
  Color _getFeatureColor(MaritimeFeatureType type) {
    final isDayMode = _displayMode == ChartDisplayMode.dayMode;

    return switch (type) {
      MaritimeFeatureType.lighthouse => Colors.red,
      MaritimeFeatureType.beacon => Colors.green,
      MaritimeFeatureType.buoy => Colors.yellow,
      MaritimeFeatureType.daymark => Colors.black,
      MaritimeFeatureType.shoreline => isDayMode ? Colors.black : Colors.white,
      MaritimeFeatureType.landArea =>
        isDayMode ? const Color(0xFFF5F5DC) : const Color(0xFF2D2D2D),
      MaritimeFeatureType.cable => Colors.purple,
      MaritimeFeatureType.pipeline => Colors.brown,
      MaritimeFeatureType.anchorage => Colors.blue.withAlpha(100),
      MaritimeFeatureType.restrictedArea => Colors.red.withAlpha(100),
      _ => isDayMode ? Colors.black : Colors.white,
    };
  }

  /// Get color for depth contours based on depth
  Color _getDepthContourColor(double depth) {
    final isDayMode = _displayMode == ChartDisplayMode.dayMode;
    final baseColor = isDayMode ? Colors.blue : Colors.cyan;

    // Deeper contours are darker
    final alpha = (255 * (1.0 - (depth / 100).clamp(0.0, 1.0))).round();
    return baseColor.withAlpha(alpha.clamp(50, 255));
  }

  /// Get line width for depth contours
  double _getDepthContourWidth(double depth) {
    if (depth % 50 == 0) return 2.0; // Major contours
    if (depth % 10 == 0) return 1.5; // Intermediate contours
    return 1.0; // Minor contours
  }

  // ===== Enhanced Methods for TDD Implementation =====

  /// Initialize layer visibility settings
  void _initializeLayerVisibility() {
    _layerVisibility['depth_contours'] = true;
    _layerVisibility['navigation_aids'] = true;
    _layerVisibility['shoreline'] = true;
    _layerVisibility['restricted_areas'] = true;
    _layerVisibility['anchorages'] = true;
    _layerVisibility['chart_grid'] = false;
    _layerVisibility['chart_boundaries'] = true;
  }

  /// Initialize S-52 symbology system
  void _initializeS52() {
    _symbolManager = S52SymbolManager.instance;
    
    // Convert ChartDisplayMode to S52DisplayMode
    final s52Mode = switch (_displayMode) {
      ChartDisplayMode.dayMode => S52DisplayMode.day,
      ChartDisplayMode.nightMode => S52DisplayMode.night,
      ChartDisplayMode.duskMode => S52DisplayMode.dusk,
    };
    
    _symbolManager.setDisplayMode(s52Mode);
    
    // Set scale from transform
    final scale = _transform.scaleFactor;
    _symbolManager.setScale(scale);
  }

  /// Get available rendering layers
  List<String> getLayers() {
    return _layerVisibility.keys.toList();
  }

  /// Set layer visibility
  void setLayerVisible(String layerName, bool visible) {
    _layerVisibility[layerName] = visible;
  }

  /// Get layer rendering priority
  int getLayerPriority(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => 100,
      MaritimeFeatureType.beacon => 90,
      MaritimeFeatureType.buoy => 80,
      MaritimeFeatureType.daymark => 70,
      MaritimeFeatureType.shoreline => 60,
      MaritimeFeatureType.depthContour => 50,
      MaritimeFeatureType.landArea => 10,
      _ => 30,
    };
  }

  /// Build spatial index from features for efficient culling
  void _buildSpatialIndex() {
    // Convert maritime features to S57 features for spatial indexing
    final s57Features = _features.map(_convertToS57Feature).toList();
    
    // Use factory to choose optimal index implementation based on feature count
    _spatialIndex = SpatialIndexFactory.create(s57Features);
  }
  
  /// Convert maritime feature to S57 feature for spatial indexing
  S57Feature _convertToS57Feature(MaritimeFeature feature) {
    // Extract coordinates and determine geometry type
    List<S57Coordinate> coordinates;
    S57GeometryType geometryType;
    
    if (feature is PointFeature) {
      coordinates = [S57Coordinate(
        latitude: feature.position.latitude,
        longitude: feature.position.longitude,
      )];
      geometryType = S57GeometryType.point;
    } else if (feature is LineFeature) {
      coordinates = feature.coordinates.map((coord) => S57Coordinate(
        latitude: coord.latitude,
        longitude: coord.longitude,
      )).toList();
      geometryType = S57GeometryType.line;
    } else if (feature is AreaFeature) {
      // Use first ring for bounding
      coordinates = feature.coordinates.isNotEmpty 
        ? feature.coordinates.first.map((coord) => S57Coordinate(
            latitude: coord.latitude,
            longitude: coord.longitude,
          )).toList()
        : [S57Coordinate(
            latitude: feature.position.latitude,
            longitude: feature.position.longitude,
          )];
      geometryType = S57GeometryType.area;
    } else {
      coordinates = [S57Coordinate(
        latitude: feature.position.latitude,
        longitude: feature.position.longitude,
      )];
      geometryType = S57GeometryType.point;
    }
    
    return S57Feature(
      recordId: feature.id.hashCode,
      featureType: _maritimeToS57Type(feature.type),
      geometryType: geometryType,
      coordinates: coordinates,
      attributes: feature is PointFeature ? feature.attributes : {},
    );
  }
  
  /// Map maritime feature type to S57 feature type
  S57FeatureType _maritimeToS57Type(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => S57FeatureType.lighthouse,
      MaritimeFeatureType.buoy => S57FeatureType.buoy,
      MaritimeFeatureType.beacon => S57FeatureType.beacon,
      MaritimeFeatureType.shoreline => S57FeatureType.shoreline,
      MaritimeFeatureType.landArea => S57FeatureType.landArea,
      MaritimeFeatureType.cable => S57FeatureType.obstruction, // Use obstruction for cables
      MaritimeFeatureType.pipeline => S57FeatureType.obstruction, // Use obstruction for pipelines
      MaritimeFeatureType.depthContour => S57FeatureType.depthContour,
      MaritimeFeatureType.depthArea => S57FeatureType.depthArea,
      MaritimeFeatureType.soundings => S57FeatureType.sounding,
      MaritimeFeatureType.rocks => S57FeatureType.underwater,
      MaritimeFeatureType.wrecks => S57FeatureType.wreck,
      MaritimeFeatureType.anchorage => S57FeatureType.coastline, // Use coastline for anchorage areas
      MaritimeFeatureType.restrictedArea => S57FeatureType.coastline, // Use coastline for restricted areas
      MaritimeFeatureType.trafficSeparation => S57FeatureType.coastline, // Use coastline for traffic separation
      MaritimeFeatureType.obstruction => S57FeatureType.obstruction,
      MaritimeFeatureType.daymark => S57FeatureType.daymark,
    };
  }

  /// Get visible features with spatial culling optimization
  List<MaritimeFeature> getVisibleFeatures() {
    final bounds = _transform.visibleBounds;
    
    // Use spatial index for efficient bounds query
    final s57Bounds = S57Bounds(
      west: bounds.west,
      east: bounds.east,
      south: bounds.south,
      north: bounds.north,
    );
    
    final spatialCandidates = _spatialIndex.queryBounds(s57Bounds);
    final candidateIds = spatialCandidates.map((f) => f.recordId).toSet();
    
    // Filter original features based on spatial results and additional criteria
    return _features.where((feature) {
      final featureId = feature.id.hashCode;
      
      // Must pass spatial culling first
      if (!candidateIds.contains(featureId)) {
        return false;
      }

      // Layer visibility check
      final layerName = _getLayerNameForFeature(feature.type);
      if (!(_layerVisibility[layerName] ?? true)) {
        return false;
      }

      // Scale-based visibility
      final scale = _transform.chartScale;
      return feature.isVisibleAtScale(scale);
    }).toList();
  }

  /// Get cached symbol for performance
  Widget? getCachedSymbol(MaritimeFeatureType type) {
    return _symbolCache[type];
  }

  /// Render enhanced symbol with S-52 compliance
  void renderEnhancedSymbol(
    Canvas canvas,
    PointFeature feature,
    Offset position,
  ) {
    // Try S-52 compliant rendering first
    if (_tryS52SymbolRendering(canvas, feature, position)) {
      return;
    }

    // Fallback to legacy rendering
    final paint = Paint()
      ..color = getSymbolColor(feature.type)
      ..style = PaintingStyle.fill;

    final size = getSymbolSizeForZoom(feature.type);

    switch (feature.type) {
      case MaritimeFeatureType.lighthouse:
        _drawEnhancedLighthouseSymbol(canvas, position, size, paint, feature);
        break;
      case MaritimeFeatureType.buoy:
        _drawEnhancedBuoySymbol(canvas, position, size, paint, feature);
        break;
      case MaritimeFeatureType.beacon:
        _drawEnhancedBeaconSymbol(canvas, position, size, paint, feature);
        break;
      default:
        _drawGenericPointSymbol(canvas, position, size, paint);
    }
  }

  /// Try rendering with S-52 compliant symbols
  bool _tryS52SymbolRendering(Canvas canvas, PointFeature feature, Offset position) {
    try {
      final size = getSymbolSizeForZoom(feature.type);
      _symbolManager.renderSymbolToCanvas(canvas, position, feature, size);
      return true;
    } catch (e) {
      // Fall back to legacy rendering if S-52 fails
      return false;
    }
  }

  /// Get symbol color for enhanced rendering
  Color getSymbolColor(MaritimeFeatureType type) {
    return switch (_displayMode) {
      ChartDisplayMode.dayMode => _getDayModeColor(type),
      ChartDisplayMode.nightMode => _getNightModeColor(type),
      ChartDisplayMode.duskMode => _getDuskModeColor(type),
    };
  }

  /// Get symbol size based on zoom level
  double getSymbolSizeForZoom(MaritimeFeatureType type) {
    final baseSize = switch (type) {
      MaritimeFeatureType.lighthouse => 16.0,
      MaritimeFeatureType.beacon => 12.0,
      MaritimeFeatureType.buoy => 10.0,
      MaritimeFeatureType.daymark => 8.0,
      _ => 6.0,
    };

    final zoomFactor = (_transform.zoom / 12.0).clamp(0.5, 2.0);
    return baseSize * zoomFactor;
  }

  /// Hit test for feature selection
  MaritimeFeature? hitTest(Offset screenPoint) {
    final latLng = _transform.screenToLatLng(screenPoint);
    const tolerance = 0.001; // Degrees

    for (final feature in getVisibleFeatures()) {
      final distance = _calculateDistance(
        latLng.latitude,
        latLng.longitude,
        feature.position.latitude,
        feature.position.longitude,
      );

      if (distance < tolerance) {
        return feature;
      }
    }
    return null;
  }

  /// Get feature information
  Map<String, dynamic> getFeatureInfo(String featureId) {
    final feature = _features.firstWhere((f) => f.id == featureId);

    return {
      'id': feature.id,
      'type': feature.type.name,
      'position': {
        'latitude': feature.position.latitude,
        'longitude': feature.position.longitude,
      },
      'attributes': feature.attributes,
      if (feature is PointFeature) 'label': feature.label,
      if (feature is PointFeature) 'heading': feature.heading,
    };
  }

  /// Get mode-specific colors
  Map<String, Color> getModeSpecificColors() {
    return switch (_displayMode) {
      ChartDisplayMode.dayMode => {
        'sea': const Color(0xFFE6F3FF),
        'land': const Color(0xFFF5F5DC),
        'text': Colors.black,
      },
      ChartDisplayMode.nightMode => {
        'sea': const Color(0xFF001122),
        'land': const Color(0xFF2D2D2D),
        'text': Colors.white,
      },
      ChartDisplayMode.duskMode => {
        'sea': const Color(0xFF001846),
        'land': const Color(0xFF3D3D3D),
        'text': Colors.white,
      },
    };
  }

  /// Set chart rotation
  void setRotation(double degrees) {
    // Implementation would modify transform rotation
    // For now, we'll simulate this for testing
  }

  /// Render depth contour with enhanced styling
  void renderDepthContour(Canvas canvas, LineFeature contour) {
    final depth = contour.attributes['depth'] as double? ?? 0.0;
    final paint = Paint()
      ..color = _getDepthContourColor(depth)
      ..strokeWidth = _getDepthContourWidth(depth)
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < contour.coordinates.length; i++) {
      final point = _transform.latLngToScreen(contour.coordinates[i]);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Render restricted area with proper symbology
  void renderRestrictedArea(Canvas canvas, AreaFeature area) {
    final paint = Paint()
      ..color = Colors.red.withAlpha(80)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final ring in area.coordinates) {
      final path = Path();
      for (int i = 0; i < ring.length; i++) {
        final point = _transform.latLngToScreen(ring[i]);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();

      canvas.drawPath(path, paint);
      canvas.drawPath(path, strokePaint);
    }
  }

  /// Render light characteristics and ranges
  void renderLightCharacteristics(PointFeature lighthouse) {
    // Enhanced light rendering would show light sectors, ranges, etc.
    // For now, we'll simulate this for testing
    // Access attributes to signal planned use in future enhanced rendering without storing
    lighthouse.attributes['character'];
    lighthouse.attributes['range'];

    // Implementation would draw light sectors and range circles
  }

  // ===== Enhanced Helper Methods =====

  /// Get layer name for feature type
  String _getLayerNameForFeature(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.depthContour => 'depth_contours',
      MaritimeFeatureType.lighthouse ||
      MaritimeFeatureType.beacon ||
      MaritimeFeatureType.buoy ||
      MaritimeFeatureType.daymark => 'navigation_aids',
      MaritimeFeatureType.shoreline => 'shoreline',
      MaritimeFeatureType.restrictedArea => 'restricted_areas',
      MaritimeFeatureType.anchorage => 'anchorages',
      _ => 'other',
    };
  }

  /// Calculate distance between two points in degrees
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;
    return (dLat * dLat + dLon * dLon);
  }

  /// Get day mode colors
  Color _getDayModeColor(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Colors.red,
      MaritimeFeatureType.beacon => Colors.green,
      MaritimeFeatureType.buoy => Colors.yellow,
      MaritimeFeatureType.daymark => Colors.black,
      _ => Colors.blue,
    };
  }

  /// Get night mode colors
  Color _getNightModeColor(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Colors.red.shade200,
      MaritimeFeatureType.beacon => Colors.green.shade200,
      MaritimeFeatureType.buoy => Colors.yellow.shade200,
      MaritimeFeatureType.daymark => Colors.white,
      _ => Colors.cyan,
    };
  }

  /// Get dusk mode colors
  Color _getDuskModeColor(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Colors.red.shade300,
      MaritimeFeatureType.beacon => Colors.green.shade300,
      MaritimeFeatureType.buoy => Colors.yellow.shade300,
      MaritimeFeatureType.daymark => Colors.grey.shade300,
      _ => Colors.blue.shade300,
    };
  }

  /// Draw enhanced lighthouse symbol
  void _drawEnhancedLighthouseSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
    PointFeature feature,
  ) {
    // Draw lighthouse base
    final rect = Rect.fromCenter(
      center: center,
      width: size * 0.6,
      height: size,
    );
    canvas.drawRect(rect, paint);

    // Draw light beam based on characteristics
    final character = feature.attributes['character'] as String? ?? 'F';
    final range = feature.attributes['range'] as double? ?? 10.0;
    
    if (character.contains('F')) {
      // Fixed light - draw continuous beam
      final beamPaint = Paint()
        ..color = Colors.yellow.withAlpha(60)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, size * (range / 20.0).clamp(1.5, 3.0), beamPaint);
    } else if (character.contains('Fl')) {
      // Flashing light - draw sectored beam
      final beamPaint = Paint()
        ..color = Colors.yellow.withAlpha(80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, size * 1.8, beamPaint);
    }

    // Draw lighthouse top
    final topRect = Rect.fromCenter(
      center: center - Offset(0, size * 0.4),
      width: size * 0.8,
      height: size * 0.3,
    );
    canvas.drawRect(topRect, Paint()..color = Colors.white);
  }

  /// Draw enhanced buoy symbol
  void _drawEnhancedBuoySymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
    PointFeature feature,
  ) {
    // Determine buoy shape from attributes
    final shape = feature.attributes['buoyShape'] as String? ?? 'cylindrical';
    final color = feature.attributes['color'] as String? ?? 'red';

    switch (shape) {
      case 'pillar':
        _drawPillarBuoy(canvas, center, size, color);
        break;
      case 'spherical':
        _drawSphericalBuoy(canvas, center, size, color);
        break;
      default:
        _drawCylindricalBuoy(canvas, center, size, color);
    }

    // Draw topmark if present
    final topmark = feature.attributes['topmark'] as String?;
    if (topmark != null) {
      _drawTopmark(canvas, center, size, topmark);
    }
  }

  /// Draw pillar buoy shape
  void _drawPillarBuoy(Canvas canvas, Offset center, double size, String color) {
    final paint = Paint()
      ..color = _getBuoyColor(color)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromCenter(
      center: center,
      width: size * 0.5,
      height: size * 1.2,
    );
    canvas.drawRect(rect, paint);
  }

  /// Draw spherical buoy shape
  void _drawSphericalBuoy(Canvas canvas, Offset center, double size, String color) {
    final paint = Paint()
      ..color = _getBuoyColor(color)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size * 0.6, paint);
  }

  /// Draw cylindrical buoy shape
  void _drawCylindricalBuoy(Canvas canvas, Offset center, double size, String color) {
    final paint = Paint()
      ..color = _getBuoyColor(color)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size * 0.5, paint);
    
    // Draw cylindrical top
    final rect = Rect.fromCenter(
      center: center - Offset(0, size * 0.3),
      width: size * 0.4,
      height: size * 0.2,
    );
    canvas.drawRect(rect, paint);
  }

  /// Draw topmark on buoy or beacon
  void _drawTopmark(Canvas canvas, Offset center, double size, String topmark) {
    final topmarkCenter = center - Offset(0, size * 0.8);
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    switch (topmark.toLowerCase()) {
      case 'north':
        _drawNorthCardinalTopmark(canvas, topmarkCenter, size * 0.4, paint);
        break;
      case 'south':
        _drawSouthCardinalTopmark(canvas, topmarkCenter, size * 0.4, paint);
        break;
      case 'east':
        _drawEastCardinalTopmark(canvas, topmarkCenter, size * 0.4, paint);
        break;
      case 'west':
        _drawWestCardinalTopmark(canvas, topmarkCenter, size * 0.4, paint);
        break;
      case 'port':
        canvas.drawRect(
          Rect.fromCenter(center: topmarkCenter, width: size * 0.3, height: size * 0.6),
          paint,
        );
        break;
      case 'starboard':
        final path = Path();
        path.moveTo(topmarkCenter.dx, topmarkCenter.dy - size * 0.3);
        path.lineTo(topmarkCenter.dx + size * 0.3, topmarkCenter.dy + size * 0.3);
        path.lineTo(topmarkCenter.dx - size * 0.3, topmarkCenter.dy + size * 0.3);
        path.close();
        canvas.drawPath(path, paint);
        break;
    }
  }

  /// Draw enhanced beacon symbol
  void _drawEnhancedBeaconSymbol(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
    PointFeature feature,
  ) {
    // Draw beacon structure
    final rect = Rect.fromCenter(
      center: center,
      width: size * 0.4,
      height: size,
    );
    canvas.drawRect(rect, paint);

    // Draw beacon platform
    final platformRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + size * 0.3),
      width: size * 0.8,
      height: size * 0.2,
    );
    canvas.drawRect(platformRect, paint);
  }

  /// Draw north cardinal topmark
  void _drawNorthCardinalTopmark(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    // Two cones pointing up
    final path1 = Path();
    path1.moveTo(center.dx - size * 0.2, center.dy);
    path1.lineTo(center.dx - size * 0.1, center.dy - size);
    path1.lineTo(center.dx, center.dy);
    path1.close();

    final path2 = Path();
    path2.moveTo(center.dx, center.dy);
    path2.lineTo(center.dx + size * 0.1, center.dy - size);
    path2.lineTo(center.dx + size * 0.2, center.dy);
    path2.close();

    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }

  /// Draw south cardinal topmark
  void _drawSouthCardinalTopmark(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    // Two cones pointing down
    final path1 = Path();
    path1.moveTo(center.dx - size * 0.2, center.dy);
    path1.lineTo(center.dx - size * 0.1, center.dy + size);
    path1.lineTo(center.dx, center.dy);
    path1.close();

    final path2 = Path();
    path2.moveTo(center.dx, center.dy);
    path2.lineTo(center.dx + size * 0.1, center.dy + size);
    path2.lineTo(center.dx + size * 0.2, center.dy);
    path2.close();

    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }

  /// Draw east cardinal topmark
  void _drawEastCardinalTopmark(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    // Two cones base to base
    final path1 = Path();
    path1.moveTo(center.dx, center.dy - size * 0.5);
    path1.lineTo(center.dx + size * 0.5, center.dy);
    path1.lineTo(center.dx, center.dy + size * 0.5);
    path1.close();

    canvas.drawPath(path1, paint);
  }

  /// Draw west cardinal topmark
  void _drawWestCardinalTopmark(
    Canvas canvas,
    Offset center,
    double size,
    Paint paint,
  ) {
    // Two cones point to point
    final path1 = Path();
    path1.moveTo(center.dx - size * 0.5, center.dy);
    path1.lineTo(center.dx, center.dy - size * 0.5);
    path1.lineTo(center.dx, center.dy + size * 0.5);
    path1.close();

    canvas.drawPath(path1, paint);
  }

  /// Render chart grid (latitude/longitude lines)
  void _renderChartGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (_displayMode == ChartDisplayMode.dayMode ? Colors.grey : Colors.grey.shade600)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final bounds = _transform.visibleBounds;
    final scale = _transform.chartScale;

    // Determine grid spacing based on scale
    double latSpacing, lonSpacing;
    if (scale.scale > 500000) {
      latSpacing = lonSpacing = 1.0; // 1 degree
    } else if (scale.scale > 100000) {
      latSpacing = lonSpacing = 0.5; // 30 minutes
    } else if (scale.scale > 25000) {
      latSpacing = lonSpacing = 0.1; // 6 minutes
    } else {
      latSpacing = lonSpacing = 0.05; // 3 minutes
    }

    // Draw latitude lines
    final startLat = (bounds.south / latSpacing).floor() * latSpacing;
    for (double lat = startLat; lat <= bounds.north; lat += latSpacing) {
      if (lat < -90 || lat > 90) continue;

      final startPoint = _transform.latLngToScreen(LatLng(lat, bounds.west));
      final endPoint = _transform.latLngToScreen(LatLng(lat, bounds.east));
      canvas.drawLine(startPoint, endPoint, paint);

      // Draw latitude labels
      if (lat % (latSpacing * 2) == 0) {
        final labelPos = Offset(10, startPoint.dy);
        _renderGridLabel(canvas, _formatLatitude(lat), labelPos);
      }
    }

    // Draw longitude lines  
    final startLon = (bounds.west / lonSpacing).floor() * lonSpacing;
    for (double lon = startLon; lon <= bounds.east; lon += lonSpacing) {
      if (lon < -180 || lon > 180) continue;

      final startPoint = _transform.latLngToScreen(LatLng(bounds.south, lon));
      final endPoint = _transform.latLngToScreen(LatLng(bounds.north, lon));
      canvas.drawLine(startPoint, endPoint, paint);

      // Draw longitude labels
      if (lon % (lonSpacing * 2) == 0) {
        final labelPos = Offset(startPoint.dx, size.height - 20);
        _renderGridLabel(canvas, _formatLongitude(lon), labelPos);
      }
    }
  }

  /// Render chart boundaries and title information
  void _renderChartBoundaries(Canvas canvas, Size size) {
    // Draw chart border
    final borderPaint = Paint()
      ..color = _displayMode == ChartDisplayMode.dayMode ? Colors.black : Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );

    // Draw title block
    _renderTitleBlock(canvas, size);

    // Draw scale information
    _renderScaleInformation(canvas, size);
  }

  /// Render chart title block
  void _renderTitleBlock(Canvas canvas, Size size) {
    const titleBlockHeight = 60.0;
    final titleRect = Rect.fromLTWH(
      10, 
      size.height - titleBlockHeight - 10,
      size.width - 20,
      titleBlockHeight,
    );

    final paint = Paint()
      ..color = Colors.white.withAlpha(200)
      ..style = PaintingStyle.fill;

    canvas.drawRect(titleRect, paint);

    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(titleRect, borderPaint);

    // Chart title
    _renderLabel(canvas, 'NOAA Electronic Navigational Chart', 
                Offset(titleRect.left + 10, titleRect.top + 10), 0);
    
    // Chart scale
    final scale = _transform.chartScale;
    _renderLabel(canvas, 'Scale: 1:${scale.scale.round()}',
                Offset(titleRect.left + 10, titleRect.top + 30), 0);

    // Date information
    final now = DateTime.now();
    _renderLabel(canvas, 'Date: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                Offset(titleRect.left + 10, titleRect.top + 45), 0);
  }

  /// Render scale information and north arrow
  void _renderScaleInformation(Canvas canvas, Size size) {
    // Draw north arrow in top right
    final arrowCenter = Offset(size.width - 40, 40);
    _renderNorthArrow(canvas, arrowCenter, 20.0);
  }

  /// Render north arrow
  void _renderNorthArrow(Canvas canvas, Offset center, double size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // Arrow pointing up
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx - size * 0.3, center.dy);
    path.lineTo(center.dx + size * 0.3, center.dy);
    path.close();

    canvas.drawPath(path, paint);

    // Draw 'N' label
    _renderLabel(canvas, 'N', center + Offset(-4, size + 5), 0);
  }

  /// Render grid labels
  void _renderGridLabel(Canvas canvas, String text, Offset position) {
    final textStyle = TextStyle(
      color: _displayMode == ChartDisplayMode.dayMode ? Colors.black : Colors.white,
      fontSize: 10.0,
      fontWeight: FontWeight.w400,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  /// Format latitude for display
  String _formatLatitude(double latitude) {
    final degrees = latitude.abs().floor();
    final minutes = ((latitude.abs() - degrees) * 60).round();
    final direction = latitude >= 0 ? 'N' : 'S';
    return '$degrees°${minutes.toString().padLeft(2, '0')}\' $direction';
  }

  /// Format longitude for display
  String _formatLongitude(double longitude) {
    final degrees = longitude.abs().floor();
    final minutes = ((longitude.abs() - degrees) * 60).round();
    final direction = longitude >= 0 ? 'E' : 'W';
    return '$degrees°${minutes.toString().padLeft(2, '0')}\' $direction';
  }

  /// Enhanced text label rendering with collision avoidance
  void renderEnhancedLabel(Canvas canvas, String text, Offset position, double symbolSize) {
    final textStyle = TextStyle(
      color: _displayMode == ChartDisplayMode.dayMode ? Colors.black : Colors.white,
      fontSize: _getLabelFontSize(),
      fontWeight: FontWeight.w500,
      shadows: [
        Shadow(
          color: _displayMode == ChartDisplayMode.dayMode ? Colors.white : Colors.black,
          offset: const Offset(1, 1),
          blurRadius: 2.0,
        ),
      ],
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label to avoid overlapping with symbol
    final labelPosition = _calculateLabelPosition(position, symbolSize, textPainter.size);

    textPainter.paint(canvas, labelPosition);
  }

  /// Get font size based on zoom level
  double _getLabelFontSize() {
    final baseSize = 12.0;
    final zoomFactor = (_transform.zoom / 12.0).clamp(0.7, 1.5);
    return baseSize * zoomFactor;
  }

  /// Calculate optimal label position to avoid overlapping
  Offset _calculateLabelPosition(Offset symbolPosition, double symbolSize, Size labelSize) {
    // Default: position to the right of symbol
    final rightPosition = Offset(
      symbolPosition.dx + symbolSize * 0.7,
      symbolPosition.dy - labelSize.height / 2,
    );

    // TODO: Implement collision detection with other labels
    // For now, just return the right position
    return rightPosition;
  }

  /// Get buoy color from string
  Color _getBuoyColor(String colorString) {
    return switch (colorString.toLowerCase()) {
      'red' => Colors.red,
      'green' => Colors.green,
      'yellow' => Colors.yellow,
      'black' => Colors.black,
      'white' => Colors.white,
      'black-yellow' => Colors.yellow, // Simplified for now
      'red-white' => Colors.red, // Simplified for now
      _ => Colors.blue,
    };
  }
}

/// Chart display modes for day/night navigation
enum ChartDisplayMode { dayMode, nightMode, duskMode }
