/// Chart display screen for marine navigation
library;

import 'package:flutter/material.dart';
import '../../core/models/chart.dart';
import 'dart:math' as math;
import '../../core/models/chart_models.dart';
import '../../core/services/chart_rendering_service.dart';
import 'chart_widget.dart';

/// Screen that displays maritime charts with navigation controls
class ChartScreen extends StatefulWidget {
  final Chart? chart; // Real NOAA chart metadata (optional for backward compatibility)
  final String? chartTitle; // Fallback title if chart not provided
  final LatLng? initialPosition; // Fallback initial position

  const ChartScreen({
    super.key,
    this.chart,
    this.chartTitle,
    this.initialPosition,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late List<MaritimeFeature> _features;
  late LatLng _currentPosition;
  ChartDisplayMode _displayMode = ChartDisplayMode.dayMode;

  @override
  void initState() {
    super.initState();
    if (widget.chart != null) {
      // Center at chart bounds center
      final c = widget.chart!.bounds.center;
      _currentPosition = LatLng(c.latitude, c.longitude);
      _features = _generateFeaturesFromChart(widget.chart!);
    } else {
      _currentPosition = widget.initialPosition ?? const LatLng(37.7749, -122.4194);
      _features = _generateSampleFeatures(); // fallback for legacy route usage
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Text(widget.chart?.title ?? widget.chartTitle ?? 'Marine Chart'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _showChartInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Chart Information',
          ),
          IconButton(
            onPressed: _showChartSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Chart Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Chart status bar
          _buildStatusBar(),
          // Main chart area
          Expanded(
            child: ChartWidget(
              initialCenter: _currentPosition,
              initialZoom: 12.0,
              features: _features,
              displayMode: _displayMode,
              onPositionChanged: (newPosition) {
                setState(() {
                  _currentPosition = newPosition;
                });
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  /// Build chart status bar showing key information
  Widget _buildStatusBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(50),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Show simplified layout on very small screens
          if (constraints.maxWidth < 400) {
            return Row(
              children: [
                Icon(
                  Icons.map,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_features.length} features',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _displayMode == ChartDisplayMode.dayMode ? Icons.light_mode : Icons.dark_mode,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            );
          }
          
          // Full layout for larger screens
          return Row(
            children: [
              Icon(
                Icons.map,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chart: ${widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _displayMode == ChartDisplayMode.dayMode ? Icons.light_mode : Icons.dark_mode,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _displayMode == ChartDisplayMode.dayMode ? 'Day' : 'Night',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.layers,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '${_features.length} features',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build floating action buttons for quick actions
  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: _addWaypoint,
          heroTag: 'waypoint',
          tooltip: 'Add Waypoint',
          child: const Icon(Icons.add_location),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          onPressed: _measureDistance,
          heroTag: 'measure',
          tooltip: 'Measure Distance',
          child: const Icon(Icons.straighten),
        ),
      ],
    );
  }

  /// Show chart information dialog
  void _showChartInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Information'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Chart Title', widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart'),
                if (widget.chart != null) ...[
                  _buildInfoRow('Chart ID', widget.chart!.id),
                  _buildInfoRow('Scale', '1:${widget.chart!.scale}'),
                  _buildInfoRow('Source', widget.chart!.source.displayName),
                  _buildInfoRow('Bounds',
                      'N:${widget.chart!.bounds.north.toStringAsFixed(4)} '
                      'S:${widget.chart!.bounds.south.toStringAsFixed(4)} '
                      'E:${widget.chart!.bounds.east.toStringAsFixed(4)} '
                      'W:${widget.chart!.bounds.west.toStringAsFixed(4)}'),
                ],
                _buildInfoRow('Current Position', 
                    '${_currentPosition.latitude.toStringAsFixed(6)}, ${_currentPosition.longitude.toStringAsFixed(6)}'),
                _buildInfoRow('Features Loaded', '${_features.length}'),
                _buildInfoRow('Display Mode', _displayMode.name),
                const SizedBox(height: 16),
                Text(
                  widget.chart == null
                      ? 'Demonstration chart with sample features (no NOAA chart provided).'
                      : 'Rendering simplified bounding box for real NOAA chart metadata.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build information row for dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  /// Show chart settings dialog
  void _showChartSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Display Mode'),
              trailing: DropdownButton<ChartDisplayMode>(
                value: _displayMode,
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() {
                      _displayMode = mode;
                    });
                    Navigator.of(context).pop();
                  }
                },
                items: ChartDisplayMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(mode.name),
                  );
                }).toList(),
              ),
            ),
            ListTile(
              title: const Text('Feature Visibility'),
              trailing: const Icon(Icons.visibility),
              onTap: () {
                Navigator.of(context).pop();
                _showFeatureVisibilitySettings();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show feature visibility settings
  void _showFeatureVisibilitySettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feature visibility controls will be implemented in a future version'),
      ),
    );
  }

  /// Add waypoint at current position
  void _addWaypoint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Waypoint added at ${_currentPosition.latitude.toStringAsFixed(4)}, ${_currentPosition.longitude.toStringAsFixed(4)}'),
      ),
    );
  }

