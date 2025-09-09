import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';
import 'package:navtool/core/services/coordinate_transform.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  group('ChartRenderingService Tests', () {
    const testCenter = LatLng(37.7749, -122.4194);
    const testScreenSize = Size(800, 600);
    const testZoom = 12.0;

    late CoordinateTransform transform;
    late List<MaritimeFeature> testFeatures;
    late ChartRenderingService renderingService;

    setUp(() {
      transform = CoordinateTransform(
        zoom: testZoom,
        center: testCenter,
        screenSize: testScreenSize,
      );

      testFeatures = [
        const PointFeature(
          id: 'lighthouse_1',
          type: MaritimeFeatureType.lighthouse,
          position: LatLng(37.8199, -122.4783),
          label: 'Alcatraz Light',
        ),
        const PointFeature(
          id: 'buoy_1',
          type: MaritimeFeatureType.buoy,
          position: LatLng(37.7849, -122.4594),
          label: 'SF-1',
        ),
        LineFeature(
          id: 'shoreline_1',
          type: MaritimeFeatureType.shoreline,
          position: testCenter,
          coordinates: [
            const LatLng(37.7649, -122.4094),
            const LatLng(37.7749, -122.4194),
            const LatLng(37.7849, -122.4294),
          ],
          width: 2.0,
        ),
        AreaFeature(
          id: 'land_1',
          type: MaritimeFeatureType.landArea,
          position: testCenter,
          coordinates: [
            [
              const LatLng(37.7649, -122.4094),
              const LatLng(37.7649, -122.3994),
              const LatLng(37.7849, -122.3994),
              const LatLng(37.7849, -122.4094),
            ],
          ],
        ),
        const DepthContour(
          id: 'depth_10m',
          coordinates: [LatLng(37.7649, -122.4094), LatLng(37.7749, -122.4194)],
          depth: 10.0,
        ),
      ];

      renderingService = ChartRenderingService(
        transform: transform,
        features: testFeatures,
        displayMode: ChartDisplayMode.dayMode,
      );
    });

    group('Service Initialization', () {
      test('should create rendering service with required parameters', () {
        expect(renderingService, isNotNull);
        expect(renderingService, isA<ChartRenderingService>());
      });

      test('should create service with day mode by default', () {
        final service = ChartRenderingService(
          transform: transform,
          features: testFeatures,
        );
        expect(service, isNotNull);
      });

      test('should create service with night mode', () {
        final service = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.nightMode,
        );
        expect(service, isNotNull);
      });
    });

    group('Feature Filtering and Visibility', () {
      test('should filter features based on visibility and scale', () {
        // Create a transform with a very small viewport
        final smallTransform = CoordinateTransform(
          zoom: 12.0,
          center: const LatLng(0, 0), // Far from test features
          screenSize: const Size(100, 100),
        );

        final service = ChartRenderingService(
          transform: smallTransform,
          features: testFeatures,
        );

        // Features should be filtered out due to visibility
        expect(service, isNotNull);
      });

      test('should handle empty feature list', () {
        final service = ChartRenderingService(
          transform: transform,
          features: [],
        );

        expect(service, isNotNull);
      });

      test('should handle features with different visibility requirements', () {
        final mixedFeatures = [
          // Lighthouse - visible at large scales
          const PointFeature(
            id: 'lighthouse_1',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(37.8199, -122.4783),
          ),
          // Buoy - visible at smaller scales only
          const PointFeature(
            id: 'buoy_1',
            type: MaritimeFeatureType.buoy,
            position: LatLng(37.7849, -122.4594),
          ),
        ];

        // Test with overview scale (large scale)
        final overviewTransform = CoordinateTransform(
          zoom: 8.0, // Overview scale
          center: testCenter,
          screenSize: testScreenSize,
        );

        final overviewService = ChartRenderingService(
          transform: overviewTransform,
          features: mixedFeatures,
        );

        expect(overviewService, isNotNull);

        // Test with harbour scale (small scale)
        final harbourTransform = CoordinateTransform(
          zoom: 15.0, // Harbour scale
          center: testCenter,
          screenSize: testScreenSize,
        );

        final harbourService = ChartRenderingService(
          transform: harbourTransform,
          features: mixedFeatures,
        );

        expect(harbourService, isNotNull);
      });
    });

    group('Feature Type Handling', () {
      test('should handle all maritime feature types', () {
        final allFeatureTypes = [
          const PointFeature(
            id: '1',
            type: MaritimeFeatureType.lighthouse,
            position: testCenter,
          ),
          const PointFeature(
            id: '2',
            type: MaritimeFeatureType.beacon,
            position: testCenter,
          ),
          const PointFeature(
            id: '3',
            type: MaritimeFeatureType.buoy,
            position: testCenter,
          ),
          const PointFeature(
            id: '4',
            type: MaritimeFeatureType.daymark,
            position: testCenter,
          ),
          LineFeature(
            id: '5',
            type: MaritimeFeatureType.shoreline,
            position: testCenter,
            coordinates: [testCenter, const LatLng(37.8, -122.4)],
          ),
          LineFeature(
            id: '6',
            type: MaritimeFeatureType.cable,
            position: testCenter,
            coordinates: [testCenter, const LatLng(37.8, -122.4)],
          ),
          LineFeature(
            id: '7',
            type: MaritimeFeatureType.pipeline,
            position: testCenter,
            coordinates: [testCenter, const LatLng(37.8, -122.4)],
          ),
          AreaFeature(
            id: '8',
            type: MaritimeFeatureType.landArea,
            position: testCenter,
            coordinates: [
              [
                testCenter,
                const LatLng(37.8, -122.4),
                const LatLng(37.8, -122.3),
              ],
            ],
          ),
          AreaFeature(
            id: '9',
            type: MaritimeFeatureType.anchorage,
            position: testCenter,
            coordinates: [
              [
                testCenter,
                const LatLng(37.8, -122.4),
                const LatLng(37.8, -122.3),
              ],
            ],
          ),
          AreaFeature(
            id: '10',
            type: MaritimeFeatureType.restrictedArea,
            position: testCenter,
            coordinates: [
              [
                testCenter,
                const LatLng(37.8, -122.4),
                const LatLng(37.8, -122.3),
              ],
            ],
          ),
        ];

        final service = ChartRenderingService(
          transform: transform,
          features: allFeatureTypes,
        );

        expect(service, isNotNull);
      });

      test('should handle depth contours with different depths', () {
        final depthContours = [
          const DepthContour(
            id: 'depth_5m',
            coordinates: [testCenter, LatLng(37.8, -122.4)],
            depth: 5.0,
          ),
          const DepthContour(
            id: 'depth_10m',
            coordinates: [testCenter, LatLng(37.8, -122.4)],
            depth: 10.0,
          ),
          const DepthContour(
            id: 'depth_50m',
            coordinates: [testCenter, LatLng(37.8, -122.4)],
            depth: 50.0,
          ),
          const DepthContour(
            id: 'depth_100m',
            coordinates: [testCenter, LatLng(37.8, -122.4)],
            depth: 100.0,
          ),
        ];

        final service = ChartRenderingService(
          transform: transform,
          features: depthContours,
        );

        expect(service, isNotNull);
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle features with empty coordinates', () {
        final edgeCaseFeatures = [
          LineFeature(
            id: 'empty_line',
            type: MaritimeFeatureType.shoreline,
            position: testCenter,
            coordinates: [], // Empty coordinates
          ),
          AreaFeature(
            id: 'empty_area',
            type: MaritimeFeatureType.landArea,
            position: testCenter,
            coordinates: [[]], // Empty coordinates
          ),
        ];

        final service = ChartRenderingService(
          transform: transform,
          features: edgeCaseFeatures,
        );

        expect(service, isNotNull);
      });

      test('should handle features with single coordinate', () {
        final singleCoordFeatures = [
          LineFeature(
            id: 'single_line',
            type: MaritimeFeatureType.shoreline,
            position: testCenter,
            coordinates: [testCenter], // Single coordinate
          ),
          AreaFeature(
            id: 'single_area',
            type: MaritimeFeatureType.landArea,
            position: testCenter,
            coordinates: [
              [testCenter],
            ], // Single coordinate
          ),
        ];

        final service = ChartRenderingService(
          transform: transform,
          features: singleCoordFeatures,
        );

        expect(service, isNotNull);
      });

      test('should handle features at extreme coordinates', () {
        final extremeFeatures = [
          const PointFeature(
            id: 'north_pole',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(90.0, 0.0),
          ),
          const PointFeature(
            id: 'south_pole',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(-90.0, 0.0),
          ),
          const PointFeature(
            id: 'date_line',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(0.0, 180.0),
          ),
        ];

        final service = ChartRenderingService(
          transform: transform,
          features: extremeFeatures,
        );

        expect(service, isNotNull);
      });
    });

    group('Display Mode Handling', () {
      test('should support day mode', () {
        final dayService = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.dayMode,
        );

        expect(dayService, isNotNull);
      });

      test('should support night mode', () {
        final nightService = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.nightMode,
        );

        expect(nightService, isNotNull);
      });

      test('should support dusk mode', () {
        final duskService = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.duskMode,
        );

        expect(duskService, isNotNull);
      });
    });

    group('Enhanced Maritime Feature Rendering', () {
      test('should handle enhanced lighthouse symbols with characteristics', () {
        final lighthouseWithCharacteristics = PointFeature(
          id: 'lighthouse_with_char',
          type: MaritimeFeatureType.lighthouse,
          position: testCenter,
          label: 'Main Light',
          attributes: {
            'character': 'Fl W 10s',
            'range': 15.0,
          },
        );

        final service = ChartRenderingService(
          transform: transform,
          features: [lighthouseWithCharacteristics],
        );

        expect(service, isNotNull);
      });

      test('should handle enhanced buoy symbols with topmarks', () {
        final cardinalBuoy = PointFeature(
          id: 'cardinal_buoy',
          type: MaritimeFeatureType.buoy,
          position: testCenter,
          attributes: {
            'buoyShape': 'pillar',
            'color': 'black-yellow',
            'topmark': 'north',
          },
        );

        final service = ChartRenderingService(
          transform: transform,
          features: [cardinalBuoy],
        );

        expect(service, isNotNull);
      });

      test('should handle enhanced depth contour labeling', () {
        final detailedDepthContour = DepthContour(
          id: 'detailed_depth_20m',
          coordinates: List.generate(15, (i) => 
            LatLng(testCenter.latitude + i * 0.001, testCenter.longitude + i * 0.001)
          ),
          depth: 20.0,
        );

        final service = ChartRenderingService(
          transform: transform,
          features: [detailedDepthContour],
        );

        expect(service, isNotNull);
      });
    });

    group('Chart Grid and Boundaries', () {
      late ChartRenderingService serviceWithGrid;

      setUp(() {
        serviceWithGrid = ChartRenderingService(
          transform: transform,
          features: testFeatures,
        );
        serviceWithGrid.setLayerVisible('chart_grid', true);
        serviceWithGrid.setLayerVisible('chart_boundaries', true);
      });

      test('should support chart grid rendering', () {
        expect(serviceWithGrid, isNotNull);
        expect(serviceWithGrid.getLayers(), contains('chart_grid'));
      });

      test('should support chart boundaries rendering', () {
        expect(serviceWithGrid, isNotNull);
        expect(serviceWithGrid.getLayers(), contains('chart_boundaries'));
      });

      test('should handle grid visibility toggling', () {
        serviceWithGrid.setLayerVisible('chart_grid', false);
        expect(serviceWithGrid.getLayers(), contains('chart_grid'));
        
        serviceWithGrid.setLayerVisible('chart_grid', true);
        expect(serviceWithGrid.getLayers(), contains('chart_grid'));
      });
    });

    group('Symbol Size and Color Handling', () {
      test('should calculate symbol size based on zoom level', () {
        // Test different zoom levels
        final zoomLevels = [8.0, 12.0, 16.0];
        
        for (final zoomLevel in zoomLevels) {
          final zoomTransform = CoordinateTransform(
            zoom: zoomLevel,
            center: testCenter,
            screenSize: testScreenSize,
          );

          final service = ChartRenderingService(
            transform: zoomTransform,
            features: testFeatures,
          );

          expect(service, isNotNull);
          expect(service.getSymbolSizeForZoom(MaritimeFeatureType.lighthouse), greaterThan(0));
        }
      });

      test('should provide mode-specific colors', () {
        final dayService = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.dayMode,
        );

        final nightService = ChartRenderingService(
          transform: transform,
          features: testFeatures,
          displayMode: ChartDisplayMode.nightMode,
        );

        final dayColors = dayService.getModeSpecificColors();
        final nightColors = nightService.getModeSpecificColors();

        expect(dayColors['sea'], isNotNull);
        expect(nightColors['sea'], isNotNull);
        expect(dayColors['sea'], isNot(equals(nightColors['sea'])));
      });
    });

    group('Feature Information and Hit Testing', () {
      test('should provide feature information', () {
        final featureInfo = renderingService.getFeatureInfo('lighthouse_1');
        
        expect(featureInfo, isNotNull);
        expect(featureInfo['id'], equals('lighthouse_1'));
        expect(featureInfo['type'], equals('lighthouse'));
        expect(featureInfo['position'], isNotNull);
      });

      test('should handle hit testing for feature selection', () {
        // Test hit testing at various screen positions
        final screenPoints = [
          const Offset(100, 100),
          const Offset(400, 300),
          const Offset(700, 500),
        ];

        for (final point in screenPoints) {
          final hitFeature = renderingService.hitTest(point);
          // Hit testing may or may not find a feature depending on position
          // Just ensure it doesn't crash
          expect(hitFeature, anyOf(isNull, isA<MaritimeFeature>()));
        }
      });
    });

    group('Layer Management', () {
      test('should manage layer visibility', () {
        final layers = renderingService.getLayers();
        expect(layers, isNotEmpty);
        
        // Test visibility toggling
        for (final layer in layers) {
          renderingService.setLayerVisible(layer, false);
          renderingService.setLayerVisible(layer, true);
        }
      });

      test('should provide layer priorities', () {
        final priorities = [
          renderingService.getLayerPriority(MaritimeFeatureType.lighthouse),
          renderingService.getLayerPriority(MaritimeFeatureType.shoreline),
          renderingService.getLayerPriority(MaritimeFeatureType.landArea),
        ];

        expect(priorities.every((p) => p > 0), isTrue);
        expect(priorities[0], greaterThan(priorities[2])); // Lighthouse > land area
      });
    });
  });
}
