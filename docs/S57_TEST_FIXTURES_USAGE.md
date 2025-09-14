# S57TestFixtures Utility Usage Guide

## Overview

The `S57TestFixtures` utility provides access to real NOAA Electronic Navigational Chart (ENC) S57 sample data for comprehensive testing of marine navigation features. This replaces artificial/synthetic chart data with actual NOAA ENC charts for improved test validity and marine navigation safety.

## Available Test Charts

### Elliott Bay Harbor Chart (US5WA50M)
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000`
- **Size**: ~411KB
- **Scale**: 1:20,000 (Harbor scale, Usage Band 5)
- **Region**: Elliott Bay, Seattle Harbor, Washington
- **Features**: Harbor navigation aids, detailed depth soundings, pier structures
- **Use for**: Harbor-scale navigation testing, detailed feature analysis

### Puget Sound Coastal Chart (US3WA01M)
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000`
- **Size**: ~1.58MB
- **Scale**: 1:90,000 (Coastal scale, Usage Band 3)
- **Region**: Puget Sound Northern Part, Washington
- **Features**: Coastlines, major navigation features, broad depth areas
- **Use for**: Coastal navigation testing, large-area spatial operations

## Basic Usage

### Loading Raw Chart Data

```dart
import '../utils/s57_test_fixtures.dart';

// Load Elliott Bay chart bytes
final elliottBayBytes = await S57TestFixtures.loadElliottBayChart();

// Load Puget Sound chart bytes  
final pugetSoundBytes = await S57TestFixtures.loadPugetSoundChart();
```

### Loading Parsed Chart Data (Recommended)

```dart
// Load parsed Elliott Bay chart with automatic caching
final elliottBayData = await S57TestFixtures.loadParsedElliottBay();

// Load parsed Puget Sound chart with automatic caching
final pugetSoundData = await S57TestFixtures.loadParsedPugetSound();
```

### Chart Metadata Validation

```dart
// Validate Elliott Bay as harbor chart
S57TestFixtures.validateChartMetadata(elliottBayData, ChartType.harbor);

// Validate Puget Sound as coastal chart
S57TestFixtures.validateChartMetadata(pugetSoundData, ChartType.coastal);
```

## Advanced Usage

### Working with Chart Bounds

```dart
// Calculate geographic bounds of chart
final bounds = S57TestFixtures.getChartBounds(chartData);

// Verify bounds are valid for marine navigation
expect(bounds.isValidForMarine, isTrue);
```

### Feature Analysis

```dart
// Get feature type distribution
final distribution = S57TestFixtures.getFeatureTypeDistribution(chartData);
print('Chart contains ${distribution.length} different feature types');

// Filter features by specific type
final lighthouses = S57TestFixtures.getFeaturesOfType(
  chartData, 
  S57FeatureType.lighthouse
);

// Get depth areas for bathymetry testing
final depthAreas = S57TestFixtures.getFeaturesOfType(
  chartData,
  S57FeatureType.depthArea
);
```

### Performance Optimization

```dart
void main() {
  group('Chart Processing Tests', () {
    // Clear cache before test group if needed
    setUpAll(() => S57TestFixtures.clearCache());
    
    test('multiple operations with cached data', () async {
      // First access parses and caches
      final data1 = await S57TestFixtures.loadParsedElliottBay();
      
      // Subsequent accesses use cache
      final data2 = await S57TestFixtures.loadParsedElliottBay();
      expect(identical(data1, data2), isTrue);
    });
  });
}
```

## Migration from Synthetic Data

### Before (Synthetic Data)
```dart
// OLD - Using artificial test data
final testChart = TestFixtures.createTestChart(
  id: 'TEST001',
  title: 'Test Chart',
  bounds: GeographicBounds(north: 25.0, south: 24.0, east: -80.0, west: -81.0),
);
```

### After (Real S57 Data)
```dart
// NEW - Using real NOAA S57 data
final chartData = await S57TestFixtures.loadParsedElliottBay();
final realFeatures = chartData.features;

// Convert to chart format if needed
final chartFeatures = realFeatures.map((f) => f.toChartFeature()).toList();
```

