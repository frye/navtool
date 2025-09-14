# GPS Integration Implementation

This document describes the GPS integration features implemented for NavTool's marine navigation system.

## Overview

The GPS integration provides real-time position tracking, vessel visualization, and track recording capabilities specifically designed for marine navigation requirements.

## Features Implemented

### ✅ Real-time GPS Position Tracking
- **Location**: `lib/core/services/gps_service_impl.dart`
- High-accuracy positioning with marine-grade filtering (≤10m accuracy)
- Cross-platform support (Windows, macOS, Linux)
- Automatic permission management
- Seattle fallback coordinates when GPS unavailable

### ✅ GPS Accuracy and Signal Quality Indicators  
- **Location**: `lib/core/models/gps_signal_quality.dart`
- Marine-grade accuracy classification
- Signal strength assessment (Excellent/Good/Fair/Poor)
- Satellite count and HDOP monitoring
- Visual quality indicators with color coding

### ✅ Vessel Position Overlay on Charts
- **Location**: `lib/features/charts/widgets/vessel_position_overlay.dart`
- Real-time vessel position display on charts
- Heading indicator with visual arrow
- Speed vector visualization
- GPS accuracy circle overlay
- Historical track display

### ✅ Heading and Course Over Ground Display
- **Location**: `lib/core/models/position_history.dart` 
- Course over ground calculation from position history
- Speed over ground in knots for marine use
- Confidence metrics for navigation data
- Real-time heading display with visual indicators

### ✅ GPS Data Logging and Track Recording
- **Location**: `lib/core/services/gps_track_recording_service.dart`
- Persistent track recording to SQLite database
- GPX export capability for data portability
- Intelligent position filtering (accuracy, distance, time)
- Track statistics (distance, speed, duration, accuracy)

## Architecture

### GPS Service Layer
```
GpsService (interface)
├── GpsServiceImpl (geolocator-based for macOS/Linux)
└── GpsServiceWin32 (Win32 API for Windows)
```

### Track Recording Service
```
GpsTrackRecordingService
├── Real-time position filtering
├── SQLite storage integration
├── GPX export functionality
└── Track statistics calculation
```

### UI Components
```
Charts Integration
├── VesselPositionOverlay (position visualization)
├── GpsControlPanel (user controls)  
└── ChartWidget (integrated display)
```

### State Management
- Riverpod providers for reactive GPS data
- Real-time position streaming
- Track recording status management
- Signal quality monitoring

## Database Schema

### GPS Tracks Table
```sql
CREATE TABLE gps_tracks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  start_time INTEGER NOT NULL,
  end_time INTEGER,
  is_active INTEGER DEFAULT 0,
  point_count INTEGER DEFAULT 0,
  total_distance REAL DEFAULT 0.0,
  average_speed REAL DEFAULT 0.0,
  max_speed REAL DEFAULT 0.0,
  marine_grade_percentage REAL DEFAULT 0.0
);
```

### GPS Track Points Table  
```sql
CREATE TABLE gps_track_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  track_id TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  timestamp INTEGER NOT NULL,
  altitude REAL,
  accuracy REAL,
  heading REAL,
  speed REAL,
  FOREIGN KEY (track_id) REFERENCES gps_tracks (id)
);
```

## Marine Navigation Standards

### Position Filtering
- **Accuracy Threshold**: ≤20m for recording, ≤10m for marine-grade
- **Distance Filter**: Minimum 5m between recorded points
- **Time Filter**: Minimum 5 seconds between points
- **Signal Quality**: Marine-grade classification at ≤10m accuracy

### Track Recording
- Automatic filtering for quality assurance  
- Incremental database saves every 10 points
- Real-time statistics calculation
- Power-efficient recording algorithms

### Chart Integration  
- Vessel symbol with heading indicator
- Real-time position updates
- Track history visualization
- GPS accuracy circle display
- Speed vector indication

## Usage Examples

### Basic GPS Position Access
```dart
final gpsService = ref.read(gpsServiceProvider);
final position = await gpsService.getCurrentPosition();
if (position != null) {
  print('Vessel at: ${position.toCoordinateString()}');
}
```

### Track Recording
```dart
final trackingService = ref.read(gpsTrackRecordingServiceProvider);
await trackingService.startRecording(trackName: 'Harbor to Anchorage');
// ... navigation ...
final completedTrack = await trackingService.stopRecording();
```

### Chart Integration
```dart
ChartWidget(
  showGpsOverlay: true,
  showGpsControls: true,
  onPositionChanged: (position) {
    // Handle chart position changes
  },
)
```

## Testing

### Unit Tests
- GPS service functionality
- Track recording logic
- Position filtering algorithms  
- Signal quality assessment

### Integration Tests
- End-to-end GPS workflow
- Chart integration
- Permission handling
- Error scenarios

### Test Files
- `test/core/services/gps_track_recording_service_test.dart`
- `test/features/charts/widgets/vessel_position_overlay_test.dart`
- `integration_test/gps_integration_test.dart`

## Performance Considerations

### Battery Optimization
- Configurable update intervals
- Accuracy-based filtering
- Intelligent wake/sleep patterns
- Background task management

### Memory Management
- Limited position history (1000 points max)
- Efficient track point storage
- Incremental database operations
- Automatic cleanup of old data

### Marine Environment Adaptations
- Extended GPS timeout (30s) for satellite connectivity
- Accuracy filtering for challenging marine conditions
- Robust error handling for intermittent signals
- Seattle fallback for development/testing

## Error Handling

### GPS Service Errors
- Permission denied → Fallback coordinates
- Location services disabled → User notification
- Poor signal quality → Accuracy warnings
- Service timeout → Retry with exponential backoff

### Track Recording Errors
- Storage errors → Graceful degradation
- GPS signal loss → Pause/resume capability  
- Low accuracy → Position filtering
- Battery low → Automatic stop with save

## Future Enhancements

### Planned Features
- NMEA sentence parsing for professional GPS units
- AIS integration for vessel traffic
- Waypoint navigation with bearing/distance
- Track analysis and performance metrics
- Cloud sync for track backup
- Advanced marine chart overlay features

### Performance Improvements
- WebGL acceleration for track rendering
- Spatial indexing for large track datasets
- Background sync optimization
- Advanced filtering algorithms

## Dependencies

### Core Dependencies
- `geolocator_platform_interface: ^4.2.6` - Cross-platform GPS
- `win32: ^5.14.0` - Windows native location services
- `sqflite: ^2.4.1` - Local database storage
- `flutter_riverpod: ^2.5.1` - State management

### Development Dependencies  
- `mockito: ^5.4.4` - Testing mocks
- `integration_test` - End-to-end testing
- `flutter_test` - Unit testing

## Conclusion

The GPS integration provides a comprehensive foundation for marine navigation with real-time position tracking, intelligent track recording, and seamless chart integration. The implementation follows marine industry standards and provides robust error handling for challenging maritime environments.

All acceptance criteria from Issue #27 have been successfully implemented:
- ✅ GPS position is tracked and updated in real-time
- ✅ Accuracy and signal quality are clearly displayed  
- ✅ Vessel position is accurately overlaid on charts
- ✅ Heading and course over ground are properly calculated
- ✅ GPS data logging captures comprehensive track data