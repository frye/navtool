import 'dart:convert';

import 'geo_types.dart';

/// Source type for coastline data.
enum ChartSource {
  /// NOAA ENC Direct data (high resolution, regional)
  enc,
  /// GSHHG data (global coverage, various resolutions)
  gshhg,
}

/// Resolution level for GSHHG data.
enum GshhgResolution {
  crude,       // ~300 KB global, zoom 0-2
  low,         // ~1 MB global, zoom 2-5
  intermediate,// ~3.5 MB global, zoom 5-8
  high,        // ~12 MB global, zoom 8+
  full,        // ~56 MB global, maximum detail
}

/// Metadata for a single chart region in the manifest.
class ChartRegion {
  final String id;
  final String name;
  final GeoBounds bounds;
  final ChartSource source;
  final List<int> lods;
  final List<String> files;
  final GshhgResolution? gshhgResolution;
  final DateTime? lastUpdated;

  const ChartRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.source,
    required this.lods,
    required this.files,
    this.gshhgResolution,
    this.lastUpdated,
  });

  factory ChartRegion.fromJson(String id, Map<String, dynamic> json) {
    final bounds = json['bounds'] as List<dynamic>;
    return ChartRegion(
      id: id,
      name: json['name'] as String,
      bounds: GeoBounds(
        minLon: (bounds[0] as num).toDouble(),
        minLat: (bounds[1] as num).toDouble(),
        maxLon: (bounds[2] as num).toDouble(),
        maxLat: (bounds[3] as num).toDouble(),
      ),
      source: ChartSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => ChartSource.gshhg,
      ),
      lods: (json['lods'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [0],
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      gshhgResolution: json['gshhgResolution'] != null
          ? GshhgResolution.values.firstWhere(
              (r) => r.name == json['gshhgResolution'],
              orElse: () => GshhgResolution.crude,
            )
          : null,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'bounds': [bounds.minLon, bounds.minLat, bounds.maxLon, bounds.maxLat],
        'source': source.name,
        'lods': lods,
        'files': files,
        if (gshhgResolution != null) 'gshhgResolution': gshhgResolution!.name,
        if (lastUpdated != null) 'lastUpdated': lastUpdated!.toIso8601String(),
      };

  /// Check if this region overlaps with given bounds.
  bool overlaps(GeoBounds other) {
    return bounds.minLon <= other.maxLon &&
        bounds.maxLon >= other.minLon &&
        bounds.minLat <= other.maxLat &&
        bounds.maxLat >= other.minLat;
  }

  /// Check if this region fully contains given bounds.
  bool contains(GeoBounds other) {
    return bounds.minLon <= other.minLon &&
        bounds.maxLon >= other.maxLon &&
        bounds.minLat <= other.minLat &&
        bounds.maxLat >= other.maxLat;
  }
}

/// Manifest file containing all available chart regions.
/// 
/// The manifest provides O(1) lookup for chart data without
/// expensive directory scanning - important for low-power
/// devices like Raspberry Pi.
class ChartManifest {
  final int version;
  final DateTime lastUpdated;
  final Map<String, ChartRegion> regions;

  const ChartManifest({
    required this.version,
    required this.lastUpdated,
    required this.regions,
  });

  factory ChartManifest.empty() => ChartManifest(
        version: 1,
        lastUpdated: DateTime.now(),
        regions: {},
      );

  factory ChartManifest.fromJson(Map<String, dynamic> json) {
    final regionsJson = json['regions'] as Map<String, dynamic>? ?? {};
    final regions = <String, ChartRegion>{};
    
    for (final entry in regionsJson.entries) {
      regions[entry.key] = ChartRegion.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }

    return ChartManifest(
      version: json['version'] as int? ?? 1,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : DateTime.now(),
      regions: regions,
    );
  }

  factory ChartManifest.parse(String jsonString) {
    return ChartManifest.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastUpdated': lastUpdated.toIso8601String(),
        'regions': {
          for (final entry in regions.entries) entry.key: entry.value.toJson(),
        },
      };

  String toJsonString({bool pretty = false}) {
    final encoder = pretty 
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// Find all regions that overlap with the given bounds.
  List<ChartRegion> findOverlapping(GeoBounds bounds) {
    return regions.values.where((r) => r.overlaps(bounds)).toList();
  }

  /// Find all ENC regions that overlap with the given bounds.
  List<ChartRegion> findEncRegions(GeoBounds bounds) {
    return regions.values
        .where((r) => r.source == ChartSource.enc && r.overlaps(bounds))
        .toList();
  }

  /// Find all GSHHG regions that overlap with the given bounds.
  List<ChartRegion> findGshhgRegions(GeoBounds bounds) {
    return regions.values
        .where((r) => r.source == ChartSource.gshhg && r.overlaps(bounds))
        .toList();
  }

  /// Get the best available GSHHG resolution for given bounds.
  GshhgResolution? getBestGshhgResolution(GeoBounds bounds) {
    final gshhgRegions = findGshhgRegions(bounds);
    if (gshhgRegions.isEmpty) return null;

    // Return highest resolution available
    GshhgResolution? best;
    for (final region in gshhgRegions) {
      final res = region.gshhgResolution;
      if (res == null) continue;
      if (best == null || res.index > best.index) {
        best = res;
      }
    }
    return best;
  }

  /// Create a new manifest with an added/updated region.
  ChartManifest withRegion(ChartRegion region) {
    return ChartManifest(
      version: version,
      lastUpdated: DateTime.now(),
      regions: {...regions, region.id: region},
    );
  }
}
