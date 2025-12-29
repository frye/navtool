import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/geo_types.dart';

/// Renders coastline data using Flutter's CustomPainter.
/// 
/// Features:
/// - Multi-layer rendering (GSHHG background + ENC overlay)
/// - GSHHG clipped to only show outside ENC bounds
/// - Efficient path caching for performance
/// - Support for pan and zoom transformations
/// - Water background in blue, land in teal
class CoastlineRenderer extends CustomPainter {
  final CoastlineData coastlineData;
  final CoastlineData? backgroundData;  // GSHHG layer rendered behind main data
  final GeoBounds projectionBounds;     // Fixed projection bounds for all layers
  final Offset panOffset;
  final double zoom;
  final Size viewSize;

  // Colors
  static const Color waterColor = Color(0xFF1E88E5); // Blue
  static const Color landColor = Color(0xFF26A69A);  // Teal
  static const Color coastlineStrokeColor = Color(0xFF004D40); // Dark teal
  // Use SAME colors for GSHHG so overlap/gaps are invisible
  static const Color gshhgLandColor = landColor;
  static const Color gshhgStrokeColor = coastlineStrokeColor;

  CoastlineRenderer({
    required this.coastlineData,
    this.backgroundData,
    required this.projectionBounds,
    required this.panOffset,
    required this.zoom,
    required this.viewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clip canvas to viewport for efficiency
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Fill background with water color
    final waterPaint = Paint()
      ..color = waterColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), waterPaint);

    // Calculate visible geographic bounds for polygon culling
    final visibleBounds = _getVisibleBounds(size);

    // Draw GSHHG background layer first (if available)
    // Only draw FILL (no stroke) - ENC will provide the detailed coastline on top
    // No clipping - GSHHG serves as base land layer everywhere
    if (backgroundData != null) {
      final bgLandPaint = Paint()
        ..color = landColor  // Use same land color so it blends with ENC
        ..style = PaintingStyle.fill;

      final bgPath = _buildLandPath(backgroundData!, size, visibleBounds);
      canvas.drawPath(bgPath, bgLandPaint);
      // NO stroke for GSHHG - only ENC draws the detailed coastline stroke
    }

