import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/providers.dart';

/// Widget to display current GPS status and position
class GpsStatusWidget extends ConsumerWidget {
  const GpsStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.gps_fixed,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'GPS Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildGpsStatus(context, ref),
            const SizedBox(height: 12),
            _buildPositionDisplay(context, ref),
            const SizedBox(height: 12),
            _buildGpsActions(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatus(BuildContext context, WidgetRef ref) {
    final gpsStatus = ref.watch(gpsStatusProvider);

    return Row(
      children: [
        Icon(
          gpsStatus.enabled ? Icons.check_circle : Icons.error,
          color: gpsStatus.enabled ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            gpsStatus.enabled ? 'GPS Service Active' : 'GPS Service Inactive',
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionDisplay(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(gpsPositionProvider);

    return positionAsync.when(
      data: (position) {
        if (position == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_searching,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No position available',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current Position',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCoordinateRow(
                context,
                'Latitude:',
                '${position.latitude.toStringAsFixed(6)}°',
              ),
              _buildCoordinateRow(
                context,
                'Longitude:',
                '${position.longitude.toStringAsFixed(6)}°',
              ),
              if (position.altitude != null)
                _buildCoordinateRow(
                  context,
                  'Altitude:',
                  '${position.altitude!.toStringAsFixed(1)} m',
                ),
              if (position.accuracy != null)
                _buildCoordinateRow(
                  context,
                  'Accuracy:',
                  '±${position.accuracy!.toStringAsFixed(1)} m',
                ),
              if (position.speed != null && position.speed! > 0)
                _buildCoordinateRow(
                  context,
                  'Speed:',
                  '${(position.speed! * 1.944).toStringAsFixed(1)} knots',
                ),
              if (position.heading != null)
                _buildCoordinateRow(
                  context,
                  'Heading:',
                  '${position.heading!.toStringAsFixed(0)}°',
                ),
              const SizedBox(height: 8),
              Text(
                'Last updated: ${_formatTime(position.timestamp)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Getting GPS position...',
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'GPS Error: ${error.toString()}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinateRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsActions(BuildContext context, WidgetRef ref) {
    final gpsService = ref.read(gpsServiceProvider);

    return Row(
      children: [
        // Check if we need a permission request button
        FutureBuilder<bool>(
          future: gpsService.checkLocationPermission(),
          builder: (context, snapshot) {
            final hasPermission = snapshot.data ?? false;

            if (!hasPermission) {
              return Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final granted = await gpsService
                        .requestLocationPermission();

                    if (granted) {
                      // Refresh position after permission granted
                      ref.invalidate(gpsPositionProvider);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Location permission granted! Updating position...',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Location permission denied. Using fallback coordinates.',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text('Enable Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              );
            }

            return Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Invalidate the provider to trigger a refresh
                  ref.invalidate(gpsPositionProvider);

                  // Show feedback to user
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing GPS position...'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Update Position'),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            _showGpsInfo(context);
          },
          icon: const Icon(Icons.info_outline),
          tooltip: 'GPS Information',
        ),
      ],
    );
  }

  void _showGpsInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Information'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GPS Service Status'),
            SizedBox(height: 8),
            Text('• Cross-platform GPS implementation'),
            Text('• Windows: Win32 API for native location services'),
            Text('• macOS/Linux: Geolocator package for standard location'),
            Text('• Real GPS integration with platform-specific optimizations'),
            SizedBox(height: 12),
            Text(
              'Marine Navigation Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('• High accuracy positioning'),
            Text('• Distance and bearing calculations'),
            Text('• Position tracking and waypoint navigation'),
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
