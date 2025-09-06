import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';

void main() {
  group('S57 Geometry Line Orientation', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should create line geometry with correct orientation (COALNE)', () {
      // Arrange
      final pointers = fixtures.getFeaturePointers('COALNE');
      final expectedCoords = fixtures.getExpectedCoordinates('COALNE');
      final expectedType = fixtures.getExpectedGeometryType('COALNE');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));
      expect(expectedType, equals('line'));

      // Verify coordinate sequence matches the updated expectation (4 coordinates)
      expect(geometry.rings.length, equals(1));
      final actualCoords = fixtures.coordinateListToLists(geometry.rings.first);

      expect(actualCoords.length, equals(expectedCoords.length));
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

      // Verify no warnings for valid line
      expect(fixtures.store.warnings, isEmpty);
    });

    test('should respect reverse orientation flag', () {
      // Arrange - Create line with forward then reverse edge
      final pointers = [
        const S57SpatialPointer(
          refId: 1,
          isEdge: true,
          reverse: false,
        ), // E1 forward
        const S57SpatialPointer(
          refId: 2,
          isEdge: true,
          reverse: true,
        ), // E2 reversed
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(
        coords.length,
        equals(4),
      ); // Four coordinates: start, middle, third, end

      // E1 forward: (0,0) -> (10,0)
      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0));
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0));

      // E2 reversed: (10,10) -> (10,0)
      expect(coords[2].x, equals(10.0));
      expect(coords[2].y, equals(10.0));
      expect(coords[3].x, equals(10.0));
      expect(coords[3].y, equals(0.0));
    });

    test('should handle single edge line', () {
      // Arrange - Single edge pointer
      final pointers = [
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: false),
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(coords.length, equals(2)); // Start and end of edge

      expect(coords[0].x, equals(0.0));
      expect(coords[0].y, equals(0.0));
      expect(coords[1].x, equals(10.0));
      expect(coords[1].y, equals(0.0));
    });

    test('should handle reverse orientation of single edge', () {
      // Arrange - Single edge pointer with reverse flag
      final pointers = [
        const S57SpatialPointer(refId: 1, isEdge: true, reverse: true),
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;
      expect(coords.length, equals(2));

      // Should be reversed: (10,0) -> (0,0)
      expect(coords[0].x, equals(10.0));
      expect(coords[0].y, equals(0.0));
      expect(coords[1].x, equals(0.0));
      expect(coords[1].y, equals(0.0));
    });

    test('should handle missing edge with warning', () {
      // Arrange - Pointer to non-existent edge
      final pointers = [
        const S57SpatialPointer(refId: 999, isEdge: true, reverse: false),
      ];

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(
        geometry.type,
        equals(S57GeometryType.point),
      ); // Falls back to point
      expect(fixtures.store.warnings, isNotEmpty);
      expect(
        fixtures.store.warnings.any((w) => w.contains('Missing edge 999')),
        isTrue,
      );
    });

    test('should create contiguous line with proper stitching', () {
      // Arrange - Test contiguous coastline without reversal
      final pointers = fixtures.getFeaturePointers('COALNE_CONTIGUOUS');
      final expectedCoords = fixtures.getExpectedCoordinates(
        'COALNE_CONTIGUOUS',
      );

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final actualCoords = fixtures.coordinateListToLists(geometry.rings.first);
      expect(actualCoords.length, equals(3)); // Should be stitched properly

      // Verify coordinate sequence
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

      // Verify no warnings
      expect(fixtures.store.warnings, isEmpty);
    });

    test('should verify first and last coordinates for orientation test', () {
      // Arrange - COALNE line with specific orientation
      final pointers = fixtures.getFeaturePointers('COALNE');

      // Act
      final geometry = assembler.buildGeometry(pointers);

      // Assert
      expect(geometry.type, equals(S57GeometryType.line));

      final coords = geometry.rings.first;

      // First coordinate should be start of E1
      expect(coords.first.x, equals(0.0));
      expect(coords.first.y, equals(0.0));

      // Last coordinate should be end of E2 reversed (10,0)
      expect(coords.last.x, equals(10.0));
      expect(coords.last.y, equals(0.0));
    });
  });
}
