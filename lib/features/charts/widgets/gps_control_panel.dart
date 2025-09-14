import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/providers.dart';
import '../../../core/models/gps_position.dart';
import '../../../core/models/gps_signal_quality.dart';

/// GPS control panel widget for chart integration
class GpsControlPanel extends ConsumerWidget {
  final VoidCallback? onTrackToggle;
  final VoidCallback? onCenterOnVessel;
  final bool showTrackControls;
  final bool isCompact;
  
  const GpsControlPanel({
    super.key,
    this.onTrackToggle,
    this.onCenterOnVessel,
    this.showTrackControls = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isCompact) {
      return _buildCompactPanel(context, ref);
    } else {
      return _buildFullPanel(context, ref);
    }
  }

  /// Build compact GPS panel for overlay use
  Widget _buildCompactPanel(BuildContext context, WidgetRef ref) {
    final gpsStatus = ref.watch(gpsStatusProvider);
    final gpsPosition = ref.watch(gpsPositionProvider);
    
    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(8),
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // GPS Status indicator
            Row(
              children: [
                Icon(
                  gpsStatus.hasPosition ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: gpsStatus.hasPosition ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  gpsStatus.hasPosition ? 'GPS Lock' : 'No GPS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Position display (compact)
            gpsPosition.when(
              data: (position) => position != null
                  ? _buildCompactPositionDisplay(context, position)
                  : Text(
                      'No position',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
              loading: () => const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, stack) => Text(
                'GPS Error',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Center on vessel button
                if (onCenterOnVessel != null)
                  Tooltip(
                    message: 'Center on vessel',
                    child: IconButton(
                      onPressed: gpsStatus.hasPosition ? onCenterOnVessel : null,
                      icon: const Icon(Icons.my_location),
                      iconSize: 16,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                
                // Track recording toggle
                if (showTrackControls)
                  _buildTrackToggleButton(context, ref, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build full GPS panel
  Widget _buildFullPanel(BuildContext context, WidgetRef ref) {
    final gpsStatus = ref.watch(gpsStatusProvider);
    final gpsPosition = ref.watch(gpsPositionProvider);
    final gpsQuality = ref.watch(gpsSignalQualityProvider);
    final courseOverGround = ref.watch(courseOverGroundProvider);
    final speedOverGround = ref.watch(speedOverGroundProvider);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.gps_fixed,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'GPS Navigation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Settings button
                IconButton(
                  onPressed: () => _showGpsSettings(context, ref),
                  icon: const Icon(Icons.settings),
                  tooltip: 'GPS Settings',
                ),
              ],
            ),
            
            const Divider(),
            
            // GPS Status
            _buildGpsStatusSection(context, ref),
            
            const SizedBox(height: 12),
            
            // Position Information
            _buildPositionSection(context, gpsPosition),
            
            const SizedBox(height: 12),
            
            // Navigation Information
            _buildNavigationSection(context, courseOverGround, speedOverGround),
            
            const SizedBox(height: 12),
            
            // Signal Quality
            _buildSignalQualitySection(context, gpsQuality),
            
            const SizedBox(height: 16),
            
            // Control Buttons
            _buildControlButtons(context, ref, gpsStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPositionDisplay(BuildContext context, GpsPosition position) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${position.latitude.toStringAsFixed(4)}°',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
        Text(
          '${position.longitude.toStringAsFixed(4)}°',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
        if (position.accuracy != null)
          Text(
            '±${position.accuracy!.toStringAsFixed(0)}m',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildGpsStatusSection(BuildContext context, WidgetRef ref) {
    final gpsStatus = ref.watch(gpsStatusProvider);
    
    return Row(
      children: [
        Icon(
          gpsStatus.hasPosition ? Icons.check_circle : Icons.error,
          color: gpsStatus.hasPosition ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gpsStatus.hasPosition ? 'GPS Active' : 'GPS Inactive',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!gpsStatus.permissionGranted)
              Text(
                'Permission required',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPositionSection(
    BuildContext context, 
    AsyncValue<GpsPosition?> gpsPosition,
  ) {
    return gpsPosition.when(
      data: (position) {
        if (position == null) {
          return const Text('No position available');
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Position',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(position.toCoordinateString()),
            if (position.altitude != null)
              Text('Altitude: ${position.altitude!.toStringAsFixed(1)}m'),
          ],
        );
      },
      loading: () => const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Getting position...'),
        ],
      ),
      error: (error, stack) => Text(
        'Position error: ${error.toString()}',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildNavigationSection(
    BuildContext context,
    AsyncValue<CourseOverGround?> cog,
    AsyncValue<SpeedOverGround?> sog,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Navigation',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // Course over ground
            Expanded(
              child: cog.when(
                data: (course) => course != null
                    ? Text('COG: ${course.bearing.toStringAsFixed(0)}°')
                    : const Text('COG: ---'),
                loading: () => const Text('COG: ...'),
                error: (error, stack) => const Text('COG: ERR'),
              ),
            ),
            // Speed over ground
            Expanded(
              child: sog.when(
                data: (speed) => speed != null
                    ? Text('SOG: ${speed.speedKnots.toStringAsFixed(1)}kts')
                    : const Text('SOG: ---'),
                loading: () => const Text('SOG: ...'),
                error: (error, stack) => const Text('SOG: ERR'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignalQualitySection(
    BuildContext context,
    AsyncValue<GpsSignalQuality?> gpsQuality,
  ) {
    return gpsQuality.when(
      data: (quality) {
        if (quality == null) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Signal Quality',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(int.parse('0xFF${quality.colorCode.substring(1)}')),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_getSignalStrengthText(quality.strength)),
                if (quality.accuracy != null)
                  Text(' (${quality.accuracy!.toStringAsFixed(0)}m)'),
              ],
            ),
            if (quality.isMarineGrade)
              Text(
                'Marine grade accuracy',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green,
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    WidgetRef ref,
    gpsStatus,
  ) {
    return Row(
      children: [
        // Center on vessel
        if (onCenterOnVessel != null)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: gpsStatus.hasPosition ? onCenterOnVessel : null,
              icon: const Icon(Icons.my_location),
              label: const Text('Center'),
            ),
          ),
        
        if (onCenterOnVessel != null && showTrackControls)
          const SizedBox(width: 8),
        
        // Track recording
        if (showTrackControls)
          Expanded(
            child: _buildTrackToggleButton(context, ref),
          ),
      ],
    );
  }

  Widget _buildTrackToggleButton(BuildContext context, WidgetRef ref, {bool compact = false}) {
    final trackingService = ref.read(gpsTrackRecordingServiceProvider);
    final isRecording = trackingService.isRecording;
    
    if (compact) {
      return Tooltip(
        message: isRecording ? 'Stop tracking' : 'Start tracking',
        child: IconButton(
          onPressed: () => _toggleTracking(ref),
          icon: Icon(
            isRecording ? Icons.stop : Icons.fiber_manual_record,
            color: isRecording ? Colors.red : Colors.green,
          ),
          iconSize: 16,
          constraints: const BoxConstraints.tightFor(
            width: 32,
            height: 32,
          ),
        ),
      );
    }
    
    return ElevatedButton.icon(
      onPressed: () => _toggleTracking(ref),
      icon: Icon(
        isRecording ? Icons.stop : Icons.fiber_manual_record,
        color: isRecording ? Colors.red : Colors.green,
      ),
      label: Text(isRecording ? 'Stop Track' : 'Record Track'),
      style: ElevatedButton.styleFrom(
        backgroundColor: isRecording 
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }

  void _toggleTracking(WidgetRef ref) async {
    final trackingService = ref.read(gpsTrackRecordingServiceProvider);
    
    if (trackingService.isRecording) {
      final track = await trackingService.stopRecording();
      if (track != null) {
        // Show confirmation
        ref.context.mounted;
      }
    } else {
      final started = await trackingService.startRecording();
      if (started) {
        // Show confirmation
        ref.context.mounted;
      }
    }
    
    // Invalidate recording status
    ref.invalidate(gpsTrackRecordingStatusProvider);
  }

  void _showGpsSettings(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Settings'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('GPS configuration options will be available in a future update.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getSignalStrengthText(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.excellent:
        return 'Excellent';
      case SignalStrength.good:
        return 'Good';
      case SignalStrength.fair:
        return 'Fair';
      case SignalStrength.poor:
        return 'Poor';
      case SignalStrength.unknown:
        return 'Unknown';
    }
  }
}