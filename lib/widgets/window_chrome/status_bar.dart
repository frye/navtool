import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status bar information models
class StatusInfo {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const StatusInfo({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.onTap,
  });
}

/// Status bar provider for managing status information
final statusBarProvider = StateNotifierProvider<StatusBarNotifier, StatusBarState>((ref) {
  return StatusBarNotifier();
});

class StatusBarState {
  final String connectionStatus;
  final String gpsStatus;
  final String chartStatus;
  final String navigationStatus;
  final String systemStatus;

  const StatusBarState({
    this.connectionStatus = 'Online',
    this.gpsStatus = 'No GPS',
    this.chartStatus = 'No Chart',
    this.navigationStatus = 'Standby',
    this.systemStatus = 'Ready',
  });

  StatusBarState copyWith({
    String? connectionStatus,
    String? gpsStatus,
    String? chartStatus,
    String? navigationStatus,
    String? systemStatus,
  }) {
    return StatusBarState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      chartStatus: chartStatus ?? this.chartStatus,
      navigationStatus: navigationStatus ?? this.navigationStatus,
      systemStatus: systemStatus ?? this.systemStatus,
    );
  }
}

class StatusBarNotifier extends StateNotifier<StatusBarState> {
  StatusBarNotifier() : super(const StatusBarState()) {
    _initializeStatus();
  }

  void _initializeStatus() {
    // Simulate status updates for development
    Future.delayed(const Duration(seconds: 2), () {
      updateConnectionStatus('Connected');
    });
  }

  void updateConnectionStatus(String status) {
    state = state.copyWith(connectionStatus: status);
  }

  void updateGpsStatus(String status) {
    state = state.copyWith(gpsStatus: status);
  }

  void updateChartStatus(String status) {
    state = state.copyWith(chartStatus: status);
  }

  void updateNavigationStatus(String status) {
    state = state.copyWith(navigationStatus: status);
  }

  void updateSystemStatus(String status) {
    state = state.copyWith(systemStatus: status);
  }
}

/// Status bar widget that displays comprehensive navigation-relevant information
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusState = ref.watch(statusBarProvider);

    return Container(
      height: 24.0,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildStatusSegment(
            context,
            StatusInfo(
              label: 'Connection',
              value: statusState.connectionStatus,
              icon: _getConnectionIcon(statusState.connectionStatus),
              color: _getConnectionColor(statusState.connectionStatus),
              onTap: () => _showConnectionDetails(context),
            ),
          ),
          _buildDivider(context),
          _buildStatusSegment(
            context,
            StatusInfo(
              label: 'GPS',
              value: statusState.gpsStatus,
              icon: Icons.gps_fixed,
              color: _getGpsColor(statusState.gpsStatus),
              onTap: () => _showGpsDetails(context),
            ),
          ),
          _buildDivider(context),
          _buildStatusSegment(
            context,
            StatusInfo(
              label: 'Chart',
              value: statusState.chartStatus,
              icon: Icons.map,
              onTap: () => _showChartDetails(context),
            ),
          ),
          _buildDivider(context),
          _buildStatusSegment(
            context,
            StatusInfo(
              label: 'Navigation',
              value: statusState.navigationStatus,
              icon: Icons.navigation,
              onTap: () => _showNavigationDetails(context),
            ),
          ),
          const Spacer(),
          _buildStatusSegment(
            context,
            StatusInfo(
              label: 'System',
              value: statusState.systemStatus,
              icon: Icons.computer,
              onTap: () => _showSystemDetails(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSegment(BuildContext context, StatusInfo info) {
    return InkWell(
      onTap: info.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info.icon != null) ...[
              Icon(
                info.icon,
                size: 16.0,
                color: info.color ?? Theme.of(context).textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 4.0),
            ],
            Text(
              info.value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: info.color,
                fontSize: 12.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      width: 1.0,
      height: 16.0,
      color: Theme.of(context).dividerColor,
    );
  }

  IconData _getConnectionIcon(String status) {
    switch (status.toLowerCase()) {
      case 'online':
      case 'connected':
        return Icons.wifi;
      case 'offline':
        return Icons.wifi_off;
      default:
        return Icons.signal_wifi_statusbar_null;
    }
  }

  Color? _getConnectionColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
      case 'connected':
        return Colors.green;
      case 'offline':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color? _getGpsColor(String status) {
    switch (status.toLowerCase()) {
      case 'fixed':
      case 'active':
        return Colors.green;
      case 'no gps':
      case 'searching':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  void _showConnectionDetails(BuildContext context) {
    _showStatusDialog(
      context,
      'Connection Status',
      'Network connection details and diagnostics would be shown here.',
    );
  }

  void _showGpsDetails(BuildContext context) {
    _showStatusDialog(
      context,
      'GPS Status',
      'GPS satellite information, accuracy, and position data would be shown here.',
    );
  }

  void _showChartDetails(BuildContext context) {
    _showStatusDialog(
      context,
      'Chart Status',
      'Currently loaded chart information, edition, and update status would be shown here.',
    );
  }

  void _showNavigationDetails(BuildContext context) {
    _showStatusDialog(
      context,
      'Navigation Status',
      'Speed, heading, coordinates, and navigation data would be shown here.',
    );
  }

  void _showSystemDetails(BuildContext context) {
    _showStatusDialog(
      context,
      'System Status',
      'Memory usage, background operations, and system diagnostics would be shown here.',
    );
  }

  void _showStatusDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
