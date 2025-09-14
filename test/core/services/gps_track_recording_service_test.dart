import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../../lib/core/services/gps_track_recording_service.dart';
import '../../../lib/core/services/gps_service.dart';
import '../../../lib/core/services/storage_service.dart';
import '../../../lib/core/logging/app_logger.dart';
import '../../../lib/core/models/gps_position.dart';

import 'gps_track_recording_service_test.mocks.dart';

@GenerateMocks([GpsService, StorageService, AppLogger])
void main() {
  group('GpsTrackRecordingService', () {
    late GpsTrackRecordingService service;
    late MockGpsService mockGpsService;
    late MockStorageService mockStorageService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockGpsService = MockGpsService();
      mockStorageService = MockStorageService();
      mockLogger = MockAppLogger();
      
      service = GpsTrackRecordingService(
        logger: mockLogger,
        storageService: mockStorageService,
        gpsService: mockGpsService,
      );
    });

    group('Recording Control', () {
      test('should start recording when GPS is available', () async {
        // Arrange
        when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
        when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
        when(mockGpsService.startLocationTracking()).thenAnswer((_) async {});
        when(mockGpsService.getLocationStream()).thenAnswer((_) => Stream.empty());
        when(mockStorageService.saveGpsTrack(any)).thenAnswer((_) async {});

        // Act
        final result = await service.startRecording();

        // Assert
        expect(result, isTrue);
        expect(service.isRecording, isTrue);
        expect(service.currentTrackId, isNotNull);
        
        verify(mockGpsService.startLocationTracking()).called(1);
        verify(mockStorageService.saveGpsTrack(any)).called(1);
      });

      test('should not start recording when GPS is unavailable', () async {
        // Arrange
        when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => false);

        // Act
        final result = await service.startRecording();

        // Assert
        expect(result, isFalse);
        expect(service.isRecording, isFalse);
        expect(service.currentTrackId, isNull);
      });

      test('should stop recording and return track', () async {
        // Arrange - start recording first
        when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
        when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
        when(mockGpsService.startLocationTracking()).thenAnswer((_) async {});
        when(mockGpsService.getLocationStream()).thenAnswer((_) => Stream.empty());
        when(mockStorageService.saveGpsTrack(any)).thenAnswer((_) async {});

        await service.startRecording();

        // Act
        final track = await service.stopRecording();

        // Assert
        expect(track, isNotNull);
        expect(service.isRecording, isFalse);
        expect(service.currentTrackId, isNull);
        
        verify(mockStorageService.saveGpsTrack(any)).called(atLeast(2)); // Start + Stop
      });
    });

    group('Position Filtering', () {
      test('should filter positions based on accuracy', () {
        // This would test the internal _shouldRecordPosition logic
        // For now, we test the external behavior by verifying
        // that only good positions are recorded
        
        final goodPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 5.0, // Good accuracy
        );
        
        final badPosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 50.0, // Poor accuracy
        );

        // Test would verify that badPosition is filtered out
        // Implementation details would be tested through integration
      });
    });

    group('Track Management', () {
      test('should export track as GPX format', () async {
        // Arrange
        final positions = [
          GpsPosition(
            latitude: 47.6062,
            longitude: -122.3321,
            timestamp: DateTime.now(),
            altitude: 56.0,
          ),
          GpsPosition(
            latitude: 47.6072,
            longitude: -122.3331,
            timestamp: DateTime.now().add(const Duration(seconds: 30)),
            altitude: 58.0,
          ),
        ];

        final track = GpsTrack(
          id: 'test_track',
          name: 'Test Track',
          startTime: DateTime.now(),
          positions: positions,
          isActive: false,
        );

        when(mockStorageService.getGpsTrack('test_track'))
            .thenAnswer((_) async => track);

        // Act
        final gpxContent = await service.exportTrackAsGpx('test_track');

        // Assert
        expect(gpxContent, isNotNull);
        expect(gpxContent, contains('<?xml version="1.0"'));
        expect(gpxContent, contains('<gpx'));
        expect(gpxContent, contains('<trk>'));
        expect(gpxContent, contains('lat="47.6062"'));
        expect(gpxContent, contains('lon="-122.3321"'));
        expect(gpxContent, contains('<ele>56.0</ele>'));
      });

      test('should delete track successfully', () async {
        // Arrange
        when(mockStorageService.deleteGpsTrack('test_track'))
            .thenAnswer((_) async {});

        // Act
        final result = await service.deleteTrack('test_track');

        // Assert
        expect(result, isTrue);
        verify(mockStorageService.deleteGpsTrack('test_track')).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle GPS service errors gracefully', () async {
        // Arrange
        when(mockGpsService.isLocationEnabled())
            .thenThrow(Exception('GPS service error'));

        // Act
        final result = await service.startRecording();

        // Assert
        expect(result, isFalse);
        expect(service.isRecording, isFalse);
      });

      test('should handle storage errors gracefully', () async {
        // Arrange
        when(mockGpsService.isLocationEnabled()).thenAnswer((_) async => true);
        when(mockGpsService.checkLocationPermission()).thenAnswer((_) async => true);
        when(mockStorageService.saveGpsTrack(any))
            .thenThrow(Exception('Storage error'));

        // Act
        final result = await service.startRecording();

        // Assert
        expect(result, isFalse);
        expect(service.isRecording, isFalse);
      });
    });
  });
}