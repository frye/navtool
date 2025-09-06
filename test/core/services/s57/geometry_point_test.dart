import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';

void main() {
  group('S57 Geometry Point Assembly', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should create point geometry from single node (SOUNDG)', () {
      // Arrange
      final pointers = fixtures.getFeaturePointers('SOUNDG');
      final expectedCoords = fixtures.getExpectedCoordinates('SOUNDG');
      final expectedType = fixtures.getExpectedGeometryType('SOUNDG');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.point));
      expect(expectedType, equals('point'));

      // Verify coordinates
      expect(geometry.rings.length, equals(1));
      expect(geometry.rings.first.length, equals(1));

      final actualCoord = geometry.rings.first.first;
      final expectedCoord = expectedCoords.first;

      expect(actualCoord.x, equals(expectedCoord[0]));
      expect(actualCoord.y, equals(expectedCoord[1]));

      // Verify no warnings for valid point
      expect(fixtures.store.warnings, isEmpty);
    });

    test('should handle missing node with warning', () {
      // Arrange - Create pointer to non-existent node
      final pointers = [
        const S57SpatialPointer(refId: 999, isEdge: false, reverse: false),
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.point));
      expect(fixtures.store.warnings, isNotEmpty);
      expect(fixtures.store.warnings.first, contains('Missing node 999'));

      // Should use synthetic fallback
      final coord = geometry.rings.first.first;
      expect(coord.x, equals(0.0));
      expect(coord.y, equals(0.0));
    });

    test('should handle empty pointer list with warning', () {
      // Arrange
      final pointers = <S57SpatialPointer>[];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.point));
      expect(fixtures.store.warnings, isNotEmpty);
      expect(
        fixtures.store.warnings.first,
        contains('Empty spatial pointer list'),
      );

      // Should use synthetic fallback
      final coord = geometry.rings.first.first;
      expect(coord.x, equals(0.0));
      expect(coord.y, equals(0.0));
    });

    test('should convert point to S57Coordinate list correctly', () {
      // Arrange
      final pointers = fixtures.getFeaturePointers('SOUNDG');

      // Act
      final geometry = assembler.buildGeometry(pointers);
      final s57Coords = geometry.toS57Coordinates();

      // Assert
      expect(s57Coords.length, equals(1));
      expect(s57Coords.first.longitude, equals(10.0));
      expect(s57Coords.first.latitude, equals(10.0));
    });

    test('should create point from S57Node correctly', () {
      // Arrange
      const node = S57Node(id: 42, x: 5.5, y: 7.3);

      // Act
      final coord = Coordinate(node.x, node.y);
      final geometry = S57Geometry.point(coord);

      // Assert
      expect(geometry.type, equals(S57GeometryType.point));
      expect(geometry.rings.length, equals(1));
      expect(geometry.rings.first.length, equals(1));

      final actualCoord = geometry.rings.first.first;
      expect(actualCoord.x, equals(5.5));
      expect(actualCoord.y, equals(7.3));
    });
  });
}
