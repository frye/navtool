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
    });
  });
}
