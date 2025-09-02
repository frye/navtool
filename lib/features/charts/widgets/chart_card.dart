import 'package:flutter/material.dart';
import 'package:navtool/core/models/chart.dart';

/// Individual chart card widget for displaying chart metadata and actions.
class ChartCard extends StatelessWidget {
  final Chart chart;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;

  const ChartCard({
    super.key,
    required this.chart,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onTap,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          label: '${chart.title} chart card',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onSelectionChanged != null) ...[
                      Semantics(
                        label: 'Select chart ${chart.title}',
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (v) {
                            if (onSelectionChanged != null) {
                              onSelectionChanged!(v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chart.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chart.id,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'Chart information for ${chart.title}',
                      child: IconButton(
                        onPressed: onInfoTap,
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'Chart information',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Chip(
                      label: Text(
                        chart.type.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _getChartTypeColor(chart.type),
                        ),
                      ),
                      backgroundColor: _getChartTypeBackgroundColor(chart.type),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Scale: 1:${_formatNumber(chart.scale)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      chart.isDownloaded ? Icons.download_done : Icons.cloud_download,
                      size: 16,
                      color: chart.isDownloaded
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chart.isDownloaded ? 'Downloaded' : 'Available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: chart.isDownloaded
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.place,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${chart.bounds.south.toStringAsFixed(1)}° - ${chart.bounds.north.toStringAsFixed(1)}°N, '
                        '${chart.bounds.east.abs().toStringAsFixed(1)}° - ${chart.bounds.west.abs().toStringAsFixed(1)}°W',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.storage,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    if (chart.fileSize != null && chart.fileSize! > 1024 * 1024)
                      Text(
                        _formatFileSize(chart.fileSize!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                    if (chart.fileSize == null)
                      Text(
                        'Size unknown',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getChartTypeColor(ChartType type) {
    switch (type) {
      case ChartType.harbor:
        return Colors.blue.shade700;
      case ChartType.approach:
        return Colors.orange.shade700;
      case ChartType.coastal:
        return Colors.green.shade700;
      case ChartType.general:
        return Colors.purple.shade700;
      case ChartType.overview:
        return Colors.grey.shade700;
      case ChartType.berthing:
        return Colors.indigo.shade700;
    }
  }

  Color _getChartTypeBackgroundColor(ChartType type) {
    switch (type) {
      case ChartType.harbor:
        return Colors.blue.shade100;
      case ChartType.approach:
        return Colors.orange.shade100;
      case ChartType.coastal:
        return Colors.green.shade100;
      case ChartType.general:
        return Colors.purple.shade100;
      case ChartType.overview:
        return Colors.grey.shade100;
      case ChartType.berthing:
        return Colors.indigo.shade100;
    }
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}