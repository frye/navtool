import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';

void main() {
  group('S57 Geometry Stitching', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should stitch edges without duplicate coordinates', () {
      // Arrange - Use COALNE_CONTIGUOUS which chains E1 + E2 without reversal
      final pointers = fixtures.getFeaturePointers('COALNE_CONTIGUOUS');
      final stitchCoord = fixtures.getStitchingTestCoordinate();

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      final coordLists = fixtures.coordinateListToLists(coords);

      // Count occurrences of the shared coordinate (10,0)
      int count = 0;
      for (final coord in coordLists) {
        if (coord[0] == stitchCoord[0] && coord[1] == stitchCoord[1]) {
          count++;
        }
      }

      // Should appear only once due to stitching
      expect(
        count,
        equals(1),
        reason:
            'Shared coordinate ${stitchCoord} should appear only once after stitching',
      );
    });

    test('should stitch multiple edges in sequence', () {
      // Arrange - Chain three edges: E1 -> E2 -> E3
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // (0,0) -> (10,0)
        const S57SpatialPointer(
          refId: 2,
          isEdge: true,
          reverse: false,
        ), // (10,0) -> (10,10)
        const S57SpatialPointer(
          refId: 3,
          isEdge: true,
          reverse: false,
        ), // (10,10) -> (0,10)
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(
        coords.length,
        equals(4),
        reason: 'Should have 4 unique coordinates after stitching',
      );

      // Verify coordinate sequence
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0)); // Start of E1
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0)); // End E1/Start E2 (shared)
      expect(coords[2].x, equals(10.0));
      expect(coords[2].y, equals(10.0)); // End E2/Start E3 (shared)
      expect(coords[3].x, equals(0.0));
      expect(coords[3].y, equals(10.0)); // End of E3
    });

    test('should handle non-contiguous edges without stitching', () {
      // Arrange - Use E1 and E3 which don't share a boundary
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // (0,0) -> (10,0)
        const S57SpatialPointer(
          refId: 3,
          isEdge: true,
          reverse: false,
        ), // (10,10) -> (0,10)
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(
        coords.length,
        equals(4),
        reason: 'Should have all 4 coordinates when edges don\'t connect',
      );

      // Verify coordinate sequence (no stitching should occur)
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0)); // Start of E1
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0)); // End of E1
      expect(coords[2].x, equals(10.0));
      expect(coords[2].y, equals(10.0)); // Start of E3
      expect(coords[3].x, equals(0.0));
      expect(coords[3].y, equals(10.0)); // End of E3
    });

    test('should stitch reversed edges correctly', () {
      // Arrange - E1 forward then E2 reversed (should not stitch as they don't connect)
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // (0,0) -> (10,0)
        const S57SpatialPointer(
          refId: 2,
          isEdge: true,
          reverse: true,
        ), // (10,10) -> (10,0)
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      // These edges don't actually connect, so no stitching occurs
      expect(
        coords.length,
        equals(4),
        reason: 'Non-contiguous edges should not be stitched',
      );

      // Verify sequence: E1 then E2 reversed (non-contiguous)
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0)); // Start of E1
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0)); // End of E1
      expect(coords[2].x, equals(10.0));
      expect(coords[2].y, equals(10.0)); // Start of reversed E2
      expect(coords[3].x, equals(10.0));
      expect(coords[3].y, equals(0.0)); // End of reversed E2
    });

    test('should stitch node and edge pointers', () {
      // Arrange - Mix node and edge pointers
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: false,
          reverse: false,
        ), // Node 1: (0,0)
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // Edge 1: (0,0) -> (10,0)
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(
        coords.length,
        equals(2),
        reason: 'Node and edge start should be stitched',
      );

      // Verify no duplication at (0,0)
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0)); // Node/Edge start
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0)); // Edge end
    });

    test('should handle empty coordinate chains gracefully', () {
      // Arrange - Include a pointer that will produce empty coordinates
      final store = PrimitiveStore();
      store.addNode(const S57Node(id: 1, x: 0.0, y: 0.0));
      // Note: Not adding edge 999, so it will be missing

      final testAssembler = S57GeometryAssembler(store);
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: false,
          reverse: false,
        ), // Valid node
        const S57SpatialPointer(
          refId: 999,
          isEdge: true,
          reverse: false,
        ), // Missing edge
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.point));
      expect(store.warnings.any((w) => w.contains('Missing edge 999')), isTrue);

      // Should only have coordinates from valid node
      final coords = geometry.rings.first;
      expect(coords.length, equals(1));
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0));
    });

    test('should verify seam coordinate count in complete polygon', () {
      // Arrange - Complete DEPARE polygon
      final pointers = fixtures.getFeaturePointers('DEPARE');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.area));

      final coords = geometry.rings.first;

      // Check that each corner appears exactly once (except closure)
      final corners = [
        [0.0, 0.0], // Node 1
        [10.0, 0.0], // Node 2
        [10.0, 10.0], // Node 3
        [0.0, 10.0], // Node 4
      ];

      for (final corner in corners) {
        int count = 0;
        for (final coord in coords) {
          if (coord.x == corner[0] && coord.y == corner[1]) {
            count++;
          }
        }

        // Each corner should appear once, except the first which appears twice (start and end)
        final expectedCount = (corner[0] == 0.0 && corner[1] == 0.0) ? 2 : 1;
        expect(
          count,
          equals(expectedCount),
          reason: 'Corner ${corner} should appear $expectedCount times',
        );
      }
    });
  });
}
