import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../../core/models/gps_position.dart';
import '../../../core/models/chart_models.dart';
import '../../../core/services/coordinate_transform.dart';
import '../providers/gps_providers.dart';

/// Overlay widget that displays vessel position and track on a chart
class VesselPositionOverlay extends ConsumerWidget {
  final CoordinateTransform transform;
  final Size canvasSize;
  final bool showTrack;
  final bool showHeading;
  final bool showAccuracyCircle;
  final Duration trackDuration;
  final Color vesselColor;
  final Color trackColor;
  final double vesselSize;

  const VesselPositionOverlay({
    super.key,
    required this.transform,
    required this.canvasSize,
    this.showTrack = true,
    this.showHeading = true,
    this.showAccuracyCircle = true,
    this.trackDuration = const Duration(minutes: 30),
    this.vesselColor = Colors.red,
    this.trackColor = Colors.blue,
    this.vesselSize = 20.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPosition = ref.watch(latestGpsPositionProvider);
    final vesselTrack = ref.watch(vesselTrackProvider(trackDuration));

    if (currentPosition == null) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      size: canvasSize,
      painter: _VesselPositionPainter(
        transform: transform,
        currentPosition: currentPosition,
        vesselTrack: vesselTrack.valueOrNull,
        showTrack: showTrack,
        showHeading: showHeading,
        showAccuracyCircle: showAccuracyCircle,
        vesselColor: vesselColor,
        trackColor: trackColor,
        vesselSize: vesselSize,
      ),
    );
  }
}

/// CustomPainter for rendering vessel position and track
class _VesselPositionPainter extends CustomPainter {
  final CoordinateTransform transform;
  final GpsPosition currentPosition;
  final PositionHistory? vesselTrack;
  final bool showTrack;
  final bool showHeading;
  final bool showAccuracyCircle;
  final Color vesselColor;
  final Color trackColor;
  final double vesselSize;

  _VesselPositionPainter({
    required this.transform,
    required this.currentPosition,
    this.vesselTrack,
    required this.showTrack,
    required this.showHeading,
    required this.showAccuracyCircle,
    required this.vesselColor,
    required this.trackColor,
    required this.vesselSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Convert GPS position to screen coordinates
    final vesselScreenPos = transform.latLngToPixel(
      LatLng(currentPosition.latitude, currentPosition.longitude),
    );

    // Only draw if vessel is within visible area
    if (!_isPositionVisible(vesselScreenPos, size)) {
      return;
    }

    // Draw vessel track if enabled and available
    if (showTrack && vesselTrack != null && vesselTrack!.positions.isNotEmpty) {
      _drawVesselTrack(canvas, size);
    }

    // Draw accuracy circle if enabled and accuracy data available
    if (showAccuracyCircle && currentPosition.accuracy != null) {
      _drawAccuracyCircle(canvas, vesselScreenPos);
    }

    // Draw vessel icon
    _drawVesselIcon(canvas, vesselScreenPos);

    // Draw heading indicator if enabled and heading data available
    if (showHeading && currentPosition.heading != null) {
      _drawHeadingIndicator(canvas, vesselScreenPos, currentPosition.heading!);
    }
  }

  void _drawVesselTrack(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = trackColor.withAlpha(180)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final trackPoints = <Offset>[];

    // Convert all track positions to screen coordinates
    for (final position in vesselTrack!.positions) {
      final screenPos = transform.latLngToPixel(
        LatLng(position.latitude, position.longitude),
      );
      
      if (_isPositionVisible(screenPos, size)) {
        trackPoints.add(screenPos);
      }
    }

    // Draw track as connected line segments
    if (trackPoints.length >= 2) {
      final path = Path();
      path.moveTo(trackPoints.first.dx, trackPoints.first.dy);
      
      for (int i = 1; i < trackPoints.length; i++) {
        path.lineTo(trackPoints[i].dx, trackPoints[i].dy);
      }
      
      canvas.drawPath(path, trackPaint);

      // Draw track dots for individual positions
      final dotPaint = Paint()
        ..color = trackColor.withAlpha(120)
        ..style = PaintingStyle.fill;

      for (final point in trackPoints) {
        canvas.drawCircle(point, 2.0, dotPaint);
      }
    }
  }

  void _drawAccuracyCircle(Canvas canvas, Offset vesselPos) {
    // Calculate accuracy circle radius in pixels
    final accuracyMeters = currentPosition.accuracy!;
    final accuracyRadius = _metersToPixels(accuracyMeters);

    if (accuracyRadius > 2.0) { // Only draw if circle is visible
      final accuracyPaint = Paint()
        ..color = vesselColor.withAlpha(50)
        ..style = PaintingStyle.fill;

      final accuracyStrokePaint = Paint()
        ..color = vesselColor.withAlpha(100)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(vesselPos, accuracyRadius, accuracyPaint);
      canvas.drawCircle(vesselPos, accuracyRadius, accuracyStrokePaint);
    }
  }

  void _drawVesselIcon(Canvas canvas, Offset vesselPos) {
    final vesselPaint = Paint()
      ..color = vesselColor
      ..style = PaintingStyle.fill;

    final vesselOutlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw vessel as a circle with white outline
    canvas.drawCircle(vesselPos, vesselSize / 2, vesselOutlinePaint);
    canvas.drawCircle(vesselPos, vesselSize / 2, vesselPaint);

    // Draw center dot
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(vesselPos, 2.0, centerPaint);
  }

  void _drawHeadingIndicator(Canvas canvas, Offset vesselPos, double heading) {
    // Convert heading to radians (0° = North, clockwise)
    final headingRad = (heading - 90) * math.pi / 180; // Adjust for screen coordinates

    // Calculate heading line end point
    final headingLength = vesselSize * 1.5;
    final headingEndX = vesselPos.dx + headingLength * math.cos(headingRad);
    final headingEndY = vesselPos.dy + headingLength * math.sin(headingRad);
    final headingEnd = Offset(headingEndX, headingEndY);

    // Draw heading line
    final headingPaint = Paint()
      ..color = vesselColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(vesselPos, headingEnd, headingPaint);

    // Draw heading arrow
    _drawArrowHead(canvas, vesselPos, headingEnd, headingPaint);
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double arrowSize = 8.0;
    const double arrowAngle = math.pi / 6; // 30 degrees

    final direction = math.atan2(end.dy - start.dy, end.dx - start.dx);
    
    final arrowLeft = Offset(
      end.dx - arrowSize * math.cos(direction - arrowAngle),
      end.dy - arrowSize * math.sin(direction - arrowAngle),
    );
    
    final arrowRight = Offset(
      end.dx - arrowSize * math.cos(direction + arrowAngle),
      end.dy - arrowSize * math.sin(direction + arrowAngle),
    );

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowLeft.dx, arrowLeft.dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowRight.dx, arrowRight.dy);

    canvas.drawPath(arrowPath, paint);
  }

