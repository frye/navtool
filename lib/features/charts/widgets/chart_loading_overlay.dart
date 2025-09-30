/// Chart loading overlay with progress indicator and queue status
/// 
/// Requirements:
/// - FR-019: Show progress indicator within 500ms if loading continues
/// - FR-019a: 500ms threshold configurable before compilation
/// - FR-027: Display queue status (position, count)
library;

import 'package:flutter/material.dart';

/// Configuration for chart loading UI behavior
class ChartLoadingConfig {
  /// Progress indicator delay threshold (compile-time constant per FR-019a)
  static const Duration progressIndicatorThreshold = Duration(milliseconds: 500);
  
  /// Private constructor to prevent instantiation
  ChartLoadingConfig._();
}

/// Loading overlay widget displayed during chart loading operations
/// 
/// Appears after [ChartLoadingConfig.progressIndicatorThreshold] to avoid
/// flickering for fast loads. Displays current chart being loaded and
/// queue status if multiple charts are pending.
class ChartLoadingOverlay extends StatelessWidget {
  /// Chart ID currently being loaded
  final String currentChartId;
  
  /// Number of charts waiting in queue (0 if no queue)
  final int queueLength;
  
  /// Create a loading overlay
  /// 
  /// Parameters:
  /// - [currentChartId]: Required, the chart being loaded (e.g., "US5WA50M")
  /// - [queueLength]: Optional, number of charts in queue (default: 0)
  const ChartLoadingOverlay({
    super.key,
    required this.currentChartId,
    this.queueLength = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54, // Semi-transparent background
      child: Center(
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Spinning progress indicator
                const CircularProgressIndicator(),
                
                const SizedBox(height: 16),
                
                // Loading message with chart ID
                Text(
                  'Loading $currentChartId',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                
                // Queue status (only if queue not empty)
                if (queueLength > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$queueLength ${queueLength == 1 ? 'chart' : 'charts'} in queue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
