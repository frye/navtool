import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';

void main() {
  group('S57 Geometry Polygon Closure', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should create closed polygon geometry (DEPARE)', () {
      // Arrange
      final pointers = fixtures.getFeaturePointers('DEPARE');
      final expectedCoords = fixtures.getExpectedCoordinates('DEPARE');
      final expectedType = fixtures.getExpectedGeometryType('DEPARE');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.area));
      expect(expectedType, equals('polygon'));

      // Verify polygon structure
      expect(geometry.rings.length, equals(1)); // Single outer ring

      final ring = geometry.rings.first;
      final actualCoords = fixtures.coordinateListToLists(ring);

      expect(actualCoords.length, equals(expectedCoords.length));

      // Verify all coordinates match
      for (int i = 0; i < expectedCoords.length; i++) {
        expect(
          actualCoords[i][0],
          equals(expectedCoords[i][0]),
          reason: 'X coordinate at index $i',
        );
        expect(
          actualCoords[i][1],
          equals(expectedCoords[i][1]),
          reason: 'Y coordinate at index $i',
        );
      }

      // Verify no warnings for valid polygon
      expect(fixtures.store.warnings, isEmpty);
    });

    test('should ensure polygon is closed (first == last)', () {
      // Arrange
      final pointers = fixtures.getFeaturePointers('DEPARE');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.area));

      final ring = geometry.rings.first;
      expect(ring.length, greaterThan(2));

      // First and last coordinates should be equal
      expect(ring.first, equals(ring.last));
      expect(ring.first.x, equals(ring.last.x));
      expect(ring.first.y, equals(ring.last.y));
    });

    test('should auto-close polygon when coordinates are not closed', () {
      // Arrange - Create unclosed polygon (missing final edge)
      final pointers = [
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: false), // E1
        const S57SpatialPointer(refId: 2, isEdge: true, reverse: false), // E2
        const S57SpatialPointer(refId: 3, isEdge: true, reverse: false), // E3
        // Missing E4 that would close the polygon
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert - Should create line since not closed
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(coords.length, equals(4)); // Start + 3 edges = 4 coordinates

      // Should not be closed
      expect(coords.first, isNot(equals(coords.last)));
    });

    test('should handle nearly-closed polygon with auto-closure warning', () {
      // Arrange - Create nearly closed polygon (within tolerance)
      final store = PrimitiveStore();

      // Create nodes that are very close but not identical
      store.addNode(const S57Node(id: 1, x: 0.0, y: 0.0));
      store.addNode(const S57Node(id: 2, x: 1.0, y: 0.0));
      store.addNode(const S57Node(id: 3, x: 1.0, y: 1.0));
      store.addNode(
        const S57Node(id: 4, x: 0.0000001, y: 0.0000001),
      ); // Very close to (0,0)

      // Create edge that almost closes
      store.addEdge(
        const S57Edge(
          id: 1,
          nodes: [
            S57Node(id: 3, x: 1.0, y: 1.0),
            S57Node(id: 4, x: 0.0000001, y: 0.0000001),
          ],
        ),
      );

      final testAssembler = S57GeometryAssembler(store);

      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: false,
          reverse: false,
        ), // Start node
        const S57SpatialPointer(
          refId: 2,
          isEdge: false,
          reverse: false,
        ), // Corner 1
        const S57SpatialPointer(
          refId: 3,
          isEdge: false,
          reverse: false,
        ), // Corner 2
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // Almost close
      ];

      // Act
      final geometry = testAssembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.area));
      expect(
        store.warnings.any((w) => w.contains('Auto-closing polygon')),
        isTrue,
      );

      // Should be closed after auto-closure
      final ring = geometry.rings.first;
      expect(ring.first, equals(ring.last));
    });

    test('should apply ensureClosed utility correctly', () {
      // Arrange
      final openCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(1.0, 1.0),
        const Coordinate(0.0, 1.0),
      ];

      // Act
      final closedCoords = ensureClosed(openCoords);

      // Assert
      expect(closedCoords.length, equals(5));
      expect(closedCoords.first, equals(closedCoords.last));
      expect(closedCoords[0], equals(const Coordinate(0.0, 0.0)));
      expect(closedCoords[4], equals(const Coordinate(0.0, 0.0)));
    });

    test('should not duplicate closure if already closed', () {
      // Arrange
      final alreadyClosedCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(1.0, 1.0),
        const Coordinate(0.0, 1.0),
        const Coordinate(0.0, 0.0), // Already closed
      ];

      // Act
      final result = ensureClosed(alreadyClosedCoords);

      // Assert
      expect(result.length, equals(5)); // Should not add another closure point
      expect(result, equals(alreadyClosedCoords));
      expect(result.first, equals(result.last));
    });

    test('should handle empty coordinate list', () {
      // Arrange
      final emptyCoords = <Coordinate>[];

      // Act
      final result = ensureClosed(emptyCoords);

      // Assert
      expect(result, isEmpty);
    });

    test('should create polygon with multiple rings', () {
      // Arrange - Test polygon factory method
      final outerRing = [
        const Coordinate(0.0, 0.0),
        const Coordinate(2.0, 0.0),
        const Coordinate(2.0, 2.0),
        const Coordinate(0.0, 2.0),
        const Coordinate(0.0, 0.0),
      ];

      final innerRing = [
        const Coordinate(0.5, 0.5),
        const Coordinate(1.5, 0.5),
        const Coordinate(1.5, 1.5),
        const Coordinate(0.5, 1.5),
        const Coordinate(0.5, 0.5),
      ];

      // Act
      final geometry = S57Geometry.polygon([outerRing, innerRing]);

      // Assert
      expect(geometry.type, equals(S57GeometryType.area));
      expect(geometry.rings.length, equals(2));
      expect(geometry.rings[0], equals(outerRing));
      expect(geometry.rings[1], equals(innerRing));
    });
  });
}
