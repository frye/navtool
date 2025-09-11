import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/gps/providers/gps_providers.dart';
import '../features/gps/widgets/gps_status_indicator.dart';

/// A simple status bar widget for macOS applications
/// Displays status text and GPS status at the bottom of the window
class MacosStatusBar extends ConsumerWidget {
  final String statusText;

  const MacosStatusBar({super.key, required this.statusText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTracking = ref.watch(isGpsTrackingProvider);
    final currentPosition = ref.watch(latestGpsPositionProvider);
    
    return Container(
      constraints: const BoxConstraints(minHeight: 24.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(50),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              statusText,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // GPS Status Indicator
          if (isTracking && currentPosition != null) ...[
            Icon(
              Icons.gps_fixed,
              size: 14,
              color: Colors.green,
            ),
            const SizedBox(width: 4),
            Text(
              currentPosition.toCoordinateString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ] else ...[
            Icon(
              Icons.gps_off,
              size: 14,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              'GPS Inactive',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
