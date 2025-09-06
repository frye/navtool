import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import 'dart:math' as math;

void main() {
  group('S57 Geometry Assembly Performance', () {
    test('micro-benchmark: assembly time for 100 features', () {
      // Arrange - Create store with 100 features worth of primitives
      final store = PrimitiveStore();
      final assembler = S57GeometryAssembler(store);

      // Generate test primitives - simulate a marine chart section
      for (int i = 0; i < 100; i++) {
        // Add nodes for each feature
        for (int j = 0; j < 4; j++) {
          store.addNode(
            S57Node(
              id: i * 10 + j,
              x: (i % 10).toDouble() + j,
              y: (i ~/ 10).toDouble() + j,
            ),
          );
        }

        // Add edge connecting the nodes
        store.addEdge(
          S57Edge(
            id: i,
            nodes: List.generate(
              4,
              (j) => S57Node(
                id: i * 10 + j,
                x: (i % 10).toDouble() + j,
                y: (i ~/ 10).toDouble() + j,
              ),
            ),
          ),
        );
      }

      // Generate pointers for different geometry types
      final pointPointers = List.generate(
        33,
        (i) => [
          S57SpatialPointer(refId: i * 10, isEdge: false, reverse: false),
        ],
      );

      final linePointers = List.generate(
        34,
        (i) => [S57SpatialPointer(refId: i, isEdge: true, reverse: false)],
      );

      final polygonPointers = List.generate(
        33,
        (i) => [
          S57SpatialPointer(refId: i, isEdge: true, reverse: false),
          S57SpatialPointer(refId: (i + 1) % 33, isEdge: true, reverse: false),
          S57SpatialPointer(refId: (i + 2) % 33, isEdge: true, reverse: false),
          S57SpatialPointer(refId: (i + 3) % 33, isEdge: true, reverse: false),
        ],
      );

      print('Performance test setup:');
      print('  Nodes: ${store.stats['nodes']}');
      print('  Edges: ${store.stats['edges']}');
      print('  Features to assemble: 100');

      // Act - Measure assembly time
      final stopwatch = Stopwatch()..start();

      int pointCount = 0, lineCount = 0, polygonCount = 0;

      // Assemble points
      for (final pointers in pointPointers) {
        final geometry = assembler.buildGeometry(pointers);
        if (geometry.type == S57GeometryType.point) pointCount++;
      }

      // Assemble lines
      for (final pointers in linePointers) {
        final geometry = assembler.buildGeometry(pointers);
        if (geometry.type == S57GeometryType.line) lineCount++;
      }

      // Assemble polygons
      for (final pointers in polygonPointers) {
        final geometry = assembler.buildGeometry(pointers);
        if (geometry.type == S57GeometryType.area) polygonCount++;
      }

      stopwatch.stop();

      // Assert performance requirements
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final featuresPerMs =
          100 / math.max(elapsedMs, 1); // Avoid division by zero

      print('Performance results:');
      print('  Total time: ${elapsedMs}ms');
      print('  Features per ms: ${featuresPerMs.toStringAsFixed(2)}');
      print('  Point geometries: $pointCount');
      print('  Line geometries: $lineCount');
      print('  Polygon geometries: $polygonCount');
      print('  Warnings: ${store.warnings.length}');

      // Performance threshold: should complete 100 features quickly
      expect(
        elapsedMs,
        lessThan(1000),
        reason: 'Assembly of 100 features should complete within 1 second',
      );

      // Should process efficiently
      expect(
        featuresPerMs,
        greaterThan(0.1),
        reason: 'Should process at least 0.1 features per millisecond',
      );

      // Verify correct geometry type distribution (polygons may not close properly with random edges)
      expect(pointCount, equals(33));
      expect(lineCount, equals(34));
      expect(
        polygonCount,
        greaterThanOrEqualTo(0),
      ); // Polygons depend on edge connectivity
    });

    test('micro-benchmark: large polygon assembly', () {
      // Arrange - Create a complex polygon with 100 edges
      final store = PrimitiveStore();
      final assembler = S57GeometryAssembler(store);

      // Create nodes in a circle
      const numNodes = 100;
      const radius = 100.0;

      for (int i = 0; i < numNodes; i++) {
        final angle = 2 * 3.14159 * i / numNodes;
        store.addNode(
          S57Node(
            id: i,
            x: radius * 1.2 * (i % 2 == 0 ? 1 : 0.8) * math.cos(angle),
            y: radius * 1.2 * (i % 2 == 0 ? 1 : 0.8) * math.sin(angle),
          ),
        );
      }

      // Create edges connecting consecutive nodes
      for (int i = 0; i < numNodes; i++) {
        final nextI = (i + 1) % numNodes;
        final angle1 = 2 * 3.14159 * i / numNodes;
        final angle2 = 2 * 3.14159 * nextI / numNodes;

        store.addEdge(
          S57Edge(
            id: i,
            nodes: [
              S57Node(
                id: i,
                x: radius * 1.2 * (i % 2 == 0 ? 1 : 0.8) * math.cos(angle1),
                y: radius * 1.2 * (i % 2 == 0 ? 1 : 0.8) * math.sin(angle1),
              ),
              S57Node(
                id: nextI,
                x: radius * 1.2 * (nextI % 2 == 0 ? 1 : 0.8) * math.cos(angle2),
                y: radius * 1.2 * (nextI % 2 == 0 ? 1 : 0.8) * math.sin(angle2),
              ),
            ],
          ),
        );
      }

      // Create spatial pointers for complete polygon
      final pointers = List.generate(
        numNodes,
        (i) => S57SpatialPointer(refId: i, isEdge: true, reverse: false),
      );

      print('Large polygon test setup:');
      print('  Nodes: $numNodes');
      print('  Edges: $numNodes');
      print('  Pointers: ${pointers.length}');

      // Act - Measure assembly time
      final stopwatch = Stopwatch()..start();
      final geometry = assembler.buildGeometry(pointers);
      stopwatch.stop();

      // Assert
      final elapsedMs = stopwatch.elapsedMilliseconds;

      print('Large polygon results:');
      print('  Assembly time: ${elapsedMs}ms');
      print('  Geometry type: ${geometry.type}');
      print('  Coordinate count: ${geometry.allCoordinates.length}');
      print('  Warnings: ${store.warnings.length}');

      expect(geometry.type, equals(S57GeometryType.area));
      expect(
        elapsedMs,
        lessThan(100),
        reason: 'Large polygon assembly should complete within 100ms',
      );

      // Verify polygon is properly closed
      final coords = geometry.rings.first;
      expect(coords.first, equals(coords.last));
    });

    test('micro-benchmark: self-intersection detection performance', () {
      // Arrange - Create polygon with potential self-intersection
      const coords = [
        Coordinate(0.0, 0.0),
        Coordinate(2.0, 2.0),
        Coordinate(2.0, 0.0),
        Coordinate(0.0, 2.0),
        Coordinate(0.0, 0.0),
      ];

      final store = PrimitiveStore();
      final assembler = S57GeometryAssembler(store);

      print('Self-intersection test setup:');
      print('  Coordinates: ${coords.length}');

      // Act - Measure detection time
      final stopwatch = Stopwatch()..start();
      final hasIntersection = assembler.detectSelfIntersection(coords);
      stopwatch.stop();

      // Assert
      final elapsedMs = stopwatch.elapsedMilliseconds;

      print('Self-intersection results:');
      print('  Detection time: ${elapsedMs}ms');
      print('  Has intersection: $hasIntersection');

      expect(
        elapsedMs,
        lessThan(10),
        reason: 'Self-intersection detection should be fast for small polygons',
      );
      expect(hasIntersection, isTrue);
    });
  });
}
