/// Chart rendering service for marine navigation
library;

import 'package:flutter/material.dart';
import '../models/chart_models.dart';
import '../services/coordinate_transform.dart';

/// Service responsible for rendering maritime charts
class ChartRenderingService {
  final CoordinateTransform _transform;
  final List<MaritimeFeature> _features;
  final ChartDisplayMode _displayMode;

  ChartRenderingService({
    required CoordinateTransform transform,
    required List<MaritimeFeature> features,
    ChartDisplayMode displayMode = ChartDisplayMode.dayMode,
  })  : _transform = transform,
        _features = features,
        _displayMode = displayMode;

  /// Render the chart to a Canvas
  void render(Canvas canvas, Size size) {
    // Clear the canvas with sea color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _getSeaColor(),
    );

    // Get visible features sorted by render priority
    final visibleFeatures = _getVisibleFeatures();
    visibleFeatures.sort((a, b) => a.renderPriority.compareTo(b.renderPriority));

    // Render features in order
    for (final feature in visibleFeatures) {
      _renderFeature(canvas, feature);
    }

    // Render scale bar and compass
    _renderScaleBar(canvas, size);
    _renderCompass(canvas, size);
  }

  /// Get features visible in current viewport
  List<MaritimeFeature> _getVisibleFeatures() {
    final currentScale = _transform.chartScale;
    return _features.where((feature) {
      return _transform.isFeatureVisible(feature) &&
          feature.isVisibleAtScale(currentScale);
    }).toList();
  }

  /// Render a single maritime feature
  void _renderFeature(Canvas canvas, MaritimeFeature feature) {
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
    switch (feature.type) {
      case MaritimeFeatureType.shoreline:
        paint.strokeWidth = 2.0;
        break;
      case MaritimeFeatureType.cable:
        // Dashed line effect will be implemented later
        paint.strokeWidth = 1.0;
        break;
      case MaritimeFeatureType.pipeline:
        // Dotted line effect will be implemented later
        paint.strokeWidth = 1.0;
        break;
      default:
        break;
    }

    canvas.drawPath(path, paint);
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
  void _drawLighthouseSymbol(Canvas canvas, Offset center, double size, Paint paint) {
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
  void _drawBeaconSymbol(Canvas canvas, Offset center, double size, Paint paint) {
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
  void _drawDaymarkSymbol(Canvas canvas, Offset center, double size, Paint paint) {
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
  void _drawGenericPointSymbol(Canvas canvas, Offset center, double size, Paint paint) {
    canvas.drawCircle(center, size * 0.4, paint);
  }

  /// Render text label for features
  void _renderLabel(Canvas canvas, String text, Offset position, double symbolSize) {
    final textStyle = TextStyle(
      color: _displayMode == ChartDisplayMode.dayMode ? Colors.black : Colors.white,
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

  /// Render depth labels along contours
  void _renderDepthLabels(Canvas canvas, DepthContour contour) {
    if (contour.coordinates.length < 10) return;

    // Place labels at regular intervals
    const int labelInterval = 5;
    for (int i = labelInterval; i < contour.coordinates.length; i += labelInterval) {
      final screenPos = _transform.latLngToScreen(contour.coordinates[i]);
      _renderLabel(canvas, '${contour.depth}m', screenPos, 0);
    }
  }

  /// Render scale bar
  void _renderScaleBar(Canvas canvas, Size size) {
    const double barWidth = 100.0;
    const double barHeight = 20.0;
    final offset = Offset(20, size.height - 60);

    // Calculate scale distance
    final leftPos = _transform.screenToLatLng(offset);
    final rightPos = _transform.screenToLatLng(offset + const Offset(barWidth, 0));
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
      MaritimeFeatureType.landArea => isDayMode ? const Color(0xFFF5F5DC) : const Color(0xFF2D2D2D),
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
}

/// Chart display modes for day/night navigation
enum ChartDisplayMode {
  dayMode,
  nightMode,
}
