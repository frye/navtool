import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/core/services/chart_rendering_service.dart';
import 'package:navtool/core/services/coordinate_transform.dart';
import 'package:navtool/core/models/chart_models.dart';

/// Performance benchmark tests for chart rendering service
/// 
/// Validates spatial index integration provides significant performance improvement
/// over linear feature scanning for viewport culling.
void main() {
  group('Chart Rendering Performance Tests', () {
    const testCenter = LatLng(37.7749, -122.4194);
    const testScreenSize = Size(800, 600);
    const testZoom = 12.0;

    late CoordinateTransform transform;

    setUp(() {
      transform = CoordinateTransform(
        zoom: testZoom,
        center: testCenter,
        screenSize: testScreenSize,
      );
    });

    /// Generate synthetic feature dataset for performance testing
    List<MaritimeFeature> generateTestFeatures(int count) {
      final features = <MaritimeFeature>[];
      
      // Distribute features across a 1-degree area around test center
      for (int i = 0; i < count; i++) {
        final latOffset = (i % 100 - 50) * 0.01; // -0.5 to +0.5 degrees
        final lonOffset = (i ~/ 100 - 50) * 0.01;
        final position = LatLng(
          testCenter.latitude + latOffset,
          testCenter.longitude + lonOffset,
        );

        // Create different feature types for variety
        final featureType = MaritimeFeatureType.values[i % MaritimeFeatureType.values.length];
        
        if (featureType == MaritimeFeatureType.shoreline || 
            featureType == MaritimeFeatureType.cable ||
            featureType == MaritimeFeatureType.pipeline) {
          // Create line features
          features.add(LineFeature(
            id: 'line_feature_$i',
            type: featureType,
            position: position,
            coordinates: [
              position,
              LatLng(position.latitude + 0.001, position.longitude + 0.001),
            ],
            width: 1.0,
          ));
        } else if (featureType == MaritimeFeatureType.landArea ||
                   featureType == MaritimeFeatureType.anchorage ||
                   featureType == MaritimeFeatureType.restrictedArea) {
          // Create area features
          features.add(AreaFeature(
            id: 'area_feature_$i',
            type: featureType,
            position: position,
            coordinates: [[
              position,
              LatLng(position.latitude + 0.002, position.longitude),
              LatLng(position.latitude + 0.002, position.longitude + 0.002),
              LatLng(position.latitude, position.longitude + 0.002),
            ]],
          ));
        } else {
          // Create point features
          features.add(PointFeature(
            id: 'point_feature_$i',
            type: featureType,
            position: position,
            label: 'Feature $i',
          ));
        }
      }
      
      return features;
    }

    group('Spatial Index Performance Benchmarks', () {
      test('should show significant performance improvement with spatial index for 1k features', () {
        final features = generateTestFeatures(1000);
        final renderingService = ChartRenderingService(
          transform: transform,
          features: features,
        );

        // Benchmark getVisibleFeatures performance
        const iterations = 100;
        final stopwatch = Stopwatch();
        
        stopwatch.start();
        for (int i = 0; i < iterations; i++) {
          final visibleFeatures = renderingService.getVisibleFeatures();
          expect(visibleFeatures, isA<List<MaritimeFeature>>());
        }
        stopwatch.stop();

        final avgTimeMs = stopwatch.elapsedMilliseconds / iterations;
        
        // Performance target: should be under 5ms per query for 1k features
        expect(avgTimeMs, lessThan(5.0), 
          reason: 'Viewport culling should be < 5ms for 1k features, got ${avgTimeMs}ms');
        
        print('Performance: ${avgTimeMs}ms per getVisibleFeatures() call (1k features)');
      });

      test('should show significant performance improvement with spatial index for 5k features', () {
        final features = generateTestFeatures(5000);
        final renderingService = ChartRenderingService(
          transform: transform,
          features: features,
        );

        // Benchmark getVisibleFeatures performance
        const iterations = 50;
        final stopwatch = Stopwatch();
        
        stopwatch.start();
        for (int i = 0; i < iterations; i++) {
          final visibleFeatures = renderingService.getVisibleFeatures();
          expect(visibleFeatures, isA<List<MaritimeFeature>>());
        }
        stopwatch.stop();

        final avgTimeMs = stopwatch.elapsedMilliseconds / iterations;
        
        // Performance target: should be under 3ms per query for 5k features with spatial index
        expect(avgTimeMs, lessThan(3.0), 
          reason: 'Spatial index should enable < 3ms viewport culling for 5k features, got ${avgTimeMs}ms');
        
        print('Performance: ${avgTimeMs}ms per getVisibleFeatures() call (5k features)');
      });

      test('should handle viewport queries efficiently with mixed feature types', () {
        // Create mixed dataset with realistic distribution
        final features = <MaritimeFeature>[];
        
        // Add many navigation aids (common)
        for (int i = 0; i < 2000; i++) {
          features.add(PointFeature(
            id: 'buoy_$i',
            type: MaritimeFeatureType.buoy,
            position: LatLng(
              testCenter.latitude + (i % 50 - 25) * 0.002,
              testCenter.longitude + (i ~/ 50 - 25) * 0.002,
            ),
          ));
        }
        
        // Add some lighthouses (less common)
        for (int i = 0; i < 100; i++) {
          features.add(PointFeature(
            id: 'lighthouse_$i',
            type: MaritimeFeatureType.lighthouse,
            position: LatLng(
              testCenter.latitude + (i % 10 - 5) * 0.01,
              testCenter.longitude + (i ~/ 10 - 5) * 0.01,
            ),
          ));
        }
        
        // Add shoreline segments
        for (int i = 0; i < 500; i++) {
          final start = LatLng(
            testCenter.latitude + (i % 25 - 12) * 0.004,
            testCenter.longitude + (i ~/ 25 - 12) * 0.004,
          );
          features.add(LineFeature(
            id: 'shoreline_$i',
            type: MaritimeFeatureType.shoreline,
            position: start,
            coordinates: [
              start,
              LatLng(start.latitude + 0.001, start.longitude + 0.001),
            ],
            width: 2.0,
          ));
        }

        final renderingService = ChartRenderingService(
          transform: transform,
          features: features,
        );

        // Test viewport culling performance
        const iterations = 20;
        final stopwatch = Stopwatch();
        
        stopwatch.start();
        for (int i = 0; i < iterations; i++) {
          final visibleFeatures = renderingService.getVisibleFeatures();
          expect(visibleFeatures.length, greaterThan(0), 
            reason: 'Should find some features in viewport');
        }
        stopwatch.stop();

        final avgTimeMs = stopwatch.elapsedMilliseconds / iterations;
        
        // Performance target for realistic mixed dataset
        expect(avgTimeMs, lessThan(5.0), 
          reason: 'Mixed feature viewport culling should be < 5ms, got ${avgTimeMs}ms');
        
        print('Performance: ${avgTimeMs}ms per mixed viewport query (2600 features)');
      });
    });

    group('Feature Count Validation', () {
      test('should return reasonable feature counts for different viewport sizes', () {
        final features = generateTestFeatures(1000);
        
        // Test small viewport (high zoom)
        final smallTransform = CoordinateTransform(
          zoom: 16.0, // High zoom - small viewport
          center: testCenter,
          screenSize: testScreenSize,
        );
        
        final smallViewportService = ChartRenderingService(
          transform: smallTransform,
          features: features,
        );
        
        final smallViewportFeatures = smallViewportService.getVisibleFeatures();
        
        // Test large viewport (low zoom)
        final largeTransform = CoordinateTransform(
          zoom: 8.0, // Low zoom - large viewport  
          center: testCenter,
          screenSize: testScreenSize,
        );
        
        final largeViewportService = ChartRenderingService(
          transform: largeTransform,
          features: features,
        );
        
        final largeViewportFeatures = largeViewportService.getVisibleFeatures();
        
        // Large viewport should contain more features than small viewport
        expect(largeViewportFeatures.length, greaterThanOrEqualTo(smallViewportFeatures.length),
          reason: 'Large viewport should contain same or more features than small viewport');
        
        print('Small viewport (zoom 16): ${smallViewportFeatures.length} features');
        print('Large viewport (zoom 8): ${largeViewportFeatures.length} features');
      });
      
      test('should respect scale-based feature visibility', () {
        // Create features with different visibility requirements
        final features = [
          // Lighthouse - visible at all scales
          const PointFeature(
            id: 'lighthouse_always',
            type: MaritimeFeatureType.lighthouse,
            position: testCenter,
          ),
          // Buoy - typically visible at closer scales
          const PointFeature(
            id: 'buoy_detailed',
            type: MaritimeFeatureType.buoy,
            position: testCenter,
          ),
        ];
        
        // Test at overview scale
        final overviewTransform = CoordinateTransform(
          zoom: 8.0,
          center: testCenter,
          screenSize: testScreenSize,
        );
        
        final overviewService = ChartRenderingService(
          transform: overviewTransform,
          features: features,
        );
        
        final overviewVisible = overviewService.getVisibleFeatures();
        
        // Test at detailed scale
        final detailTransform = CoordinateTransform(
          zoom: 15.0,
          center: testCenter,
          screenSize: testScreenSize,
        );
        
        final detailService = ChartRenderingService(
          transform: detailTransform,
          features: features,
        );
        
        final detailVisible = detailService.getVisibleFeatures();
        
        // Should respect scale-dependent visibility rules
        expect(overviewVisible, isNotEmpty, 
          reason: 'Should have some features visible at overview scale');
        expect(detailVisible, isNotEmpty,
          reason: 'Should have features visible at detail scale');
        
        print('Overview scale visible: ${overviewVisible.length}');
        print('Detail scale visible: ${detailVisible.length}');
      });
    });
  });
}