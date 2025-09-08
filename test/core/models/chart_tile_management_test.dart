import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  group('Chart Tile Management', () {
    late List<MaritimeFeature> testFeatures;
    late LatLngBounds testBounds;

    setUp(() {
      testBounds = LatLngBounds(
        north: 47.7,
        south: 47.6,
        east: -122.3,
        west: -122.4,
      );
      
      testFeatures = _createTestFeatures();
    });

    group('ChartTile', () {
      test('should create chart tile with correct properties', () {
        final tile = ChartTile(
          id: 'test_tile_1',
          bounds: testBounds,
          zoomLevel: 12,
          features: testFeatures,
          scale: ChartScale.coastal,
          lastUpdated: DateTime.now(),
        );

        expect(tile.id, equals('test_tile_1'));
        expect(tile.bounds, equals(testBounds));
        expect(tile.zoomLevel, equals(12));
        expect(tile.features.length, equals(testFeatures.length));
        expect(tile.scale, equals(ChartScale.coastal));
      });

      test('should determine if tile should render at zoom level', () {
        final tile = ChartTile(
          id: 'test_tile_1',
          bounds: testBounds,
          zoomLevel: 12,
          features: testFeatures,
          scale: ChartScale.coastal,
          lastUpdated: DateTime.now(),
        );

        expect(tile.shouldRenderAtZoom(11.0), isTrue); // zoomLevel - 1
        expect(tile.shouldRenderAtZoom(12.0), isTrue); // exact zoomLevel
        expect(tile.shouldRenderAtZoom(14.0), isTrue); // zoomLevel + 2
        expect(tile.shouldRenderAtZoom(10.0), isFalse); // too far below
        expect(tile.shouldRenderAtZoom(15.0), isFalse); // too far above
      });

      test('should filter visible features by scale', () {
        final tile = ChartTile(
          id: 'test_tile_1',
          bounds: testBounds,
          zoomLevel: 12,
          features: testFeatures,
          scale: ChartScale.overview, // Only lighthouses and land visible
          lastUpdated: DateTime.now(),
        );

        final visibleFeatures = tile.getVisibleFeatures();

        // At overview scale, only lighthouses and land should be visible
        final visibleTypes = visibleFeatures.map((f) => f.type).toSet();
        expect(visibleTypes, contains(MaritimeFeatureType.lighthouse));
        expect(visibleTypes, isNot(contains(MaritimeFeatureType.buoy)));
      });

      test('should count features by type', () {
        final tile = ChartTile(
          id: 'test_tile_1',
          bounds: testBounds,
          zoomLevel: 12,
          features: testFeatures,
          scale: ChartScale.coastal,
          lastUpdated: DateTime.now(),
        );

        final counts = tile.getFeatureCountsByType();

        expect(counts[MaritimeFeatureType.lighthouse], equals(1));
        expect(counts[MaritimeFeatureType.buoy], equals(2));
        expect(counts[MaritimeFeatureType.beacon], equals(1));
        expect(counts[MaritimeFeatureType.anchorage], equals(1));
      });
    });

    group('ChartCell', () {
      test('should create chart cell with metadata', () {
        final cell = ChartCell(
          cellName: 'US5WA50M',
          bounds: testBounds,
          edition: 15,
          updateNumber: 3,
          producer: 'NOAA',
          issueDate: DateTime(2023, 6, 15),
          nativeScale: ChartScale.harbour,
          tiles: [],
        );

        expect(cell.cellName, equals('US5WA50M'));
        expect(cell.edition, equals(15));
        expect(cell.updateNumber, equals(3));
        expect(cell.producer, equals('NOAA'));
        expect(cell.nativeScale, equals(ChartScale.harbour));
      });

      test('should create tiles for cell based on feature density', () {
        // Small number of features - should create single tile
        final smallFeatureSet = testFeatures.sublist(0, 2);
        final tiles = ChartCell.createTilesForCell(
          cellName: 'TEST_CELL',
          bounds: testBounds,
          features: smallFeatureSet,
          scale: ChartScale.coastal,
          maxFeaturesPerTile: 1000,
        );

        expect(tiles.length, equals(1));
        expect(tiles.first.features.length, equals(2));
        expect(tiles.first.id, equals('TEST_CELL_0'));
      });

      test('should subdivide into quadrants for large feature sets', () {
        // Create many features to trigger subdivision
        final largeFeatureSet = List.generate(2000, (i) => PointFeature(
          id: 'feature_$i',
          type: MaritimeFeatureType.buoy,
          position: LatLng(
            47.6 + (i % 50) * 0.002, // Spread across bounds
            -122.4 + (i ~/ 50) * 0.0025,
          ),
        ));

        final tiles = ChartCell.createTilesForCell(
          cellName: 'LARGE_CELL',
          bounds: testBounds,
          features: largeFeatureSet,
          scale: ChartScale.coastal,
          maxFeaturesPerTile: 1000,
        );

        expect(tiles.length, greaterThan(1));
        expect(tiles.length, lessThanOrEqualTo(4)); // Max 4 quadrants

        // Verify tile IDs
        for (int i = 0; i < tiles.length; i++) {
          expect(tiles[i].id, startsWith('LARGE_CELL_'));
        }
      });

      test('should get tiles in viewport bounds', () {
        final allTiles = [
          ChartTile(
            id: 'tile_0',
            bounds: LatLngBounds(north: 47.65, south: 47.60, east: -122.35, west: -122.40),
            zoomLevel: 12,
            features: [testFeatures[0]],
            scale: ChartScale.coastal,
            lastUpdated: DateTime.now(),
          ),
          ChartTile(
            id: 'tile_1',
            bounds: LatLngBounds(north: 47.70, south: 47.65, east: -122.35, west: -122.40),
            zoomLevel: 12,
            features: [testFeatures[1]],
            scale: ChartScale.coastal,
            lastUpdated: DateTime.now(),
          ),
          ChartTile(
            id: 'tile_2',
            bounds: LatLngBounds(north: 47.80, south: 47.75, east: -122.25, west: -122.30), // Outside viewport
            zoomLevel: 12,
            features: [testFeatures[2]],
            scale: ChartScale.coastal,
            lastUpdated: DateTime.now(),
          ),
        ];

        final cell = ChartCell(
          cellName: 'TEST_CELL',
          bounds: testBounds,
          edition: 1,
          updateNumber: 0,
          producer: 'TEST',
          issueDate: DateTime.now(),
          nativeScale: ChartScale.coastal,
          tiles: allTiles,
        );

        final viewportBounds = LatLngBounds(
          north: 47.68,
          south: 47.62,
          east: -122.32,
          west: -122.38,
        );

        final visibleTiles = cell.getTilesInBounds(viewportBounds);

        expect(visibleTiles.length, equals(2)); // Should exclude tile_2
        expect(visibleTiles.map((t) => t.id), isNot(contains('tile_2')));
      });

      test('should determine if cell data is current', () {
        final recentCell = ChartCell(
          cellName: 'RECENT',
          bounds: testBounds,
          edition: 1,
          updateNumber: 0,
          producer: 'TEST',
          issueDate: DateTime.now().subtract(Duration(days: 15)), // 15 days old
          nativeScale: ChartScale.coastal,
          tiles: [],
        );

        final oldCell = ChartCell(
          cellName: 'OLD',
          bounds: testBounds,
          edition: 1,
          updateNumber: 0,
          producer: 'TEST',
          issueDate: DateTime.now().subtract(Duration(days: 45)), // 45 days old
          nativeScale: ChartScale.coastal,
          tiles: [],
        );

        expect(recentCell.isCurrent, isTrue);
        expect(oldCell.isCurrent, isFalse);
      });
    });

    group('ChartMetadata', () {
      test('should create metadata from S-57 parameters', () {
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
          additionalAttributes: {'usage_band': 1},
        );

        expect(metadata.id, equals('US5WA50M'));
        expect(metadata.title, equals('Elliott Bay Harbor Chart'));
        expect(metadata.producer, equals('NOAA'));
        expect(metadata.edition, equals(15));
        expect(metadata.updateNumber, equals(3));
        expect(metadata.nativeScale, equals(ChartScale.approach)); // 50000 scale
        expect(metadata.attributes['usage_band'], equals(1));
      });

      test('should determine appropriate scale from compilation scale', () {
        expect(ChartMetadata.fromS57(
          cellName: 'TEST',
          datasetTitle: 'Test',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          north: 47.7,
          south: 47.6,
          east: -122.3,
          west: -122.4,
          compilationScale: 5000,
        ).nativeScale, equals(ChartScale.berthing));

        expect(ChartMetadata.fromS57(
          cellName: 'TEST',
          datasetTitle: 'Test',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          north: 47.7,
          south: 47.6,
          east: -122.3,
          west: -122.4,
          compilationScale: 1500000,
        ).nativeScale, equals(ChartScale.overview));
      });

      test('should detect overlapping charts', () {
        final metadata1 = ChartMetadata(
          id: 'chart1',
          title: 'Chart 1',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          bounds: LatLngBounds(north: 47.7, south: 47.6, east: -122.3, west: -122.4),
          nativeScale: ChartScale.coastal,
        );

        final metadata2 = ChartMetadata(
          id: 'chart2',
          title: 'Chart 2',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          bounds: LatLngBounds(north: 47.65, south: 47.55, east: -122.25, west: -122.35),
          nativeScale: ChartScale.coastal,
        );

        final metadata3 = ChartMetadata(
          id: 'chart3',
          title: 'Chart 3',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          bounds: LatLngBounds(north: 48.0, south: 47.9, east: -121.0, west: -121.1),
          nativeScale: ChartScale.coastal,
        );

        expect(metadata1.overlaps(metadata2), isTrue); // Overlapping
        expect(metadata1.overlaps(metadata3), isFalse); // Non-overlapping
      });

      test('should calculate coverage percentage', () {
        final metadata = ChartMetadata(
          id: 'chart1',
          title: 'Chart 1',
          producer: 'TEST',
          issueDate: DateTime.now(),
          edition: 1,
          updateNumber: 0,
          bounds: LatLngBounds(north: 47.7, south: 47.6, east: -122.3, west: -122.4),
          nativeScale: ChartScale.coastal,
        );

        // Query bounds fully within chart bounds
        final queryBounds1 = LatLngBounds(
          north: 47.65,
          south: 47.62,
          east: -122.32,
          west: -122.38,
        );

        // Query bounds partially overlapping
        final queryBounds2 = LatLngBounds(
          north: 47.75,
          south: 47.65,
          east: -122.25,
          west: -122.35,
        );

        // Query bounds outside chart
        final queryBounds3 = LatLngBounds(
          north: 48.0,
          south: 47.9,
          east: -121.0,
          west: -121.1,
        );

        final coverage1 = metadata.calculateCoverage(queryBounds1);
        final coverage2 = metadata.calculateCoverage(queryBounds2);
        final coverage3 = metadata.calculateCoverage(queryBounds3);

        expect(coverage1, equals(1.0)); // Full coverage
        expect(coverage2, greaterThan(0.0)); // Partial coverage
        expect(coverage2, lessThan(1.0));
        expect(coverage3, equals(0.0)); // No coverage
      });
    });
  });
}

List<MaritimeFeature> _createTestFeatures() {
  return [
    PointFeature(
      id: 'lighthouse_1',
      type: MaritimeFeatureType.lighthouse,
      position: LatLng(47.6062, -122.3321),
      label: 'Alki Point Light',
    ),
    PointFeature(
      id: 'buoy_1',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6235, -122.3517),
      label: 'Elliott Bay Buoy 1',
    ),
    PointFeature(
      id: 'buoy_2',
      type: MaritimeFeatureType.buoy,
      position: LatLng(47.6150, -122.3650),
      label: 'Elliott Bay Buoy 2',
    ),
    PointFeature(
      id: 'beacon_1',
      type: MaritimeFeatureType.beacon,
      position: LatLng(47.6167, -122.3656),
      label: 'Harbor Beacon',
    ),
    AreaFeature(
      id: 'anchorage_1',
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