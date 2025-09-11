/// Interactive chart widget for marine navigation
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../core/models/chart_models.dart';
import '../../core/services/coordinate_transform.dart';
import '../../core/services/chart_rendering_service.dart';
import '../gps/widgets/vessel_position_overlay.dart';
import '../gps/providers/gps_providers.dart';
import 'widgets/chart_display_controls.dart';
import 'widgets/chart_info_overlay.dart';

/// Main chart widget that displays maritime charts with interactive controls
class ChartWidget extends ConsumerStatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final List<MaritimeFeature> features;
  final ChartDisplayMode displayMode;
  final bool showVesselPosition;
  final bool showVesselTrack;
  final VoidCallback? onChartTap;
  final Function(LatLng)? onPositionChanged;

  const ChartWidget({
    super.key,
    this.initialCenter = const LatLng(37.7749, -122.4194), // San Francisco
    this.initialZoom = 10.0,
    this.features = const [],
    this.displayMode = ChartDisplayMode.dayMode,
    this.showVesselPosition = true,
    this.showVesselTrack = true,
    this.onChartTap,
    this.onPositionChanged,
  });

  @override
  ConsumerState<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends ConsumerState<ChartWidget> {
  late LatLng _center;
  late double _zoom;
  late ChartDisplayMode _displayMode;
  late double _rotation;

  // UI state
  bool _isLayerPanelOpen = false;
  bool _isInfoOverlayOpen = false;
  bool _isInfoOverlayExpanded = false;
  Map<String, bool> _layerVisibility = {};
  late List<String> _availableLayers;

  // Rendering service for enhanced controls
  late ChartRenderingService _renderingService;

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
    _rotation = 0.0;
    
    // Initialize default layer visibility (will be updated in didChangeDependencies)
    _layerVisibility = {
      'depth_contours': true,
      'navigation_aids': true,
      'shoreline': true,
      'restricted_areas': true,
      'anchorages': true,
      'chart_grid': false,
      'chart_boundaries': true,
    };
    
    _availableLayers = _layerVisibility.keys.toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeRenderingService();
  }

  void _initializeRenderingService() {
    final transform = CoordinateTransform(
      zoom: _zoom,
      center: _center,
      screenSize: Size(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height,
      ),
    );
    
    _renderingService = ChartRenderingService(
      transform: transform,
      features: widget.features,
      displayMode: _displayMode,
    );
    
    // Update available layers from rendering service
    try {
      _availableLayers = _renderingService.getLayers();
      // Update layer visibility map to include any new layers
      for (String layer in _availableLayers) {
        _layerVisibility[layer] ??= true;
      }
    } catch (e) {
      // Fallback if rendering service doesn't have layers method
      // Keep existing layer visibility
    }
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
                    rotation: _rotation,
                    layerVisibility: _layerVisibility,
                  ),
                ),
                
                // Vessel position overlay
                if (widget.showVesselPosition)
                  _buildVesselPositionOverlay(constraints),
                
                // Enhanced chart display controls
                ChartDisplayControls(
                  zoom: _zoom,
                  rotation: _rotation,
                  displayMode: _displayMode,
                  chartScale: ChartScale.fromZoom(_zoom),
                  position: _center,
                  isLayerPanelOpen: _isLayerPanelOpen,
                  layerVisibility: _layerVisibility,
                  availableLayers: _availableLayers,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onRotationChanged: _onRotationChanged,
                  onResetRotation: _resetRotation,
                  onDisplayModeChanged: _onDisplayModeChanged,
                  onCenterPosition: _centerOnPosition,
                  onToggleLayerPanel: _toggleLayerPanel,
                  onLayerToggle: _toggleLayer,
                  onShowChartInfo: _showChartInfo,
                ),
                // Enhanced chart info overlay
                if (_isInfoOverlayOpen)
                  Positioned(
                    top: 80,
                    right: 16,
                    child: ChartInfoOverlay(
                      features: widget.features,
                      currentPosition: _center,
                      zoom: _zoom,
                      displayMode: _displayMode,
                      chartScale: ChartScale.fromZoom(_zoom),
                      featureCounts: _getFeatureCounts(),
                      isExpanded: _isInfoOverlayExpanded,
                      onToggleExpanded: _toggleInfoOverlayExpanded,
                      onClose: _closeInfoOverlay,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
      screenSize: Size(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height,
      ),
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

          final deltaLng =
              -focalDelta.dx * scaleFactor / transform.pixelsPerDegree;
          final deltaLat =
              focalDelta.dy * scaleFactor / transform.pixelsPerDegree;

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

  /// Change display mode
  void _onDisplayModeChanged(ChartDisplayMode mode) {
    setState(() {
      _displayMode = mode;
      _initializeRenderingService();
    });
  }

  /// Handle rotation change
  void _onRotationChanged(double rotation) {
    setState(() {
      _rotation = rotation;
    });
  }

  /// Reset rotation to north up
  void _resetRotation() {
    setState(() {
      _rotation = 0.0;
    });
  }

  /// Toggle layer panel visibility
  void _toggleLayerPanel() {
    setState(() {
      _isLayerPanelOpen = !_isLayerPanelOpen;
    });
  }

  /// Toggle layer visibility
  void _toggleLayer(String layerName) {
    setState(() {
      _layerVisibility[layerName] = !(_layerVisibility[layerName] ?? true);
      _renderingService.setLayerVisible(layerName, _layerVisibility[layerName]!);
    });
  }

  /// Show chart information overlay
  void _showChartInfo() {
    setState(() {
      _isInfoOverlayOpen = true;
    });
  }

  /// Close chart information overlay
  void _closeInfoOverlay() {
    setState(() {
      _isInfoOverlayOpen = false;
      _isInfoOverlayExpanded = false;
    });
  }

  /// Toggle info overlay expanded state
  void _toggleInfoOverlayExpanded() {
    setState(() {
      _isInfoOverlayExpanded = !_isInfoOverlayExpanded;
    });
  }

  /// Get feature counts by type
  Map<MaritimeFeatureType, int> _getFeatureCounts() {
    final counts = <MaritimeFeatureType, int>{};
    for (final feature in widget.features) {
      counts[feature.type] = (counts[feature.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Build vessel position overlay widget
  Widget _buildVesselPositionOverlay(BoxConstraints constraints) {
    final transform = CoordinateTransform(
      zoom: _zoom,
      center: _center,
      screenSize: Size(constraints.maxWidth, constraints.maxHeight),
    );

    return VesselPositionOverlay(
      transform: transform,
      canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
      showTrack: widget.showVesselTrack,
      showHeading: true,
      showAccuracyCircle: true,
      trackDuration: const Duration(minutes: 30),
      vesselColor: Colors.red,
      trackColor: Colors.blue.withAlpha(180),
      vesselSize: 16.0,
    );
  }

  /// Center on current GPS position
  void _centerOnPosition() async {
    try {
      final gpsPosition = ref.read(latestGpsPositionProvider);
      if (gpsPosition != null) {
        setState(() {
          _center = LatLng(gpsPosition.latitude, gpsPosition.longitude);
        });
        widget.onPositionChanged?.call(_center);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Centered on vessel position: ${gpsPosition.toCoordinateString()}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No GPS position available'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error centering on GPS position: $error'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      screenSize: Size(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height,
      ),
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
  final double rotation;
  final Map<String, bool> layerVisibility;

  _ChartPainter({
    required this.center,
    required this.zoom,
    required this.features,
    required this.displayMode,
    this.rotation = 0.0,
    this.layerVisibility = const {},
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

    // Apply layer visibility settings
    for (final entry in layerVisibility.entries) {
      renderingService.setLayerVisible(entry.key, entry.value);
    }

    // Apply rotation if needed
    if (rotation != 0.0) {
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(rotation * math.pi / 180);
      canvas.translate(-size.width / 2, -size.height / 2);
      renderingService.render(canvas, size);
      canvas.restore();
    } else {
      renderingService.render(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.zoom != zoom ||
        oldDelegate.features != features ||
        oldDelegate.displayMode != displayMode ||
        oldDelegate.rotation != rotation ||
        oldDelegate.layerVisibility != layerVisibility;
  }
}