    // Draw main (ENC) layer on top - this covers GSHHG in overlapping areas
    final landPaint = Paint()
      ..color = landColor
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = coastlineStrokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = _buildLandPath(coastlineData, size, visibleBounds);
    canvas.drawPath(path, landPaint);
    canvas.drawPath(path, strokePaint);
  }

  ui.Path _buildLandPath(CoastlineData data, Size size, GeoBounds? visibleBounds) {
    final path = ui.Path();

    for (final polygon in data.polygons) {
      // Skip polygons entirely outside visible bounds (viewport culling)
      if (visibleBounds != null && !polygon.bounds.intersects(visibleBounds)) {
        continue;
      }

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
  /// All layers use the same projectionBounds for consistent alignment.
  Offset _geoToScreen(GeoPoint point, Size size) {
    // Calculate latitude correction factor (cosine of center latitude)
    // This scales longitude to match the actual ground distance at this latitude
    final centerLatRad = projectionBounds.centerLat * math.pi / 180.0;
    final latCorrection = centerLatRad.abs() < 1.5 ? math.cos(centerLatRad) : 0.1;
    
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
    
    // Normalize coordinates relative to projection bounds
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

  /// Convert screen coordinates to geographic coordinates (inverse of _geoToScreen).
  GeoPoint _screenToGeo(Offset screenPoint, Size size) {
    // Calculate latitude correction factor
    final centerLatRad = projectionBounds.centerLat * math.pi / 180.0;
    final latCorrection = centerLatRad.abs() < 1.5 ? math.cos(centerLatRad) : 0.1;
    
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
    
    // Center offsets
    final centerOffsetX = (size.width - renderedWidth * zoom) / 2;
    final centerOffsetY = (size.height - renderedHeight * zoom) / 2;
    
    // Reverse the screen transformation
    final baseX = (screenPoint.dx - centerOffsetX - panOffset.dx) / (baseScale * zoom);
    final baseY = (screenPoint.dy - centerOffsetY - panOffset.dy) / (baseScale * zoom);
    
    // Convert normalized coordinates back to geographic
    final longitude = (baseX / latCorrection) + projectionBounds.minLon;
    final latitude = projectionBounds.maxLat - baseY;
    
    return GeoPoint(longitude, latitude);
  }

  /// Calculate the geographic bounds visible in the current viewport.
  GeoBounds _getVisibleBounds(Size size) {
    // Convert the four screen corners to geographic coordinates
    final topLeft = _screenToGeo(Offset.zero, size);
    final topRight = _screenToGeo(Offset(size.width, 0), size);
    final bottomLeft = _screenToGeo(Offset(0, size.height), size);
    final bottomRight = _screenToGeo(Offset(size.width, size.height), size);
    
    // Find the bounding box of all four corners
    final minLon = [topLeft.longitude, topRight.longitude, bottomLeft.longitude, bottomRight.longitude].reduce(math.min);
    final maxLon = [topLeft.longitude, topRight.longitude, bottomLeft.longitude, bottomRight.longitude].reduce(math.max);
    final minLat = [topLeft.latitude, topRight.latitude, bottomLeft.latitude, bottomRight.latitude].reduce(math.min);
    final maxLat = [topLeft.latitude, topRight.latitude, bottomLeft.latitude, bottomRight.latitude].reduce(math.max);
    
    return GeoBounds(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat);
  }

  @override
  bool shouldRepaint(CoastlineRenderer oldDelegate) {
    return oldDelegate.panOffset != panOffset ||
        oldDelegate.zoom != zoom ||
        oldDelegate.coastlineData != coastlineData ||
        oldDelegate.backgroundData != backgroundData ||
        oldDelegate.projectionBounds != projectionBounds ||
        oldDelegate.viewSize != viewSize;
  }
}

/// Interactive chart view widget with pan and zoom support.
/// Renders GSHHG global data as background with regional ENC data overlaid.
class ChartView extends StatefulWidget {
  final CoastlineData coastlineData;
  final List<CoastlineData>? coastlineLods;  // Regional ENC LODs
  final List<CoastlineData>? globalLods;     // Global GSHHG LODs
  final GeoBounds? viewBounds;               // Optional fixed view bounds
  final double minZoom;
  final double maxZoom;
  final double initialZoom;

  const ChartView({
    super.key,
    required this.coastlineData,
    this.coastlineLods,
    this.globalLods,
    this.viewBounds,
    this.minZoom = 0.1,
    this.maxZoom = 1000.0,
    this.initialZoom = 1.0,
  });

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  late double _zoom;
  Offset _panOffset = Offset.zero;
  Offset? _lastFocalPoint;
  CoastlineData? _lastActiveRegional;
  CoastlineData? _lastActiveGlobal;
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
    // Select best regional (ENC) data for current zoom
    final regionalData = _selectRegionalData(_zoom);
    // Select best global (GSHHG) data for current zoom
    final globalData = _selectGlobalData(_zoom);
    
    // Determine projection bounds - use regional if available, otherwise use view bounds or global
    final GeoBounds projectionBounds;
    if (widget.viewBounds != null) {
      projectionBounds = widget.viewBounds!;
    } else if (regionalData != null) {
      projectionBounds = regionalData.bounds;
    } else if (globalData != null) {
      // For global-only view, use world bounds
      projectionBounds = const GeoBounds(
        minLon: -180, minLat: -90, maxLon: 180, maxLat: 90,
      );
    } else {
      projectionBounds = widget.coastlineData.bounds;
    }
    
    // The "active" data is regional if available, otherwise global
    final activeData = regionalData ?? globalData ?? widget.coastlineData;
    
    // Determine if we should show GSHHG background
    // Skip GSHHG when using LOD0 (highest detail) - user is zoomed in too far to see it
    final showGshhgBackground = regionalData != null && 
                                 globalData != null && 
                                 (regionalData.lodLevel ?? 0) > 0;
    
    // Log LOD switches
    if (!identical(regionalData, _lastActiveRegional)) {
      if (regionalData != null) {
        debugPrint('Regional LOD -> ${regionalData.name} (lod=${regionalData.lodLevel}, points=${regionalData.totalPoints}, zoom=${_zoom.toStringAsFixed(2)})');
      }
      _lastActiveRegional = regionalData;
    }
    if (!identical(globalData, _lastActiveGlobal)) {
      if (globalData != null) {
        debugPrint('Global LOD -> ${globalData.name} (lod=${globalData.lodLevel}, points=${globalData.totalPoints}, zoom=${_zoom.toStringAsFixed(2)})');
      }
      _lastActiveGlobal = globalData;
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
                  backgroundData: showGshhgBackground ? globalData : null,
                  projectionBounds: projectionBounds,
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
                if (globalData != null && regionalData != null)
                  Text(
                    '+ GSHHG: ${globalData.totalPoints} pts',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Select best regional (ENC) LOD for current zoom.
  CoastlineData? _selectRegionalData(double zoom) {
    final lods = widget.coastlineLods;
    if (lods == null || lods.isEmpty) {
      // Check if coastlineData is regional
      if (!widget.coastlineData.isGlobal) {
        return widget.coastlineData;
      }
      return null;
    }

    // Sort by minZoom descending (highest detail first)
    final sorted = List<CoastlineData>.of(lods.where((d) => !d.isGlobal));
    sorted.sort((a, b) {
      final aMin = a.minZoom ?? double.negativeInfinity;
      final bMin = b.minZoom ?? double.negativeInfinity;
      return bMin.compareTo(aMin);
    });

    for (final data in sorted) {
      if (data.supportsZoom(zoom)) {
        return data;
      }
    }

    // If zoom is below all regional LODs, return null (use global only)
    if (sorted.isNotEmpty) {
      final lowestLod = sorted.last;
      final minZoom = lowestLod.minZoom ?? 0.0;
      if (zoom < minZoom) {
        return null;
      }
      // Otherwise return the lowest detail regional LOD
      return lowestLod;
    }

    return null;
  }

  /// Select best global (GSHHG) LOD for current zoom.
  CoastlineData? _selectGlobalData(double zoom) {
    final lods = widget.globalLods ?? widget.coastlineLods;
    if (lods == null || lods.isEmpty) {
      if (widget.coastlineData.isGlobal) {
        return widget.coastlineData;
      }
      return null;
    }

    // Get only global LODs
    final globalLods = lods.where((d) => d.isGlobal).toList();
    if (globalLods.isEmpty) return null;

    // Sort by minZoom descending (highest detail first)
    globalLods.sort((a, b) {
      final aMin = a.minZoom ?? double.negativeInfinity;
      final bMin = b.minZoom ?? double.negativeInfinity;
      return bMin.compareTo(aMin);
    });

    // Find the best GSHHG for current zoom
    for (final data in globalLods) {
      if (data.supportsZoom(zoom)) {
        return data;
      }
    }

    // Fallback to highest detail global LOD
    return globalLods.first;
  }
}
