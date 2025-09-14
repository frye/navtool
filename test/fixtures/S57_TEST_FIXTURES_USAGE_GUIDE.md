# S57TestFixtures Usage Guide

## Overview

The `S57TestFixtures` utility provides access to real NOAA ENC (Electronic Navigational Chart) S57 data for testing, replacing artificial/synthetic chart data with actual marine navigation charts. This improves test validity for safety-critical marine navigation features.

## Available Charts

### Elliott Bay Harbor (US5WA50M)
- **Size**: ~411KB
- **Usage Band**: 5 (Harbor)
- **Features**: Navigation aids, harbor facilities, concentrated depth data
- **Recommended Use**: Unit tests, fast feedback testing
- **Location**: Elliott Bay, Seattle area

### Puget Sound (US3WA01M)
- **Size**: ~1.58MB  
- **Usage Band**: 3 (Coastal)
- **Features**: Extensive coastline, comprehensive soundings, navigation aids
- **Recommended Use**: Integration tests, performance testing
- **Location**: Puget Sound, Washington state

## Basic Usage

### Loading Raw S57 Data

```dart
import '../utils/s57_test_fixtures.dart';

// Load Elliott Bay raw chart data (fast)
final elliottBayData = await S57TestFixtures.loadElliottBayChart();
expect(elliottBayData.length, greaterThan(400000)); // ~411KB

// Load Puget Sound raw chart data (larger)
final pugetSoundData = await S57TestFixtures.loadPugetSoundChart();
expect(pugetSoundData.length, greaterThan(1500000)); // ~1.58MB
```

### Loading Parsed Chart Data

```dart
import 'package:navtool/core/services/s57/s57_models.dart';

// Load and parse Elliott Bay chart (with caching)
final elliottBayChart = await S57TestFixtures.loadParsedElliottBay();
expect(elliottBayChart.features, isNotEmpty);
expect(elliottBayChart.metadata.producer, isNotEmpty);

// Load and parse Puget Sound chart (with caching)
final pugetSoundChart = await S57TestFixtures.loadParsedPugetSound();
expect(pugetSoundChart.features.length, greaterThan(elliottBayChart.features.length));
```

### Loading with Warning Collection

```dart
// Enable S57 parsing warning collection for debugging
final chartData = await S57TestFixtures.loadParsedElliottBay(
  useWarningCollector: true,
);

// Warnings are logged automatically
expect(chartData.features, isNotEmpty);
```

## Chart Metadata Validation

```dart
// Validate chart metadata for correctness
final parsedChart = await S57TestFixtures.loadParsedElliottBay();
final validation = S57TestFixtures.validateChartMetadata(parsedChart, 'US5WA50M');

expect(validation.isValid, isTrue);
if (validation.hasWarnings) {
  print('Validation warnings: ${validation.warnings}');
}
if (validation.hasErrors) {
  print('Validation errors: ${validation.errors}');
}
```

## Fixture Availability Checking

```dart
// Check which fixtures are available before testing
final availability = await S57TestFixtures.checkFixtureAvailability();

if (availability.allAvailable) {
  // Run all tests
  print('All fixtures available');
} else if (availability.hasAnyFixtures) {
  // Run partial tests
  print('Some fixtures available: ${availability.statusMessage}');
} else {
  // Skip tests or fail
  print('No fixtures available - install at: ${availability.fixturesPath}');
}
```

## Feature Analysis

```dart
final chart = await S57TestFixtures.loadParsedElliottBay();

// Analyze feature types
final featureTypeCounts = <S57FeatureType, int>{};
for (final feature in chart.features) {
  featureTypeCounts[feature.featureType] = 
      (featureTypeCounts[feature.featureType] ?? 0) + 1;
}

// Check for specific marine features
final hasDepthAreas = featureTypeCounts.containsKey(S57FeatureType.depthArea);
final hasSoundings = featureTypeCounts.containsKey(S57FeatureType.sounding);
final hasNavigationAids = featureTypeCounts.containsKey(S57FeatureType.buoy);

expect(hasDepthAreas, isTrue);
expect(hasSoundings, isTrue);
```

## Spatial Queries

```dart
final chart = await S57TestFixtures.loadParsedPugetSound();

// Query features within bounds
final boundsFeatures = chart.queryFeaturesInBounds(chart.bounds);

// Query features near a point (lat, lon with radius in degrees)
final nearbyFeatures = chart.queryFeaturesNear(47.6062, -122.3321, 
  radiusDegrees: 0.01);

// Query specific feature types
final navigationAids = chart.queryNavigationAids();
final depthFeatures = chart.queryDepthFeatures();

expect(navigationAids, isNotEmpty);
expect(depthFeatures, isNotEmpty);
```

## Performance Considerations

### Caching Behavior

Both raw and parsed data are automatically cached for performance:

