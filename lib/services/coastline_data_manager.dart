import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/chart_manifest.dart';
import '../models/geo_types.dart';
import '../parser/coastline_parser.dart';

/// Download progress information.
class DownloadProgress {
  final String regionId;
  final String description;
  final double progress; // 0.0 to 1.0
  final bool isComplete;
  final String? error;

  const DownloadProgress({
    required this.regionId,
    required this.description,
    required this.progress,
    this.isComplete = false,
    this.error,
  });

  DownloadProgress copyWith({
    String? regionId,
    String? description,
    double? progress,
    bool? isComplete,
    String? error,
  }) {
    return DownloadProgress(
      regionId: regionId ?? this.regionId,
      description: description ?? this.description,
      progress: progress ?? this.progress,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }
}

/// Manages coastline data from multiple sources (GSHHG + ENC).
/// 
/// Responsibilities:
/// - Load manifest at startup
/// - Provide coastline data for visible region
/// - Trigger downloads for missing GSHHG data
/// - Select best available data (ENC > GSHHG)
class CoastlineDataManager {
  ChartManifest _manifest = ChartManifest.empty();
  final Map<String, CoastlineData> _loadedData = {};
  final Map<String, List<CoastlineData>> _loadedLods = {};
  
  final _downloadProgressController = StreamController<DownloadProgress>.broadcast();
  
  /// Stream of download progress updates.
  Stream<DownloadProgress> get downloadProgress => _downloadProgressController.stream;
  
  /// Current manifest.
  ChartManifest get manifest => _manifest;
  
