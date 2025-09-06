import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status bar that displays comprehensive navigation and system information
/// at the bottom of the application window. Provides marine navigation-focused
/// status indicators with click-to-expand functionality.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  static const double statusBarHeight = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: statusBarHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: _StatusSegment(
              icon: Icons.wifi,
              text: 'Online',
              color: Colors.green,
              onTap: () => _showConnectionStatus(context),
            ),
          ),
          _buildDivider(context),
          Flexible(
            child: _StatusSegment(
              icon: Icons.gps_fixed,
              text: 'GPS: 8 satellites',
              color: Colors.blue,
              onTap: () => _showGpsStatus(context),
            ),
          ),
          _buildDivider(context),
          Flexible(
            child: _StatusSegment(
              icon: Icons.map,
              text: 'Chart: NOAA 12345',
              color: Colors.orange,
              onTap: () => _showChartStatus(context),
            ),
          ),
          _buildDivider(context),
          Flexible(
            child: _StatusSegment(
              icon: Icons.navigation,
              text: 'Speed: 0.0 kts',
              color: Colors.grey,
              onTap: () => _showNavigationStatus(context),
            ),
          ),
          const Spacer(),
          _StatusSegment(
            icon: Icons.memory,
            text: '245 MB',
            color: Colors.grey,
            onTap: () => _showSystemStatus(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      color: Theme.of(context).dividerColor,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  void _showConnectionStatus(BuildContext context) {
    _showStatusDialog(
      context,
      'Connection Status',
      [
        'Status: Online',
        'Network: WiFi',
        'Signal Strength: Excellent',
        'Last Updated: Just now',
      ],
      Icons.wifi,
      Colors.green,
    );
  }

  void _showGpsStatus(BuildContext context) {
    _showStatusDialog(
      context,
      'GPS Status',
      [
        'Satellites: 8 in view, 6 in use',
        'Signal Quality: Good',
        'Accuracy: ± 3.2 meters',
        'Last Fix: 2 seconds ago',
        'Position: 40°45\'12"N, 73°58\'24"W',
      ],
      Icons.gps_fixed,
      Colors.blue,
    );
  }

  void _showChartStatus(BuildContext context) {
    _showStatusDialog(
      context,
      'Chart Status',
      [
        'Current Chart: NOAA 12345',
        'Chart Name: New York Harbor',
        'Edition: 45th Edition, 2024',
        'Scale: 1:20,000',
        'Last Updated: March 2024',
      ],
      Icons.map,
      Colors.orange,
    );
  }

  void _showNavigationStatus(BuildContext context) {
    _showStatusDialog(
      context,
      'Navigation Status',
      [
        'Speed: 0.0 knots',
        'Course: 000° True',
        'Heading: 000° Magnetic',
        'Distance to Destination: --',
        'ETA: --',
      ],
      Icons.navigation,
      Colors.grey,
    );
  }

  void _showSystemStatus(BuildContext context) {
    _showStatusDialog(
      context,
      'System Status',
      [
        'Memory Usage: 245 MB',
        'CPU Usage: 12%',
        'Background Tasks: 3 running',
        'Chart Cache: 1.2 GB',
        'Free Disk Space: 45.8 GB',
      ],
      Icons.memory,
      Colors.grey,
    );
  }

  void _showStatusDialog(
    BuildContext context,
    String title,
    List<String> details,
    IconData icon,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details
              .map(
                (detail) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(detail),
                ),
              )
              .toList(),
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
}

class _StatusSegment extends StatefulWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;

  const _StatusSegment({
    required this.icon,
    required this.text,
    required this.color,
    this.onTap,
  });

  @override
  State<_StatusSegment> createState() => _StatusSegmentState();
}

class _StatusSegmentState extends State<_StatusSegment> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.grey.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: widget.color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