## Error Handling

### Chart Availability Check
```dart
test('S57 chart processing', () async {
  // Verify charts are available before testing
  if (!S57TestFixtures.areAllChartsAvailable()) {
    print('Skipping S57 tests - chart fixtures not available');
    return;
  }
  
  // Proceed with S57 testing...
});
```

### Graceful Error Handling
```dart
try {
  final chartData = await S57TestFixtures.loadParsedElliottBay();
  // Process chart data...
} on TestFailure catch (e) {
  // Handle missing fixtures or parsing errors
  print('S57 test skipped: ${e.message}');
  return;
}
```

## Test Categories

### Harbor Navigation Tests (Elliott Bay)
```dart
test('harbor navigation features', () async {
  final chartData = await S57TestFixtures.loadParsedElliottBay();
  
  // Validate harbor-specific features
  final beacons = S57TestFixtures.getFeaturesOfType(chartData, S57FeatureType.beacon);
  final buoys = S57TestFixtures.getFeaturesOfType(chartData, S57FeatureType.buoy);
  
  expect(beacons, isNotEmpty, reason: 'Harbor should have navigation beacons');
  expect(buoys, isNotEmpty, reason: 'Harbor should have navigation buoys');
});
```

### Coastal Navigation Tests (Puget Sound)
```dart
test('coastal navigation features', () async {
  final chartData = await S57TestFixtures.loadParsedPugetSound();
  
  // Validate coastal-specific features
  final coastlines = S57TestFixtures.getFeaturesOfType(chartData, S57FeatureType.coastline);
  final depthAreas = S57TestFixtures.getFeaturesOfType(chartData, S57FeatureType.depthArea);
  
  expect(coastlines, isNotEmpty, reason: 'Coastal chart should have coastline features');
  expect(depthAreas, isNotEmpty, reason: 'Coastal chart should have depth areas');
});
```

### Spatial Operations Tests
```dart
test('chart bounds and spatial queries', () async {
  final chartData = await S57TestFixtures.loadParsedElliottBay();
  final bounds = S57TestFixtures.getChartBounds(chartData);
  
  // Test spatial containment
  final featuresInBounds = chartData.features.where((feature) =>
    feature.coordinates.every((coord) =>
      bounds.contains(coord.latitude, coord.longitude)
    )
  ).toList();
  
  expect(featuresInBounds.length, equals(chartData.features.length),
      reason: 'All features should be within calculated bounds');
});
```

## Performance Guidelines

### Parsing Performance
- **Elliott Bay**: ~2-5 seconds initial parse, cached afterwards
- **Puget Sound**: ~5-10 seconds initial parse, cached afterwards
- Use `clearCache()` sparingly - only when testing cache invalidation

### Memory Usage
- **Elliott Bay**: ~10-20MB parsed data in memory
- **Puget Sound**: ~40-80MB parsed data in memory
- Cache is shared across tests in same test run

### Test Timeout Considerations
```dart
test('S57 parsing with adequate timeout', () async {
  // Allow sufficient time for initial parsing
}, timeout: const Timeout(Duration(minutes: 2)));
```

## Best Practices

1. **Use Parsed Data**: Prefer `loadParsedElliottBay()` over `loadElliottBayChart()` for most tests
2. **Cache Awareness**: Understand that parsed data is cached across tests
3. **Appropriate Chart Selection**: Use Elliott Bay for harbor tests, Puget Sound for coastal tests
4. **Validation**: Always validate chart metadata matches expected test requirements
5. **Error Handling**: Check chart availability for CI/CD environments
6. **Performance**: Set appropriate test timeouts for initial parsing

## Integration with Existing Tests

The S57TestFixtures utility integrates seamlessly with existing test infrastructure:

- **Test Fixtures**: Extends existing `TestFixtures` class patterns
- **Test Logger**: Uses `testLogger` for consistent logging
- **Error Handling**: Follows `TestFailure` conventions
- **Validation**: Compatible with existing assertion patterns

For questions or issues with S57TestFixtures utility, refer to the inline documentation in `test/utils/s57_test_fixtures.dart`.