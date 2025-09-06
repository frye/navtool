import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';
import '../../../utils/s57_geometry_test_fixtures.dart';
// Import math for trigonometric functions
import 'dart:math' as math;

void main() {
  group('S57 Geometry Self-Intersection Warning', () {
    late S57GeometryTestFixtures fixtures;
    late S57GeometryAssembler assembler;

    setUpAll(() async {
      fixtures = await S57GeometryTestFixtures.load();
      assembler = S57GeometryAssembler(fixtures.store);
    });

    test('should detect self-intersection in bow-tie polygon', () {
      // Arrange
      final selfIntersectingCoords = fixtures.createSelfIntersectingPolygon();

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        selfIntersectingCoords,
      );

      // Assert
      expect(hasSelfIntersection, isTrue);
    });

    test('should validate simple polygon without self-intersection', () {
      // Arrange - Simple square polygon
      final simpleCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(1.0, 1.0),
        const Coordinate(0.0, 1.0),
        const Coordinate(0.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        simpleCoords,
      );

      // Assert
      expect(hasSelfIntersection, isFalse);
    });

    test('should validate geometry with self-intersection check enabled', () {
      // Arrange
      final selfIntersectingCoords = fixtures.createSelfIntersectingPolygon();
      final polygon = S57Geometry.polygon([selfIntersectingCoords]);

      // Act
      final validationResult = S57GeometryValidator.validate(
        polygon,
        checkSelfIntersection: true,
      );

      // Assert
      expect(validationResult.hasWarnings, isTrue);
      expect(
        validationResult.warnings.any((w) => w.type == 'self_intersection'),
        isTrue,
      );
      expect(
        validationResult.warnings.any(
          (w) => w.message.contains('Self-intersection detected'),
        ),
        isTrue,
      );
    });

    test(
      'should not detect self-intersection in valid polygon when enabled',
      () {
        // Arrange - Use DEPARE polygon from fixtures
        final pointers = fixtures.getFeaturePointers('DEPARE');
        final geometry = assembler.buildGeometry(pointers);

        // Act
        final validationResult = S57GeometryValidator.validate(
          geometry,
          checkSelfIntersection: true,
        );

        // Assert
        expect(
          validationResult.warnings.any((w) => w.type == 'self_intersection'),
          isFalse,
        );
      },
    );

    test('should skip self-intersection check when disabled', () {
      // Arrange
      final selfIntersectingCoords = fixtures.createSelfIntersectingPolygon();
      final polygon = S57Geometry.polygon([selfIntersectingCoords]);

      // Act
      final validationResult = S57GeometryValidator.validate(
        polygon,
        checkSelfIntersection: false, // Disabled
      );

      // Assert
      expect(
        validationResult.warnings.any((w) => w.type == 'self_intersection'),
        isFalse,
      );
    });

    test('should handle triangle without self-intersection', () {
      // Arrange
      final triangleCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(0.5, 1.0),
        const Coordinate(0.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        triangleCoords,
      );

      // Assert
      expect(hasSelfIntersection, isFalse);
    });

    test('should handle figure-eight polygon with self-intersection', () {
      // Arrange - Figure-eight shape
      final figureEightCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 1.0),
        const Coordinate(2.0, 0.0),
        const Coordinate(2.0, 2.0),
        const Coordinate(1.0, 1.0), // Crosses previous segment
        const Coordinate(0.0, 2.0),
        const Coordinate(0.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        figureEightCoords,
      );

      // Assert
      expect(hasSelfIntersection, isTrue);
    });

    test('should handle degenerate polygon (too few coordinates)', () {
      // Arrange
      final degenerateCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        degenerateCoords,
      );

      // Assert
      expect(hasSelfIntersection, isFalse); // Too few points to self-intersect
    });

    test('should detect adjacent segment intersection correctly', () {
      // Arrange - Create segments that share an endpoint but don't intersect
      final coords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(1.0, 1.0),
        const Coordinate(0.0, 1.0),
        const Coordinate(0.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(coords);

      // Assert
      expect(
        hasSelfIntersection,
        isFalse,
      ); // Adjacent segments share endpoints but don't cross
    });

    test('should validate complex polygon with multiple rings', () {
      // Arrange - Polygon with hole (no self-intersection)
      final outerRing = [
        const Coordinate(0.0, 0.0),
        const Coordinate(4.0, 0.0),
        const Coordinate(4.0, 4.0),
        const Coordinate(0.0, 4.0),
        const Coordinate(0.0, 0.0),
      ];

      final innerRing = [
        const Coordinate(1.0, 1.0),
        const Coordinate(3.0, 1.0),
        const Coordinate(3.0, 3.0),
        const Coordinate(1.0, 3.0),
        const Coordinate(1.0, 1.0),
      ];

      final polygon = S57Geometry.polygon([outerRing, innerRing]);

      // Act
      final validationResult = S57GeometryValidator.validate(
        polygon,
        checkSelfIntersection: true,
      );

      // Assert
      expect(
        validationResult.warnings.any((w) => w.type == 'self_intersection'),
        isFalse,
      );
    });

    test('should provide detailed warning context for self-intersection', () {
      // Arrange
      final selfIntersectingCoords = fixtures.createSelfIntersectingPolygon();
      final polygon = S57Geometry.polygon([selfIntersectingCoords]);

      // Act
      final validationResult = S57GeometryValidator.validate(
        polygon,
        checkSelfIntersection: true,
      );

      // Assert
      final selfIntersectionWarning = validationResult.warnings.firstWhere(
        (w) => w.type == 'self_intersection',
      );

      expect(selfIntersectionWarning.context.containsKey('ring'), isTrue);
      expect(selfIntersectionWarning.context['ring'], equals(0));
      expect(selfIntersectionWarning.message, contains('ring 0'));
    });

    test('should handle edge case with collinear points', () {
      // Arrange - Polygon with some collinear points
      final collinearCoords = [
        const Coordinate(0.0, 0.0),
        const Coordinate(1.0, 0.0),
        const Coordinate(2.0, 0.0), // Collinear with previous two
        const Coordinate(2.0, 1.0),
        const Coordinate(0.0, 1.0),
        const Coordinate(0.0, 0.0),
      ];

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(
        collinearCoords,
      );

      // Assert
      expect(
        hasSelfIntersection,
        isFalse,
      ); // Collinear points don't constitute intersection
    });

    test('should perform within reasonable time for moderate polygon size', () {
      // Arrange - Create polygon with 20 vertices (reasonable test size)
      final coords = <Coordinate>[];
      const numVertices = 20;
      const radius = 10.0;

      for (int i = 0; i < numVertices; i++) {
        final angle = 2 * 3.14159 * i / numVertices;
        coords.add(
          Coordinate(
            radius *
                1.2 *
                (i % 2 == 0 ? 1 : 0.8) *
                math.cos(angle), // Slightly irregular
            radius * 1.2 * (i % 2 == 0 ? 1 : 0.8) * math.sin(angle),
          ),
        );
      }
      coords.add(coords.first); // Close polygon

      final stopwatch = Stopwatch()..start();

      // Act
      final hasSelfIntersection = assembler.detectSelfIntersection(coords);

      stopwatch.stop();

      // Assert
      expect(hasSelfIntersection, isFalse);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason:
            'Self-intersection check should complete quickly for moderate polygon sizes',
      );
    });
  });
}
