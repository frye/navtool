import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import '../../../../lib/core/models/gps_position.dart';
import '../../../../lib/core/models/gps_signal_quality.dart';
import '../../../../lib/core/services/gps_service.dart';
import '../../../../lib/core/state/providers.dart' show gpsServiceProvider;
import '../../../../lib/features/gps/widgets/gps_status_indicator.dart';
import '../../../../lib/features/gps/providers/gps_providers.dart';

import 'gps_status_indicator_test.mocks.dart';

@GenerateMocks([GpsService])
void main() {
  group('GpsStatusIndicator Widget Tests', () {
    late MockGpsService mockGpsService;

    setUp(() {
      mockGpsService = MockGpsService();
    });

    Widget createTestWidget({
      bool showDetails = false,
      bool isCompact = false,
    }) {
      return ProviderScope(
        overrides: [
          gpsServiceProvider.overrideWithValue(mockGpsService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GpsStatusIndicator(
              showDetails: showDetails,
              isCompact: isCompact,
            ),
          ),
        ),
      );
    }

    group('Compact GPS Status Indicator', () {
      testWidgets('should show GPS icon and status', (WidgetTester tester) async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 5.0,
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => GpsSignalQuality.fromAccuracy(5.0),
        );

        // Act
        await tester.pumpWidget(createTestWidget(isCompact: true));
        await tester.pump();

        // Assert
        expect(find.byType(GpsStatusIndicator), findsOneWidget);
        expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget); // Marine grade indicator
      });

      testWidgets('should show error state when GPS unavailable', (WidgetTester tester) async {
        // Arrange
        when(mockGpsService.startLocationTracking()).thenThrow(Exception('GPS error'));

        // Act
        await tester.pumpWidget(createTestWidget(isCompact: true));
        await tester.pump();

        // Assert
        expect(find.byIcon(Icons.gps_off), findsOneWidget);
        expect(find.text('No GPS'), findsOneWidget);
      });
    });

    group('Detailed GPS Status Panel', () {
      testWidgets('should show detailed GPS information', (WidgetTester tester) async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 8.0,
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => GpsSignalQuality.fromAccuracy(8.0),
        );

        // Act
        await tester.pumpWidget(createTestWidget(showDetails: true));
        await tester.pump();

        // Assert
        expect(find.text('GPS'), findsOneWidget);
        expect(find.text('Good'), findsOneWidget); // Signal strength
        expect(find.text('Accuracy'), findsOneWidget);
        expect(find.text('±8.0m'), findsOneWidget);
        expect(find.text('Marine Grade'), findsOneWidget);
        expect(find.text('Yes'), findsOneWidget); // 8m is marine grade
      });

      testWidgets('should show loading state while acquiring GPS', (WidgetTester tester) async {
        // Arrange
        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(null).cast<GpsPosition>(),
        );

        // Act
        await tester.pumpWidget(createTestWidget(showDetails: true));
        await tester.pump();

        // Assert
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Acquiring...'), findsOneWidget);
      });
    });

    group('Signal Quality Display', () {
      testWidgets('should show excellent signal for high accuracy', (WidgetTester tester) async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 3.0, // Excellent accuracy
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => GpsSignalQuality.fromAccuracy(3.0),
        );

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Assert
        expect(find.text('Excellent'), findsOneWidget);
        expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
      });

      testWidgets('should show poor signal for low accuracy', (WidgetTester tester) async {
        // Arrange
        final testPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 30.0, // Poor accuracy
        );

        when(mockGpsService.startLocationTracking()).thenAnswer((_) async => {});
        when(mockGpsService.getLocationStream()).thenAnswer(
          (_) => Stream.value(testPosition),
        );
        when(mockGpsService.logPosition(any)).thenAnswer((_) async => {});
        when(mockGpsService.assessSignalQuality(testPosition)).thenAnswer(
          (_) async => GpsSignalQuality.fromAccuracy(30.0),
        );

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Assert
        expect(find.text('Poor'), findsOneWidget);
        expect(find.byIcon(Icons.gps_not_fixed), findsOneWidget);
        expect(find.byIcon(Icons.warning), findsOneWidget); // Not marine grade
      });
    });
  });
}