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
  List<CoastlineData>? _lodData;
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
      // First, try to load ENC data for a specific region (Seattle as default)
      final encLods = await _dataManager.getCoastlineLods('seattle');
      
      if (encLods != null && encLods.isNotEmpty) {
        setState(() {
          _lodData = encLods;
          _coastlineData = encLods.first;
          _isLoading = false;
        });
        return;
      }

      // Try to load single ENC binary files
      final lodData = await _loadAvailableLods();
      if (lodData.isNotEmpty) {
        setState(() {
          _lodData = lodData;
          _coastlineData = lodData.first;
          _isLoading = false;
        });
        return;
      }

      // Fall back to GSHHG global data
      try {
        final gshhgData = await CoastlineParser.loadBinaryAsset(
          'assets/gshhg/gshhg_crude.bin',
          name: 'GSHHG Global (Crude)',
        );
        setState(() {
          _coastlineData = gshhgData.copyWith(
            lodLevel: 5,
            minZoom: 0.0,
            maxZoom: 2.0,
          );
          _lodData = [_coastlineData!];
          _isLoading = false;
        });
        return;
      } catch (e) {
        print('GSHHG crude not found: $e');
      }

      // Try legacy single file formats
      try {
        final data = await CoastlineParser.loadBinaryAsset(
          'assets/charts/seattle_coastline.bin',
          name: 'Seattle Coastline',
        );
        setState(() {
          _coastlineData = data;
          _lodData = null;
          _isLoading = false;
        });
        return;
      } catch (e) {
        print('Binary format not found, trying GeoJSON: $e');
      }

      try {
        final data = await CoastlineParser.parseGeoJsonAsset(
          'assets/charts/seattle_coastline.geojson',
          name: 'Seattle Coastline',
        );
        setState(() {
          _coastlineData = data;
          _lodData = null;
          _isLoading = false;
        });
        return;
      } catch (e) {
        print('GeoJSON not found: $e');
      }

      // No data found
      setState(() {
        _error = 'No coastline data available.\n\n'
            'Run the GSHHG download script to get global coastline data:\n'
            'python tools/download_gshhg.py --bundle-crude';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load coastline data: $e';
        _isLoading = false;
      });
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
      coastlineLods: _lodData,
      initialZoom: 1.0,
      minZoom: 0.1,
      maxZoom: 50.0,
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
