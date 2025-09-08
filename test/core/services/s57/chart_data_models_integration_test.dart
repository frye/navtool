import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/services/s57/spatial_grid.dart';
import 'package:navtool/core/services/s57/chart_bounds_calculator.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  group('Chart Data Models Integration Tests', () {
    late List<S57Feature> testFeatures;
    late List<MaritimeFeature> maritimeFeatures;

    setUp(() {
      testFeatures = _createElliotBayTestFeatures();
      maritimeFeatures = _createMaritimeFeatures();
    });

    test('should demonstrate R-tree spatial query performance', () {
      final rtree = S57SpatialTree.bulkLoad(testFeatures);
      
      final queryBounds = S57Bounds(
        north: 47.625,
        south: 47.620,
        east: -122.350,
        west: -122.360,
      );

      final stopwatch = Stopwatch()..start();
      final results = rtree.queryBounds(queryBounds);
      stopwatch.stop();

      expect(results, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(10)); // Should be very fast
      print('R-tree query time: ${stopwatch.elapsedMilliseconds}ms for ${testFeatures.length} features');
    });

    test('should demonstrate spatial grid performance vs linear search', () {
      final bounds = S57Bounds(north: 47.7, south: 47.6, east: -122.3, west: -122.4);
      final grid = SpatialGrid(bounds: bounds, cellSizeDegrees: 0.01);
      
      // Add features to grid
      final addStopwatch = Stopwatch()..start();
      grid.addFeatures(testFeatures);
      addStopwatch.stop();

      // Test query performance
      final queryStopwatch = Stopwatch()..start();
      final results = grid.queryPoint(47.625, -122.355, radiusDegrees: 0.01);
      queryStopwatch.stop();

      expect(results, isNotEmpty);
      expect(queryStopwatch.elapsedMilliseconds, lessThan(5));
      
      final stats = grid.getStats();
      print('Grid stats: ${stats}');
      print('Grid query time: ${queryStopwatch.elapsedMilliseconds}ms');
    });

    test('should calculate optimal chart bounds and scales', () {
      final bounds = ChartBoundsCalculator.calculateOptimalBounds(maritimeFeatures);
      final density = ChartBoundsCalculator.calculateFeatureDensity(maritimeFeatures, bounds);
      final scale = ChartBoundsCalculator.determineOptimalScale(
        bounds: bounds,
        features: maritimeFeatures,
        viewportSizeDegrees: 0.1,
      );

      expect(bounds.north, greaterThan(bounds.south));
      expect(bounds.east, greaterThan(bounds.west));
      expect(density, greaterThan(0.0));
      expect(scale, isA<ChartScale>());
      
      print('Chart bounds: ${bounds}');
      print('Feature density: ${density.toStringAsFixed(2)} features/deg²');
      print('Optimal scale: ${scale}');
    });

    test('should create chart tiles and cells efficiently', () {
      final bounds = LatLngBounds(north: 47.7, south: 47.6, east: -122.3, west: -122.4);
      
      final tiles = ChartCell.createTilesForCell(
        cellName: 'US5WA50M_TEST',
        bounds: bounds,
        features: maritimeFeatures,
        scale: ChartScale.harbour,
      );

      expect(tiles, isNotEmpty);
      expect(tiles.length, lessThanOrEqualTo(4)); // Max quadrants
      
      for (final tile in tiles) {
        expect(tile.features, isNotEmpty);
        expect(tile.id, startsWith('US5WA50M_TEST_'));
      }

      print('Created ${tiles.length} tiles for ${maritimeFeatures.length} features');
    });

    test('should manage chart metadata with S-57 compliance', () {
      final metadata = ChartMetadata.fromS57(
        cellName: 'US5WA50M',
        datasetTitle: 'Elliott Bay Harbor Chart',
        producer: 'NOAA',
        issueDate: DateTime(2023, 6, 15),
        edition: 15,
        updateNumber: 3,
        north: 47.7,
        south: 47.6,
        east: -122.3,
        west: -122.4,
        compilationScale: 50000,
      );

      expect(metadata.id, equals('US5WA50M'));
      expect(metadata.nativeScale, equals(ChartScale.approach));
      
      // Test coverage calculation
      final queryBounds = LatLngBounds(north: 47.65, south: 47.62, east: -122.32, west: -122.38);
      final coverage = metadata.calculateCoverage(queryBounds);
      expect(coverage, equals(1.0)); // Full coverage
      
      print('Chart metadata: ${metadata.title}, Scale: ${metadata.nativeScale}');
    });

    test('should demonstrate marine feature classification', () {
      final rtree = S57SpatialTree.bulkLoad(testFeatures);
      
      final navAids = rtree.queryNavigationAids();
      final depthFeatures = rtree.queryDepthFeatures();
      final buoys = rtree.queryByType(S57FeatureType.buoy);
      
      expect(navAids, isNotEmpty);
      expect(depthFeatures, isNotEmpty);
      expect(buoys, isNotEmpty);
      
      print('Navigation aids: ${navAids.length}');
      print('Depth features: ${depthFeatures.length}');
      print('Buoys: ${buoys.length}');
      
      // Verify feature types are correctly classified
      for (final navAid in navAids) {
        expect(_isNavigationAid(navAid.featureType), isTrue);
      }
    });

    test('should validate spatial index performance scaling', () {
      // Test with different dataset sizes
      final smallDataset = testFeatures.sublist(0, min(5, testFeatures.length));
      final mediumDataset = testFeatures;
      final largeDataset = _createLargeTestDataset(1000);

      // Test R-tree performance scaling
      final rtreeSmall = S57SpatialTree.bulkLoad(smallDataset);
      final rtreeMedium = S57SpatialTree.bulkLoad(mediumDataset);
      final rtreeLarge = S57SpatialTree.bulkLoad(largeDataset);

      final queryBounds = S57Bounds(north: 47.625, south: 47.620, east: -122.350, west: -122.360);

      // Small dataset
      var stopwatch = Stopwatch()..start();
      rtreeSmall.queryBounds(queryBounds);
      stopwatch.stop();
      final smallTime = stopwatch.elapsedMilliseconds;

      // Medium dataset
      stopwatch.reset();
      stopwatch.start();
      rtreeMedium.queryBounds(queryBounds);
      stopwatch.stop();
      final mediumTime = stopwatch.elapsedMilliseconds;

      // Large dataset
      stopwatch.reset();
      stopwatch.start();
      rtreeLarge.queryBounds(queryBounds);
      stopwatch.stop();
      final largeTime = stopwatch.elapsedMilliseconds;

      print('Query times - Small: ${smallTime}ms, Medium: ${mediumTime}ms, Large: ${largeTime}ms');
      
      // R-tree should scale logarithmically, not linearly
      expect(largeTime, lessThan(100)); // Should still be fast even with 1000 features
    });
  });
}

