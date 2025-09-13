import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/models/gps_position.dart';
import '../../../core/models/chart_models.dart';
import '../../../core/services/coordinate_transform.dart';

/// Vessel position overlay widget for displaying GPS position on marine charts
class VesselOverlay extends StatelessWidget {
  /// Current GPS position of the vessel
  final GpsPosition? position;
  
  /// Coordinate transformation for positioning on chart
  final CoordinateTransform transform;
  
  /// Whether to show the vessel heading indicator
  final bool showHeading;
  
  /// Whether to show the accuracy circle
  final bool showAccuracyCircle;
  
  /// Scale factor for the vessel icon
  final double scale;
  
  /// Color of the vessel indicator
  final Color vesselColor;
  
  /// Color of the accuracy circle
  final Color accuracyColor;

  const VesselOverlay({
    super.key,
    required this.position,
    required this.transform,
    this.showHeading = true,
    this.showAccuracyCircle = true,
    this.scale = 1.0,
    this.vesselColor = Colors.red,
    this.accuracyColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    if (position == null) {
      return const SizedBox.shrink();
    }

    final vesselPosition = LatLng(position!.latitude, position!.longitude);
    final screenPoint = transform.latLngToScreen(vesselPosition);
    
    // Don't render if position is off-screen
    if (!_isPointOnScreen(screenPoint, transform.screenSize)) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Accuracy circle (behind vessel)
        if (showAccuracyCircle && position!.accuracy != null)
          _buildAccuracyCircle(screenPoint),
        
        // Vessel position indicator
        _buildVesselIndicator(screenPoint),
        
        // Heading indicator (in front of vessel)
        if (showHeading && position!.heading != null)
          _buildHeadingIndicator(screenPoint),
      ],
    );
  }

  /// Builds the accuracy circle showing GPS position uncertainty
  Widget _buildAccuracyCircle(Offset screenPoint) {
    final accuracy = position!.accuracy!;
    final accuracyPixels = transform.metersToPixels(accuracy);
    
    return Positioned(
      left: screenPoint.dx - accuracyPixels,
      top: screenPoint.dy - accuracyPixels,
      child: Container(
        width: accuracyPixels * 2,
        height: accuracyPixels * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accuracyColor.withOpacity(0.3),
            width: 2.0,
          ),
          color: accuracyColor.withOpacity(0.1),
        ),
      ),
    );
  }

  /// Builds the main vessel position indicator
  Widget _buildVesselIndicator(Offset screenPoint) {
    const double vesselSize = 24.0;
    final scaledSize = vesselSize * scale;
    
    return Positioned(
      left: screenPoint.dx - scaledSize / 2,
      top: screenPoint.dy - scaledSize / 2,
      child: Container(
        width: scaledSize,
        height: scaledSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: vesselColor,
          border: Border.all(
            color: Colors.white,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation,
          color: Colors.white,
          size: scaledSize * 0.6,
        ),
      ),
    );
  }

  /// Builds the heading indicator showing vessel direction
  Widget _buildHeadingIndicator(Offset screenPoint) {
    final heading = position!.heading!;
    const double lineLength = 40.0;
    final scaledLength = lineLength * scale;
    
    // Convert heading to radians (heading is in degrees, 0° = North)
    final headingRad = (heading - 90) * math.pi / 180; // Adjust for screen coordinates
    
    final endX = screenPoint.dx + math.cos(headingRad) * scaledLength;
    final endY = screenPoint.dy + math.sin(headingRad) * scaledLength;
    
    return CustomPaint(
      painter: _HeadingLinePainter(
        start: screenPoint,
        end: Offset(endX, endY),
        color: vesselColor,
        strokeWidth: 3.0,
      ),
    );
  }

  /// Checks if a screen point is visible within the screen bounds
  bool _isPointOnScreen(Offset point, Size screenSize) {
    const double margin = 50.0; // Allow some margin for partially visible indicators
    
    return point.dx >= -margin &&
           point.dx <= screenSize.width + margin &&
           point.dy >= -margin &&
           point.dy <= screenSize.height + margin;
  }
}

