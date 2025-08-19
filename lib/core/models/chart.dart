import 'package:flutter/foundation.dart';
import 'geographic_bounds.dart';

/// Enum for chart data sources
enum ChartSource {
  noaa,
  ukho,
  ic,
  other;

  String get displayName {
    switch (this) {
      case ChartSource.noaa:
        return 'NOAA';
      case ChartSource.ukho:
        return 'UKHO';
      case ChartSource.ic:
        return 'IIC';
      case ChartSource.other:
        return 'Other';
    }
  }
}

/// Enum for chart status
enum ChartStatus {
  current,
  superseded,
  cancelled,
  preliminary;

  String get displayName {
    switch (this) {
      case ChartStatus.current:
        return 'Current';
      case ChartStatus.superseded:
        return 'Superseded';
      case ChartStatus.cancelled:
        return 'Cancelled';
      case ChartStatus.preliminary:
        return 'Preliminary';
    }
  }
}

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
  
  // Enhanced NOAA-specific fields
  final int edition;
  final int updateNumber;
  final ChartSource source;
  final ChartStatus status;
  final Map<String, dynamic> metadata;

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
    this.edition = 0,
    this.updateNumber = 0,
    this.source = ChartSource.noaa,
    this.status = ChartStatus.current,
    this.metadata = const {},
  }) {
    if (scale <= 0) {
      throw ArgumentError('Scale must be positive');
    }
    if (edition < 0) {
      throw ArgumentError('Edition must be non-negative');
    }
    if (updateNumber < 0) {
      throw ArgumentError('Update number must be non-negative');
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
          fileSize == other.fileSize &&
          edition == other.edition &&
          updateNumber == other.updateNumber &&
          source == other.source &&
          status == other.status &&
          _mapEquals(metadata, other.metadata);

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
      fileSize.hashCode ^
      edition.hashCode ^
      updateNumber.hashCode ^
      source.hashCode ^
      status.hashCode ^
      _mapHashCode(metadata);

  /// Helper method to compare metadata maps
  bool _mapEquals(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (!map2.containsKey(key) || map1[key] != map2[key]) return false;
    }
    return true;
  }

  /// Helper method to compute hash code for metadata map
  int _mapHashCode(Map<String, dynamic> map) {
    int hash = 0;
    for (final entry in map.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  @override
  String toString() {
    return 'Chart(id: $id, title: $title, scale: $scale, state: $state, type: ${type.displayName}, edition: $edition, source: ${source.displayName})';
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
    int? edition,
    int? updateNumber,
    ChartSource? source,
    ChartStatus? status,
    Map<String, dynamic>? metadata,
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
      edition: edition ?? this.edition,
      updateNumber: updateNumber ?? this.updateNumber,
      source: source ?? this.source,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Creates a Chart from JSON map
  factory Chart.fromJson(Map<String, dynamic> json) {
    return Chart(
      id: json['id'] as String,
      title: json['title'] as String,
      scale: json['scale'] as int,
      bounds: GeographicBounds(
        north: json['bounds']['north'] as double,
        south: json['bounds']['south'] as double,
        east: json['bounds']['east'] as double,
        west: json['bounds']['west'] as double,
      ),
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(json['lastUpdate'] as int),
      state: json['state'] as String,
      type: ChartType.values.firstWhere((t) => t.name == json['type']),
      description: json['description'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      fileSize: json['fileSize'] as int?,
      edition: json['edition'] as int? ?? 0,
      updateNumber: json['updateNumber'] as int? ?? 0,
      source: json['source'] != null 
        ? ChartSource.values.firstWhere((s) => s.name == json['source'])
        : ChartSource.noaa,
      status: json['status'] != null
        ? ChartStatus.values.firstWhere((s) => s.name == json['status'])
        : ChartStatus.current,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Converts this Chart to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'scale': scale,
      'bounds': {
        'north': bounds.north,
        'south': bounds.south,
        'east': bounds.east,
        'west': bounds.west,
      },
      'lastUpdate': lastUpdate.millisecondsSinceEpoch,
      'state': state,
      'type': type.name,
      'description': description,
      'isDownloaded': isDownloaded,
      'fileSize': fileSize,
      'edition': edition,
      'updateNumber': updateNumber,
      'source': source.name,
      'status': status.name,
      'metadata': metadata,
    };
  }
}
