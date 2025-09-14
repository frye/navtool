import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../../core/models/gps_position.dart';
import '../../../core/models/chart_models.dart';
import '../../../core/models/position_history.dart';
import '../../../core/services/coordinate_transform.dart';
import '../../../core/state/providers.dart';

/// Overlay widget that displays vessel position, heading, and track on charts
class VesselPositionOverlay extends ConsumerWidget {
  final CoordinateTransform coordinateTransform;
  final bool showTrack;
  final bool showHeading;
  final bool showAccuracyCircle;
  final Duration trackDuration;
  
  const VesselPositionOverlay({
    super.key,
    required this.coordinateTransform,
    this.showTrack = true,
    this.showHeading = true,
    this.showAccuracyCircle = true,
    this.trackDuration = const Duration(hours: 1),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPosition = ref.watch(gpsPositionProvider);
    final gpsStatus = ref.watch(gpsStatusProvider);
    final gpsService = ref.watch(gpsServiceProvider);
    
    return currentPosition.when(
      data: (position) {
        if (position == null || !gpsStatus.hasPosition) {
          return const SizedBox.shrink();
        }
        
        // Get track history asynchronously for display
        return FutureBuilder<PositionHistory>(
          future: showTrack 
              ? gpsService.getPositionHistory(trackDuration)
              : Future.value(const PositionHistory(
                  positions: [],
                  totalDistance: 0.0,
                  averageSpeed: 0.0,
                  maxSpeed: 0.0,
                  minSpeed: 0.0,
                  duration: Duration.zero,
                )),
          builder: (context, trackSnapshot) {
            final trackHistory = trackSnapshot.data;
            
            return CustomPaint(
              painter: VesselOverlayPainter(
                position: position,
                coordinateTransform: coordinateTransform,
                showTrack: showTrack,
                showHeading: showHeading,
                showAccuracyCircle: showAccuracyCircle,
                context: context,
                trackHistory: trackHistory,
              ),
              size: Size.infinite,
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}

/// Custom painter for vessel position, heading, and track visualization
class VesselOverlayPainter extends CustomPainter {
  final GpsPosition position;
  final CoordinateTransform coordinateTransform;
  final bool showTrack;
  final bool showHeading;
  final bool showAccuracyCircle;
  final BuildContext context;
  final PositionHistory? trackHistory;
  
  VesselOverlayPainter({
    required this.position,
    required this.coordinateTransform,
    required this.showTrack,
    required this.showHeading,
    required this.showAccuracyCircle,
    required this.context,
    this.trackHistory,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vesselScreenPos = coordinateTransform.latLngToScreen(
      LatLng(position.latitude, position.longitude),
    );
    
    // Don't draw if vessel is off-screen
    if (vesselScreenPos.dx < 0 || vesselScreenPos.dx > size.width ||
        vesselScreenPos.dy < 0 || vesselScreenPos.dy > size.height) {
      return;
    }
    
    // Draw track history first (so it's behind the vessel)
    if (showTrack) {
      _drawTrack(canvas, size);
    }
    
    // Draw accuracy circle
    if (showAccuracyCircle && position.accuracy != null) {
      _drawAccuracyCircle(canvas, vesselScreenPos, position.accuracy!);
    }
    
    // Draw vessel symbol
    _drawVesselSymbol(canvas, vesselScreenPos);
    
    // Draw heading indicator
    if (showHeading && position.heading != null) {
      _drawHeadingIndicator(canvas, vesselScreenPos, position.heading!);
    }
    
    // Draw speed vector if moving
    if (position.speed != null && position.speed! > 0.5) { // > 0.5 m/s
      _drawSpeedVector(canvas, vesselScreenPos, position.speed!, position.heading);
    }
  }

  /// Draws the vessel track history
  void _drawTrack(Canvas canvas, Size size) {
    if (trackHistory == null || trackHistory!.positions.length < 2) return;
    
    final trackPaint = Paint()
      ..color = Theme.of(context).colorScheme.primary.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    bool firstPoint = true;
    
    for (final pos in trackHistory!.positions) {
      final screenPos = coordinateTransform.latLngToScreen(
        LatLng(pos.latitude, pos.longitude),
      );
      
      if (firstPoint) {
        path.moveTo(screenPos.dx, screenPos.dy);
        firstPoint = false;
      } else {
        path.lineTo(screenPos.dx, screenPos.dy);
      }
    }
    
    canvas.drawPath(path, trackPaint);
  }

  /// Draws accuracy circle around vessel position
  void _drawAccuracyCircle(Canvas canvas, Offset center, double accuracyMeters) {
    // Convert accuracy from meters to screen pixels
    final accuracyPixels = coordinateTransform.metersToPixels(accuracyMeters);
    
    final accuracyPaint = Paint()
      ..color = Theme.of(context).colorScheme.primary.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    
    final accuracyBorderPaint = Paint()
      ..color = Theme.of(context).colorScheme.primary.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    canvas.drawCircle(center, accuracyPixels, accuracyPaint);
    canvas.drawCircle(center, accuracyPixels, accuracyBorderPaint);
  }

  /// Draws the vessel symbol (triangle pointing north)
  void _drawVesselSymbol(Canvas canvas, Offset center) {
    final vesselPaint = Paint()
      ..color = Theme.of(context).colorScheme.primary
      ..style = PaintingStyle.fill;
    
    final vesselBorderPaint = Paint()
      ..color = Theme.of(context).colorScheme.onSurface
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    // Draw vessel as a triangle (bow pointing north)
    const vesselSize = 12.0;
    final path = Path();
    
    // Triangle pointing up (north)
    path.moveTo(center.dx, center.dy - vesselSize); // Bow (top)
    path.lineTo(center.dx - vesselSize * 0.6, center.dy + vesselSize * 0.4); // Port stern
    path.lineTo(center.dx + vesselSize * 0.6, center.dy + vesselSize * 0.4); // Starboard stern
    path.close();
    
    canvas.drawPath(path, vesselPaint);
    canvas.drawPath(path, vesselBorderPaint);
    
    // Add center dot
    final centerPaint = Paint()
      ..color = Theme.of(context).colorScheme.onSurface
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, 2.0, centerPaint);
  }

  /// Draws heading indicator line
  void _drawHeadingIndicator(Canvas canvas, Offset center, double headingDegrees) {
    final headingPaint = Paint()
      ..color = Theme.of(context).colorScheme.secondary
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    // Convert heading to radians (0° = north, clockwise)
    final headingRadians = (headingDegrees - 90) * math.pi / 180;
    
    const lineLength = 30.0;
    final endPoint = Offset(
      center.dx + lineLength * math.cos(headingRadians),
      center.dy + lineLength * math.sin(headingRadians),
    );
    
    canvas.drawLine(center, endPoint, headingPaint);
    
    // Draw arrowhead
    const arrowSize = 8.0;
    final arrowPath = Path();
    arrowPath.moveTo(endPoint.dx, endPoint.dy);
    arrowPath.lineTo(
      endPoint.dx - arrowSize * math.cos(headingRadians - 0.5),
      endPoint.dy - arrowSize * math.sin(headingRadians - 0.5),
    );
    arrowPath.moveTo(endPoint.dx, endPoint.dy);
    arrowPath.lineTo(
      endPoint.dx - arrowSize * math.cos(headingRadians + 0.5),
      endPoint.dy - arrowSize * math.sin(headingRadians + 0.5),
    );
    
    canvas.drawPath(arrowPath, headingPaint);
  }

  /// Draws speed vector indicator
  void _drawSpeedVector(Canvas canvas, Offset center, double speedMs, double? heading) {
    if (heading == null) return;
    
    final speedPaint = Paint()
      ..color = Theme.of(context).colorScheme.tertiary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    // Convert speed to line length (scale: 10 m/s = 50 pixels)
    final vectorLength = math.min(speedMs * 5, 100); // Max 100 pixels
    
    // Convert heading to radians
    final headingRadians = (heading - 90) * math.pi / 180;
    
    final endPoint = Offset(
      center.dx + vectorLength * math.cos(headingRadians),
      center.dy + vectorLength * math.sin(headingRadians),
    );
    
    // Draw speed vector with different start point (behind vessel)
    final startPoint = Offset(
      center.dx - 15 * math.cos(headingRadians),
      center.dy - 15 * math.sin(headingRadians),
    );
    
    canvas.drawLine(startPoint, endPoint, speedPaint);
  }

  @override
  bool shouldRepaint(VesselOverlayPainter oldDelegate) {
    return oldDelegate.position != position ||
           oldDelegate.coordinateTransform != coordinateTransform ||
           oldDelegate.showTrack != showTrack ||
           oldDelegate.showHeading != showHeading ||
           oldDelegate.showAccuracyCircle != showAccuracyCircle ||
           oldDelegate.trackHistory != trackHistory;
  }
}

/// Extension to add meter to pixel conversion to CoordinateTransform
extension CoordinateTransformExtension on CoordinateTransform {
  /// Converts meters to screen pixels at current zoom level
  double metersToPixels(double meters) {
    // Rough approximation: 1 meter ≈ zoom_level * 0.5 pixels at equator
    // This is simplified - a more accurate implementation would use the exact projection
    const double metersPerPixelAtZoom1 = 78271.52; // Web Mercator at equator
    final metersPerPixel = metersPerPixelAtZoom1 / math.pow(2, zoom);
    return meters / metersPerPixel;
  }
}