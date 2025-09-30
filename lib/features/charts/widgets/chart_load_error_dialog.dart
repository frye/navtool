/// Chart load error dialog with retry/dismiss actions
/// 
/// Requirements:
/// - FR-005: Display structured error information
/// - FR-012: Show error message after retry exhaustion
/// - FR-022: Provide retry and dismiss user actions
library;

import 'package:flutter/material.dart';
import 'package:navtool/features/charts/chart_load_error.dart';

/// Error dialog displayed when chart loading fails
/// 
/// Shows error message, troubleshooting guidance, and action buttons.
/// Supports retry and dismiss actions per FR-022.
class ChartLoadErrorDialog extends StatelessWidget {
  /// The error to display
  final ChartLoadError error;
  
  /// Callback when user taps "Retry" button
  final VoidCallback onRetry;
  
  /// Callback when user taps "Dismiss" button
  final VoidCallback onDismiss;
  
  /// Create an error dialog
  /// 
  /// Parameters:
  /// - [error]: Required, the chart load error with message and guidance
  /// - [onRetry]: Required, callback to reattempt chart loading
  /// - [onDismiss]: Required, callback to close dialog and return to browser
  const ChartLoadErrorDialog({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          const Text('Chart Loading Error'),
        ],
      ),
      
          content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error message (prominently displayed)
            Text(
              error.message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Error type
            Text(
              'Type: ${error.type.toString().split('.').last}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            
            // Timestamp
            const SizedBox(height: 8),
            Text(
              'Occurred: ${error.timestamp.toString()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Troubleshooting guidance (suggestions)
            if (error.suggestions.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Troubleshooting',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.blue[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...error.suggestions.map((suggestion) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ', style: TextStyle(color: Colors.blue[900])),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            
            // Technical details (only if present - debug mode)
            if (error.detail != null && error.detail!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Technical Details'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      error.detail!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),      actions: [
        // Dismiss button
        TextButton(
          onPressed: onDismiss,
          child: const Text('Dismiss'),
        ),
        
        // Retry button (primary action)
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
