import 'package:flutter/foundation.dart';
import 'gps_position.dart';

/// Container for GPS position history and calculated metrics
@immutable
class PositionHistory {
  /// List of GPS positions in chronological order
  final List<GpsPosition> positions;
  
  /// Total distance traveled in meters
  final double totalDistance;
  
  /// Average speed in meters per second
  final double averageSpeed;
  
  /// Maximum speed recorded in meters per second
  final double maxSpeed;
  
  /// Minimum speed recorded in meters per second
  final double minSpeed;
  
  /// Duration covered by this history
  final Duration duration;
  
  /// Starting timestamp of this history
  final DateTime? startTime;
  
  /// Ending timestamp of this history
  final DateTime? endTime;

  const PositionHistory({
    required this.positions,
    required this.totalDistance,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.minSpeed,
    required this.duration,
    this.startTime,
    this.endTime,
  });

  /// Creates position history from a list of GPS positions
  factory PositionHistory.fromPositions(List<GpsPosition> positions) {
    if (positions.isEmpty) {
      return const PositionHistory(
        positions: [],
        totalDistance: 0.0,
        averageSpeed: 0.0,
        maxSpeed: 0.0,
        minSpeed: 0.0,
        duration: Duration.zero,
      );
    }

    // Sort positions by timestamp
    final sortedPositions = List<GpsPosition>.from(positions)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Calculate total distance
    double totalDistance = 0.0;
    for (int i = 1; i < sortedPositions.length; i++) {
      totalDistance += sortedPositions[i - 1].distanceTo(sortedPositions[i]);
    }

    // Calculate duration
    final startTime = sortedPositions.first.timestamp;
    final endTime = sortedPositions.last.timestamp;
    final duration = endTime.difference(startTime);

    // Calculate speed statistics
    final speedsFromGps = sortedPositions
        .where((p) => p.speed != null)
        .map((p) => p.speed!)
        .toList();

    double averageSpeed;
    double maxSpeed;
    double minSpeed;

    if (speedsFromGps.isNotEmpty) {
      // Use GPS-reported speeds if available
      averageSpeed = speedsFromGps.reduce((a, b) => a + b) / speedsFromGps.length;
      maxSpeed = speedsFromGps.reduce((a, b) => a > b ? a : b);
      minSpeed = speedsFromGps.reduce((a, b) => a < b ? a : b);
    } else if (duration.inSeconds > 0) {
      // Calculate speed from distance/time
      averageSpeed = totalDistance / duration.inSeconds;
      maxSpeed = averageSpeed; // Can't determine max without instantaneous measurements
      minSpeed = averageSpeed;
    } else {
      averageSpeed = 0.0;
      maxSpeed = 0.0;
      minSpeed = 0.0;
    }

    return PositionHistory(
      positions: sortedPositions,
      totalDistance: totalDistance,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      minSpeed: minSpeed,
      duration: duration,
      startTime: startTime,
      endTime: endTime,
    );
  }

  /// Creates position history filtered by time window
  factory PositionHistory.fromPositionsInTimeWindow(
    List<GpsPosition> positions,
    Duration timeWindow,
  ) {
    final cutoffTime = DateTime.now().subtract(timeWindow);
    final filteredPositions = positions
        .where((position) => position.timestamp.isAfter(cutoffTime))
        .toList();
    
    return PositionHistory.fromPositions(filteredPositions);
  }

  /// Gets the average speed in knots
  double get averageSpeedKnots => averageSpeed * 1.944;

  /// Gets the maximum speed in knots
  double get maxSpeedKnots => maxSpeed * 1.944;

  /// Gets whether this track indicates significant movement
  bool get hasSignificantMovement => totalDistance > 10.0; // More than 10 meters

  /// Gets the average accuracy of positions (if available)
  double? get averageAccuracy {
    final accuracies = positions
        .where((p) => p.accuracy != null)
        .map((p) => p.accuracy!)
        .toList();
    
    if (accuracies.isEmpty) return null;
    
    return accuracies.reduce((a, b) => a + b) / accuracies.length;
  }

  /// Gets the best (lowest) accuracy value
  double? get bestAccuracy {
    final accuracies = positions
        .where((p) => p.accuracy != null)
        .map((p) => p.accuracy!)
        .toList();
    
    if (accuracies.isEmpty) return null;
    
    return accuracies.reduce((a, b) => a < b ? a : b);
  }

  /// Gets the percentage of positions that meet marine-grade accuracy
  double get marineGradePercentage {
    if (positions.isEmpty) return 0.0;
    
    final marineGradeCount = positions
        .where((p) => p.accuracy != null && p.accuracy! <= 10.0)
        .length;
    
    return marineGradeCount / positions.length;
  }

  /// Gets positions within a specific accuracy threshold
  List<GpsPosition> getPositionsWithAccuracy(double maxAccuracy) {
    return positions
        .where((p) => p.accuracy != null && p.accuracy! <= maxAccuracy)
        .toList();
  }

