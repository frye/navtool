import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/gps_position.dart';
import '../../../core/models/gps_signal_quality.dart';
import '../../../core/models/position_history.dart';
import '../../../core/state/providers.dart';

/// Enhanced GPS status widget with detailed signal quality and navigation information
class EnhancedGpsStatusWidget extends ConsumerStatefulWidget {
  /// Whether to show expanded details by default
  final bool expandedByDefault;
  
  /// Whether to show course and speed information
  final bool showNavigationData;
  
  /// Whether to show track recording controls
  final bool showTrackControls;

  const EnhancedGpsStatusWidget({
    super.key,
    this.expandedByDefault = false,
    this.showNavigationData = true,
    this.showTrackControls = true,
  });

  @override
  ConsumerState<EnhancedGpsStatusWidget> createState() => _EnhancedGpsStatusWidgetState();
}

class _EnhancedGpsStatusWidgetState extends ConsumerState<EnhancedGpsStatusWidget> {
  bool _isExpanded = false;
  bool _isTrackRecording = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.expandedByDefault;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildQuickStatus(context),
            if (_isExpanded) ...[
              const SizedBox(height: 12),
              _buildDetailedStatus(context),
              if (widget.showNavigationData) ...[
                const SizedBox(height: 12),
                _buildNavigationData(context),
              ],
              if (widget.showTrackControls) ...[
                const SizedBox(height: 12),
                _buildTrackControls(context),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.gps_fixed,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'GPS Navigation',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          tooltip: _isExpanded ? 'Show less' : 'Show more',
        ),
      ],
    );
  }

  Widget _buildQuickStatus(BuildContext context) {
    final positionAsync = ref.watch(gpsPositionProvider);
    
    return positionAsync.when(
      data: (position) => _buildPositionStatus(context, position),
      loading: () => _buildLoadingStatus(context),
      error: (error, stack) => _buildErrorStatus(context, error),
    );
  }

  Widget _buildPositionStatus(BuildContext context, GpsPosition? position) {
    if (position == null) {
      return _buildNoPositionStatus(context);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildSignalQualityIndicator(context, position),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCoordinateDisplay(context, position),
              ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            _buildPositionMetadata(context, position),
          ],
        ],
      ),
    );
  }

  Widget _buildSignalQualityIndicator(BuildContext context, GpsPosition position) {
    final quality = GpsSignalQuality.fromAccuracy(position.accuracy);
    
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getQualityColor(quality.strength),
          ),
          child: Icon(
            _getQualityIcon(quality.strength),
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _getQualityText(quality.strength),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCoordinateDisplay(BuildContext context, GpsPosition position) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          position.toCoordinateString(),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        if (position.accuracy != null)
          Text(
            'Accuracy: ±${position.accuracy!.toStringAsFixed(1)}m',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Text(
          'Updated: ${_formatTime(position.timestamp)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionMetadata(BuildContext context, GpsPosition position) {
    return Column(
      children: [
        if (position.altitude != null)
          _buildMetadataRow(
            context,
            'Altitude',
            '${position.altitude!.toStringAsFixed(1)} m',
            Icons.height,
          ),
        if (position.speed != null && position.speed! > 0)
          _buildMetadataRow(
            context,
            'Speed',
            '${(position.speed! * 1.944).toStringAsFixed(1)} kts',
            Icons.speed,
          ),
        if (position.heading != null)
          _buildMetadataRow(
            context,
            'Heading',
            '${position.heading!.toStringAsFixed(0)}°',
            Icons.navigation,
          ),
      ],
    );
  }

  Widget _buildMetadataRow(BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatus(BuildContext context) {
    return FutureBuilder<GpsSignalQuality?>(
      future: _getSignalQuality(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final quality = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: quality.isMarineGrade
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    quality.isMarineGrade ? Icons.check_circle : Icons.warning,
                    color: quality.isMarineGrade
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onErrorContainer,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    quality.isMarineGrade ? 'Marine Grade GPS' : 'GPS Quality Warning',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: quality.isMarineGrade
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                quality.recommendedAction,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: quality.isMarineGrade
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationData(BuildContext context) {
    return FutureBuilder<(CourseOverGround?, SpeedOverGround?)>(
      future: _getNavigationData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildNavigationLoadingState(context);
        }

        final (cog, sog) = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Navigation Data',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildNavigationMetric(
                      context,
                      'Course Over Ground',
                      cog != null ? '${cog.bearing.toStringAsFixed(0)}°' : 'N/A',
                      Icons.explore,
                      cog?.confidence,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildNavigationMetric(
                      context,
                      'Speed Over Ground',
                      sog != null ? '${sog.speedKnots.toStringAsFixed(1)} kts' : 'N/A',
                      Icons.speed,
                      sog?.confidence,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationMetric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    double? confidence,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        if (confidence != null)
          LinearProgressIndicator(
            value: confidence,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildNavigationLoadingState(BuildContext context) {
    return Container(
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
          Text(
            'Calculating navigation data...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildTrackControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Track Recording',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _toggleTrackRecording(),
                icon: Icon(_isTrackRecording ? Icons.stop : Icons.play_arrow),
                label: Text(_isTrackRecording ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTrackRecording
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: _isTrackRecording
                      ? Theme.of(context).colorScheme.onError
                      : Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _isTrackRecording ? null : _clearTrack,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
              const Spacer(),
              FutureBuilder<PositionHistory>(
                future: _getTrackHistory(),
                builder: (context, snapshot) {
                  final history = snapshot.data;
                  if (history == null) return const SizedBox.shrink();
                  
                  return Text(
                    '${history.positions.length} points',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingStatus(BuildContext context) {
    return Container(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPositionStatus(BuildContext context) {
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
              'No GPS position available',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStatus(BuildContext context, Object error) {
    return Container(
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
            ),
          ),
        ],
      ),
    );
  }

  Color _getQualityColor(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.excellent:
        return Colors.green;
      case SignalStrength.good:
        return Colors.lightGreen;
      case SignalStrength.fair:
        return Colors.orange;
      case SignalStrength.poor:
        return Colors.red;
      case SignalStrength.unknown:
        return Colors.grey;
    }
  }

  IconData _getQualityIcon(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.excellent:
        return Icons.gps_fixed;
      case SignalStrength.good:
        return Icons.gps_fixed;
      case SignalStrength.fair:
        return Icons.gps_not_fixed;
      case SignalStrength.poor:
        return Icons.gps_off;
      case SignalStrength.unknown:
        return Icons.gps_not_fixed;
    }
  }

  String _getQualityText(SignalStrength strength) {
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  Future<GpsSignalQuality?> _getSignalQuality() async {
    final positionAsync = ref.read(gpsPositionProvider);
    return positionAsync.when(
      data: (position) async {
        if (position == null) return null;
        final gpsService = ref.read(gpsServiceProvider);
        return await gpsService.assessSignalQuality(position);
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }

  Future<(CourseOverGround?, SpeedOverGround?)> _getNavigationData() async {
    final gpsService = ref.read(gpsServiceProvider);
    final timeWindow = const Duration(minutes: 5);
    
    final cogFuture = gpsService.calculateCourseOverGround(timeWindow);
    final sogFuture = gpsService.calculateSpeedOverGround(timeWindow);
    
    final results = await Future.wait([cogFuture, sogFuture]);
    return (results[0] as CourseOverGround?, results[1] as SpeedOverGround?);
  }

  Future<PositionHistory> _getTrackHistory() async {
    final gpsService = ref.read(gpsServiceProvider);
    return await gpsService.getPositionHistory(const Duration(hours: 1));
  }

  void _toggleTrackRecording() {
    setState(() {
      _isTrackRecording = !_isTrackRecording;
    });

    final gpsService = ref.read(gpsServiceProvider);
    if (_isTrackRecording) {
      // Start tracking by starting location tracking
      gpsService.startLocationTracking().then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS track recording started'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _isTrackRecording = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to start GPS tracking: $error'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    } else {
      // Stop tracking
      gpsService.stopLocationTracking().then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS track recording stopped'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  void _clearTrack() {
    final gpsService = ref.read(gpsServiceProvider);
    gpsService.clearPositionHistory().then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS track history cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }
}