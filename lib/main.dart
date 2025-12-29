import 'dart:async';

import 'package:flutter/material.dart';

import 'models/geo_types.dart';
import 'parser/coastline_parser.dart';
import 'renderer/coastline_renderer.dart';
import 'services/coastline_data_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NavToolApp());
}

class NavToolApp extends StatelessWidget {
  const NavToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavTool - NOAA Chart Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChartViewerScreen(),
    );
  }
}

class ChartViewerScreen extends StatefulWidget {
  const ChartViewerScreen({super.key});

  @override
  State<ChartViewerScreen> createState() => _ChartViewerScreenState();
}

class _ChartViewerScreenState extends State<ChartViewerScreen> {
  final CoastlineDataManager _dataManager = CoastlineDataManager();
  
  CoastlineData? _coastlineData;
  List<CoastlineData>? _regionalLods;  // ENC regional data
  List<CoastlineData>? _globalLods;    // GSHHG global data
  GeoBounds? _viewBounds;              // Expanded view bounds
  bool _isLoading = true;
  String? _error;
  
  // Download progress
  StreamSubscription<DownloadProgress>? _downloadSubscription;
  DownloadProgress? _currentDownload;

  @override
  void initState() {
    super.initState();
    _initializeDataManager();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _dataManager.dispose();
    debugPrint('NavTool exited cleanly (window closed by user).');
    super.dispose();
  }

  Future<void> _initializeDataManager() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _dataManager.initialize();
      
      // Subscribe to download progress
      _downloadSubscription = _dataManager.downloadProgress.listen((progress) {
        setState(() {
          _currentDownload = progress.isComplete ? null : progress;
        });
      });
      
      await _loadCoastlineData();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCoastlineData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final regionalLods = <CoastlineData>[];
      final globalLods = <CoastlineData>[];

      // Load ENC data for regional detail (Seattle)
      final encLods = await _dataManager.getCoastlineLods('seattle');
      if (encLods != null && encLods.isNotEmpty) {
        regionalLods.addAll(encLods);
        debugPrint('Loaded ${encLods.length} Seattle ENC LODs');
      } else {
        // Try legacy direct file loading
        final legacyLods = await _loadAvailableLods();
        regionalLods.addAll(legacyLods);
        if (legacyLods.isNotEmpty) {
          debugPrint('Loaded ${legacyLods.length} legacy ENC LODs');
        }
      }

      // Load GSHHG global data for different zoom levels
      await _loadGshhgData(globalLods);

      if (regionalLods.isEmpty && globalLods.isEmpty) {
        setState(() {
          _error = 'No coastline data available.\n\n'
              'Run the GSHHG download script to get global coastline data:\n'
              'python tools/download_gshhg.py --bundle-crude';
          _isLoading = false;
        });
        return;
      }

      // Determine the view bounds - expand regional bounds to show GSHHG context
      GeoBounds? viewBounds;
      if (regionalLods.isNotEmpty) {
        final regionalBounds = regionalLods.first.bounds;
        // Expand bounds by 100% on each side to show surrounding GSHHG data
        // This gives a 3x wider/taller view to see coastlines beyond the ENC region
        final expandLon = regionalBounds.width * 1.0;
        final expandLat = regionalBounds.height * 1.0;
        viewBounds = GeoBounds(
          minLon: regionalBounds.minLon - expandLon,
          minLat: regionalBounds.minLat - expandLat,
          maxLon: regionalBounds.maxLon + expandLon,
          maxLat: regionalBounds.maxLat + expandLat,
        );
        debugPrint('View bounds expanded: ${viewBounds.minLon.toStringAsFixed(1)}, ${viewBounds.minLat.toStringAsFixed(1)} to ${viewBounds.maxLon.toStringAsFixed(1)}, ${viewBounds.maxLat.toStringAsFixed(1)}');
      }

      debugPrint('Regional LODs: ${regionalLods.length}');
      for (final lod in regionalLods) {
        debugPrint('  ${lod.name}: zoom ${lod.minZoom?.toStringAsFixed(1) ?? "?"}-${lod.maxZoom?.toStringAsFixed(1) ?? "∞"}, ${lod.totalPoints} points');
      }
      debugPrint('Global LODs: ${globalLods.length}');
      for (final lod in globalLods) {
        debugPrint('  ${lod.name}: zoom ${lod.minZoom?.toStringAsFixed(1) ?? "?"}-${lod.maxZoom?.toStringAsFixed(1) ?? "∞"}, ${lod.totalPoints} points');
      }