bool _isNavigationAid(S57FeatureType type) {
  return [
    S57FeatureType.buoy,
    S57FeatureType.buoyLateral,
    S57FeatureType.buoyCardinal,
    S57FeatureType.buoyIsolatedDanger,
    S57FeatureType.buoySpecialPurpose,
    S57FeatureType.beacon,
    S57FeatureType.lighthouse,
    S57FeatureType.daymark,
  ].contains(type);
}

List<S57Feature> _createElliotBayTestFeatures() {
  return [
    // Elliott Bay entrance buoy
    S57Feature(
      recordId: 1001,
      featureType: S57FeatureType.buoy,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6235, longitude: -122.3517)],
      attributes: const {'name': 'Elliott Bay Entrance Buoy', 'catboy': 1},
    ),
    // Alki Point Light
    S57Feature(
      recordId: 1002,
      featureType: S57FeatureType.lighthouse,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6062, longitude: -122.3321)],
      attributes: const {'name': 'Alki Point Light', 'height': 12.0},
    ),
    // Harbor beacon
    S57Feature(
      recordId: 1003,
      featureType: S57FeatureType.beacon,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6167, longitude: -122.3656)],
      attributes: const {'name': 'Harbor Beacon'},
    ),
    // Depth contour (10m)
    S57Feature(
      recordId: 2001,
      featureType: S57FeatureType.depthContour,
      geometryType: S57GeometryType.line,
      coordinates: [
        S57Coordinate(latitude: 47.620, longitude: -122.360),
        S57Coordinate(latitude: 47.625, longitude: -122.355),
        S57Coordinate(latitude: 47.630, longitude: -122.350),
      ],
      attributes: const {'valdco': 10.0},
    ),
    // Sounding
    S57Feature(
      recordId: 2002,
      featureType: S57FeatureType.sounding,
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: 47.6289, longitude: -122.3478)],
      attributes: const {'valsou': 15.2},
    ),
    // Coastline
    S57Feature(
      recordId: 3001,
      featureType: S57FeatureType.coastline,
      geometryType: S57GeometryType.line,
      coordinates: [
        S57Coordinate(latitude: 47.610, longitude: -122.340),
        S57Coordinate(latitude: 47.615, longitude: -122.345),
        S57Coordinate(latitude: 47.620, longitude: -122.350),
        S57Coordinate(latitude: 47.625, longitude: -122.355),
      ],
      attributes: const {'catcoa': 1}, // Natural coastline
    ),
  ];
}

List<MaritimeFeature> _createMaritimeFeatures() {
  return [
    PointFeature(
      id: 'lighthouse_alki',
      type: MaritimeFeatureType.lighthouse,
      position: LatLng(47.6062, -122.3321),
      label: 'Alki Point Light',
    ),
    PointFeature(
      id: 'buoy_elliott_bay',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6235, -122.3517),
      label: 'Elliott Bay Buoy',
    ),
    PointFeature(
      id: 'beacon_harbor',
      type: MaritimeFeatureType.beacon,
      position: LatLng(47.6167, -122.3656),
      label: 'Harbor Beacon',
    ),
    LineFeature(
      id: 'shoreline_elliott',
      type: MaritimeFeatureType.shoreline,
      position: LatLng(47.615, -122.345),
      coordinates: [
        LatLng(47.610, -122.340),
        LatLng(47.615, -122.345),
        LatLng(47.620, -122.350),
      ],
    ),
    AreaFeature(
      id: 'anchorage_elliott',
      type: MaritimeFeatureType.anchorage,
      position: LatLng(47.618, -122.355),
      coordinates: [[
        LatLng(47.615, -122.350),
        LatLng(47.620, -122.350),
        LatLng(47.620, -122.360),
        LatLng(47.615, -122.360),
        LatLng(47.615, -122.350),
      ]],
    ),
  ];
}

List<S57Feature> _createLargeTestDataset(int count) {
  final features = <S57Feature>[];
  final featureTypes = [
    S57FeatureType.buoy,
    S57FeatureType.beacon,
    S57FeatureType.sounding,
    S57FeatureType.depthContour,
    S57FeatureType.obstruction,
  ];

  for (int i = 0; i < count; i++) {
    final lat = 47.60 + (i % 100) * 0.001; // Spread across Elliott Bay
    final lon = -122.40 + (i ~/ 100) * 0.001;
    
    features.add(S57Feature(
      recordId: 10000 + i,
      featureType: featureTypes[i % featureTypes.length],
      geometryType: S57GeometryType.point,
      coordinates: [S57Coordinate(latitude: lat, longitude: lon)],
      attributes: {'test_id': i},
    ));
  }

  return features;
}