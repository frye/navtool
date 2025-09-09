/// Enhanced chart display controls for marine navigation
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/models/chart_models.dart';
import '../../../core/services/chart_rendering_service.dart';

/// Enhanced chart navigation and display controls
class ChartDisplayControls extends StatelessWidget {
  final double zoom;
  final double rotation;
  final ChartDisplayMode displayMode;
  final ChartScale chartScale;
  final LatLng position;
  final bool isLayerPanelOpen;
  final Map<String, bool> layerVisibility;
  final List<String> availableLayers;
  
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final ValueChanged<double>? onRotationChanged;
  final VoidCallback? onResetRotation;
  final ValueChanged<ChartDisplayMode>? onDisplayModeChanged;
  final VoidCallback? onCenterPosition;
  final VoidCallback? onToggleLayerPanel;
  final ValueChanged<String>? onLayerToggle;
  final VoidCallback? onShowChartInfo;

  const ChartDisplayControls({
    super.key,
    required this.zoom,
    this.rotation = 0.0,
    required this.displayMode,
    required this.chartScale,
    required this.position,
    this.isLayerPanelOpen = false,
    this.layerVisibility = const {},
    this.availableLayers = const [],
    this.onZoomIn,
    this.onZoomOut,
    this.onRotationChanged,
    this.onResetRotation,
    this.onDisplayModeChanged,
    this.onCenterPosition,
    this.onToggleLayerPanel,
    this.onLayerToggle,
    this.onShowChartInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main navigation controls (top-right)
        Positioned(
          top: 16,
          right: 16,
          child: _buildNavigationControls(context),
        ),
        // Chart scale and position info (bottom-left)
        Positioned(
          bottom: 16,
          left: 16,
          child: _buildScaleAndPositionInfo(context),
        ),
        // Layer control panel (top-left, when open)
        if (isLayerPanelOpen)
          Positioned(
            top: 16,
            left: 16,
            child: _buildLayerControlPanel(context),
          ),
        // Display mode controls (bottom-right)
        Positioned(
          bottom: 16,
          right: 16,
          child: _buildDisplayModeControls(context),
        ),
      ],
    );
  }

  /// Build main navigation controls (zoom, rotation, center)
  Widget _buildNavigationControls(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom controls
            _buildZoomControls(context),
            const SizedBox(height: 12),
            // Rotation controls
            _buildRotationControls(context),
            const SizedBox(height: 12),
            // Center and info buttons
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  /// Build zoom controls with indicator
  Widget _buildZoomControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onZoomIn,
          icon: const Icon(Icons.add),
          tooltip: 'Zoom In',
          iconSize: 24,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              zoom.toStringAsFixed(1),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove),
          tooltip: 'Zoom Out',
          iconSize: 24,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  /// Build rotation controls with compass indicator
  Widget _buildRotationControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Compass indicator
        GestureDetector(
          onTap: onResetRotation,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainer,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Compass rose
                Center(
                  child: Transform.rotate(
                    angle: -rotation * math.pi / 180,
                    child: Icon(
                      Icons.navigation,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                ),
                // North indicator
                const Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'N',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Rotation value
        Text(
          '${rotation.round()}°',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Build action buttons (center, info, layers)
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onCenterPosition,
          icon: const Icon(Icons.my_location),
          tooltip: 'Center on Position',
          iconSize: 20,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        IconButton(
          onPressed: onToggleLayerPanel,
          icon: Icon(
            isLayerPanelOpen ? Icons.layers_clear : Icons.layers,
          ),
          tooltip: isLayerPanelOpen ? 'Close Layer Panel' : 'Open Layer Panel',
          iconSize: 20,
          style: IconButton.styleFrom(
            backgroundColor: isLayerPanelOpen 
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surface,
            foregroundColor: isLayerPanelOpen
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        IconButton(
          onPressed: onShowChartInfo,
          icon: const Icon(Icons.info_outline),
          tooltip: 'Chart Information',
          iconSize: 20,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  /// Build chart scale and position information
  Widget _buildScaleAndPositionInfo(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Position
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatLatitude(position.latitude),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      _formatLongitude(position.longitude),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Scale information
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scale: ${chartScale.label}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '1:${chartScale.scale}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build layer control panel
  Widget _buildLayerControlPanel(BuildContext context) {
    return Card(
      elevation: 6,
      child: Container(
        width: 280,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.layers,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chart Layers',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleLayerPanel,
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    style: IconButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            // Layer list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableLayers.length,
                itemBuilder: (context, index) {
                  final layer = availableLayers[index];
                  final isVisible = layerVisibility[layer] ?? true;
                  
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      _getLayerIcon(layer),
                      size: 20,
                      color: isVisible
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(
                      _formatLayerName(layer),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isVisible
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    trailing: Switch(
                      value: isVisible,
                      onChanged: (_) => onLayerToggle?.call(layer),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onTap: () => onLayerToggle?.call(layer),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build display mode controls
  Widget _buildDisplayModeControls(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current mode indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getDisplayModeIcon(displayMode),
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDisplayModeName(displayMode),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Mode cycle button
            IconButton(
              onPressed: () => _cycleDisplayMode(),
              icon: const Icon(Icons.brightness_6),
              tooltip: 'Cycle Display Mode',
              iconSize: 20,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cycle through display modes
  void _cycleDisplayMode() {
    final modes = ChartDisplayMode.values;
    final currentIndex = modes.indexOf(displayMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    onDisplayModeChanged?.call(modes[nextIndex]);
  }

  /// Format latitude for display
  String _formatLatitude(double latitude) {
    final degrees = latitude.abs().floor();
    final minutes = ((latitude.abs() - degrees) * 60).toStringAsFixed(3);
    final direction = latitude >= 0 ? 'N' : 'S';
    return '$degrees°${minutes}\' $direction';
  }

  /// Format longitude for display
  String _formatLongitude(double longitude) {
    final degrees = longitude.abs().floor();
    final minutes = ((longitude.abs() - degrees) * 60).toStringAsFixed(3);
    final direction = longitude >= 0 ? 'E' : 'W';
    return '$degrees°${minutes}\' $direction';
  }

  /// Get icon for display mode
  IconData _getDisplayModeIcon(ChartDisplayMode mode) {
    return switch (mode) {
      ChartDisplayMode.dayMode => Icons.light_mode,
      ChartDisplayMode.nightMode => Icons.dark_mode,
      ChartDisplayMode.duskMode => Icons.brightness_4,
    };
  }

  /// Format display mode name
  String _formatDisplayModeName(ChartDisplayMode mode) {
    return switch (mode) {
      ChartDisplayMode.dayMode => 'Day',
      ChartDisplayMode.nightMode => 'Night',
      ChartDisplayMode.duskMode => 'Dusk',
    };
  }

  /// Get icon for layer type
  IconData _getLayerIcon(String layer) {
    return switch (layer) {
      'depth_contours' => Icons.water,
      'navigation_aids' => Icons.navigation,
      'shoreline' => Icons.landscape,
      'restricted_areas' => Icons.warning,
      'anchorages' => Icons.anchor,
      'chart_grid' => Icons.grid_on,
      'chart_boundaries' => Icons.border_outer,
      _ => Icons.layers,
    };
  }

  /// Format layer name for display
  String _formatLayerName(String layer) {
    return switch (layer) {
      'depth_contours' => 'Depth Contours',
      'navigation_aids' => 'Navigation Aids',
      'shoreline' => 'Shoreline',
      'restricted_areas' => 'Restricted Areas',
      'anchorages' => 'Anchorages',
      'chart_grid' => 'Chart Grid',
      'chart_boundaries' => 'Chart Boundaries',
      _ => layer.replaceAll('_', ' ').split(' ').map((word) => 
          word[0].toUpperCase() + word.substring(1)).join(' '),
    };
  }
}