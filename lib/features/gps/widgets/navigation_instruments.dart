import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../../core/models/position_history.dart';
import '../providers/gps_providers.dart';

/// Widget that displays navigation instruments (heading, COG, SOG)
class NavigationInstruments extends ConsumerWidget {
  final bool isCompact;
  final Duration analysisWindow;

  const NavigationInstruments({
    super.key,
    this.isCompact = false,
    this.analysisWindow = const Duration(minutes: 5),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPosition = ref.watch(latestGpsPositionProvider);
    final courseOverGround = ref.watch(courseOverGroundProvider(analysisWindow));
    final speedOverGround = ref.watch(speedOverGroundProvider(analysisWindow));
    final movementState = ref.watch(movementStateProvider(analysisWindow));

    if (currentPosition == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_off, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(
                'No GPS Position',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isCompact) {
      return _buildCompactInstruments(context, currentPosition, courseOverGround, speedOverGround);
    } else {
      return _buildFullInstruments(context, currentPosition, courseOverGround, speedOverGround, movementState);
    }
  }

  Widget _buildCompactInstruments(
    BuildContext context,
    currentPosition,
    AsyncValue<CourseOverGround?> courseOverGround,
    AsyncValue<SpeedOverGround?> speedOverGround,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading indicator
            if (currentPosition.heading != null)
              _buildCompactHeadingIndicator(context, currentPosition.heading!),
            if (currentPosition.heading != null) const SizedBox(width: 12),
            
            // Speed indicator
            speedOverGround.when(
              data: (sog) => sog != null
                  ? _buildCompactSpeedIndicator(context, sog.speedKnots)
                  : _buildCompactSpeedIndicator(context, currentPosition.speed != null ? currentPosition.speed! * 1.944 : 0.0),
              loading: () => _buildCompactSpeedIndicator(context, 0.0),
              error: (_, __) => _buildCompactSpeedIndicator(context, 0.0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullInstruments(
    BuildContext context,
    currentPosition,
    AsyncValue<CourseOverGround?> courseOverGround,
    AsyncValue<SpeedOverGround?> speedOverGround,
    AsyncValue<MovementState> movementState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Navigation Instruments',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Main instrument row
            Row(
              children: [
                // Heading compass
                Expanded(
                  child: _buildHeadingCompass(context, currentPosition.heading),
                ),
                const SizedBox(width: 16),
                
                // Speed and course displays
                Expanded(
                  child: Column(
                    children: [
                      // Speed over ground
                      speedOverGround.when(
                        data: (sog) => _buildSpeedDisplay(context, sog),
                        loading: () => _buildLoadingDisplay(context, 'Speed'),
                        error: (_, __) => _buildErrorDisplay(context, 'Speed'),
                      ),
                      const SizedBox(height: 12),
                      
                      // Course over ground
                      courseOverGround.when(
                        data: (cog) => _buildCourseDisplay(context, cog),
                        loading: () => _buildLoadingDisplay(context, 'Course'),
                        error: (_, __) => _buildErrorDisplay(context, 'Course'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Movement state indicator
            movementState.when(
              data: (state) => _buildMovementStateIndicator(context, state),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactHeadingIndicator(BuildContext context, double heading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(24, 24),
          painter: _CompassPainter(heading: heading, isCompact: true),
        ),
        const SizedBox(height: 2),
        Text(
          '${heading.toStringAsFixed(0)}°',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactSpeedIndicator(BuildContext context, double speedKnots) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speed,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 2),
        Text(
          '${speedKnots.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'kts',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildHeadingCompass(BuildContext context, double? heading) {
    return Column(
      children: [
        Text(
          'Heading',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _CompassPainter(heading: heading),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          heading != null ? '${heading.toStringAsFixed(0)}°' : '---°',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDisplay(BuildContext context, SpeedOverGround? sog) {
    final speedKnots = sog?.speedKnots ?? 0.0;
    final confidence = sog?.confidence ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'Speed Over Ground',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${speedKnots.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'knots',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (confidence > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: confidence,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                confidence > 0.7 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseDisplay(BuildContext context, CourseOverGround? cog) {
    final bearing = cog?.bearing ?? 0.0;
    final confidence = cog?.confidence ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'Course Over Ground',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${bearing.toStringAsFixed(0)}°',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            _getCompassDirection(bearing),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (confidence > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: confidence,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                confidence > 0.7 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMovementStateIndicator(BuildContext context, MovementState state) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: state.isStationary 
            ? Colors.orange.shade50 
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: state.isStationary 
              ? Colors.orange.shade200 
              : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            state.isStationary ? Icons.anchor : Icons.directions_boat,
            color: state.isStationary ? Colors.orange : Colors.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isStationary ? 'Stationary' : 'Under Way',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: state.isStationary ? Colors.orange.shade800 : Colors.green.shade800,
                  ),
                ),
                if (state.stationaryDuration != null)
                  Text(
                    'For ${_formatDuration(state.stationaryDuration!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            '${(state.confidence * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingDisplay(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 8),
          Text(
            'Calculating...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorDisplay(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Icon(Icons.error, color: Colors.red.shade600),
          const SizedBox(height: 8),
          Text(
            'No Data',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }

  String _getCompassDirection(double bearing) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                       'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((bearing + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

/// Custom painter for compass heading display
class _CompassPainter extends CustomPainter {
  final double? heading;
  final bool isCompact;

  _CompassPainter({this.heading, this.isCompact = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 2;

    // Draw compass circle
    final compassPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCompact ? 1.5 : 2.0;
    canvas.drawCircle(center, radius, compassPaint);

    // Draw compass markings
    _drawCompassMarkings(canvas, center, radius);

    // Draw heading indicator if available
    if (heading != null) {
      _drawHeadingIndicator(canvas, center, radius, heading!);
    }

    // Draw north indicator
    _drawNorthIndicator(canvas, center, radius);
  }

  void _drawCompassMarkings(Canvas canvas, Offset center, double radius) {
    final markingPaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = isCompact ? 0.5 : 1.0;

    for (int i = 0; i < 360; i += 30) {
      final angle = i * math.pi / 180;
      final startRadius = radius * (i % 90 == 0 ? 0.8 : 0.9);
      final start = Offset(
        center.dx + startRadius * math.sin(angle),
        center.dy - startRadius * math.cos(angle),
      );
      final end = Offset(
        center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle),
      );
      canvas.drawLine(start, end, markingPaint);
    }
  }

  void _drawHeadingIndicator(Canvas canvas, Offset center, double radius, double heading) {
    final headingAngle = heading * math.pi / 180;
    final headingPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = isCompact ? 2.0 : 3.0
      ..strokeCap = StrokeCap.round;

    final headingEnd = Offset(
      center.dx + (radius * 0.7) * math.sin(headingAngle),
      center.dy - (radius * 0.7) * math.cos(headingAngle),
    );

    canvas.drawLine(center, headingEnd, headingPaint);

    // Draw heading arrow
    if (!isCompact) {
      final arrowPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      final arrowPath = Path();
      final arrowSize = 6.0;
      arrowPath.moveTo(headingEnd.dx, headingEnd.dy);
      arrowPath.lineTo(
        headingEnd.dx - arrowSize * math.sin(headingAngle + 0.5),
        headingEnd.dy + arrowSize * math.cos(headingAngle + 0.5),
      );
      arrowPath.lineTo(
        headingEnd.dx - arrowSize * math.sin(headingAngle - 0.5),
        headingEnd.dy + arrowSize * math.cos(headingAngle - 0.5),
      );
      arrowPath.close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  void _drawNorthIndicator(Canvas canvas, Offset center, double radius) {
    final northPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;

    final northIndicator = Offset(center.dx, center.dy - radius + (isCompact ? 3 : 6));
    canvas.drawCircle(northIndicator, isCompact ? 2 : 3, northPaint);

    if (!isCompact) {
      // Draw 'N' text
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'N',
          style: TextStyle(
            color: Colors.blue.shade700,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          center.dy - radius - textPainter.height - 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) {
    return oldDelegate.heading != heading || oldDelegate.isCompact != isCompact;
  }
}