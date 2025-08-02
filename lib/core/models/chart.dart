import 'package:flutter/foundation.dart';
import 'geographic_bounds.dart';

/// A range of scale values for nautical charts
@immutable
class ScaleRange {
  final int min;
  final int max;

  ScaleRange(this.min, this.max) {
    if (min <= 0) {
      throw ArgumentError('Minimum scale must be positive');
    }
    if (max < min) {
      throw ArgumentError('Maximum scale must be greater than or equal to minimum');
    }
  }

  /// Checks if a scale value is within this range (inclusive)
  bool contains(int scale) {
    return scale >= min && scale <= max;
  }

  /// Gets the midpoint of this scale range
  int get midpoint => (min + max) ~/ 2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScaleRange &&
          runtimeType == other.runtimeType &&
          min == other.min &&
          max == other.max;

  @override
  int get hashCode => min.hashCode ^ max.hashCode;

  @override
  String toString() => 'ScaleRange($min-$max)';
}

/// Enum for different chart types based on scale and usage
enum ChartType {
  overview,
  general,
  coastal,
  approach,
  harbor,
  berthing;

  /// Display name for the chart type
  String get displayName {
    switch (this) {
      case ChartType.overview:
        return 'Overview';
      case ChartType.general:
        return 'General';
      case ChartType.coastal:
        return 'Coastal';
      case ChartType.approach:
        return 'Approach';
      case ChartType.harbor:
        return 'Harbor';
      case ChartType.berthing:
        return 'Berthing';
    }
  }

  /// Returns the typical scale range for this chart type
  ScaleRange get scaleRange {
    switch (this) {
      case ChartType.overview:
        return ScaleRange(1000000, 10000000);
      case ChartType.general:
        return ScaleRange(300000, 1000000);
      case ChartType.coastal:
        return ScaleRange(50000, 300000);
      case ChartType.approach:
        return ScaleRange(25000, 50000);
      case ChartType.harbor:
        return ScaleRange(5000, 25000);
      case ChartType.berthing:
        return ScaleRange(500, 5000);
    }
  }
}

/// Represents an electronic navigational chart (ENC)
@immutable
class Chart {
  final String id;
  final String title;
  final int scale;
  final GeographicBounds bounds;
  final DateTime lastUpdate;
  final String state;
  final ChartType type;
  final String? description;
  final bool isDownloaded;
  final int? fileSize;

  Chart({
    required this.id,
    required this.title,
    required this.scale,
    required this.bounds,
    required this.lastUpdate,
    required this.state,
    required this.type,
    this.description,
    this.isDownloaded = false,
    this.fileSize,
  }) {
    if (scale <= 0) {
      throw ArgumentError('Scale must be positive');
    }
  }

  /// Gets the display scale as a formatted string
  String get displayScale => '1:${scale.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  )}';

  /// Checks if this chart covers a specific point
  bool coversPoint(double latitude, double longitude) {
    return bounds.contains(latitude, longitude);
  }

  /// Returns the priority of this chart type (lower number = higher priority)
  int get typePriority {
    switch (type) {
      case ChartType.berthing:
        return 1;
      case ChartType.harbor:
        return 2;
      case ChartType.approach:
        return 3;
      case ChartType.coastal:
        return 4;
      case ChartType.general:
        return 5;
      case ChartType.overview:
        return 6;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chart &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          scale == other.scale &&
          bounds == other.bounds &&
          lastUpdate == other.lastUpdate &&
          state == other.state &&
          type == other.type &&
          description == other.description &&
          isDownloaded == other.isDownloaded &&
          fileSize == other.fileSize;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      scale.hashCode ^
      bounds.hashCode ^
      lastUpdate.hashCode ^
      state.hashCode ^
      type.hashCode ^
      description.hashCode ^
      isDownloaded.hashCode ^
      fileSize.hashCode;

  @override
  String toString() {
    return 'Chart(id: $id, title: $title, scale: $scale, state: $state, type: ${type.displayName})';
  }

  /// Creates a copy with optional parameter overrides
  Chart copyWith({
    String? id,
    String? title,
    int? scale,
    GeographicBounds? bounds,
    DateTime? lastUpdate,
    String? state,
    ChartType? type,
    String? description,
    bool? isDownloaded,
    int? fileSize,
  }) {
    return Chart(
      id: id ?? this.id,
      title: title ?? this.title,
      scale: scale ?? this.scale,
      bounds: bounds ?? this.bounds,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      state: state ?? this.state,
      type: type ?? this.type,
      description: description ?? this.description,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}
