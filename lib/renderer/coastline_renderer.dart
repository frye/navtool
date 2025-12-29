import 'dart:math' as math;
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
  /// Uses equirectangular projection with latitude correction for proper aspect ratio.
  /// The correction factor cos(lat) compensates for longitude convergence toward poles:
  /// - At equator (0°): 1° lon = 1° lat in distance
  /// - At 47° (Seattle): 1° lon ≈ 0.68° lat in distance
  /// - At 60° (Alaska): 1° lon = 0.5° lat in distance
  Offset _geoToScreen(GeoPoint point, Size size) {
    // For global data, use fixed world bounds for consistent projection
    final GeoBounds projectionBounds;
    if (coastlineData.isGlobal) {
      // Use world bounds centered on prime meridian
      projectionBounds = const GeoBounds(
        minLon: -180,
        minLat: -90,
        maxLon: 180,
        maxLat: 90,
      );
    } else {
      projectionBounds = coastlineData.bounds;
    }
    
    // Calculate latitude correction factor (cosine of center latitude)
    // This scales longitude to match the actual ground distance at this latitude
    final centerLatRad = projectionBounds.centerLat * math.pi / 180.0; // Convert to radians
    final latCorrection = centerLatRad.abs() < 1.5 ? math.cos(centerLatRad) : 0.1; // cos(lat), min 0.1
    
    // Calculate corrected dimensions
    final correctedWidth = projectionBounds.width * latCorrection;
    final correctedHeight = projectionBounds.height;
    
    // Determine scale to fit view while maintaining aspect ratio
    final scaleX = size.width / correctedWidth;
    final scaleY = size.height / correctedHeight;
    final baseScale = scaleX < scaleY ? scaleX : scaleY;
    
    // Calculate the rendered size
    final renderedWidth = correctedWidth * baseScale;
    final renderedHeight = correctedHeight * baseScale;
    
    // Normalize coordinates relative to bounds
    final normalizedX = (point.longitude - projectionBounds.minLon) * latCorrection;
    final normalizedY = projectionBounds.maxLat - point.latitude; // Flip Y
    
    // Calculate base position
    final baseX = normalizedX * baseScale * zoom;
    final baseY = normalizedY * baseScale * zoom;

    // Center the chart in the view
    final centerOffsetX = (size.width - renderedWidth * zoom) / 2;
    final centerOffsetY = (size.height - renderedHeight * zoom) / 2;

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
  final List<CoastlineData>? coastlineLods; // Optional list of LOD datasets
  final double minZoom;
  final double maxZoom;
  final double initialZoom;

  const ChartView({
    super.key,
    required this.coastlineData,
    this.coastlineLods,
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
  CoastlineData? _lastActive;
  Offset? _doubleTapPosition;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    if (_doubleTapPosition == null) return;

    setState(() {
      final tapPoint = _doubleTapPosition!;
      final viewCenter = Offset(_viewSize.width / 2, _viewSize.height / 2);

      // Pan so tapped point moves to center
      _panOffset += viewCenter - tapPoint;
    });

    _doubleTapPosition = null;
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

  void _zoomAroundCenter(double factor) {
    setState(() {
      final newZoom = (_zoom * factor).clamp(widget.minZoom, widget.maxZoom);
      if (newZoom != _zoom) {
        // Zoom around view center - scale pan offset proportionally
        final zoomDelta = newZoom / _zoom;
        _panOffset = _panOffset * zoomDelta;
        _zoom = newZoom;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeData = _selectCoastlineData(_zoom);
    if (!identical(activeData, _lastActive)) {
      debugPrint('LOD switch -> ${activeData.name ?? 'unknown'} (lod=${activeData.lodLevel}, points=${activeData.totalPoints}, zoom=${_zoom.toStringAsFixed(2)})');
      _lastActive = activeData;
    }

    return Stack(
      children: [
        GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: CoastlineRenderer(
                  coastlineData: activeData,
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
                onPressed: () => _zoomAroundCenter(1.5),
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                onPressed: () => _zoomAroundCenter(1 / 1.5),
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
                  activeData.name ?? 'Chart',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Zoom: ${_zoom.toStringAsFixed(2)}x',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (activeData.lodLevel != null)
                  Text(
                    'LOD: ${activeData.lodLevel}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                Text(
                  'Polygons: ${activeData.polygonCount}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Points: ${activeData.totalPoints}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<CoastlineData> _lodsSorted() {
    final lods = widget.coastlineLods;
    if (lods == null || lods.isEmpty) {
      return [widget.coastlineData];
    }

    final sorted = List<CoastlineData>.of(lods);
    sorted.sort((a, b) {
      final aMin = a.minZoom ?? double.negativeInfinity;
      final bMin = b.minZoom ?? double.negativeInfinity;
      if (aMin != bMin) return bMin.compareTo(aMin); // higher minZoom = higher detail

      final aLod = a.lodLevel ?? 999;
      final bLod = b.lodLevel ?? 999;
      if (aLod != bLod) return aLod.compareTo(bLod);

      return b.totalPoints.compareTo(a.totalPoints); // more points treated as higher detail
    });
    return sorted;
  }

  CoastlineData _selectCoastlineData(double zoom) {
    final sorted = _lodsSorted();
    
    // First pass: find a regional (non-global) LOD that supports this zoom
    for (final data in sorted) {
      if (!data.isGlobal && data.supportsZoom(zoom)) {
        return data;
      }
    }
    
    // Second pass: fall back to global LOD that supports this zoom
    for (final data in sorted) {
      if (data.supportsZoom(zoom)) {
        return data;
      }
    }

    // Fallback: pick the highest-detail entry (first after sorting)
    return sorted.first;
  }
}
