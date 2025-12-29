import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/geo_types.dart';

/// Renders coastline data using Flutter's CustomPainter.
/// 
/// Features:
/// - Efficient path caching for performance
/// - Support for pan and zoom transformations
/// - Water background in blue, land in teal
class CoastlineRenderer extends CustomPainter {
  final CoastlineData coastlineData;
  final Offset panOffset;
  final double zoom;
  final Size viewSize;

  // Cached paths for performance
  ui.Path? _cachedLandPath;
  GeoBounds? _cachedBounds;
  double? _cachedZoom;

  // Colors
  static const Color waterColor = Color(0xFF1E88E5); // Blue
  static const Color landColor = Color(0xFF26A69A);  // Teal
  static const Color coastlineStrokeColor = Color(0xFF004D40); // Dark teal

  CoastlineRenderer({
    required this.coastlineData,
    required this.panOffset,
    required this.zoom,
    required this.viewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background with water color
    final waterPaint = Paint()
      ..color = waterColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), waterPaint);

    // Draw land masses
    final landPaint = Paint()
      ..color = landColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = coastlineStrokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = _buildLandPath(size);
    canvas.drawPath(path, landPaint);
    canvas.drawPath(path, strokePaint);
  }

  ui.Path _buildLandPath(Size size) {
    final path = ui.Path();

    for (final polygon in coastlineData.polygons) {
      // Draw exterior ring
      _addRingToPath(path, polygon.exteriorRing, size);

      // Draw interior rings (holes) - these will be subtracted
      for (final ring in polygon.interiorRings) {
        _addRingToPath(path, ring, size);
      }
    }

    // Use even-odd fill rule to handle holes correctly
    path.fillType = ui.PathFillType.evenOdd;

    return path;
  }

  void _addRingToPath(ui.Path path, List<GeoPoint> ring, Size size) {
    if (ring.isEmpty) return;

    final firstPoint = _geoToScreen(ring.first, size);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (int i = 1; i < ring.length; i++) {
      final point = _geoToScreen(ring[i], size);
      path.lineTo(point.dx, point.dy);
    }

    path.close();
  }

  /// Convert geographic coordinates to screen coordinates.
  /// Uses Mercator-like projection for the view.
  Offset _geoToScreen(GeoPoint point, Size size) {
    final bounds = coastlineData.bounds;
    
    // Normalize to 0-1 range within bounds
    final normalizedX = (point.longitude - bounds.minLon) / bounds.width;
    final normalizedY = (bounds.maxLat - point.latitude) / bounds.height; // Flip Y

    // Calculate base position
    final baseX = normalizedX * size.width * zoom;
    final baseY = normalizedY * size.height * zoom;

    // Apply pan offset and center
    final centerOffsetX = (size.width - size.width * zoom) / 2;
    final centerOffsetY = (size.height - size.height * zoom) / 2;

    return Offset(
      baseX + centerOffsetX + panOffset.dx,
      baseY + centerOffsetY + panOffset.dy,
    );
  }

  @override
  bool shouldRepaint(CoastlineRenderer oldDelegate) {
    return oldDelegate.panOffset != panOffset ||
        oldDelegate.zoom != zoom ||
        oldDelegate.coastlineData != coastlineData ||
        oldDelegate.viewSize != viewSize;
  }
}

/// Interactive chart view widget with pan and zoom support.
class ChartView extends StatefulWidget {
  final CoastlineData coastlineData;
  final double minZoom;
  final double maxZoom;
  final double initialZoom;

  const ChartView({
    super.key,
    required this.coastlineData,
    this.minZoom = 0.5,
    this.maxZoom = 20.0,
    this.initialZoom = 1.0,
  });

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  late double _zoom;
  Offset _panOffset = Offset.zero;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Handle zoom
      if (details.scale != 1.0) {
        final newZoom = (_zoom * details.scale).clamp(widget.minZoom, widget.maxZoom);
        
        // Adjust pan to zoom toward focal point
        if (newZoom != _zoom) {
          final focalPoint = details.focalPoint;
          final zoomDelta = newZoom / _zoom;
          _panOffset = Offset(
            focalPoint.dx - (focalPoint.dx - _panOffset.dx) * zoomDelta,
            focalPoint.dy - (focalPoint.dy - _panOffset.dy) * zoomDelta,
          );
          _zoom = newZoom;
        }
      }

      // Handle pan
      if (_lastFocalPoint != null) {
        _panOffset += details.focalPoint - _lastFocalPoint!;
      }
      _lastFocalPoint = details.focalPoint;
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastFocalPoint = null;
  }

  void _resetView() {
    setState(() {
      _zoom = widget.initialZoom;
      _panOffset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: CoastlineRenderer(
                  coastlineData: widget.coastlineData,
                  panOffset: _panOffset,
                  zoom: _zoom,
                  viewSize: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              );
            },
          ),
        ),
        // Zoom controls
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                onPressed: () {
                  setState(() {
                    _zoom = (_zoom * 1.5).clamp(widget.minZoom, widget.maxZoom);
                  });
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                onPressed: () {
                  setState(() {
                    _zoom = (_zoom / 1.5).clamp(widget.minZoom, widget.maxZoom);
                  });
                },
                child: const Icon(Icons.remove),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'reset',
                onPressed: _resetView,
                child: const Icon(Icons.center_focus_strong),
              ),
            ],
          ),
        ),
        // Info overlay
        Positioned(
          left: 16,
          top: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.coastlineData.name ?? 'Chart',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Zoom: ${_zoom.toStringAsFixed(2)}x',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Polygons: ${widget.coastlineData.polygonCount}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Points: ${widget.coastlineData.totalPoints}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
