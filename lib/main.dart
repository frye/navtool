import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/geo_types.dart';
import 'parser/coastline_parser.dart';
import 'renderer/coastline_renderer.dart';

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
  CoastlineData? _coastlineData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCoastlineData();
  }

  Future<void> _loadCoastlineData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to load binary format first (faster)
      try {
        final data = await CoastlineParser.loadBinaryAsset(
          'assets/charts/seattle_coastline.bin',
          name: 'Seattle Coastline',
        );
        setState(() {
          _coastlineData = data;
          _isLoading = false;
        });
        return;
      } catch (e) {
        // Binary not available, try GeoJSON
        print('Binary format not found, trying GeoJSON: $e');
      }

      // Try to load GeoJSON
      try {
        final data = await CoastlineParser.parseGeoJsonAsset(
          'assets/charts/seattle_coastline.geojson',
          name: 'Seattle Coastline',
        );
        setState(() {
          _coastlineData = data;
          _isLoading = false;
        });
        return;
      } catch (e) {
        print('GeoJSON not found: $e');
      }

      // No data found - show demo data
      setState(() {
        _coastlineData = _createDemoData();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load coastline data: $e';
        _isLoading = false;
      });
    }
  }

  /// Creates demo coastline data for Seattle area for testing.
  CoastlineData _createDemoData() {
    // Simplified demo coastline around Seattle/Puget Sound area
    // This is placeholder data - real data should be downloaded from NOAA
    final polygons = [
      // Main land mass (simplified Washington State coastline)
      CoastlinePolygon(
        exteriorRing: [
          const GeoPoint(-122.80, 47.20),
          const GeoPoint(-122.75, 47.25),
          const GeoPoint(-122.70, 47.30),
          const GeoPoint(-122.65, 47.40),
          const GeoPoint(-122.60, 47.50),
          const GeoPoint(-122.55, 47.60),
          const GeoPoint(-122.50, 47.70),
          const GeoPoint(-122.45, 47.75),
          const GeoPoint(-122.35, 47.80),
          const GeoPoint(-122.20, 47.85),
          const GeoPoint(-122.10, 47.80),
          const GeoPoint(-122.00, 47.75),
          const GeoPoint(-121.90, 47.70),
          const GeoPoint(-121.85, 47.60),
          const GeoPoint(-121.80, 47.50),
          const GeoPoint(-121.85, 47.40),
          const GeoPoint(-121.90, 47.30),
          const GeoPoint(-122.00, 47.25),
          const GeoPoint(-122.10, 47.20),
          const GeoPoint(-122.20, 47.18),
          const GeoPoint(-122.30, 47.17),
          const GeoPoint(-122.40, 47.16),
          const GeoPoint(-122.50, 47.15),
          const GeoPoint(-122.60, 47.16),
          const GeoPoint(-122.70, 47.18),
          const GeoPoint(-122.80, 47.20),
        ],
        interiorRings: [
          // Puget Sound water body (hole in the land)
          [
            const GeoPoint(-122.50, 47.30),
            const GeoPoint(-122.45, 47.35),
            const GeoPoint(-122.40, 47.45),
            const GeoPoint(-122.35, 47.55),
            const GeoPoint(-122.30, 47.60),
            const GeoPoint(-122.25, 47.55),
            const GeoPoint(-122.20, 47.45),
            const GeoPoint(-122.25, 47.35),
            const GeoPoint(-122.30, 47.30),
            const GeoPoint(-122.40, 47.28),
            const GeoPoint(-122.50, 47.30),
          ],
        ],
      ),
      // Bainbridge Island
      CoastlinePolygon(
        exteriorRing: [
          const GeoPoint(-122.58, 47.62),
          const GeoPoint(-122.52, 47.65),
          const GeoPoint(-122.48, 47.68),
          const GeoPoint(-122.50, 47.72),
          const GeoPoint(-122.55, 47.70),
          const GeoPoint(-122.60, 47.67),
          const GeoPoint(-122.58, 47.62),
        ],
      ),
      // Vashon Island
      CoastlinePolygon(
        exteriorRing: [
          const GeoPoint(-122.48, 47.38),
          const GeoPoint(-122.42, 47.42),
          const GeoPoint(-122.40, 47.48),
          const GeoPoint(-122.44, 47.52),
          const GeoPoint(-122.50, 47.50),
          const GeoPoint(-122.52, 47.44),
          const GeoPoint(-122.48, 47.38),
        ],
      ),
    ];

    return CoastlineData(
      polygons: polygons,
      bounds: const GeoBounds(
        minLon: -122.80,
        minLat: 47.15,
        maxLon: -121.80,
        maxLat: 47.85,
      ),
      name: 'Seattle Demo (Placeholder)',
      lastUpdated: DateTime.now(),
    );
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
      body: _buildBody(),
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
      );
    }

    if (_coastlineData == null) {
      return const Center(
        child: Text('No coastline data available'),
      );
    }

    return ChartView(
      coastlineData: _coastlineData!,
      initialZoom: 1.0,
      minZoom: 0.5,
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
            Text('Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Pinch to zoom'),
            Text('• Drag to pan'),
            Text('• Use buttons for zoom control'),
            SizedBox(height: 16),
            Text('Data: NOAA coastline data'),
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
