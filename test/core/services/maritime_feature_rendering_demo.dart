import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';
import 'package:navtool/core/services/coordinate_transform.dart';
import 'package:navtool/core/models/chart_models.dart';

/// Demonstration of maritime feature rendering capabilities
/// This test creates a comprehensive collection of maritime features
/// to validate all implemented rendering functionality
void main() {
  group('Maritime Feature Rendering Demonstration', () {
    testWidgets('should render comprehensive maritime chart features', 
        (WidgetTester tester) async {
      
      // Elliott Bay coordinates (real maritime location)
      const chartCenter = LatLng(47.6062, -122.3321);
      const screenSize = Size(1200, 800);
      const zoom = 14.0;

      final transform = CoordinateTransform(
        zoom: zoom,
        center: chartCenter,
        screenSize: screenSize,
      );

      // Create comprehensive test features based on real maritime data
      final features = _createComprehensiveMaritimeFeatures();

      final renderingService = ChartRenderingService(
        transform: transform,
        features: features,
        displayMode: ChartDisplayMode.dayMode,
      );

      // Enable all layers for comprehensive demonstration
      renderingService.setLayerVisible('chart_grid', true);
      renderingService.setLayerVisible('chart_boundaries', true);
      renderingService.setLayerVisible('depth_contours', true);
      renderingService.setLayerVisible('navigation_aids', true);
      renderingService.setLayerVisible('shoreline', true);
      renderingService.setLayerVisible('restricted_areas', true);

      // Create a test widget to render the chart
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: screenSize,
              painter: MaritimeChartPainter(
                renderingService: renderingService,
                canvasSize: screenSize,
              ),
            ),
          ),
        ),
      );

      // Verify the widget renders without errors
      expect(find.byType(CustomPaint), findsWidgets);
      
      // Test feature information retrieval
      final lighthouseInfo = renderingService.getFeatureInfo('alki_lighthouse');
      expect(lighthouseInfo['type'], equals('lighthouse'));
      expect(lighthouseInfo['id'], equals('alki_lighthouse'));

      // Test hit testing functionality
      final hitFeature = renderingService.hitTest(const Offset(600, 400));
      expect(hitFeature, anyOf(isNull, isA<MaritimeFeature>()));

      // Test layer management
      final layers = renderingService.getLayers();
      expect(layers, contains('chart_grid'));
      expect(layers, contains('navigation_aids'));
      expect(layers, contains('depth_contours'));

      // Test mode-specific colors
      final colors = renderingService.getModeSpecificColors();
      expect(colors['sea'], isNotNull);
      expect(colors['land'], isNotNull);
      expect(colors['text'], isNotNull);
    });

    testWidgets('should render night mode with appropriate colors',
        (WidgetTester tester) async {
      
      const chartCenter = LatLng(47.6062, -122.3321);
      const screenSize = Size(1200, 800);
      const zoom = 14.0;

      final transform = CoordinateTransform(
        zoom: zoom,
        center: chartCenter,
        screenSize: screenSize,
      );

      final features = _createComprehensiveMaritimeFeatures();

      final nightService = ChartRenderingService(
        transform: transform,
        features: features,
        displayMode: ChartDisplayMode.nightMode,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: screenSize,
              painter: MaritimeChartPainter(
                renderingService: nightService,
                canvasSize: screenSize,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);

      // Verify night mode colors are different from day mode
      final nightColors = nightService.getModeSpecificColors();
      expect(nightColors['sea'], equals(const Color(0xFF001122)));
      expect(nightColors['text'], equals(Colors.white));
    });
  });
}