      setState(() {
        _regionalLods = regionalLods.isNotEmpty ? regionalLods : null;
        _globalLods = globalLods.isNotEmpty ? globalLods : null;
        _viewBounds = viewBounds;
        _coastlineData = regionalLods.isNotEmpty ? regionalLods.first : globalLods.first;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load coastline data: $e';
        _isLoading = false;
      });
    }
  }

  /// Load available GSHHG resolutions and add them to the LOD list.
  /// GSHHG is used as fallback when zoomed out beyond regional ENC coverage.
  Future<void> _loadGshhgData(List<CoastlineData> allLods) async {
    // GSHHG is for global view only - regional ENC data takes priority
    // These ranges are for when NO regional ENC data is available
    // When ENC is available, ENC zoom ranges take precedence
    final gshhgConfigs = [
      ('full', 'GSHHG Full (Global)', 0, 8.0, null),
      ('high', 'GSHHG High (Global)', 1, 5.0, 8.0),
      ('intermediate', 'GSHHG Intermediate (Global)', 2, 2.0, 5.0),
      ('low', 'GSHHG Low (Global)', 3, 0.5, 2.0),
      ('crude', 'GSHHG Crude (Global)', 4, 0.0, 0.5),
    ];

    for (final config in gshhgConfigs) {
      final (resolution, name, lodLevel, minZoom, maxZoom) = config;
      try {
        final data = await CoastlineParser.loadBinaryAsset(
          'assets/gshhg/gshhg_$resolution.bin',
          name: name,
        );
        allLods.add(data.copyWith(
          lodLevel: lodLevel,
          minZoom: minZoom,
          maxZoom: maxZoom,
          isGlobal: true,  // Mark as global data for world projection
        ));
        debugPrint('Loaded GSHHG $resolution: ${data.totalPoints} points');
      } catch (e) {
        // Resolution not downloaded yet - skip
        debugPrint('GSHHG $resolution not available: $e');
      }
    }
  }

  Future<List<CoastlineData>> _loadAvailableLods() async {
    final candidates = [
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod0.bin',
        lodLevel: 0,
        minZoom: 15,
        maxZoom: 1e9,
        label: 'Seattle Coastline (LOD0 – finest)'
      ),
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod1.bin',
        lodLevel: 1,
        minZoom: 10,
        maxZoom: 15,
        label: 'Seattle Coastline (LOD1 – ultra)'
      ),
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod2.bin',
        lodLevel: 2,
        minZoom: 6,
        maxZoom: 10,
        label: 'Seattle Coastline (LOD2 – very high)'
      ),
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod3.bin',
        lodLevel: 3,
        minZoom: 3,
        maxZoom: 6,
        label: 'Seattle Coastline (LOD3 – high)'
      ),
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod4.bin',
        lodLevel: 4,
        minZoom: 1.5,
        maxZoom: 3,
        label: 'Seattle Coastline (LOD4 – medium)'
      ),
      _LodConfig(
        asset: 'assets/charts/seattle_coastline_lod5.bin',
        lodLevel: 5,
        minZoom: 0.5,
        maxZoom: 1.5,
        label: 'Seattle Coastline (LOD5 – low)'
      ),
    ];

    final loaded = <CoastlineData>[];
    for (final config in candidates) {
      try {
        final data = await CoastlineParser.loadBinaryAsset(
          config.asset,
          name: config.label,
        );
        loaded.add(
          data.copyWith(
            lodLevel: config.lodLevel,
            minZoom: config.minZoom,
            maxZoom: config.maxZoom,
          ),
        );
      } catch (_) {
        // Asset not present; continue to next.
      }
    }

    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NavTool - NOAA Chart Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCoastlineData,
            tooltip: 'Reload Chart',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: 'About',
          ),
        ],
      ),
      body: Column(
        children: [
          // Download status bar
          if (_currentDownload != null)
            _DownloadStatusBar(progress: _currentDownload!),
          
          // Main content
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading coastline data...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadCoastlineData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_coastlineData == null) {
      return const Center(
        child: Text('No coastline data available'),
      );
    }

    return ChartView(
      coastlineData: _coastlineData!,
      coastlineLods: _regionalLods,
      globalLods: _globalLods,
      viewBounds: _viewBounds,
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About NavTool'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NavTool - NOAA Chart Viewer'),
            SizedBox(height: 8),
            Text('A cross-platform application for viewing NOAA nautical charts.'),
            SizedBox(height: 16),
            Text('Data Sources:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• NOAA ENC Direct (high resolution)'),
            Text('• GSHHG Database (global coverage)'),
            SizedBox(height: 16),
            Text('Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Pinch/scroll to zoom'),
            Text('• Drag to pan'),
            Text('• Double-tap to center'),
            Text('• Buttons for zoom control'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Download status bar widget showing progress.
class _DownloadStatusBar extends StatelessWidget {
  final DownloadProgress progress;

  const _DownloadStatusBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blue.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  progress.description,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress.progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress.progress * 100).toInt()}%',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LodConfig {
  final String asset;
  final int lodLevel;
  final double minZoom;
  final double maxZoom;
  final String label;

  const _LodConfig({
    required this.asset,
    required this.lodLevel,
    required this.minZoom,
    required this.maxZoom,
    required this.label,
  });
}
