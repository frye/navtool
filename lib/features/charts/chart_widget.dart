/// Interactive chart widget for marine navigation
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/models/chart_models.dart';
import '../../core/services/coordinate_transform.dart';
import '../../core/services/chart_rendering_service.dart';

/// Main chart widget that displays maritime charts with interactive controls
class ChartWidget extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final List<MaritimeFeature> features;
  final ChartDisplayMode displayMode;
  final VoidCallback? onChartTap;
  final Function(LatLng)? onPositionChanged;

  const ChartWidget({
    super.key,
    this.initialCenter = const LatLng(37.7749, -122.4194), // San Francisco
    this.initialZoom = 10.0,
    this.features = const [],
    this.displayMode = ChartDisplayMode.dayMode,
    this.onChartTap,
    this.onPositionChanged,
  });

  @override
  State<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends State<ChartWidget> {
  late LatLng _center;
  late double _zoom;
  late ChartDisplayMode _displayMode;
  
  // Scale gesture state
  double? _lastScaleValue;
  Offset? _lastFocalPoint;
  Offset? _scaleCenter;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _zoom = widget.initialZoom;
    _displayMode = widget.displayMode;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: widget.onChartTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              children: [
                // Main chart canvas
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _ChartPainter(
                    center: _center,
                    zoom: _zoom,
                    features: widget.features,
                    displayMode: _displayMode,
                  ),
                ),
                // Chart controls overlay
                _buildControlsOverlay(constraints),
                // Chart info overlay
                _buildInfoOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build chart controls overlay
  Widget _buildControlsOverlay(BoxConstraints constraints) {
    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        children: [
          // Zoom controls
          Card(
            child: Column(
              children: [
                IconButton(
                  onPressed: _zoomIn,
                  icon: const Icon(Icons.add),
                  tooltip: 'Zoom In',
                ),
                IconButton(
                  onPressed: _zoomOut,
                  icon: const Icon(Icons.remove),
                  tooltip: 'Zoom Out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Day/Night mode toggle
          Card(
            child: IconButton(
              onPressed: _toggleDisplayMode,
              icon: Icon(_displayMode == ChartDisplayMode.dayMode 
                  ? Icons.dark_mode 
                  : Icons.light_mode),
              tooltip: _displayMode == ChartDisplayMode.dayMode 
                  ? 'Switch to Night Mode' 
                  : 'Switch to Day Mode',
            ),
          ),
          const SizedBox(height: 8),
          // Center position button
          Card(
            child: IconButton(
              onPressed: _centerOnPosition,
              icon: const Icon(Icons.my_location),
              tooltip: 'Center on Position',
            ),
          ),
        ],
      ),
    );
  }

  /// Build chart information overlay
  Widget _buildInfoOverlay() {
    final transform = CoordinateTransform(
      zoom: _zoom,
      center: _center,
      screenSize: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
    );

    return Positioned(
      bottom: 16,
      left: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Position: ${CoordinateUtils.formatLatitude(_center.latitude)}, ${CoordinateUtils.formatLongitude(_center.longitude)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                'Zoom: ${_zoom.toStringAsFixed(1)} | Scale: ${transform.chartScale.label}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Mode: ${_displayMode.name}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle scale start (includes pan and zoom)
  void _onScaleStart(ScaleStartDetails details) {
    _lastScaleValue = 1.0;
    _lastFocalPoint = details.localFocalPoint;
    _scaleCenter = details.localFocalPoint;
  }

  /// Handle scale update (includes pan and zoom)
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_lastScaleValue == null || _lastFocalPoint == null) return;

    final transform = CoordinateTransform(
      zoom: _zoom,
      center: _center,
      screenSize: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
    );

    setState(() {
      // Handle panning (when scale is approximately 1.0)
      if ((details.scale - 1.0).abs() < 0.01) {
        // This is primarily a pan gesture
        final delta = details.localFocalPoint - _lastFocalPoint!;
        
        // Convert screen delta to geographic delta
        final deltaLng = -delta.dx / transform.pixelsPerDegree;
        final deltaLat = delta.dy / transform.pixelsPerDegree;

        _center = LatLng(
          (_center.latitude + deltaLat).clamp(-85.0, 85.0),
          CoordinateUtils.normalizeLongitude(_center.longitude + deltaLng),
        );
      } else {
        // Handle zooming
        final scaleChange = details.scale / _lastScaleValue!;
        
        // Update zoom level
        _zoom = (_zoom + math.log(scaleChange) / math.ln2).clamp(2.0, 18.0);

        // Adjust center point to zoom toward gesture center
        if (_scaleCenter != null) {
          final screenCenter = Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          );

          final focalDelta = _scaleCenter! - screenCenter;
          final scaleFactor = (scaleChange - 1.0) * 0.1;

          final deltaLng = -focalDelta.dx * scaleFactor / transform.pixelsPerDegree;
          final deltaLat = focalDelta.dy * scaleFactor / transform.pixelsPerDegree;

          _center = LatLng(
            (_center.latitude + deltaLat).clamp(-85.0, 85.0),
            CoordinateUtils.normalizeLongitude(_center.longitude + deltaLng),
          );
        }
      }
    });

    _lastScaleValue = details.scale;
    _lastFocalPoint = details.localFocalPoint;
    widget.onPositionChanged?.call(_center);
  }

  /// Handle scale end
  void _onScaleEnd(ScaleEndDetails details) {
    _lastScaleValue = null;
    _lastFocalPoint = null;
    _scaleCenter = null;
  }

  /// Zoom in
  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + 1.0).clamp(2.0, 18.0);
    });
    widget.onPositionChanged?.call(_center);
  }

  /// Zoom out
  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - 1.0).clamp(2.0, 18.0);
    });
    widget.onPositionChanged?.call(_center);
  }

  /// Toggle display mode between day and night
  void _toggleDisplayMode() {
    setState(() {
      _displayMode = _displayMode == ChartDisplayMode.dayMode
          ? ChartDisplayMode.nightMode
          : ChartDisplayMode.dayMode;
    });
  }

  /// Center on current position (placeholder implementation)
  void _centerOnPosition() {
    // In a real implementation, this would get GPS position
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GPS positioning will be implemented in a future version'),
      ),
    );
  }

  /// Update chart center programmatically
  void updateCenter(LatLng newCenter) {
    setState(() {
      _center = newCenter;
    });
    widget.onPositionChanged?.call(_center);
  }

  /// Update zoom level programmatically
  void updateZoom(double newZoom) {
    setState(() {
      _zoom = newZoom.clamp(2.0, 18.0);
    });
  }

  /// Get current chart bounds
  LatLngBounds getCurrentBounds() {
    final transform = CoordinateTransform(
      zoom: _zoom,
      center: _center,
      screenSize: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
    );
    return transform.visibleBounds;
  }
}

/// Custom painter for rendering the chart
class _ChartPainter extends CustomPainter {
  final LatLng center;
  final double zoom;
  final List<MaritimeFeature> features;
  final ChartDisplayMode displayMode;

  _ChartPainter({
    required this.center,
    required this.zoom,
    required this.features,
    required this.displayMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final transform = CoordinateTransform(
      zoom: zoom,
      center: center,
      screenSize: size,
    );

    final renderingService = ChartRenderingService(
      transform: transform,
      features: features,
      displayMode: displayMode,
    );

    renderingService.render(canvas, size);
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.zoom != zoom ||
        oldDelegate.features != features ||
        oldDelegate.displayMode != displayMode;
  }
}