  /// Whether the manager has been initialized.
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the manager by loading the manifest.
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final manifestJson = await rootBundle.loadString('assets/charts/manifest.json');
      _manifest = ChartManifest.parse(manifestJson);
      _initialized = true;
    } catch (e) {
      // Create empty manifest if none exists
      _manifest = ChartManifest.empty();
      _initialized = true;
    }
  }

  /// Get the best available coastline data for the given bounds and zoom level.
  /// 
  /// Priority:
  /// 1. ENC data (highest detail, regional)
  /// 2. GSHHG high resolution (if downloaded)
  /// 3. GSHHG intermediate (if downloaded)
  /// 4. GSHHG low (if downloaded)
  /// 5. GSHHG crude (bundled, always available)
  Future<CoastlineData?> getCoastlineData(GeoBounds bounds, double zoom) async {
    await initialize();
    
    // Find ENC regions that cover this area
    final encRegions = _manifest.findEncRegions(bounds);
    
    // If we have ENC data and zoom is high enough, prefer it
    if (encRegions.isNotEmpty && zoom >= 2.0) {
      // Load the first matching ENC region
      final encRegion = encRegions.first;
      return _loadRegionData(encRegion, zoom);
    }
    
    // Fall back to GSHHG data
    final gshhgRegions = _manifest.findGshhgRegions(bounds);
    if (gshhgRegions.isNotEmpty) {
      // Select best resolution based on zoom
      final targetResolution = _getTargetResolution(zoom);
      
      // Find GSHHG region with best matching resolution
      ChartRegion? bestRegion;
      for (final region in gshhgRegions) {
        if (region.gshhgResolution == null) continue;
        if (bestRegion == null) {
          bestRegion = region;
        } else if (region.gshhgResolution!.index >= targetResolution.index &&
            (bestRegion.gshhgResolution!.index < targetResolution.index ||
                region.gshhgResolution!.index < bestRegion.gshhgResolution!.index)) {
          bestRegion = region;
        }
      }
      
      if (bestRegion != null) {
        return _loadRegionData(bestRegion, zoom);
      }
    }
    
    return null;
  }

  /// Get all LOD levels for a region (for LOD-switching renderer).
  Future<List<CoastlineData>?> getCoastlineLods(String regionId) async {
    await initialize();
    
    if (_loadedLods.containsKey(regionId)) {
      return _loadedLods[regionId];
    }
    
    final region = _manifest.regions[regionId];
    if (region == null) return null;
    
    final lods = <CoastlineData>[];
    for (final lodLevel in region.lods) {
      final data = await _loadLodData(region, lodLevel);
      if (data != null) {
        lods.add(data);
      }
    }
    
    if (lods.isNotEmpty) {
      _loadedLods[regionId] = lods;
    }
    
    return lods.isEmpty ? null : lods;
  }

  /// Get target GSHHG resolution for a given zoom level.
  GshhgResolution _getTargetResolution(double zoom) {
    if (zoom < 2) return GshhgResolution.crude;
    if (zoom < 5) return GshhgResolution.low;
    if (zoom < 8) return GshhgResolution.intermediate;
    if (zoom < 12) return GshhgResolution.high;
    return GshhgResolution.full;
  }

  /// Load region data (cached).
  Future<CoastlineData?> _loadRegionData(ChartRegion region, double zoom) async {
    final cacheKey = region.id;
    
    if (_loadedData.containsKey(cacheKey)) {
      return _loadedData[cacheKey];
    }
    
    // Determine which LOD to load based on zoom
    final targetLod = _getLodForZoom(zoom, region.lods);
    return _loadLodData(region, targetLod);
  }

  /// Load specific LOD level for a region.
  Future<CoastlineData?> _loadLodData(ChartRegion region, int lodLevel) async {
    final cacheKey = '${region.id}_lod$lodLevel';
    
    if (_loadedData.containsKey(cacheKey)) {
      return _loadedData[cacheKey];
    }
    
    // Find the file for this LOD
    String? targetFile;
    for (final file in region.files) {
      if (file.contains('lod$lodLevel')) {
        targetFile = file;
        break;
      }
    }
    
    // If no specific LOD file, use the first available
    targetFile ??= region.files.isNotEmpty ? region.files.first : null;
    if (targetFile == null) return null;
    
    try {
      // Determine asset path based on source
      final assetPath = region.source == ChartSource.gshhg
          ? 'assets/gshhg/$targetFile'
          : 'assets/charts/$targetFile';
      
      final bytes = await rootBundle.load(assetPath);
      final data = CoastlineParser.fromBinary(
        bytes.buffer.asUint8List(),
        name: region.name,
      );
      
      // Apply LOD metadata
      final dataWithLod = data.copyWith(
        lodLevel: lodLevel,
        minZoom: _getMinZoomForLod(lodLevel),
        maxZoom: _getMaxZoomForLod(lodLevel),
      );
      
      _loadedData[cacheKey] = dataWithLod;
      return dataWithLod;
    } catch (e) {
      // File not found or parse error
      return null;
    }
  }

  /// Get the best LOD level for a given zoom.
  int _getLodForZoom(double zoom, List<int> availableLods) {
    if (availableLods.isEmpty) return 0;
    
    // Higher zoom = lower LOD number (more detail)
    int targetLod;
    if (zoom >= 10) {
      targetLod = 0;
    } else if (zoom >= 6) {
      targetLod = 1;
    } else if (zoom >= 4) {
      targetLod = 2;
    } else if (zoom >= 2) {
      targetLod = 3;
    } else if (zoom >= 1) {
      targetLod = 4;
    } else {
      targetLod = 5;
    }
    
    // Find closest available LOD
    availableLods.sort();
    for (final lod in availableLods) {
      if (lod >= targetLod) return lod;
    }
    return availableLods.first;
  }

  double _getMinZoomForLod(int lod) {
    switch (lod) {
      case 0: return 10.0;
      case 1: return 6.0;
      case 2: return 4.0;
      case 3: return 2.0;
      case 4: return 1.0;
      default: return 0.0;
    }
  }

  double? _getMaxZoomForLod(int lod) {
    switch (lod) {
      case 1: return 10.0;
      case 2: return 6.0;
      case 3: return 4.0;
      case 4: return 2.0;
      case 5: return 1.0;
      default: return null;
    }
  }

  /// Check if better GSHHG data should be downloaded for the given bounds/zoom.
  Future<GshhgResolution?> checkForBetterData(GeoBounds bounds, double zoom) async {
    await initialize();
    
    final targetResolution = _getTargetResolution(zoom);
    final currentBest = _manifest.getBestGshhgResolution(bounds);
    
    // If we don't have the target resolution, return it
    if (currentBest == null || currentBest.index < targetResolution.index) {
      return targetResolution;
    }
    
    return null;
  }

  /// Request download of GSHHG data for given resolution.
  /// Returns a stream of progress updates.
  Future<void> downloadGshhgData(GshhgResolution resolution) async {
    // TODO: Implement actual download from NOAA
    // For now, emit progress updates as placeholder
    
    final regionId = 'gshhg_${resolution.name}_global';
    
    _downloadProgressController.add(DownloadProgress(
      regionId: regionId,
      description: 'Downloading GSHHG ${resolution.name}...',
      progress: 0.0,
    ));
    
    // Simulate download progress
    for (var i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      _downloadProgressController.add(DownloadProgress(
        regionId: regionId,
        description: 'Downloading GSHHG ${resolution.name}...',
        progress: i / 10,
      ));
    }
    
    _downloadProgressController.add(DownloadProgress(
      regionId: regionId,
      description: 'Download complete',
      progress: 1.0,
      isComplete: true,
    ));
  }

  /// Dispose resources.
  void dispose() {
    _downloadProgressController.close();
  }
}
