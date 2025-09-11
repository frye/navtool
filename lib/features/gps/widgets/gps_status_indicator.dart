import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/gps_signal_quality.dart';
import '../providers/gps_providers.dart';

/// Widget that displays GPS signal quality and accuracy status
class GpsStatusIndicator extends ConsumerWidget {
  final bool showDetails;
  final bool isCompact;
  
  const GpsStatusIndicator({
    super.key,
    this.showDetails = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signalQuality = ref.watch(gpsSignalQualityProvider);
    final isTracking = ref.watch(isGpsTrackingProvider);
    final isMarineGrade = ref.watch(isMarineGradeGpsProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 8.0 : 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSignalIcon(signalQuality, isTracking),
                const SizedBox(width: 8),
                if (!isCompact) ...[
                  Text(
                    'GPS',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _buildStatusIndicator(signalQuality, isMarineGrade, context),
              ],
            ),
            if (showDetails && !isCompact) ...[
              const SizedBox(height: 8),
              _buildDetailedStatus(signalQuality, context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIcon(AsyncValue<GpsSignalQuality> signalQuality, bool isTracking) {
    return signalQuality.when(
      data: (quality) => Icon(
        _getSignalIcon(quality.strength),
        color: _getSignalColor(quality.strength),
        size: isCompact ? 16 : 20,
      ),
      loading: () => SizedBox(
        width: isCompact ? 16 : 20,
        height: isCompact ? 16 : 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
        ),
      ),
      error: (_, __) => Icon(
        Icons.gps_off,
        color: Colors.red,
        size: isCompact ? 16 : 20,
      ),
    );
  }

  Widget _buildStatusIndicator(AsyncValue<GpsSignalQuality> signalQuality, bool isMarineGrade, BuildContext context) {
    return signalQuality.when(
      data: (quality) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCompact) ...[
            Text(
              _getSignalStrengthText(quality.strength),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _getSignalColor(quality.strength),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (isMarineGrade)
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: isCompact ? 12 : 16,
            )
          else
            Icon(
              Icons.warning,
              color: Colors.orange,
              size: isCompact ? 12 : 16,
            ),
        ],
      ),
      loading: () => Text(
        'Acquiring...',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.grey.shade600,
        ),
      ),
      error: (_, __) => Text(
        'No GPS',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _buildDetailedStatus(AsyncValue<GpsSignalQuality> signalQuality, BuildContext context) {
    return signalQuality.when(
      data: (quality) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quality.accuracy != null)
            _buildDetailRow(
              'Accuracy',
              '±${quality.accuracy!.toStringAsFixed(1)}m',
              context,
            ),
          if (quality.satelliteCount != null)
            _buildDetailRow(
              'Satellites',
              '${quality.satelliteCount}',
              context,
            ),
          if (quality.hdop != null)
            _buildDetailRow(
              'HDOP',
              quality.hdop!.toStringAsFixed(1),
              context,
            ),
          _buildDetailRow(
            'Marine Grade',
            quality.isMarineGrade ? 'Yes' : 'No',
            context,
            valueColor: quality.isMarineGrade ? Colors.green : Colors.orange,
          ),
        ],
      ),
      loading: () => const Text('Loading GPS details...'),
      error: (error, _) => Text(
        'GPS Error: ${error.toString()}',
        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, BuildContext context, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSignalIcon(SignalStrength strength) {
    return switch (strength) {
      SignalStrength.excellent => Icons.gps_fixed,
      SignalStrength.good => Icons.gps_fixed,
      SignalStrength.fair => Icons.gps_not_fixed,
      SignalStrength.poor => Icons.gps_not_fixed,
      SignalStrength.unknown => Icons.gps_off,
    };
  }

  Color _getSignalColor(SignalStrength strength) {
    return switch (strength) {
      SignalStrength.excellent => Colors.green,
      SignalStrength.good => Colors.lightGreen,
      SignalStrength.fair => Colors.orange,
      SignalStrength.poor => Colors.red,
      SignalStrength.unknown => Colors.grey,
    };
  }

  String _getSignalStrengthText(SignalStrength strength) {
    return switch (strength) {
      SignalStrength.excellent => 'Excellent',
      SignalStrength.good => 'Good',
      SignalStrength.fair => 'Fair',
      SignalStrength.poor => 'Poor',
      SignalStrength.unknown => 'Unknown',
    };
  }
}

/// Compact GPS status indicator for toolbars
class CompactGpsStatusIndicator extends StatelessWidget {
  const CompactGpsStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const GpsStatusIndicator(
      isCompact: true,
      showDetails: false,
    );
  }
}

/// Detailed GPS status panel for settings/info screens
class DetailedGpsStatusPanel extends StatelessWidget {
  const DetailedGpsStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const GpsStatusIndicator(
      isCompact: false,
      showDetails: true,
    );
  }
}