  /// Gets a summary string of this position history
  String get summary {
    if (positions.isEmpty) {
      return 'No position data available';
    }

    final distanceKm = totalDistance / 1000;
    final avgSpeedKnots = averageSpeedKnots;
    final durationHours = duration.inMinutes / 60.0;

    return 'Track: ${distanceKm.toStringAsFixed(2)}km, '
           'Avg Speed: ${avgSpeedKnots.toStringAsFixed(1)}kts, '
           'Duration: ${durationHours.toStringAsFixed(1)}h, '
           'Points: ${positions.length}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionHistory &&
          runtimeType == other.runtimeType &&
          listEquals(positions, other.positions) &&
          totalDistance == other.totalDistance &&
          averageSpeed == other.averageSpeed &&
          duration == other.duration;

  @override
  int get hashCode =>
      positions.hashCode ^
      totalDistance.hashCode ^
      averageSpeed.hashCode ^
      duration.hashCode;

  @override
  String toString() {
    return 'PositionHistory(${positions.length} positions, ${totalDistance.toStringAsFixed(1)}m, ${duration.inSeconds}s)';
  }
}

/// Statistics about GPS position accuracy over time
@immutable
class AccuracyStatistics {
  /// Average accuracy in meters
  final double averageAccuracy;
  
  /// Best (lowest) accuracy recorded in meters
  final double bestAccuracy;
  
  /// Worst (highest) accuracy recorded in meters
  final double worstAccuracy;
  
  /// Percentage of positions meeting marine-grade accuracy (≤10m)
  final double marineGradePercentage;
  
  /// Number of positions used in calculation
  final int sampleCount;
  
  /// Time period these statistics cover
  final Duration period;

  const AccuracyStatistics({
    required this.averageAccuracy,
    required this.bestAccuracy,
    required this.worstAccuracy,
    required this.marineGradePercentage,
    required this.sampleCount,
    required this.period,
  });

  /// Creates accuracy statistics from position history
  factory AccuracyStatistics.fromPositions(
    List<GpsPosition> positions,
    Duration period,
  ) {
    final positionsWithAccuracy = positions
        .where((p) => p.accuracy != null)
        .toList();

    if (positionsWithAccuracy.isEmpty) {
      return AccuracyStatistics(
        averageAccuracy: 0.0,
        bestAccuracy: 0.0,
        worstAccuracy: 0.0,
        marineGradePercentage: 0.0,
        sampleCount: 0,
        period: period,
      );
    }

    final accuracies = positionsWithAccuracy.map((p) => p.accuracy!).toList();
    final averageAccuracy = accuracies.reduce((a, b) => a + b) / accuracies.length;
    final bestAccuracy = accuracies.reduce((a, b) => a < b ? a : b);
    final worstAccuracy = accuracies.reduce((a, b) => a > b ? a : b);
    
    final marineGradeCount = accuracies.where((acc) => acc <= 10.0).length;
    final marineGradePercentage = marineGradeCount / accuracies.length;

    return AccuracyStatistics(
      averageAccuracy: averageAccuracy,
      bestAccuracy: bestAccuracy,
      worstAccuracy: worstAccuracy,
      marineGradePercentage: marineGradePercentage,
      sampleCount: accuracies.length,
      period: period,
    );
  }

  @override
  String toString() {
    return 'AccuracyStats(avg: ${averageAccuracy.toStringAsFixed(1)}m, '
           'best: ${bestAccuracy.toStringAsFixed(1)}m, '
           'marine: ${(marineGradePercentage * 100).toStringAsFixed(0)}%)';
  }
}

/// Information about vessel movement state
@immutable
class MovementState {
  /// Whether the vessel appears to be stationary
  final bool isStationary;
  
  /// Average speed over the analysis period (m/s)
  final double averageSpeed;
  
  /// How long the vessel has been stationary (if applicable)
  final Duration? stationaryDuration;
  
  /// Confidence level in the movement assessment (0.0 to 1.0)
  final double confidence;
  
  /// Radius of movement in meters (for stationary detection)
  final double movementRadius;

  const MovementState({
    required this.isStationary,
    required this.averageSpeed,
    required this.confidence,
    required this.movementRadius,
    this.stationaryDuration,
  });