/// Custom painter for drawing the vessel heading line
class _HeadingLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;

  const _HeadingLinePainter({
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw the heading line
    canvas.drawLine(start, end, paint);
    
    // Draw arrowhead at the end
    _drawArrowhead(canvas, paint);
  }

  /// Draws an arrowhead at the end of the heading line
  void _drawArrowhead(Canvas canvas, Paint paint) {
    const double arrowLength = 12.0;
    const double arrowAngle = math.pi / 6; // 30 degrees
    
    final lineAngle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    
    final arrowPoint1 = Offset(
      end.dx - arrowLength * math.cos(lineAngle - arrowAngle),
      end.dy - arrowLength * math.sin(lineAngle - arrowAngle),
    );
    
    final arrowPoint2 = Offset(
      end.dx - arrowLength * math.cos(lineAngle + arrowAngle),
      end.dy - arrowLength * math.sin(lineAngle + arrowAngle),
    );
    
    canvas.drawLine(end, arrowPoint1, paint);
    canvas.drawLine(end, arrowPoint2, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingLinePainter oldDelegate) {
    return start != oldDelegate.start ||
           end != oldDelegate.end ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth;
  }
}

/// Enhanced vessel overlay with track history
class VesselTrackOverlay extends StatelessWidget {
  /// Current GPS position
  final GpsPosition? currentPosition;
  
  /// Historical GPS positions for track display
  final List<GpsPosition> trackHistory;
  
  /// Coordinate transformation
  final CoordinateTransform transform;
  
  /// Track line color
  final Color trackColor;
  
  /// Track line width
  final double trackWidth;
  
  /// Maximum number of track points to display
  final int maxTrackPoints;

  const VesselTrackOverlay({
    super.key,
    required this.currentPosition,
    required this.trackHistory,
    required this.transform,
    this.trackColor = Colors.cyan,
    this.trackWidth = 2.0,
    this.maxTrackPoints = 500,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Track history
        if (trackHistory.isNotEmpty)
          _buildTrackHistory(),
        
        // Current vessel position
        VesselOverlay(
          position: currentPosition,
          transform: transform,
        ),
      ],
    );
  }

  /// Builds the track history visualization
  Widget _buildTrackHistory() {
    // Limit track points for performance
    final limitedTrack = trackHistory.length > maxTrackPoints
        ? trackHistory.sublist(trackHistory.length - maxTrackPoints)
        : trackHistory;
    
    if (limitedTrack.length < 2) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: _TrackPainter(
        positions: limitedTrack,
        transform: transform,
        color: trackColor,
        strokeWidth: trackWidth,
      ),
    );
  }
}

/// Custom painter for drawing GPS track history
class _TrackPainter extends CustomPainter {
  final List<GpsPosition> positions;
  final CoordinateTransform transform;
  final Color color;
  final double strokeWidth;

  const _TrackPainter({
    required this.positions,
    required this.transform,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool firstPoint = true;

    for (final position in positions) {
      final latLng = LatLng(position.latitude, position.longitude);
      final screenPoint = transform.latLngToScreen(latLng);
      
      // Only add points that are on or near the screen
      if (_isPointNearScreen(screenPoint, size)) {
        if (firstPoint) {
          path.moveTo(screenPoint.dx, screenPoint.dy);
          firstPoint = false;
        } else {
          path.lineTo(screenPoint.dx, screenPoint.dy);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  /// Checks if a point is near the screen (including some margin for smooth drawing)
  bool _isPointNearScreen(Offset point, Size screenSize) {
    const double margin = 100.0;
    
    return point.dx >= -margin &&
           point.dx <= screenSize.width + margin &&
           point.dy >= -margin &&
           point.dy <= screenSize.height + margin;
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) {
    return positions != oldDelegate.positions ||
           transform != oldDelegate.transform ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth;
  }
}