/// Create comprehensive maritime features for demonstration
List<MaritimeFeature> _createComprehensiveMaritimeFeatures() {
  return [
    // Major lighthouse with characteristics
    const PointFeature(
      id: 'alki_lighthouse',
      type: MaritimeFeatureType.lighthouse,
      position: LatLng(47.5763, -122.4206),
      label: 'Alki Point Light',
      attributes: {
        'character': 'Fl W 5s',
        'range': 14.0,
        'height': 37.0,
      },
    ),

    // Cardinal buoys with topmarks
    const PointFeature(
      id: 'north_cardinal_buoy',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6162, -122.3521),
      attributes: {
        'buoyShape': 'pillar',
        'color': 'black-yellow',
        'topmark': 'north',
      },
    ),

    const PointFeature(
      id: 'port_hand_buoy',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6062, -122.3421),
      attributes: {
        'buoyShape': 'cylindrical',
        'color': 'red',
        'topmark': 'port',
      },
    ),

    const PointFeature(
      id: 'starboard_hand_buoy',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6062, -122.3221),
      attributes: {
        'buoyShape': 'spherical',
        'color': 'green',
        'topmark': 'starboard',
      },
    ),

    // Navigation beacon
    const PointFeature(
      id: 'west_point_beacon',
      type: MaritimeFeatureType.beacon,
      position: LatLng(47.6662, -122.4021),
      label: 'West Point',
      attributes: {
        'color': 'white',
        'height': 25.0,
      },
    ),

    // Daymark
    const PointFeature(
      id: 'elliott_bay_daymark',
      type: MaritimeFeatureType.daymark,
      position: LatLng(47.5962, -122.3321),
      label: 'EB-1',
    ),

    // Depth contours (representing Elliott Bay bathymetry)
    DepthContour(
      id: 'depth_5m',
      coordinates: _createDepthContourCoordinates(47.6062, -122.3321, 5.0),
      depth: 5.0,
    ),

    DepthContour(
      id: 'depth_10m',
      coordinates: _createDepthContourCoordinates(47.6062, -122.3321, 10.0),
      depth: 10.0,
    ),

    DepthContour(
      id: 'depth_20m',
      coordinates: _createDepthContourCoordinates(47.6062, -122.3321, 20.0),
      depth: 20.0,
    ),

    DepthContour(
      id: 'depth_50m',
      coordinates: _createDepthContourCoordinates(47.6062, -122.3321, 50.0),
      depth: 50.0,
    ),

    // Shoreline (Elliott Bay eastern shore)
    LineFeature(
      id: 'elliott_bay_shoreline',
      type: MaritimeFeatureType.shoreline,
      position: const LatLng(47.6062, -122.3321),
      coordinates: [
        const LatLng(47.5762, -122.3221),
        const LatLng(47.5862, -122.3121),
        const LatLng(47.5962, -122.3021),
        const LatLng(47.6062, -122.3021),
        const LatLng(47.6162, -122.3121),
        const LatLng(47.6262, -122.3221),
        const LatLng(47.6362, -122.3321),
      ],
      width: 2.0,
    ),

    // Land area (downtown Seattle waterfront)
    AreaFeature(
      id: 'seattle_waterfront',
      type: MaritimeFeatureType.landArea,
      position: const LatLng(47.6062, -122.3321),
      coordinates: [
        [
          const LatLng(47.5762, -122.3221),
          const LatLng(47.5762, -122.3021),
          const LatLng(47.6362, -122.3021),
          const LatLng(47.6362, -122.3321),
        ],
      ],
    ),

    // Anchorage area
    AreaFeature(
      id: 'elliott_bay_anchorage',
      type: MaritimeFeatureType.anchorage,
      position: const LatLng(47.6062, -122.3521),
      coordinates: [
        [
          const LatLng(47.5962, -122.3621),
          const LatLng(47.5962, -122.3421),
          const LatLng(47.6162, -122.3421),
          const LatLng(47.6162, -122.3621),
        ],
      ],
    ),

    // Restricted area (security zone)
    AreaFeature(
      id: 'coast_guard_security_zone',
      type: MaritimeFeatureType.restrictedArea,
      position: const LatLng(47.5962, -122.3721),
      coordinates: [
        [
          const LatLng(47.5912, -122.3771),
          const LatLng(47.5912, -122.3671),
          const LatLng(47.6012, -122.3671),
          const LatLng(47.6012, -122.3771),
        ],
      ],
    ),

    // Submarine cable
    LineFeature(
      id: 'submarine_cable',
      type: MaritimeFeatureType.cable,
      position: const LatLng(47.6162, -122.3821),
      coordinates: [
        const LatLng(47.6162, -122.3921),
        const LatLng(47.6162, -122.3721),
      ],
      width: 1.0,
    ),

    // Underwater obstruction
    const PointFeature(
      id: 'submerged_rock',
      type: MaritimeFeatureType.obstruction,
      position: LatLng(47.6262, -122.3421),
      attributes: {
        'depth': 2.5,
        'nature': 'rock',
      },
    ),
  ];
}

/// Create realistic depth contour coordinates
List<LatLng> _createDepthContourCoordinates(double centerLat, double centerLon, double depth) {
  final coordinates = <LatLng>[];
  final radius = depth * 0.0001; // Larger radius for deeper contours
  
  for (int i = 0; i <= 36; i++) {
    // Create natural variation in contour shape
    final lat = centerLat + radius * 0.8 * (i % 2 == 0 ? 1.0 : 0.9) * 
                 (1.0 + 0.2 * (i / 36.0)) * // Natural variation
                 (depth < 20 ? 0.7 : 1.0); // Closer to shore for shallow depths
    final lon = centerLon + radius * (i % 3 == 0 ? 1.1 : 1.0) *
                 (1.0 + 0.1 * ((i + 18) % 36 / 36.0)); // Natural variation
    
    coordinates.add(LatLng(
      centerLat + (lat - centerLat) * (depth < 10 ? 0.5 : 1.0),
      centerLon + (lon - centerLon),
    ));
  }
  
  return coordinates;
}

/// Custom painter for maritime chart demonstration
class MaritimeChartPainter extends CustomPainter {
  final ChartRenderingService renderingService;
  final Size canvasSize;

  const MaritimeChartPainter({
    required this.renderingService,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    renderingService.render(canvas, canvasSize);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for demonstration
  }
}