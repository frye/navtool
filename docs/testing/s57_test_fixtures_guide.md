# S57TestFixtures Utility Documentation

## Overview

The `S57TestFixtures` utility provides access to real NOAA ENC S57 Electronic Navigational Chart data for testing marine navigation functionality. This replaces synthetic test data with actual chart data from Elliott Bay and Puget Sound, ensuring realistic testing of safety-critical maritime features.

## Available Charts

### Elliott Bay Harbor Chart (US5WA50M)
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000`
- **Size**: ~411KB
- **Scale**: 1:20,000 (harbor scale)
- **Coverage**: Seattle Elliott Bay area
- **Features**: Navigation aids, depth contours, harbor infrastructure

### Puget Sound Coastal Chart (US3WA01M)
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000`  
- **Size**: ~1.58MB
- **Scale**: 1:90,000 (coastal scale)
- **Coverage**: Broader Puget Sound region
- **Features**: Coastlines, major navigation features

## Usage Examples

### Basic Chart Loading

```dart
import '../utils/s57_test_fixtures.dart';

test('should load real S57 chart data', () async {
  // Check if charts are available in test environment
  final available = await S57TestFixtures.areChartsAvailable();
  if (!available) return; // Skip if charts not available
  
  // Load raw chart data
  final rawData = await S57TestFixtures.loadElliottBayChart();
  expect(rawData, isNotEmpty);
  expect(rawData.length, greaterThan(400000)); // ~411KB
});
```

### Parsed Chart Data

```dart
test('should parse S57 chart features', () async {
  if (!await S57TestFixtures.areChartsAvailable()) return;
  
  // Load and parse chart
  final parsedData = await S57TestFixtures.loadParsedElliottBay();
  
  // Validate structure
  expect(parsedData.features, isNotEmpty);
  expect(parsedData.metadata, isNotNull);
  
  // Check feature types
  final featureTypes = parsedData.features.map((f) => f.featureType).toSet();
  expect(featureTypes, contains(S57FeatureType.depthContour));
});
```

### Chart Validation

```dart
test('should validate chart against expectations', () async {
  if (!await S57TestFixtures.areChartsAvailable()) return;
  
  final parsedData = await S57TestFixtures.loadParsedElliottBay();
  
  // Comprehensive validation
  S57TestFixtures.validateParsedChart(
    parsedData, 
    S57TestFixtures.elliottBayChartId,
  );
  
  // Get expectations for custom validation
  final expectations = S57TestFixtures.getElliottBayExpectations();
  expect(expectations.scale, equals(20000));
});
```

## Current Parser Capabilities

Based on testing with real NOAA charts, the current S57 parser extracts:

### Elliott Bay Chart (3 features found):
- ✅ **DEPCNT** - Depth Contours
- ✅ **BOYLAT** - Lateral Buoys  
- ✅ **LIGHTS** - Navigation Lights

### Geographic Coverage:
- **Latitude**: 47.0° to 48.0°N (Seattle area)
- **Longitude**: 122.0° to 123.0°W (Puget Sound region)
- **Real coordinates** from actual NOAA survey data

## Migration from Synthetic Data

### Before (Synthetic):
```dart
// Old approach - synthetic data
final testChart = TestFixtures.createTestChart(
  id: 'TEST001',
  title: 'Fake Chart',
  // ... synthetic properties
);
```

### After (Real S57):
```dart
// New approach - real NOAA data
final parsedChart = await S57TestFixtures.loadParsedElliottBay();
final features = parsedChart.features; // Real marine features
final coordinates = features.first.coordinates; // Real Seattle coordinates
```

## Performance Features

### Caching
- **Raw data caching**: Chart files cached after first load
- **Parsed data caching**: Parsed S57 structures cached for performance
- **Memory management**: `clearCache()` method for cleanup

### Error Handling
- **File validation**: Checks file existence and size
- **Graceful degradation**: Tests skip if charts unavailable
- **Size validation**: Ensures file integrity with tolerance

## Integration with Existing Tests

### Test File Updates Required:
```dart
// Add import
import '../utils/s57_test_fixtures.dart';

// Replace synthetic data usage
group('S57 Parser Tests', () {
  test('should parse real chart data', () async {
    if (!await S57TestFixtures.areChartsAvailable()) return;
    
    final parsedData = await S57TestFixtures.loadParsedElliottBay();
    // Test with real data instead of synthetic
  });
});
```

### Conditional Testing:
```dart
test('marine feature validation', () async {
  final chartsAvailable = await S57TestFixtures.areChartsAvailable();
  if (!chartsAvailable) {
    // Skip or use fallback synthetic data
    return;
  }
  
  // Use real chart data for comprehensive testing
  final chart = await S57TestFixtures.loadParsedElliottBay();
  // ... real data testing
});
```

## Marine Navigation Validation

### Expected Features in Harbor Charts:
- Navigation aids (buoys, lights, beacons)
- Depth information (contours, soundings, areas)
- Coastal features (shorelines, constructions)
- Harbor infrastructure (piers, docks, facilities)

### Real Coordinate Validation:
```dart
// Validates coordinates are in Seattle/Elliott Bay area
expect(coordinate.latitude, inInclusiveRange(47.0, 48.0));
expect(coordinate.longitude, inInclusiveRange(-123.0, -122.0));
```

## Best Practices

### 1. Always Check Availability
```dart
final available = await S57TestFixtures.areChartsAvailable();
if (!available) return; // Skip gracefully
```

### 2. Use Appropriate Chart for Test Scale
- **Elliott Bay**: Harbor-scale features, detailed navigation
- **Puget Sound**: Coastal-scale features, broader coverage

### 3. Cache Management
```dart
// Clear cache in tearDown for memory management
tearDown(() {
  S57TestFixtures.clearCache();
});
```

### 4. Realistic Expectations
- Current parser extracts ~3 features per chart
- Focus on feature types rather than counts
- Validate coordinate ranges and geographic consistency

## CI/CD Integration

### Test Environment Setup:
- Charts included in repository at `test/fixtures/charts/s57_data/`
- Tests skip gracefully if charts unavailable
- No external dependencies or network requirements

### Performance Considerations:
- Chart loading: ~10-50ms (cached)
- Parsing: ~100-500ms (cached after first parse)
- Memory usage: ~2MB for both charts

## Future Enhancements

### Parser Improvements:
- Support for more S57 feature types
- Enhanced metadata extraction
- Spatial index integration
- Update processing capabilities

### Additional Charts:
- More geographic regions
- Different chart scales
- International chart data
- Test edge cases and error conditions

## Support and Troubleshooting

### Common Issues:

1. **Charts Not Available**:
   - Verify files exist in `test/fixtures/charts/s57_data/ENC_ROOT/`
   - Check file permissions and sizes
   - Tests should skip gracefully with availability check

2. **Parsing Failures**:
   - Ensure S57Parser dependencies are properly configured
   - Check for S57 model compatibility
   - Verify binary data integrity

3. **Performance Issues**:
   - Use caching for repeated test runs
   - Clear cache periodically for memory management
   - Consider chart size for performance-critical tests

### Debugging:
```dart
// Enable debug output
final parsedData = await S57TestFixtures.loadParsedElliottBay();
print('Features found: ${parsedData.features.length}');
print('Feature types: ${parsedData.features.map((f) => f.featureType.acronym).join(', ')}');
```

---

This utility provides the foundation for realistic marine navigation testing using actual NOAA chart data, ensuring that NavTool's S57 parsing and maritime features work correctly with real-world navigational information.