```dart
// First call - loads and parses from disk
final stopwatch1 = Stopwatch()..start();
final chart1 = await S57TestFixtures.loadParsedElliottBay();
stopwatch1.stop();

// Second call - returns cached data (much faster)
final stopwatch2 = Stopwatch()..start();
final chart2 = await S57TestFixtures.loadParsedElliottBay();
stopwatch2.stop();

expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds));
```

### Cache Management

```dart
// Clear all cached data (useful for memory management in long test runs)
S57TestFixtures.clearCache();

// Subsequent calls will reload from disk
final chart = await S57TestFixtures.loadParsedElliottBay();
```

## Test Patterns

### Unit Tests - Use Elliott Bay

```dart
group('chart feature parsing', () {
  test('should parse navigation aids correctly', () async {
    final chart = await S57TestFixtures.loadParsedElliottBay();
    final navAids = chart.queryNavigationAids();
    
    expect(navAids, isNotEmpty);
    for (final aid in navAids) {
      expect(aid.featureType.code, greaterThan(0));
      expect(aid.coordinates, isNotEmpty);
    }
  });
});
```

### Integration Tests - Use Puget Sound

```dart
group('full chart processing workflow', () {
  test('should process large chart successfully', () async {
    final chart = await S57TestFixtures.loadParsedPugetSound();
    
    // Test with larger, more comprehensive dataset
    expect(chart.features.length, greaterThan(1000));
    
    final validation = S57TestFixtures.validateChartMetadata(chart, 'US3WA01M');
    expect(validation.isValid, isTrue);
    
    // Test spatial indexing performance
    final stopwatch = Stopwatch()..start();
    final features = chart.queryFeaturesNear(47.6, -122.3);
    stopwatch.stop();
    
    expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
  });
});
```

### Conditional Testing Based on Availability

```dart
group('S57 chart tests', () {
  late FixtureAvailability availability;
  
  setUpAll(() async {
    availability = await S57TestFixtures.checkFixtureAvailability();
  });
  
  test('Elliott Bay specific features', () async {
    if (!availability.elliottBayAvailable) {
      print('Elliott Bay fixture not available - skipping test');
      return;
    }
    
    final chart = await S57TestFixtures.loadParsedElliottBay();
    // Test Elliott Bay specific features
  });
  
  test('Puget Sound specific features', () async {
    if (!availability.pugetSoundAvailable) {
      print('Puget Sound fixture not available - skipping test');
      return;
    }
    
    final chart = await S57TestFixtures.loadParsedPugetSound();
    // Test Puget Sound specific features
  });
});
```

## Error Handling

### Graceful Fixture Handling

```dart
test('should handle missing fixtures gracefully', () async {
  try {
    final chart = await S57TestFixtures.loadParsedElliottBay();
    // Test with available chart
  } on TestFailure catch (e) {
    if (e.message!.contains('fixture not found')) {
      print('Chart fixture not available - test skipped');
      return;
    }
    rethrow;
  }
});
```

### Validation Error Handling

```dart
final chart = await S57TestFixtures.loadParsedElliottBay();
final validation = S57TestFixtures.validateChartMetadata(chart, 'US5WA50M');

if (!validation.isValid) {
  print('Validation failed:');
  for (final error in validation.errors) {
    print('  ERROR: $error');
  }
}

if (validation.hasWarnings) {
  print('Validation warnings:');
  for (final warning in validation.warnings) {
    print('  WARNING: $warning');
  }
}
```

## Chart Information Reference

```dart
// Get information about available charts
final charts = S57TestFixtures.getAvailableCharts();

for (final chart in charts) {
  print('Chart: ${chart.chartId}');
  print('  Title: ${chart.title}');
  print('  Usage Band: ${chart.usageBand}');
  print('  Size: ~${(chart.approximateSize / 1024).round()}KB');
  print('  Features: ${chart.features.join(', ')}');
  print('  Recommended Use: ${chart.recommendedUse}');
  print('');
}
```

## Usage Recommendations

```dart
// Get detailed usage recommendations
final recommendations = S57TestFixtures.getUsageRecommendations();
print(recommendations);
```

## Fixture Installation

If fixtures are missing, they should be installed at:
- `test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000`
- `test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000`

The utility will provide helpful error messages pointing to the expected paths when fixtures are missing.

## Migration from Artificial Data

### Before (using artificial data):

```dart
// OLD: Artificial chart data
final chart = TestFixtures.createTestChart(
  id: 'TEST001',
  title: 'Test Chart',
  scale: 25000,
);
```

### After (using real S57 data):

```dart
// NEW: Real NOAA ENC data
final chart = await S57TestFixtures.loadParsedElliottBay();
// Now testing with actual marine navigation data!
```

## Integration with Existing Tests

The S57TestFixtures utility is designed to work alongside existing test infrastructure:

```dart
import '../utils/test_fixtures.dart'; // Existing utilities
import '../utils/s57_test_fixtures.dart'; // New S57 utilities

// Use both as needed:
// - S57TestFixtures for real chart data
// - TestFixtures for mock/artificial data where appropriate
```

This ensures a smooth migration path while maintaining compatibility with existing tests.