  /// Creates movement state from position history
  factory MovementState.fromPositions(
    List<GpsPosition> positions,
    Duration analysisWindow,
  ) {
    if (positions.length < 2) {
      return const MovementState(
        isStationary: true,
        averageSpeed: 0.0,
        confidence: 0.0,
        movementRadius: 0.0,
      );
    }

    // Calculate average speed
    final speedValues = positions
        .where((p) => p.speed != null)
        .map((p) => p.speed!)
        .toList();

    double averageSpeed;
    if (speedValues.isNotEmpty) {
      averageSpeed = speedValues.reduce((a, b) => a + b) / speedValues.length;
    } else {
      // Calculate from position changes
      final history = PositionHistory.fromPositions(positions);
      averageSpeed = history.averageSpeed;
    }

    // Calculate movement radius (maximum distance from centroid)
    final centroidLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
    final centroidLon = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
    
    final centroid = GpsPosition(
      latitude: centroidLat,
      longitude: centroidLon,
      timestamp: DateTime.now(),
    );

    double maxDistance = 0.0;
    for (final position in positions) {
      final distance = position.distanceTo(centroid);
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }

    // Determine if stationary (average speed < 0.5 m/s and radius < 20m)
    final isStationary = averageSpeed < 0.5 && maxDistance < 20.0;
    
    // Calculate confidence based on data quality
    final hasSpeedData = speedValues.isNotEmpty;
    final hasGoodAccuracy = positions.any((p) => p.accuracy != null && p.accuracy! <= 10.0);
    double confidence = 0.5;
    if (hasSpeedData) confidence += 0.3;
    if (hasGoodAccuracy) confidence += 0.2;

    // Calculate stationary duration if applicable
    Duration? stationaryDuration;
    if (isStationary && positions.length >= 2) {
      stationaryDuration = positions.last.timestamp.difference(positions.first.timestamp);
    }

    return MovementState(
      isStationary: isStationary,
      averageSpeed: averageSpeed,
      confidence: confidence,
      movementRadius: maxDistance,
      stationaryDuration: stationaryDuration,
    );
  }

  @override
  String toString() {
    return 'MovementState(stationary: $isStationary, '
           'speed: ${averageSpeed.toStringAsFixed(1)}m/s, '
           'radius: ${movementRadius.toStringAsFixed(1)}m)';
  }
}

/// Enumeration of position data staleness levels
enum StalenessLevel {
  fresh,    // < 30 seconds old
  recent,   // 30 seconds to 2 minutes old
  stale,    // 2 to 10 minutes old
  veryStale // > 10 minutes old
}

/// Information about the freshness of position data
@immutable
class PositionFreshness {
  /// Time since the last position update
  final Duration lastUpdateAge;
  
  /// Whether the position data is considered fresh
  final bool isFresh;
  
  /// Staleness level of the position data
  final StalenessLevel stalenessLevel;
  
  /// Timestamp of the last position update
  final DateTime? lastUpdateTime;

  const PositionFreshness({
    required this.lastUpdateAge,
    required this.isFresh,
    required this.stalenessLevel,
    this.lastUpdateTime,
  });

  /// Creates freshness info from the last position timestamp
  factory PositionFreshness.fromLastUpdate(DateTime? lastUpdate) {
    if (lastUpdate == null) {
      return const PositionFreshness(
        lastUpdateAge: Duration(days: 1), // Arbitrarily old
        isFresh: false,
        stalenessLevel: StalenessLevel.veryStale,
      );
    }

    final age = DateTime.now().difference(lastUpdate);
    final isFresh = age.inSeconds <= 30;
    
    StalenessLevel stalenessLevel;
    if (age.inSeconds <= 30) {
      stalenessLevel = StalenessLevel.fresh;
    } else if (age.inSeconds <= 120) {
      stalenessLevel = StalenessLevel.recent;
    } else if (age.inMinutes <= 10) {
      stalenessLevel = StalenessLevel.stale;
    } else {
      stalenessLevel = StalenessLevel.veryStale;
    }

    return PositionFreshness(
      lastUpdateAge: age,
      isFresh: isFresh,
      stalenessLevel: stalenessLevel,
      lastUpdateTime: lastUpdate,
    );
  }

  @override
  String toString() {
    return 'PositionFreshness(age: ${lastUpdateAge.inSeconds}s, level: $stalenessLevel)';
  }
}

/// Course over ground calculation result
@immutable
class CourseOverGround {
  /// Bearing in degrees (0-360)
  final double bearing;
  
  /// Confidence in the bearing calculation (0.0 to 1.0)
  final double confidence;
  
  /// Number of position samples used
  final int sampleCount;
  
  /// Time period over which COG was calculated
  final Duration period;

  const CourseOverGround({
    required this.bearing,
    required this.confidence,
    required this.sampleCount,
    required this.period,
  });

  @override
  String toString() {
    return 'COG: ${bearing.toStringAsFixed(1)}° (confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
  }
}

/// Speed over ground calculation result
@immutable
class SpeedOverGround {
  /// Speed in meters per second
  final double speedMetersPerSecond;
  
  /// Speed in knots
  final double speedKnots;
  
  /// Confidence in the speed calculation (0.0 to 1.0)
  final double confidence;
  
  /// Number of position samples used
  final int sampleCount;
  
  /// Time period over which SOG was calculated
  final Duration period;

  const SpeedOverGround({
    required this.speedMetersPerSecond,
    required this.confidence,
    required this.sampleCount,
    required this.period,
  }) : speedKnots = speedMetersPerSecond * 1.944;

  @override
  String toString() {
    return 'SOG: ${speedKnots.toStringAsFixed(1)}kts (${speedMetersPerSecond.toStringAsFixed(1)}m/s)';
  }
}