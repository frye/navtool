/// Chart display screen for marine navigation
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../core/models/chart.dart';
import 'dart:math' as math;
import '../../core/models/chart_models.dart';
import '../../core/services/chart_rendering_service.dart';
import '../../core/services/s57/s57_parser.dart';

import '../../core/adapters/s57_to_maritime_adapter.dart';
import '../../core/utils/zip_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chart_widget.dart';

/// Screen that displays maritime charts with navigation controls
class ChartScreen extends StatefulWidget {
  final Chart?
  chart; // Real NOAA chart metadata (optional for backward compatibility)
  final String? chartTitle; // Fallback title if chart not provided
  final LatLng? initialPosition; // Fallback initial position

  const ChartScreen({
    super.key,
    this.chart,
    this.chartTitle,
    this.initialPosition,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late List<MaritimeFeature> _features;
  // Preserve full unfiltered feature list for layer visibility toggling
  List<MaritimeFeature> _allFeatures = [];
  late LatLng _currentPosition;
  ChartDisplayMode _displayMode = ChartDisplayMode.dayMode;
  bool _isLoadingFeatures = false;
  final Map<String, bool> _layerVisibility = {
    'depth': true,
    'shoreline': true,
    'nav_aids': true,
    'land': true,
  };

  @override
  void initState() {
    super.initState();
    
    // Initialize position and default features immediately
    if (widget.chart != null) {
      // Center at chart bounds center
      final c = widget.chart!.bounds.center;
      _currentPosition = LatLng(c.latitude, c.longitude);
      _features = []; // Start with empty features
      _loadLayerVisibility(); // Load persisted layer settings first
      _loadChartFeatures(); // Load features asynchronously
    } else {
      _currentPosition =
          widget.initialPosition ?? const LatLng(37.7749, -122.4194);
      _features = _generateSampleFeatures(); // fallback for legacy route usage
    }
  }
  
  /// Load chart features asynchronously
  Future<void> _loadChartFeatures() async {
    if (widget.chart == null) return;
    
    setState(() {
      _isLoadingFeatures = true;
    });
    
    try {
      print('[ChartScreen] Starting feature loading for chart ${widget.chart!.id}');
      final features = await _generateFeaturesFromChart(widget.chart!);
      
      if (features.isNotEmpty) {
        print('[ChartScreen] Successfully loaded ${features.length} maritime features');
        setState(() {
          _features = features;
          _isLoadingFeatures = false;
        });
      } else {
        print('[ChartScreen] No features generated, using boundary fallback');
        setState(() {
          _features = _generateChartBoundaryFeatures(widget.chart!);
          _isLoadingFeatures = false;
        });
        
        // Show user feedback about fallback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loaded chart boundary for ${widget.chart!.id}'),
                  const SizedBox(height: 4),
                  const Text(
                    'S-57 feature loading incomplete. Showing basic chart outline only.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              duration: const Duration(seconds: 6),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () => _showChartLoadingDiagnostics(),
              ),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('[ChartScreen] ERROR loading chart features: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
      
      setState(() {
        _features = _generateChartBoundaryFeatures(widget.chart!);
        _isLoadingFeatures = false;
      });
      
      // Show user error feedback with retry option
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Failed to load S-57 chart data for ${widget.chart!.id}'),
                const SizedBox(height: 4),
                const Text(
                  'Showing chart boundary only. Check test data availability.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Diagnose',
              textColor: Colors.white,
              onPressed: () => _showChartLoadingDiagnostics(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chart?.title ?? widget.chartTitle ?? 'Marine Chart'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _showChartInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Chart Information',
          ),
          IconButton(
            onPressed: _showChartSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Chart Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Chart status bar
          _buildStatusBar(),
          // Main chart area
          Expanded(
            child: Stack(
              children: [
                ChartWidget(
                  initialCenter: _currentPosition,
                  initialZoom: 12.0,
                  features: _features,
                  displayMode: _displayMode,
                  onPositionChanged: (newPosition) {
                    setState(() {
                      _currentPosition = newPosition;
                    });
                  },
                ),
                // Loading indicator overlay with enhanced progress information
                if (_isLoadingFeatures)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Parsing S-57 chart data...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Extracting maritime features from chart',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  /// Build chart status bar showing key information
  Widget _buildStatusBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(50),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Show simplified layout on very small screens
          if (constraints.maxWidth < 400) {
            return Row(
              children: [
                Icon(
                  Icons.map,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_features.length} features',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _displayMode == ChartDisplayMode.dayMode
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            );
          }

          // Full layout for larger screens
          return Row(
            children: [
              Icon(
                Icons.map,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chart: ${widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _displayMode == ChartDisplayMode.dayMode
                    ? Icons.light_mode
                    : Icons.dark_mode,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _displayMode == ChartDisplayMode.dayMode ? 'Day' : 'Night',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.layers,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '${_features.length} features',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build floating action buttons for quick actions
  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: _addWaypoint,
          heroTag: 'waypoint',
          tooltip: 'Add Waypoint',
          child: const Icon(Icons.add_location),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          onPressed: _measureDistance,
          heroTag: 'measure',
          tooltip: 'Measure Distance',
          child: const Icon(Icons.straighten),
        ),
      ],
    );
  }

  /// Show chart information dialog
  void _showChartInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Information'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Chart Title',
                  widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart',
                ),
                if (widget.chart != null) ...[
                  _buildInfoRow('Chart ID', widget.chart!.id),
                  _buildInfoRow('Scale', '1:${widget.chart!.scale}'),
                  _buildInfoRow('Source', widget.chart!.source.displayName),
                  _buildInfoRow(
                    'Bounds',
                    'N:${widget.chart!.bounds.north.toStringAsFixed(4)} '
                        'S:${widget.chart!.bounds.south.toStringAsFixed(4)} '
                        'E:${widget.chart!.bounds.east.toStringAsFixed(4)} '
                        'W:${widget.chart!.bounds.west.toStringAsFixed(4)}',
                  ),
                ],
                _buildInfoRow(
                  'Current Position',
                  '${_currentPosition.latitude.toStringAsFixed(6)}, ${_currentPosition.longitude.toStringAsFixed(6)}',
                ),
                _buildInfoRow('Features Loaded', '${_features.length}'),
                _buildInfoRow('Display Mode', _displayMode.name),
                const SizedBox(height: 16),
                // S-57 Parsing Diagnostics
                const Text(
                  'S-57 Parsing Diagnostics:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildInfoRow('Feature Count', '${_features.length}'),
                _buildInfoRow(
                  'Data Source',
                  _features.length > 10 
                    ? 'Real S-57 chart data' 
                    : _features.length > 0 
                      ? 'Synthetic test features (S-57 parser may need debugging)'
                      : 'Chart boundary fallback only',
                ),
                if (_features.isNotEmpty) ...[
                  _buildInfoRow(
                    'Feature Types',
                    _features.map((f) => f.type.toString().split('.').last).toSet().join(', '),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  widget.chart == null
                      ? 'Demonstration chart with sample features (no NOAA chart provided).'
                      : _features.length > 10
                        ? 'Successfully loaded real S-57 chart features.'
                        : 'S-57 parsing resulted in ${_features.length} features. Check console for detailed parsing logs.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build information row for dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Show chart settings dialog
  void _showChartSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Display Mode'),
              trailing: DropdownButton<ChartDisplayMode>(
                value: _displayMode,
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() {
                      _displayMode = mode;
                    });
                    Navigator.of(context).pop();
                  }
                },
                items: ChartDisplayMode.values.map((mode) {
                  return DropdownMenuItem(value: mode, child: Text(mode.name));
                }).toList(),
              ),
            ),
            ListTile(
              title: const Text('Feature Visibility'),
              trailing: const Icon(Icons.visibility),
              onTap: () {
                Navigator.of(context).pop();
                _showFeatureVisibilitySettings();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show chart loading diagnostics dialog
  void _showChartLoadingDiagnostics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Loading Diagnostics'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.chart != null) ...[
                  _buildDiagnosticSection('Chart Information', [
                    'Chart ID: ${widget.chart!.id}',
                    'Title: ${widget.chart!.title}',
                    'Scale: 1:${widget.chart!.scale}',
                    'Type: ${widget.chart!.type.name}',
                  ]),
                  _buildDiagnosticSection('Expected File Locations', [
                    'Asset: ${_getElliottBayAssetPath(widget.chart!.id) ?? 'Not configured'}',
                    'Test fixture: ${_getElliottBayTestPath(widget.chart!.id) ?? 'Not available'}',
                  ]),
                  _buildDiagnosticSection('Troubleshooting Steps', [
                    '1. Verify test data files exist in test/fixtures/charts/noaa_enc/',
                    '2. Check that ZIP files contain .000 S-57 data files',
                    '3. Ensure archive package is properly installed',
                    '4. Run Elliott Bay rendering tests to validate pipeline',
                    '5. Check console logs for detailed error messages',
                  ]),
                ],
                const SizedBox(height: 16),
                const Text(
                  'For Elliott Bay charts to display properly, the complete S-57 parsing '
                  'pipeline must work: ZIP extraction → S-57 parsing → Maritime feature conversion → Rendering.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (widget.chart != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _retryChartLoading();
              },
              child: const Text('Retry Loading'),
            ),
        ],
      ),
    );
  }

  /// Build diagnostic section with title and items
  Widget _buildDiagnosticSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text('• $item', style: const TextStyle(fontSize: 12)),
        )),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Show feature visibility settings
  void _showFeatureVisibilitySettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feature Visibility'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Currently loaded features:'),
            const SizedBox(height: 12),
            ..._buildFeatureTypeCounts().entries.map((entry) {
              final layerKey = _mapFeatureTypeToLayer(entry.key);
              final enabled = _layerVisibility[layerKey] ?? true;
              return SwitchListTile(
                secondary: Icon(_getFeatureTypeIcon(entry.key)),
                title: Text(entry.key.name),
                subtitle: Text('${entry.value} items'),
                value: enabled,
                onChanged: (val) async {
                  setState(() => _layerVisibility[layerKey] = val);
                  await _persistLayerVisibility();
                  _applyLayerFilter();
                },
                dense: true,
              );
            }),
            const SizedBox(height: 16),
            const Text('Layer visibility (persisted per chart)', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _mapFeatureTypeToLayer(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.depthArea || MaritimeFeatureType.depthContour => 'depth',
      MaritimeFeatureType.shoreline => 'shoreline',
      MaritimeFeatureType.buoy || MaritimeFeatureType.beacon || MaritimeFeatureType.lighthouse || MaritimeFeatureType.daymark => 'nav_aids',
      MaritimeFeatureType.landArea => 'land',
      _ => 'other',
    };
  }

  Future<void> _persistLayerVisibility() async {
    if (widget.chart == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'layer_visibility_${widget.chart!.id}';
    await prefs.setString(key, _layerVisibility.entries.map((e) => '${e.key}:${e.value}').join(','));
  }

  Future<void> _loadLayerVisibility() async {
    if (widget.chart == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'layer_visibility_${widget.chart!.id}';
    final stored = prefs.getString(key);
    if (stored != null) {
      for (final part in stored.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) _layerVisibility[kv[0]] = kv[1] == 'true';
      }
      if (mounted) setState(() {});
    }
  }

  /// Build feature type counts for display
  Map<MaritimeFeatureType, int> _buildFeatureTypeCounts() {
    final counts = <MaritimeFeatureType, int>{};
    for (final feature in _features) {
      counts[feature.type] = (counts[feature.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Get icon for feature type
  IconData _getFeatureTypeIcon(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Icons.lightbulb,
      MaritimeFeatureType.buoy => Icons.circle,
      MaritimeFeatureType.beacon => Icons.radio_button_checked,
      MaritimeFeatureType.shoreline => Icons.water,
      MaritimeFeatureType.landArea => Icons.landscape,
      MaritimeFeatureType.depthContour => Icons.timeline,
      MaritimeFeatureType.anchorage => Icons.anchor,
      MaritimeFeatureType.restrictedArea => Icons.block,
      _ => Icons.place,
    };
  }

  /// Retry chart loading
  void _retryChartLoading() {
    if (widget.chart != null) {
      _loadChartFeatures();
    }
  }

  /// Add waypoint at current position
  void _addWaypoint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Waypoint added at ${_currentPosition.latitude.toStringAsFixed(4)}, ${_currentPosition.longitude.toStringAsFixed(4)}',
        ),
      ),
    );
  }

  /// Measure distance tool
  void _measureDistance() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Distance measurement tool will be implemented in a future version',
        ),
      ),
    );
  }

  /// Generate minimal real features from a NOAA chart's bounding box
  /// Generate maritime features from S-57 chart data
  Future<List<MaritimeFeature>> _generateFeaturesFromChart(Chart chart) async {
    print('[ChartScreen] Starting S-57 processing for chart ${chart.id}');
    print('[ChartScreen] Chart metadata:');
    print('[ChartScreen]   Title: ${chart.title}');
    print('[ChartScreen]   Scale: 1:${chart.scale}');
    print('[ChartScreen]   Bounds: N:${chart.bounds.north.toStringAsFixed(4)} S:${chart.bounds.south.toStringAsFixed(4)} E:${chart.bounds.east.toStringAsFixed(4)} W:${chart.bounds.west.toStringAsFixed(4)}');
    print('[ChartScreen]   Source: ${chart.source.displayName}');
    
    try {
      // Phase 1: Load S-57 chart data if available
      final chartData = await _loadChartData(chart);
      
      if (chartData != null && chartData.isNotEmpty) {
        print('[ChartScreen] Starting S-57 parsing for ${chartData.length} bytes');
        
        // Parse S-57 data and convert to maritime features
        try {
          print('[ChartScreen] Starting S-57 parsing for ${chartData.length} bytes');
          final s57Data = S57Parser.parse(chartData);
          print('[ChartScreen] S-57 parsing successful!');
          print('[ChartScreen]   Features found: ${s57Data.features.length}');
          print('[ChartScreen]   Chart bounds: ${s57Data.bounds.toMap()}');
          print('[ChartScreen]   Chart metadata: ${s57Data.metadata.toMap()}');
          
          // S-57 feature type breakdown
          final featureTypeCount = <String, int>{};
          for (final feature in s57Data.features) {
            featureTypeCount[feature.featureType.acronym] = 
                (featureTypeCount[feature.featureType.acronym] ?? 0) + 1;
          }
          print('[ChartScreen]   S-57 feature breakdown: $featureTypeCount');
          
          if (s57Data.features.isNotEmpty) {
            // Convert to maritime features with detailed tracking
            print('[ChartScreen] Converting ${s57Data.features.length} S-57 features to maritime features...');
            final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
            print('[ChartScreen] Feature conversion completed!');
            print('[ChartScreen]   Maritime features generated: ${maritimeFeatures.length}');
            
            // Maritime feature breakdown
            final maritimeTypeCount = <String, int>{};
            for (final feature in maritimeFeatures) {
              maritimeTypeCount[feature.type.name] = 
                  (maritimeTypeCount[feature.type.name] ?? 0) + 1;
            }
            print('[ChartScreen]   Maritime feature breakdown: $maritimeTypeCount');
            
            // Log conversion efficiency
            final conversionRate = (maritimeFeatures.length / s57Data.features.length * 100).toStringAsFixed(1);
            print('[ChartScreen]   Conversion rate: $conversionRate% (${maritimeFeatures.length}/${s57Data.features.length})');
            
            if (maritimeFeatures.isNotEmpty) {
              print('[ChartScreen] SUCCESS: Loaded ${maritimeFeatures.length} real maritime features from Elliott Bay S-57 chart ${chart.id}');
              _allFeatures = maritimeFeatures;
              _applyLayerFilter();
              return _features;
            } else {
              print('[ChartScreen] ERROR: S57ToMaritimeAdapter produced no maritime features despite ${s57Data.features.length} S-57 features');
            }
          } else {
            print('[ChartScreen] ERROR: S-57 parser found no features in ${chartData.length} bytes of chart data');
          }
        } catch (parseError, parseStack) {
          print('[ChartScreen] CRITICAL ERROR: S-57 parsing failed: $parseError');
          print('[ChartScreen] Parse stack trace: $parseStack');
        }
      } else {
        print('[ChartScreen] No chart data available for S-57 processing');
      }
    } catch (e, stackTrace) {
      // Log error but continue with fallback
      print('[ChartScreen] Error in S-57 feature generation for ${chart.id}: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
    }
    
    // Fallback: Generate basic chart boundary features as before
    print('[ChartScreen] Using chart boundary fallback for ${chart.id}');
    print('[ChartScreen] Fallback will generate ${_generateChartBoundaryFeatures(chart).length} boundary features');
    return _generateChartBoundaryFeatures(chart);
  }
  
  /// Generate basic chart boundary features (fallback)
  List<MaritimeFeature> _generateChartBoundaryFeatures(Chart chart) {
    final b = chart.bounds;
    final c = b.center;
    final center = LatLng(c.latitude, c.longitude);
    final polygon = [
      LatLng(b.north, b.west),
      LatLng(b.north, b.east),
      LatLng(b.south, b.east),
      LatLng(b.south, b.west),
    ];

    return [
      AreaFeature(
        id: 'chart_bounds_${chart.id}',
        type: MaritimeFeatureType.restrictedArea,
        position: center,
        coordinates: [polygon],
        fillColor: const Color(0x22007AFF),
        strokeColor: const Color(0xFF007AFF),
        attributes: {
          'chartId': chart.id,
          'scale': chart.scale,
          'source': chart.source.displayName,
        },
      ),
      PointFeature(
        id: 'chart_center_${chart.id}',
        type: MaritimeFeatureType.beacon,
        position: center,
        label: chart.id,
        attributes: {'role': 'center'},
      ),
    ];
  }
  
  /// Load S-57 chart data for the given chart
  Future<List<int>?> _loadChartData(Chart chart) async {
    print('[ChartScreen] Loading chart data for ${chart.id}');
    
    try {
      // Phase 4 Policy: Prefer real ENC ZIP fixture first
      final testPath = _getElliottBayTestPath(chart.id);
      if (testPath != null) {
        final f = File(testPath);
        if (await f.exists()) {
          try {
            print('[ChartScreen] Attempting loadFromZip for real ENC: $testPath');
            final parsed = await S57Parser.loadFromZip(testPath, chartId: chart.id); // Parsed once
            print('[ChartScreen] loadFromZip succeeded; feature count: ${parsed.features.length}');
            // Cache parsed result directly to avoid re-parse later
            _allFeatures = S57ToMaritimeAdapter.convertFeatures(parsed.features);
            _applyLayerFilter();
            // Return empty list to signal upstream that we already populated features (special case)
            return <int>[];
          } catch (e) {
            print('[ChartScreen] loadFromZip failed ($e), trying asset fallback');
          }
        } else {
          print('[ChartScreen] Real ENC fixture missing: $testPath');
        }
      }

      // Asset fallback (.000 packaged in assets)
      final assetPath = _getElliottBayAssetPath(chart.id);
      if (assetPath != null) {
        try {
          final data = await rootBundle.load(assetPath);
          final bytes = data.buffer.asUint8List();
          print('[ChartScreen] Loaded asset ENC .000 (${bytes.length} bytes)');
          return bytes;
        } catch (e) {
          print('[ChartScreen] Asset load failed: $e');
        }
      }

      print('[ChartScreen] No ENC source found (fixture or asset) for ${chart.id}');
      
    } catch (e, stackTrace) {
      print('[ChartScreen] ERROR loading chart data for ${chart.id}: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
    }
    
    return null;
  }

  /// Apply layer visibility toggles to full feature set
  void _applyLayerFilter() {
    if (_allFeatures.isEmpty) {
      setState(() => _features = []);
      return;
    }
    final filtered = <MaritimeFeature>[];
    for (final f in _allFeatures) {
      final layer = _mapFeatureTypeToLayer(f.type);
      final visible = _layerVisibility[layer] ?? true;
      if (visible || layer == 'other') {
        filtered.add(f);
      }
    }
    setState(() => _features = filtered);
  }
  
  /// Get asset path for Elliott Bay charts (primary method)
  String? _getElliottBayAssetPath(String chartId) {
    // Map Elliott Bay chart IDs to asset bundle paths
    return switch (chartId) {
      'US5WA50M' => 'assets/s57/charts/US5WA50M.000',
      'US3WA01M' => 'assets/s57/charts/US3WA01M.000',
      // Add other Elliott Bay chart variations
      'US5WA17M' => 'assets/s57/charts/US5WA50M.000', // Alias for harbor chart
      'US5WA18M' => 'assets/s57/charts/US3WA01M.000', // Alias for approach chart
      _ => null,
    };
  }
  
  /// Get test fixture path for Elliott Bay charts (fallback for development)
  String? _getElliottBayTestPath(String chartId) {
    // Map Elliott Bay chart IDs to actual test fixture ZIP files
    return switch (chartId) {
      'US5WA50M' => 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip',
      'US3WA01M' => 'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip',
      // Add other Elliott Bay chart variations
      'US5WA17M' => 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip', // Alias for harbor chart
      'US5WA18M' => 'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip', // Alias for approach chart
      _ => null,
    };
  }

  /// Generate sample maritime features for demonstration (legacy fallback)
  List<MaritimeFeature> _generateSampleFeatures() {
    final List<MaritimeFeature> features = [];

    // Add sample lighthouse
    features.add(
      PointFeature(
        id: 'lighthouse_1',
        type: MaritimeFeatureType.lighthouse,
        position: const LatLng(37.8199, -122.4783),
        label: 'Alcatraz Light',
        attributes: {'height': 84, 'range': 22},
      ),
    );

    // Add sample buoys
    features.add(
      PointFeature(
        id: 'buoy_1',
        type: MaritimeFeatureType.buoy,
        position: const LatLng(37.7849, -122.4594),
        label: 'SF-1',
        attributes: {'color': 'red', 'type': 'lateral'},
      ),
    );

    features.add(
      PointFeature(
        id: 'buoy_2',
        type: MaritimeFeatureType.buoy,
        position: const LatLng(37.7949, -122.4694),
        label: 'SF-2',
        attributes: {'color': 'green', 'type': 'lateral'},
      ),
    );

    // Add sample beacon
    features.add(
      PointFeature(
        id: 'beacon_1',
        type: MaritimeFeatureType.beacon,
        position: const LatLng(37.8049, -122.4394),
        label: 'Bay Bridge Beacon',
        attributes: {'type': 'radar_reflector'},
      ),
    );

    // Add sample shoreline
    features.add(
      LineFeature(
        id: 'shoreline_1',
        type: MaritimeFeatureType.shoreline,
        position: const LatLng(37.7749, -122.4194),
        coordinates: [
          const LatLng(37.7649, -122.4094),
          const LatLng(37.7749, -122.4194),
          const LatLng(37.7849, -122.4294),
          const LatLng(37.7949, -122.4394),
        ],
        width: 2.0,
      ),
    );

    // Add sample land area
    features.add(
      AreaFeature(
        id: 'land_1',
        type: MaritimeFeatureType.landArea,
        position: const LatLng(37.7749, -122.4094),
        coordinates: [
          [
            const LatLng(37.7649, -122.4094),
            const LatLng(37.7649, -122.3994),
            const LatLng(37.7849, -122.3994),
            const LatLng(37.7849, -122.4094),
          ],
        ],
      ),
    );

    // Add sample depth contours
    for (int depth = 10; depth <= 50; depth += 10) {
      features.add(
        DepthContour(
          id: 'depth_${depth}m',
          coordinates: _generateContourLine(depth.toDouble()),
          depth: depth.toDouble(),
        ),
      );
    }

    // Add sample anchorage area
    features.add(
      AreaFeature(
        id: 'anchorage_1',
        type: MaritimeFeatureType.anchorage,
        position: const LatLng(37.7949, -122.4594),
        coordinates: [
          [
            const LatLng(37.7899, -122.4644),
            const LatLng(37.7899, -122.4544),
            const LatLng(37.7999, -122.4544),
            const LatLng(37.7999, -122.4644),
          ],
        ],
        fillColor: Colors.blue.withAlpha(50),
        strokeColor: Colors.blue,
      ),
    );

    return features;
  }

  /// Generate a sample depth contour line
  List<LatLng> _generateContourLine(double depth) {
    final List<LatLng> points = [];
    final int numPoints = 20;
    final double radius =
        0.01 * depth / 10; // Larger radius for deeper contours

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i / numPoints) * 2 * math.pi;
      final double lat =
          _currentPosition.latitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.cos(angle);
      final double lng =
          _currentPosition.longitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.sin(angle);
      points.add(LatLng(lat, lng));
    }

    return points;
  }
}
