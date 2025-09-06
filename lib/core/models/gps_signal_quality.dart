import 'package:flutter/foundation.dart';

/// Enumeration of GPS signal strength levels
enum SignalStrength {
  /// Signal strength unknown or unavailable
  unknown,

  /// Very poor signal (>20m accuracy or unavailable)
  poor,

  /// Fair signal (10-20m accuracy)
  fair,

  /// Good signal (5-10m accuracy)
  good,

  /// Excellent signal (<5m accuracy)
  excellent,
}

/// GPS signal quality assessment for marine navigation
@immutable
class GpsSignalQuality {
  /// Signal strength level
  final SignalStrength strength;

  /// Position accuracy in meters (null if unavailable)
  final double? accuracy;

  /// Whether this signal quality meets marine navigation standards
  final bool isMarineGrade;

  /// Number of satellites used in position calculation (if available)
  final int? satelliteCount;

  /// Horizontal dilution of precision (if available)
  final double? hdop;

  /// Recommended action for improving signal quality
  final String recommendedAction;

  /// Timestamp when this assessment was made
  final DateTime assessmentTime;

  const GpsSignalQuality({
    required this.strength,
    required this.accuracy,
    required this.isMarineGrade,
    required this.recommendedAction,
    required this.assessmentTime,
    this.satelliteCount,
    this.hdop,
  });

  /// Creates a signal quality assessment from position accuracy
  factory GpsSignalQuality.fromAccuracy(double? accuracy) {
    final assessmentTime = DateTime.now();

    if (accuracy == null) {
      return GpsSignalQuality(
        strength: SignalStrength.unknown,
        accuracy: null,
        isMarineGrade: false,
        recommendedAction: 'GPS accuracy data unavailable. Check GPS receiver.',
        assessmentTime: assessmentTime,
      );
    }

    SignalStrength strength;
    bool isMarineGrade;
    String recommendedAction;

    if (accuracy <= 5.0) {
      strength = SignalStrength.excellent;
      isMarineGrade = true;
      recommendedAction = 'Excellent GPS signal. Ideal for marine navigation.';
    } else if (accuracy <= 10.0) {
      strength = SignalStrength.good;
      isMarineGrade = true;
      recommendedAction = 'Good GPS signal. Suitable for marine navigation.';
    } else if (accuracy <= 20.0) {
      strength = SignalStrength.fair;
      isMarineGrade = false;
      recommendedAction =
          'Fair GPS signal. Consider finding better location or waiting for signal improvement.';
    } else {
      strength = SignalStrength.poor;
      isMarineGrade = false;
      recommendedAction =
          'Poor GPS signal. Move to better location away from obstructions for improved signal.';
    }

    return GpsSignalQuality(
      strength: strength,
      accuracy: accuracy,
      isMarineGrade: isMarineGrade,
      recommendedAction: recommendedAction,
      assessmentTime: assessmentTime,
    );
  }

  /// Creates a quality assessment with satellite information
  factory GpsSignalQuality.withSatelliteInfo({
    required double? accuracy,
    required int satelliteCount,
    double? hdop,
  }) {
    final baseQuality = GpsSignalQuality.fromAccuracy(accuracy);

    String enhancedRecommendation = baseQuality.recommendedAction;

    if (satelliteCount < 4) {
      enhancedRecommendation +=
          ' Low satellite count ($satelliteCount) - move to open sky area.';
    } else if (satelliteCount >= 8) {
      enhancedRecommendation +=
          ' Good satellite coverage ($satelliteCount satellites).';
    }

    if (hdop != null && hdop > 2.0) {
      enhancedRecommendation +=
          ' High HDOP ($hdop) indicates poor satellite geometry.';
    }

    return GpsSignalQuality(
      strength: baseQuality.strength,
      accuracy: accuracy,
      isMarineGrade: baseQuality.isMarineGrade && satelliteCount >= 4,
      recommendedAction: enhancedRecommendation,
      assessmentTime: baseQuality.assessmentTime,
      satelliteCount: satelliteCount,
      hdop: hdop,
    );
  }

  /// Gets a color representation for UI display
  String get colorCode {
    switch (strength) {
      case SignalStrength.excellent:
        return '#4CAF50'; // Green
      case SignalStrength.good:
        return '#8BC34A'; // Light Green
      case SignalStrength.fair:
        return '#FF9800'; // Orange
      case SignalStrength.poor:
        return '#F44336'; // Red
      case SignalStrength.unknown:
        return '#9E9E9E'; // Grey
    }
  }

  /// Gets a numeric score (0-100) for this signal quality
  int get qualityScore {
    if (accuracy == null) return 0;

    if (accuracy! <= 3.0) return 100;
    if (accuracy! <= 5.0) return 90;
    if (accuracy! <= 8.0) return 75;
    if (accuracy! <= 12.0) return 60;
    if (accuracy! <= 20.0) return 40;
    return 20;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsSignalQuality &&
          runtimeType == other.runtimeType &&
          strength == other.strength &&
          accuracy == other.accuracy &&
          isMarineGrade == other.isMarineGrade &&
          satelliteCount == other.satelliteCount &&
          hdop == other.hdop;

  @override
  int get hashCode =>
      strength.hashCode ^
      accuracy.hashCode ^
      isMarineGrade.hashCode ^
      satelliteCount.hashCode ^
      hdop.hashCode;

  @override
  String toString() {
    return 'GpsSignalQuality(strength: $strength, accuracy: ${accuracy?.toStringAsFixed(1)}m, '
        'marine: $isMarineGrade, satellites: $satelliteCount)';
  }
}
