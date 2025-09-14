import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/gps_position.dart';
import '../../models/position_history.dart';
import '../../logging/app_logger.dart';
import '../../services/storage_service.dart';
import '../../services/gps_service.dart';

/// Service for recording and managing GPS tracks
class GpsTrackRecordingService {
  final AppLogger _logger;
  final StorageService _storageService;
  final GpsService _gpsService;
  
  StreamSubscription<GpsPosition>? _trackingSubscription;
  bool _isRecording = false;
  String? _currentTrackId;
  final List<GpsPosition> _currentTrackPositions = [];
  
  // Track recording settings
  static const Duration _minPointInterval = Duration(seconds: 5);
  static const double _minDistanceMeters = 5.0;
  static const double _maxAccuracyMeters = 20.0;
  
  GpsPosition? _lastRecordedPosition;
  
  GpsTrackRecordingService({
    required AppLogger logger,
    required StorageService storageService, 
    required GpsService gpsService,
  }) : _logger = logger,
       _storageService = storageService,
       _gpsService = gpsService;

  /// Whether track recording is currently active
  bool get isRecording => _isRecording;

  /// Current track ID if recording
  String? get currentTrackId => _currentTrackId;

  /// Number of positions in current track
  int get currentTrackPointCount => _currentTrackPositions.length;

  /// Duration of current track
  Duration get currentTrackDuration {
    if (_currentTrackPositions.isEmpty) return Duration.zero;
    return _currentTrackPositions.last.timestamp
        .difference(_currentTrackPositions.first.timestamp);
  }

  /// Start recording a new GPS track
  Future<bool> startRecording({String? trackName}) async {
    try {
      if (_isRecording) {
        _logger.warning('Track recording already in progress');
        return false;
      }

      _logger.info('Starting GPS track recording');
      
      // Check if GPS is available
      if (!await _gpsService.isLocationEnabled() || 
          !await _gpsService.checkLocationPermission()) {
        _logger.error('GPS not available for track recording');
        return false;
      }

      // Generate new track ID
      _currentTrackId = 'track_${DateTime.now().millisecondsSinceEpoch}';
      _currentTrackPositions.clear();
      _lastRecordedPosition = null;

      // Create track record in database
      final trackRecord = GpsTrack(
        id: _currentTrackId!,
        name: trackName ?? 'Track ${DateTime.now().toString().substring(0, 19)}',
        startTime: DateTime.now(),
        positions: [],
        isActive: true,
      );
      
      await _storageService.saveGpsTrack(trackRecord);

      // Start GPS tracking
      await _gpsService.startLocationTracking();
      
      // Subscribe to position updates
      _trackingSubscription = _gpsService.getLocationStream().listen(
        _onPositionUpdate,
        onError: _onTrackingError,
      );

      _isRecording = true;
      _logger.info('GPS track recording started with ID: $_currentTrackId');
      return true;

    } catch (error) {
      _logger.error('Failed to start track recording', exception: error);
      await _cleanup();
      return false;
    }
  }

  /// Stop the current GPS track recording
  Future<GpsTrack?> stopRecording() async {
    try {
      if (!_isRecording) {
        _logger.warning('No track recording in progress');
        return null;
      }

      _logger.info('Stopping GPS track recording');

      // Cancel position subscription
      await _trackingSubscription?.cancel();
      _trackingSubscription = null;

      // Create final track record
      final finalTrack = GpsTrack(
        id: _currentTrackId!,
        name: await _getTrackName(_currentTrackId!),
        startTime: _currentTrackPositions.isNotEmpty 
            ? _currentTrackPositions.first.timestamp
            : DateTime.now(),
        endTime: _currentTrackPositions.isNotEmpty
            ? _currentTrackPositions.last.timestamp 
            : DateTime.now(),
        positions: List.from(_currentTrackPositions),
        isActive: false,
        statistics: _calculateTrackStatistics(),
      );

      // Save final track to database
      await _storageService.saveGpsTrack(finalTrack);

      _logger.info(
        'GPS track recording completed: ${finalTrack.positions.length} points, '
        '${finalTrack.statistics?.totalDistance.toStringAsFixed(0)}m',
      );

      await _cleanup();
      return finalTrack;

    } catch (error) {
      _logger.error('Failed to stop track recording', exception: error);
      await _cleanup();
      return null;
    }
  }

