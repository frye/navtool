import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';

void main() {
  group('S57 Geometry Degenerate Warning', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should detect and skip degenerate edge with warning', () {
      // Arrange - Create store with degenerate edge
      final store = PrimitiveStore();
      final degenerateEdge = fixtures.createDegenerateEdge();
      store.addEdge(degenerateEdge);
      
      // Add a valid node for fallback
      store.addNode(const S57Node(id: 1, x: 5.0, y: 5.0));
      
      final testAssembler = S57GeometryAssembler(store);
      final pointers = [
        S57SpatialPointer(refId: degenerateEdge.id, isEdge: true, reverse: false),
        const S57SpatialPointer(refId: 1, isEdge: false, reverse: false), // Valid fallback
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(store.warnings.any((w) => w.contains('Degenerate edge')), isTrue);
      expect(store.warnings.any((w) => w.contains('${degenerateEdge.id}')), isTrue);
      
      // Should skip degenerate edge and use valid node
      expect(geometry.type, equals(S57GeometryType.point));
      final coords = geometry.rings.first;
      expect(coords.length, equals(1));
      expect(coords[0].x, equals(5.0));
      expect(coords[0].y, equals(5.0));
    });

    test('should detect edge with single node as degenerate', () {
      // Arrange
      const singleNodeEdge = S57Edge(
        id: 100,
        nodes: [S57Node(id: 1, x: 0.0, y: 0.0)],
      );

      // Act & Assert
      expect(singleNodeEdge.isDegenerate, isTrue);
      expect(singleNodeEdge.nodes.length, equals(1));
    });

    test('should detect edge with no nodes as degenerate', () {
      // Arrange
      const emptyEdge = S57Edge(id: 101, nodes: []);

      // Act & Assert
      expect(emptyEdge.isDegenerate, isTrue);
      expect(emptyEdge.nodes.length, equals(0));
    });

    test('should not flag valid edge as degenerate', () {
      // Arrange
      const validEdge = S57Edge(
        id: 102,
        nodes: [
          S57Node(id: 1, x: 0.0, y: 0.0),
          S57Node(id: 2, x: 1.0, y: 1.0),
        ],
      );

      // Act & Assert
      expect(validEdge.isDegenerate, isFalse);
      expect(validEdge.nodes.length, equals(2));
    });

    test('should handle multiple degenerate edges in sequence', () {
      // Arrange
      final store = PrimitiveStore();
      
      // Add multiple degenerate edges
      const degenerate1 = S57Edge(id: 201, nodes: []);
      const degenerate2 = S57Edge(id: 202, nodes: [S57Node(id: 1, x: 0.0, y: 0.0)]);
      
      store.addEdge(degenerate1);
      store.addEdge(degenerate2);
      
      final testAssembler = S57GeometryAssembler(store);
      final pointers = [
        const S57SpatialPointer(refId: 201, isEdge: true, reverse: false),
        const S57SpatialPointer(refId: 202, isEdge: true, reverse: false),
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(store.warnings.length, greaterThanOrEqualTo(2));
      expect(store.warnings.any((w) => w.contains('Degenerate edge 201')), isTrue);
      expect(store.warnings.any((w) => w.contains('Degenerate edge 202')), isTrue);
      
      // Should fallback to synthetic point when all edges are degenerate
      expect(geometry.type, equals(S57GeometryType.point));
      final coords = geometry.rings.first;
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0));
    });

    test('should continue with valid edges after skipping degenerate ones', () {
      // Arrange
      final store = PrimitiveStore();
      
      // Add valid edge from fixture data
      store.addEdge(const S57Edge(id: 1, nodes: [
        S57Node(id: 1, x: 0.0, y: 0.0),
        S57Node(id: 2, x: 10.0, y: 0.0),
      ]));
      
      // Add degenerate edge  
      const degenerateEdge = S57Edge(id: 999, nodes: []);
      store.addEdge(degenerateEdge);
      
      final testAssembler = S57GeometryAssembler(store);
      final pointers = [
        const S57SpatialPointer(refId: 999, isEdge: true, reverse: false), // Degenerate
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: false),   // Valid
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(store.warnings.any((w) => w.contains('Degenerate edge 999')), isTrue);
      
      // Should create line from valid edge only
      expect(geometry.type, equals(S57GeometryType.line));
      final coords = geometry.rings.first;
      expect(coords.length, equals(2));
      expect(coords[0].x, equals(0.0)); expect(coords[0].y, equals(0.0));
      expect(coords[1].x, equals(10.0)); expect(coords[1].y, equals(0.0));
    });

    test('should handle missing primitives with appropriate warnings', () {
      // Arrange
      final missingPointers = fixtures.getMissingPrimitivePointers();

      // Act
      final geometry = assembler.buildGeometry(missingPointers);

      // Assert
      expect(fixtures.store.warnings, isNotEmpty);
      expect(fixtures.store.warnings.any((w) => w.contains('Missing edge 999')), isTrue);
      
      // Should use synthetic fallback
      expect(geometry.type, equals(S57GeometryType.point));
      final coords = geometry.rings.first;
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0));
    });

    test('should provide helpful warning messages for different degenerate conditions', () {
      // Arrange
      final store = PrimitiveStore();
      
      const emptyEdge = S57Edge(id: 1, nodes: []);
      const singleNodeEdge = S57Edge(id: 2, nodes: [S57Node(id: 1, x: 0.0, y: 0.0)]);
      
      store.addEdge(emptyEdge);
      store.addEdge(singleNodeEdge);
      
      final testAssembler = S57GeometryAssembler(store);
      
      // Act - Test empty edge
      testAssembler.buildGeometry([
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: false),
      ]);
      
      // Act - Test single node edge  
      testAssembler.buildGeometry([
        const S57SpatialPointer(refId: 2, isEdge: true, reverse: false),
      ]);

      // Assert
      final warnings = store.warnings;
      expect(warnings.any((w) => w.contains('Degenerate edge 1 with 0 nodes')), isTrue);
      expect(warnings.any((w) => w.contains('Degenerate edge 2 with 1 nodes')), isTrue);
    });

    test('should maintain geometry integrity after skipping degenerate edges', () {
      // Arrange - Mix valid and degenerate edges in polygon
      final store = PrimitiveStore();
      
      // Add valid edges for most of polygon
      store.addEdge(const S57Edge(id: 1, nodes: [
        S57Node(id: 1, x: 0.0, y: 0.0),
        S57Node(id: 2, x: 10.0, y: 0.0),
      ]));
      store.addEdge(const S57Edge(id: 2, nodes: [
        S57Node(id: 2, x: 10.0, y: 0.0),
        S57Node(id: 3, x: 10.0, y: 10.0),
      ]));
      // Skip edge 3, add degenerate
      const degenerateEdge = S57Edge(id: 999, nodes: []);
      store.addEdge(degenerateEdge);
      
      final testAssembler = S57GeometryAssembler(store);
      final pointers = [
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: false),   // Valid
        const S57SpatialPointer(refId: 2, isEdge: true, reverse: false),   // Valid  
        const S57SpatialPointer(refId: 999, isEdge: true, reverse: false), // Degenerate
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(store.warnings.any((w) => w.contains('Degenerate edge 999')), isTrue);
      
      // Should create line from valid edges only
      expect(geometry.type, equals(S57GeometryType.line));
      final coords = geometry.rings.first;
      expect(coords.length, equals(3)); // 2 edges = 3 coordinates
      
      // Verify coordinate sequence from valid edges
      expect(coords[0].x, equals(0.0));  expect(coords[0].y, equals(0.0));
      expect(coords[1].x, equals(10.0)); expect(coords[1].y, equals(0.0));
      expect(coords[2].x, equals(10.0)); expect(coords[2].y, equals(10.0));
    });
  });
}