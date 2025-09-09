/// Utility for creating dashed and dotted path effects
library;

import 'dart:ui';

/// Utility class for rendering dashed and dotted lines in marine charts
class PathDashUtils {
  /// Create a dashed path from a source path
  /// 
  /// [sourcePath] - The original path to dash
  /// [dashArray] - Array of dash lengths [on, off, on, off, ...]
  /// [dashOffset] - Offset to start the dash pattern
  static Path createDashedPath(
    Path sourcePath, 
    List<double> dashArray, {
    double dashOffset = 0.0,
  }) {
    if (dashArray.isEmpty || dashArray.every((element) => element == 0)) {
      return sourcePath;
    }

    final dashedPath = Path();
    final pathMetrics = sourcePath.computeMetrics();
    
    for (final metric in pathMetrics) {
      double distance = dashOffset;
      bool isDash = true;
      int dashIndex = 0;
      
      while (distance < metric.length) {
        final dashLength = dashArray[dashIndex % dashArray.length];
        final nextDistance = distance + dashLength;
        
        if (isDash) {
          final extractPath = metric.extractPath(
            distance.clamp(0.0, metric.length), 
            nextDistance.clamp(0.0, metric.length),
          );
          dashedPath.addPath(extractPath, Offset.zero);
        }
        
        distance = nextDistance;
        isDash = !isDash;
        if (isDash) dashIndex++;
      }
    }
    
    return dashedPath;
  }

  /// Create a dotted path pattern
  /// 
  /// [sourcePath] - The original path to dot
  /// [dotLength] - Length of each dot
  /// [gapLength] - Length of gap between dots
  static Path createDottedPath(
    Path sourcePath, 
    double dotLength, 
    double gapLength,
  ) {
    return createDashedPath(sourcePath, [dotLength, gapLength]);
  }

  /// Standard maritime dashed pattern for cables
  static Path cableDashedPath(Path sourcePath) {
    // Maritime standard: 5 units on, 3 units off
    return createDashedPath(sourcePath, [5.0, 3.0]);
  }

  /// Standard maritime dotted pattern for pipelines  
  static Path pipelineDottedPath(Path sourcePath) {
    // Maritime standard: 2 units on, 2 units off (dotted effect)
    return createDashedPath(sourcePath, [2.0, 2.0]);
  }

  /// Submarine cable pattern (longer dashes)
  static Path submarineCablePath(Path sourcePath) {
    // Submarine cables: 8 units on, 4 units off, 2 on, 4 off
    return createDashedPath(sourcePath, [8.0, 4.0, 2.0, 4.0]);
  }

  /// Pipeline with inspection points pattern
  static Path pipelineWithMarkersPath(Path sourcePath) {
    // Pipeline: 6 units on, 2 off, 1 on (marker), 2 off  
    return createDashedPath(sourcePath, [6.0, 2.0, 1.0, 2.0]);
  }
}