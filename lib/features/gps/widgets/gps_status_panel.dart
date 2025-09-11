import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/gps_signal_quality.dart';
import '../providers/gps_providers.dart';
import 'gps_status_indicator.dart';
import 'navigation_instruments.dart';
import 'vessel_position_overlay.dart';

/// Panel that shows comprehensive GPS status and navigation information
class GpsStatusPanel extends ConsumerStatefulWidget {
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;

  const GpsStatusPanel({
    super.key,
    this.isExpanded = false,
    this.onToggleExpanded,
  });

  @override
  ConsumerState<GpsStatusPanel> createState() => _GpsStatusPanelState();
}

class _GpsStatusPanelState extends ConsumerState<GpsStatusPanel> {
  @override
  Widget build(BuildContext context) {
    final currentPosition = ref.watch(latestGpsPositionProvider);
    final isTracking = ref.watch(isGpsTrackingProvider);
    final signalQuality = ref.watch(gpsSignalQualityProvider);

    return Card(
      elevation: 4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: widget.isExpanded ? 360 : 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with expand/collapse button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.gps_fixed,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS Status',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.onToggleExpanded != null)
                    IconButton(
                      onPressed: widget.onToggleExpanded,
                      icon: Icon(
                        widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      iconSize: 20,
                    ),
                ],
              ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GPS status indicator
                  const DetailedGpsStatusPanel(),
                  
                  if (widget.isExpanded) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                    
                    // Vessel position info
                    const VesselPositionInfo(),
                    
                    const SizedBox(height: 12),
                    
                    // Navigation instruments (compact)
                    const NavigationInstruments(isCompact: true),
                    
                    const SizedBox(height: 12),
                    
                    // GPS actions
                    _buildGpsActions(context),
                  ] else if (currentPosition != null) ...[
                    const SizedBox(height: 8),
                    // Compact position display
                    Text(
                      currentPosition.toCoordinateString(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () => _centerMapOnVessel(),
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Center Map'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showTrackHistory(),
              icon: const Icon(Icons.timeline, size: 16),
              label: const Text('Track History'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showGpsSettings(),
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _centerMapOnVessel() {
    final currentPosition = ref.read(latestGpsPositionProvider);
    if (currentPosition != null) {
      // TODO: Integrate with chart widget to center on vessel position
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Centering on vessel position: ${currentPosition.toCoordinateString()}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS position available'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showTrackHistory() {
    showDialog(
      context: context,
      builder: (context) => const TrackHistoryDialog(),
    );
  }

  void _showGpsSettings() {
    showDialog(
      context: context,
      builder: (context) => const GpsSettingsDialog(),
    );
  }
}

/// Dialog showing vessel track history
class TrackHistoryDialog extends ConsumerWidget {
  const TrackHistoryDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackHistory = ref.watch(vesselTrackProvider(const Duration(hours: 6)));
    final accuracyStats = ref.watch(gpsAccuracyStatsProvider(const Duration(hours: 1)));

    return AlertDialog(
      title: const Text('Vessel Track History'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              trackHistory.when(
                data: (history) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last 6 Hours',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Total Distance: ${(history.totalDistance / 1000).toStringAsFixed(2)} km'),
                    Text('Average Speed: ${history.averageSpeedKnots.toStringAsFixed(1)} kts'),
                    Text('Max Speed: ${history.maxSpeedKnots.toStringAsFixed(1)} kts'),
                    Text('Duration: ${_formatDuration(history.duration)}'),
                    Text('Position Count: ${history.positions.length}'),
                    const SizedBox(height: 12),
                    Text('Marine Grade: ${(history.marineGradePercentage * 100).toStringAsFixed(0)}%'),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('Error loading track: $error'),
              ),
              const SizedBox(height: 16),
              accuracyStats.when(
                data: (stats) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GPS Accuracy (Last Hour)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Average: ±${stats.averageAccuracy.toStringAsFixed(1)}m'),
                    Text('Best: ±${stats.bestAccuracy.toStringAsFixed(1)}m'),
                    Text('Worst: ±${stats.worstAccuracy.toStringAsFixed(1)}m'),
                    Text('Marine Grade: ${(stats.marineGradePercentage * 100).toStringAsFixed(0)}%'),
                    Text('Sample Count: ${stats.sampleCount}'),
                  ],
                ),
                loading: () => const Text('Loading accuracy stats...'),
                error: (error, _) => Text('Error loading stats: $error'),
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
        ElevatedButton(
          onPressed: () => _clearTrackHistory(context, ref),
          child: const Text('Clear History'),
        ),
      ],
    );
  }

  void _clearTrackHistory(BuildContext context, WidgetRef ref) async {
    final gpsService = ref.read(gpsServiceProvider);
    await gpsService.clearPositionHistory();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Track history cleared'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

/// Dialog for GPS settings and configuration
class GpsSettingsDialog extends ConsumerWidget {
  const GpsSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpsService = ref.read(gpsServiceProvider);
    
    return AlertDialog(
      title: const Text('GPS Settings'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GPS Configuration',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Location Permission'),
              subtitle: const Text('Check location service permissions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _checkLocationPermissions(context, gpsService),
            ),
            
            ListTile(
              leading: const Icon(Icons.gps_fixed),
              title: const Text('Location Services'),
              subtitle: const Text('Check if location services are enabled'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _checkLocationServices(context, gpsService),
            ),
            
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Restart GPS'),
              subtitle: const Text('Restart GPS tracking'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _restartGpsTracking(context, gpsService),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _checkLocationPermissions(BuildContext context, gpsService) async {
    final hasPermission = await gpsService.checkLocationPermission();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPermission 
                ? 'Location permission granted' 
                : 'Location permission denied',
          ),
          backgroundColor: hasPermission ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      
      if (!hasPermission) {
        await gpsService.requestLocationPermission();
      }
    }
  }

  void _checkLocationServices(BuildContext context, gpsService) async {
    final isEnabled = await gpsService.isLocationEnabled();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnabled 
                ? 'Location services enabled' 
                : 'Location services disabled',
          ),
          backgroundColor: isEnabled ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _restartGpsTracking(BuildContext context, gpsService) async {
    try {
      await gpsService.stopLocationTracking();
      await gpsService.startLocationTracking();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS tracking restarted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error restarting GPS: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}