  bool _isPositionVisible(Offset screenPos, Size size) {
    return screenPos.dx >= -vesselSize &&
           screenPos.dx <= size.width + vesselSize &&
           screenPos.dy >= -vesselSize &&
           screenPos.dy <= size.height + vesselSize;
  }

  double _metersToPixels(double meters) {
    // Approximate conversion from meters to pixels at current zoom level
    // This is a simplified calculation - in practice you'd use the transform's
    // scale factor based on latitude and zoom level
    final pixelsPerMeter = transform.pixelsPerDegree / 111320; // Rough approximation
    return meters * pixelsPerMeter;
  }

  @override
  bool shouldRepaint(_VesselPositionPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
           oldDelegate.vesselTrack != vesselTrack ||
           oldDelegate.showTrack != showTrack ||
           oldDelegate.showHeading != showHeading ||
           oldDelegate.showAccuracyCircle != showAccuracyCircle ||
           oldDelegate.vesselColor != vesselColor ||
           oldDelegate.trackColor != trackColor ||
           oldDelegate.vesselSize != vesselSize;
  }
}

/// Widget that shows vessel position summary info
class VesselPositionInfo extends ConsumerWidget {
  const VesselPositionInfo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPosition = ref.watch(latestGpsPositionProvider);
    final courseOverGround = ref.watch(courseOverGroundProvider(const Duration(minutes: 5)));
    final speedOverGround = ref.watch(speedOverGroundProvider(const Duration(minutes: 5)));

    if (currentPosition == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12.0),
          child: Text('No GPS position available'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Vessel Position',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              currentPosition.toCoordinateString(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            if (currentPosition.heading != null)
              Text(
                'Heading: ${currentPosition.heading!.toStringAsFixed(0)}°',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (currentPosition.speed != null)
              Text(
                'Speed: ${(currentPosition.speed! * 1.944).toStringAsFixed(1)} kts',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            courseOverGround.when(
              data: (cog) => cog != null
                  ? Text(
                      'COG: ${cog.bearing.toStringAsFixed(0)}° (${(cog.confidence * 100).toStringAsFixed(0)}%)',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            speedOverGround.when(
              data: (sog) => sog != null
                  ? Text(
                      'SOG: ${sog.speedKnots.toStringAsFixed(1)} kts (${(sog.confidence * 100).toStringAsFixed(0)}%)',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}