import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../../../lib/features/charts/widgets/vessel_position_overlay.dart';
import '../../../../lib/core/services/coordinate_transform.dart';
import '../../../../lib/core/models/gps_position.dart';
import '../../../../lib/core/models/chart_models.dart';
import '../../../../lib/core/state/providers.dart';
import '../../../../lib/core/services/gps_service.dart';

import 'vessel_position_overlay_test.mocks.dart';

@GenerateMocks([GpsService])
void main() {
  group('VesselPositionOverlay', () {
    late MockGpsService mockGpsService;
    late CoordinateTransform transform;

    setUp(() {
      mockGpsService = MockGpsService();
      transform = CoordinateTransform(
        zoom: 12.0,
        center: const LatLng(47.6062, -122.3321),
        screenSize: const Size(800, 600),
      );
    });

    testWidgets('should display vessel position when GPS is available', (tester) async {
      // Arrange
      final testPosition = GpsPosition(
        latitude: 47.6062,
        longitude: -122.3321,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        heading: 45.0,
        speed: 2.5,
      );

      when(mockGpsService.getCurrentPosition())
          .thenAnswer((_) async => testPosition);

      // Create a test app with providers
      final app = ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VesselPositionOverlay(
              coordinateTransform: transform,
            ),
          ),
        ),
      );

      // Act
      await tester.pumpWidget(app);
      await tester.pump(); // Allow futures to complete

      // Assert
      expect(find.byType(VesselPositionOverlay), findsOneWidget);
      // The custom paint widget should be present
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('should hide overlay when no GPS position available', (tester) async {
      // Arrange
      when(mockGpsService.getCurrentPosition())
          .thenAnswer((_) async => null);

      // Create a test app with providers  
      final app = ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VesselPositionOverlay(
              coordinateTransform: transform,
            ),
          ),
        ),
      );

      // Act
      await tester.pumpWidget(app);
      await tester.pump();

      // Assert
      expect(find.byType(VesselPositionOverlay), findsOneWidget);
      // Should show SizedBox.shrink() when no position
      expect(find.byType(CustomPaint), findsNothing);
    });

    testWidgets('should handle GPS errors gracefully', (tester) async {
      // Arrange
      when(mockGpsService.getCurrentPosition())
          .thenThrow(Exception('GPS error'));

      final app = ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VesselPositionOverlay(
              coordinateTransform: transform,
            ),
          ),
        ),
      );

      // Act
      await tester.pumpWidget(app);
      await tester.pump();

      // Assert - Should not crash and show empty overlay
      expect(find.byType(VesselPositionOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsNothing);
    });

    group('VesselOverlayPainter', () {
      test('should create painter with required parameters', () {
        // Arrange
        final position = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
        );

        final painter = VesselOverlayPainter(
          position: position,
          coordinateTransform: transform,
          showTrack: true,
          showHeading: true,
          showAccuracyCircle: true,
          context: MockBuildContext(),
        );

        // Assert
        expect(painter.position, equals(position));
        expect(painter.showTrack, isTrue);
        expect(painter.showHeading, isTrue);
        expect(painter.showAccuracyCircle, isTrue);
      });

      test('should indicate repaint when position changes', () {
        // Arrange
        final position1 = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
        );

        final position2 = GpsPosition(
          latitude: 47.6072,
          longitude: -122.3331,
          timestamp: DateTime.now(),
        );

        final painter1 = VesselOverlayPainter(
          position: position1,
          coordinateTransform: transform,
          showTrack: true,
          showHeading: true,
          showAccuracyCircle: true,
          context: MockBuildContext(),
        );

        final painter2 = VesselOverlayPainter(
          position: position2,
          coordinateTransform: transform,
          showTrack: true,
          showHeading: true,
          showAccuracyCircle: true,
          context: MockBuildContext(),
        );

        // Act & Assert
        expect(painter1.shouldRepaint(painter2), isTrue);
      });
    });
  });
}

// Mock BuildContext for testing
class MockBuildContext extends Mock implements BuildContext {
  @override
  Widget get widget => Container();
}