  /// Measure distance tool
  void _measureDistance() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Distance measurement tool will be implemented in a future version'),
      ),
    );
  }

  /// Generate minimal real features from a NOAA chart's bounding box
  List<MaritimeFeature> _generateFeaturesFromChart(Chart chart) {
    final b = chart.bounds;
  final c = b.center;
  final center = LatLng(c.latitude, c.longitude);
    final polygon = [
      LatLng(b.north, b.west),
      LatLng(b.north, b.east),
      LatLng(b.south, b.east),
      LatLng(b.south, b.west),
    ];

    return [
      AreaFeature(
        id: 'chart_bounds_${chart.id}',
        type: MaritimeFeatureType.restrictedArea,
        position: center,
        coordinates: [polygon],
        fillColor: const Color(0x22007AFF),
        strokeColor: const Color(0xFF007AFF),
        attributes: {
          'chartId': chart.id,
          'scale': chart.scale,
          'source': chart.source.displayName,
        },
      ),
      PointFeature(
        id: 'chart_center_${chart.id}',
        type: MaritimeFeatureType.beacon,
        position: center,
        label: chart.id,
        attributes: {'role': 'center'},
      ),
    ];
  }

  /// Generate sample maritime features for demonstration (legacy fallback)
  List<MaritimeFeature> _generateSampleFeatures() {
    final List<MaritimeFeature> features = [];

    // Add sample lighthouse
    features.add(PointFeature(
      id: 'lighthouse_1',
      type: MaritimeFeatureType.lighthouse,
      position: const LatLng(37.8199, -122.4783),
      label: 'Alcatraz Light',
      attributes: {'height': 84, 'range': 22},
    ));

    // Add sample buoys
    features.add(PointFeature(
      id: 'buoy_1',
      type: MaritimeFeatureType.buoy,
      position: const LatLng(37.7849, -122.4594),
      label: 'SF-1',
      attributes: {'color': 'red', 'type': 'lateral'},
    ));

    features.add(PointFeature(
      id: 'buoy_2',
      type: MaritimeFeatureType.buoy,
      position: const LatLng(37.7949, -122.4694),
      label: 'SF-2',
      attributes: {'color': 'green', 'type': 'lateral'},
    ));

    // Add sample beacon
    features.add(PointFeature(
      id: 'beacon_1',
      type: MaritimeFeatureType.beacon,
      position: const LatLng(37.8049, -122.4394),
      label: 'Bay Bridge Beacon',
      attributes: {'type': 'radar_reflector'},
    ));

    // Add sample shoreline
    features.add(LineFeature(
      id: 'shoreline_1',
      type: MaritimeFeatureType.shoreline,
      position: const LatLng(37.7749, -122.4194),
      coordinates: [
        const LatLng(37.7649, -122.4094),
        const LatLng(37.7749, -122.4194),
        const LatLng(37.7849, -122.4294),
        const LatLng(37.7949, -122.4394),
      ],
      width: 2.0,
    ));

    // Add sample land area
    features.add(AreaFeature(
      id: 'land_1',
      type: MaritimeFeatureType.landArea,
      position: const LatLng(37.7749, -122.4094),
      coordinates: [
        [
          const LatLng(37.7649, -122.4094),
          const LatLng(37.7649, -122.3994),
          const LatLng(37.7849, -122.3994),
          const LatLng(37.7849, -122.4094),
        ]
      ],
    ));

    // Add sample depth contours
    for (int depth = 10; depth <= 50; depth += 10) {
      features.add(DepthContour(
        id: 'depth_${depth}m',
        coordinates: _generateContourLine(depth.toDouble()),
        depth: depth.toDouble(),
      ));
    }

    // Add sample anchorage area
    features.add(AreaFeature(
      id: 'anchorage_1',
      type: MaritimeFeatureType.anchorage,
      position: const LatLng(37.7949, -122.4594),
      coordinates: [
        [
          const LatLng(37.7899, -122.4644),
          const LatLng(37.7899, -122.4544),
          const LatLng(37.7999, -122.4544),
          const LatLng(37.7999, -122.4644),
        ]
      ],
      fillColor: Colors.blue.withAlpha(50),
      strokeColor: Colors.blue,
    ));

    return features;
  }

  /// Generate a sample depth contour line
  List<LatLng> _generateContourLine(double depth) {
    final List<LatLng> points = [];
    final int numPoints = 20;
    final double radius = 0.01 * depth / 10; // Larger radius for deeper contours

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i / numPoints) * 2 * math.pi;
      final double lat = _currentPosition.latitude + radius * (1 + depth / 100) * 0.5 * (1 + 0.3 * (i % 3)) * math.cos(angle);
      final double lng = _currentPosition.longitude + radius * (1 + depth / 100) * 0.5 * (1 + 0.3 * (i % 3)) * math.sin(angle);
      points.add(LatLng(lat, lng));
    }

    return points;
  }
}