  /// Pause track recording without stopping
  Future<void> pauseRecording() async {
    if (!_isRecording) return;

    _logger.info('Pausing GPS track recording');
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
    
    // Mark current position as pause point
    if (_currentTrackPositions.isNotEmpty) {
      final lastPos = _currentTrackPositions.last;
      _currentTrackPositions.add(lastPos.copyWith(
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Resume paused track recording
  Future<bool> resumeRecording() async {
    if (!_isRecording) return false;

    try {
      _logger.info('Resuming GPS track recording');
      
      // Restart position stream
      _trackingSubscription = _gpsService.getLocationStream().listen(
        _onPositionUpdate,
        onError: _onTrackingError,
      );
      
      return true;
    } catch (error) {
      _logger.error('Failed to resume track recording', exception: error);
      return false;
    }
  }

  /// Get all saved tracks
  Future<List<GpsTrack>> getAllTracks() async {
    try {
      return await _storageService.getAllGpsTracks();
    } catch (error) {
      _logger.error('Failed to retrieve GPS tracks', exception: error);
      return [];
    }
  }

  /// Get a specific track by ID
  Future<GpsTrack?> getTrack(String trackId) async {
    try {
      return await _storageService.getGpsTrack(trackId);
    } catch (error) {
      _logger.error('Failed to retrieve GPS track: $trackId', exception: error);
      return null;
    }
  }

  /// Delete a saved track
  Future<bool> deleteTrack(String trackId) async {
    try {
      await _storageService.deleteGpsTrack(trackId);
      _logger.info('Deleted GPS track: $trackId');
      return true;
    } catch (error) {
      _logger.error('Failed to delete GPS track: $trackId', exception: error);
      return false;
    }
  }

  /// Export track as GPX format
  Future<String?> exportTrackAsGpx(String trackId) async {
    try {
      final track = await getTrack(trackId);
      if (track == null) return null;

      return _generateGpxContent(track);
    } catch (error) {
      _logger.error('Failed to export track as GPX', exception: error);
      return null;
    }
  }

  /// Handle incoming position updates
  void _onPositionUpdate(GpsPosition position) {
    try {
      // Filter position based on recording criteria
      if (!_shouldRecordPosition(position)) {
        return;
      }

      _currentTrackPositions.add(position);
      _lastRecordedPosition = position;

      // Periodically save to database (every 10 points)
      if (_currentTrackPositions.length % 10 == 0) {
        _saveTrackIncremental();
      }

      _logger.debug(
        'Recorded GPS position: ${position.toCoordinateString()} '
        '(${_currentTrackPositions.length} points)',
      );

    } catch (error) {
      _logger.error('Error processing position update', exception: error);
    }
  }

  /// Handle tracking errors
  void _onTrackingError(dynamic error) {
    _logger.error('GPS tracking error during recording', exception: error);
    // Continue recording despite errors - GPS can be intermittent
  }

  /// Determine if position should be recorded based on quality criteria
  bool _shouldRecordPosition(GpsPosition position) {
    // Check accuracy threshold
    if (position.accuracy != null && position.accuracy! > _maxAccuracyMeters) {
      return false;
    }

    // Check time interval
    if (_lastRecordedPosition != null) {
      final timeDiff = position.timestamp.difference(_lastRecordedPosition!.timestamp);
      if (timeDiff < _minPointInterval) {
        return false;
      }

      // Check distance threshold
      final distance = position.distanceTo(_lastRecordedPosition!);
      if (distance < _minDistanceMeters) {
        return false;
      }
    }

    return true;
  }

  /// Calculate statistics for the current track
  TrackStatistics _calculateTrackStatistics() {
    if (_currentTrackPositions.isEmpty) {
      return TrackStatistics.empty();
    }

    final history = PositionHistory.fromPositions(_currentTrackPositions);
    
    return TrackStatistics(
      totalDistance: history.totalDistance,
      totalDuration: history.duration,
      averageSpeed: history.averageSpeed,
      maxSpeed: history.maxSpeed,
      averageAccuracy: history.averageAccuracy ?? 0.0,
      bestAccuracy: history.bestAccuracy ?? 0.0,
      pointCount: _currentTrackPositions.length,
      marineGradePercentage: history.marineGradePercentage,
    );
  }

  /// Save current track state incrementally
  Future<void> _saveTrackIncremental() async {
    try {
      if (_currentTrackId == null) return;

      final track = GpsTrack(
        id: _currentTrackId!,
        name: await _getTrackName(_currentTrackId!),
        startTime: _currentTrackPositions.isNotEmpty
            ? _currentTrackPositions.first.timestamp
            : DateTime.now(),
        positions: List.from(_currentTrackPositions),
        isActive: true,
        statistics: _calculateTrackStatistics(),
      );

      await _storageService.saveGpsTrack(track);
    } catch (error) {
      _logger.error('Failed to save track incrementally', exception: error);
    }
  }

  /// Get track name from database
  Future<String> _getTrackName(String trackId) async {
    try {
      final track = await _storageService.getGpsTrack(trackId);
      return track?.name ?? 'Unnamed Track';
    } catch (error) {
      return 'Unnamed Track';
    }
  }

  /// Generate GPX file content for track
  String _generateGpxContent(GpsTrack track) {
    final buffer = StringBuffer();
    
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="NavTool Marine Navigation">');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_escapeXml(track.name)}</name>');
    buffer.writeln('    <trkseg>');
    
    for (final position in track.positions) {
      buffer.writeln(
        '      <trkpt lat="${position.latitude}" lon="${position.longitude}">',
      );
      if (position.altitude != null) {
        buffer.writeln('        <ele>${position.altitude}</ele>');
      }
      buffer.writeln(
        '        <time>${position.timestamp.toUtc().toIso8601String()}</time>',
      );
      buffer.writeln('      </trkpt>');
    }
    
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');
    
    return buffer.toString();
  }

  /// Escape XML characters
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Clean up recording state
  Future<void> _cleanup() async {
    _isRecording = false;
    _currentTrackId = null;
    _currentTrackPositions.clear();
    _lastRecordedPosition = null;
    
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _cleanup();
    _logger.debug('GPS track recording service disposed');
  }
}

/// Model class for GPS tracks
@immutable
class GpsTrack {
  final String id;
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final List<GpsPosition> positions;
  final bool isActive;
  final TrackStatistics? statistics;

  const GpsTrack({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    required this.positions,
    required this.isActive,
    this.statistics,
  });

  /// Duration of this track
  Duration get duration {
    if (positions.isEmpty) return Duration.zero;
    final end = endTime ?? positions.last.timestamp;
    return end.difference(startTime);
  }

  /// Whether this track has enough points to be meaningful
  bool get isSignificant => positions.length >= 3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsTrack &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GpsTrack(id: $id, name: $name, points: ${positions.length})';
  }
}

/// Statistics for a GPS track
@immutable  
class TrackStatistics {
  final double totalDistance;
  final Duration totalDuration;
  final double averageSpeed;
  final double maxSpeed;
  final double averageAccuracy;
  final double bestAccuracy;
  final int pointCount;
  final double marineGradePercentage;

  const TrackStatistics({
    required this.totalDistance,
    required this.totalDuration,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.averageAccuracy,
    required this.bestAccuracy,
    required this.pointCount,
    required this.marineGradePercentage,
  });

  factory TrackStatistics.empty() {
    return const TrackStatistics(
      totalDistance: 0.0,
      totalDuration: Duration.zero,
      averageSpeed: 0.0,
      maxSpeed: 0.0,
      averageAccuracy: 0.0,
      bestAccuracy: 0.0,
      pointCount: 0,
      marineGradePercentage: 0.0,
    );
  }

  /// Get average speed in knots
  double get averageSpeedKnots => averageSpeed * 1.944;

  /// Get max speed in knots  
  double get maxSpeedKnots => maxSpeed * 1.944;

  @override
  String toString() {
    return 'TrackStats(${totalDistance.toStringAsFixed(0)}m, '
           '${pointCount} points, ${averageSpeedKnots.toStringAsFixed(1)}kts avg)';
  }
}