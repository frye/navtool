/// Enhanced chart information overlay for marine navigation
library;

import 'package:flutter/material.dart';
import '../../../core/models/chart_models.dart';
import '../../../core/models/chart.dart';
import '../../../core/services/chart_rendering_service.dart';

/// Enhanced chart information overlay with metadata and feature details
class ChartInfoOverlay extends StatelessWidget {
  final Chart? chart;
  final List<MaritimeFeature> features;
  final LatLng currentPosition;
  final double zoom;
  final ChartDisplayMode displayMode;
  final ChartScale chartScale;
  final Map<MaritimeFeatureType, int> featureCounts;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onClose;

  const ChartInfoOverlay({
    super.key,
    this.chart,
    required this.features,
    required this.currentPosition,
    required this.zoom,
    required this.displayMode,
    required this.chartScale,
    this.featureCounts = const {},
    this.isExpanded = false,
    this.onToggleExpanded,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isExpanded ? 380 : 280,
      constraints: BoxConstraints(
        maxHeight: isExpanded ? 500 : 250,
        minHeight: 150,
      ),
      child: Card(
        elevation: 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            if (isExpanded) ...[
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildExpandedContent(context),
                ),
              ),
            ] else
              Flexible(
                child: SingleChildScrollView(
                  child: _buildCompactContent(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build header with title and controls
  Widget _buildHeader(BuildContext context) {
    return Container(
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
            Icons.map,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chart?.title ?? 'Marine Chart',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onToggleExpanded,
            icon: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            iconSize: 20,
            tooltip: isExpanded ? 'Collapse' : 'Expand',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            iconSize: 20,
            tooltip: 'Close',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// Build compact content for collapsed state
  Widget _buildCompactContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBasicInfo(context),
          const SizedBox(height: 12),
          _buildFeatureSummary(context),
        ],
      ),
    );
  }

  /// Build expanded content with detailed information
  Widget _buildExpandedContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBasicInfo(context),
          const SizedBox(height: 16),
          _buildChartMetadata(context),
          const SizedBox(height: 16),
          _buildNavigationInfo(context),
          const SizedBox(height: 16),
          _buildFeatureSummary(context),
          const SizedBox(height: 16),
          _buildDisplaySettings(context),
        ],
      ),
    );
  }

  /// Build basic chart information
  Widget _buildBasicInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          context,
          'Current Position',
          '${_formatLatitude(currentPosition.latitude)}\n'
          '${_formatLongitude(currentPosition.longitude)}',
          Icons.location_on,
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          'Chart Scale',
          '${chartScale.label} (1:${chartScale.scale})',
          Icons.straighten,
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          'Zoom Level',
          '${zoom.toStringAsFixed(1)}',
          Icons.zoom_in,
        ),
      ],
    );
  }

  /// Build chart metadata (only in expanded view)
  Widget _buildChartMetadata(BuildContext context) {
    if (chart == null) {
      return _buildSectionHeader(context, 'Chart Data', Icons.description);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Chart Metadata', Icons.description),
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          'Chart ID',
          chart!.id,
          Icons.tag,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Source',
          chart!.source.displayName,
          Icons.source,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Scale',
          '1:${chart!.scale}',
          Icons.straighten,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Coverage',
          _formatBounds(chart!.bounds),
          Icons.map_outlined,
        ),
      ],
    );
  }

  /// Build navigation information
  Widget _buildNavigationInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Navigation', Icons.navigation),
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          'Display Mode',
          _formatDisplayModeName(displayMode),
          _getDisplayModeIcon(displayMode),
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Coordinate System',
          'WGS84 Geographic',
          Icons.public,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Projection',
          'Mercator',
          Icons.layers,
        ),
      ],
    );
  }

  /// Build feature summary with counts
  Widget _buildFeatureSummary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Features', Icons.category),
        const SizedBox(height: 8),
        if (featureCounts.isEmpty)
          Text(
            '${features.length} features loaded',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: featureCounts.entries.map((entry) {
              return Chip(
                avatar: Icon(
                  _getFeatureTypeIcon(entry.key),
                  size: 16,
                ),
                label: Text(
                  '${_getFeatureTypeName(entry.key)}: ${entry.value}',
                  style: const TextStyle(fontSize: 12),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
      ],
    );
  }

  /// Build display settings information
  Widget _buildDisplaySettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Display Settings', Icons.settings),
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          'Rendering Engine',
          'S-57/S-52 Compatible',
          Icons.auto_awesome,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Performance',
          'Spatial Indexing Enabled',
          Icons.speed,
        ),
        const SizedBox(height: 6),
        _buildInfoRow(
          context,
          'Safety Features',
          'Marine Standards Compliant',
          Icons.security,
        ),
      ],
    );
  }

  /// Build section header
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  /// Build information row
  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
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

  /// Format chart bounds for display
  String _formatBounds(dynamic bounds) {
    return 'N:${bounds.north.toStringAsFixed(2)}° '
           'S:${bounds.south.toStringAsFixed(2)}°\n'
           'E:${bounds.east.toStringAsFixed(2)}° '
           'W:${bounds.west.toStringAsFixed(2)}°';
  }

  /// Format display mode name
  String _formatDisplayModeName(ChartDisplayMode mode) {
    return switch (mode) {
      ChartDisplayMode.dayMode => 'Day Mode',
      ChartDisplayMode.nightMode => 'Night Mode',
      ChartDisplayMode.duskMode => 'Dusk Mode',
    };
  }

  /// Get icon for display mode
  IconData _getDisplayModeIcon(ChartDisplayMode mode) {
    return switch (mode) {
      ChartDisplayMode.dayMode => Icons.light_mode,
      ChartDisplayMode.nightMode => Icons.dark_mode,
      ChartDisplayMode.duskMode => Icons.brightness_4,
    };
  }

  /// Get icon for feature type
  IconData _getFeatureTypeIcon(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Icons.lightbulb,
      MaritimeFeatureType.beacon => Icons.navigation,
      MaritimeFeatureType.buoy => Icons.anchor,
      MaritimeFeatureType.daymark => Icons.flag,
      MaritimeFeatureType.depthContour => Icons.water,
      MaritimeFeatureType.depthArea => Icons.waves,
      MaritimeFeatureType.soundings => Icons.numbers,
      MaritimeFeatureType.shoreline => Icons.landscape,
      MaritimeFeatureType.landArea => Icons.terrain,
      MaritimeFeatureType.rocks => Icons.dangerous,
      MaritimeFeatureType.wrecks => Icons.sailing,
      MaritimeFeatureType.anchorage => Icons.anchor,
      MaritimeFeatureType.restrictedArea => Icons.warning,
      MaritimeFeatureType.trafficSeparation => Icons.timeline,
      MaritimeFeatureType.obstruction => Icons.block,
      MaritimeFeatureType.cable => Icons.cable,
      MaritimeFeatureType.pipeline => Icons.horizontal_rule,
      MaritimeFeatureType.shoreConstruction => Icons.construction,
      MaritimeFeatureType.builtArea => Icons.business,
    };
  }

  /// Get name for feature type
  String _getFeatureTypeName(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => 'Lighthouses',
      MaritimeFeatureType.beacon => 'Beacons',
      MaritimeFeatureType.buoy => 'Buoys',
      MaritimeFeatureType.daymark => 'Daymarks',
      MaritimeFeatureType.depthContour => 'Depth Contours',
      MaritimeFeatureType.depthArea => 'Depth Areas',
      MaritimeFeatureType.soundings => 'Soundings',
      MaritimeFeatureType.shoreline => 'Shoreline',
      MaritimeFeatureType.landArea => 'Land Areas',
      MaritimeFeatureType.rocks => 'Rocks',
      MaritimeFeatureType.wrecks => 'Wrecks',
      MaritimeFeatureType.anchorage => 'Anchorages',
      MaritimeFeatureType.restrictedArea => 'Restricted Areas',
      MaritimeFeatureType.trafficSeparation => 'Traffic Separation',
      MaritimeFeatureType.obstruction => 'Obstructions',
      MaritimeFeatureType.cable => 'Cables',
      MaritimeFeatureType.pipeline => 'Pipelines',
      MaritimeFeatureType.shoreConstruction => 'Shore Constructions',
      MaritimeFeatureType.builtArea => 'Built Areas',
    };
  }
}