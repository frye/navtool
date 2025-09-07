# S-57 API Migration Guide

This guide helps developers migrate between different versions of the NavTool S-57 parser API and adopt best practices for production use.

## Current API vs. Planned API

### Current API (Available Now)

```dart
import 'package:navtool/s57.dart';

// Basic parsing
final chart = S57Parser.parse(data);
```

### Planned API (Future Enhancement)

```dart
import 'package:navtool/s57.dart';

// File-based parsing with options
final chart = await S57Parser.parseFile('US5WA50M.000', 
  options: S57ParseOptions(strictMode: false));

// Data parsing with options  
final chart = S57Parser.parse(data, 
  options: S57ParseOptions.development());
```

## Migration Patterns

### From Legacy Enum Usage

**Before (Deprecated):**
```dart
// Old enum-based feature types
final beacons = chart.features.where((f) => 
  f.featureType == S57FeatureType.beacon).toList();
```

**After (Current):**
```dart
// Use acronym-based filtering
final beacons = chart.findFeatures(types: {'BCNCAR', 'LIGHTS'});
```

### Error Handling Migration

**Before (Basic):**
```dart
try {
  final chart = S57Parser.parse(data);
} catch (e) {
  print('Parse failed: $e');
}
```

**After (Structured):**
```dart
try {
  final chart = S57Parser.parse(data);
  
  // Check for warnings (when warning system is available)
  if (chart.warnings?.isNotEmpty == true) {
    for (final warning in chart.warnings!) {
      print('${warning.severity}: ${warning.message}');
    }
  }
} on AppError catch (e) {
  print('Parse failed: ${e.message}');
  print('Error type: ${e.type}');
}
```

### Spatial Query Migration

**Before (Manual Filtering):**
```dart
final results = <S57Feature>[];
for (final feature in chart.features) {
  if (feature.coordinates.isNotEmpty) {
    final lat = feature.coordinates.first[1];
    final lon = feature.coordinates.first[0];
    if (lat >= bounds.south && lat <= bounds.north &&
        lon >= bounds.west && lon <= bounds.east) {
      results.add(feature);
    }
  }
}
```

**After (Spatial Index):**
```dart
final results = chart.findFeatures(
  bounds: S57Bounds(
    north: 47.61, south: 47.60, 
    east: -122.33, west: -122.34
  )
);
```

## Feature Type Mapping

The following table shows migration from simplified enum values to official S-57 acronyms:

| Legacy Enum | Official Acronym | Object Name | Code |
|-------------|------------------|-------------|------|
| `beacon` | `BCNCAR` | Cardinal Beacon | 57 |
| `buoy` | `BOYLAT` | Lateral Buoy | 58 |
| `buoyCardinal` | `BOYCAR` | Cardinal Buoy | 59 |
| `buoySpecialPurpose` | `BOYSAW` | Safe Water Buoy | 61 |
| `lighthouse` | `LIGHTS` | Light | 75 |
| `depthArea` | `DEPARE` | Depth Area | 42 |
| `sounding` | `SOUNDG` | Sounding | 129 |
| `coastline` | `COALNE` | Coastline | 30 |
| `obstruction` | `OBSTRN` | Obstruction | 104 |
| `wreck` | `WRECKS` | Wreck | 159 |

### Migration Helper

```dart
// Utility function to convert from legacy enum to acronym
String legacyToAcronym(S57FeatureType legacyType) {
  const mapping = {
    S57FeatureType.beacon: 'BCNCAR',
    S57FeatureType.buoy: 'BOYLAT',
    S57FeatureType.lighthouse: 'LIGHTS',
    S57FeatureType.depthArea: 'DEPARE',
    S57FeatureType.sounding: 'SOUNDG',
    S57FeatureType.coastline: 'COALNE',
    // Add other mappings as needed
  };
  return mapping[legacyType] ?? 'UNKNOW';
}
```

## Breaking Changes to Expect

### Version 1.0 (Planned)

- **Parse Options**: `S57Parser.parse()` will accept optional `S57ParseOptions` parameter
- **File Methods**: `S57Parser.parseFile()` convenience method for direct file parsing
- **Warning System**: All parsing methods will return warning information
- **Strict Mode**: Production parsing will fail fast on critical errors

### Version 2.0 (Future)

- **Async Parsing**: Large chart parsing will become asynchronous
- **Streaming**: Support for parsing charts larger than available memory
- **Object Catalog**: Dynamic loading of S-57 object catalogs
- **Update Processing**: Incremental update application

## Best Practices

### For Development

```dart
// Use permissive parsing during development
final chart = S57Parser.parse(data);

// Log any parsing issues (when warning system available)
// Enable debug output to see detailed parsing steps
```

### For Production

```dart
// Plan for strict mode when available
try {
  final chart = S57Parser.parse(data);
  // Future: options: S57ParseOptions.production()
  
  // Validate critical chart data
  if (chart.features.isEmpty) {
    throw Exception('Chart contains no navigational features');
  }
  
  final soundings = chart.findFeatures(types: {'SOUNDG'});
  if (soundings.isEmpty) {
    print('Warning: No depth soundings found in chart');
  }
  
} catch (e) {
  // Handle parsing failures gracefully
  print('Chart parsing failed: $e');
  // Fall back to cached chart or alternative data source
}
```

### For Testing

```dart
// Test with both valid and invalid chart data
void testChartParsing() {
  group('S57 Parsing', () {
    test('should parse valid chart', () {
      final chart = S57Parser.parse(validTestData);
      expect(chart.features, isNotEmpty);
      expect(chart.summary(), containsPair('SOUNDG', greaterThan(0)));
    });
    
    test('should handle malformed data gracefully', () {
      expect(() => S57Parser.parse(malformedData), 
        throwsA(isA<AppError>()));
    });
  });
}
```

## Backward Compatibility

The current API is designed to maintain backward compatibility:

- Existing `S57Parser.parse(data)` calls will continue to work
- Feature access methods (`findFeatures`, `summary`, `toGeoJson`) remain stable
- Data models (`S57Feature`, `S57ParsedData`) maintain consistent structure

New features will be added as optional parameters or new methods to avoid breaking existing code.

## Timeline

| Version | Features | Timeline |
|---------|----------|----------|
| **Current** | Basic parsing, spatial queries | Available now |
| **0.1.0** | Parse options, warning system | Q1 2024 |
| **0.2.0** | File parsing, update processing | Q2 2024 |
| **1.0.0** | Production-ready, full S-57 compliance | Q3 2024 |

## Related Documentation

- [S-57 Format Overview](s57_format_overview.md) - Technical implementation details
- [Troubleshooting Guide](s57_troubleshooting.md) - Common issues and solutions
- [Implementation Analysis](../S57_IMPLEMENTATION_ANALYSIS.md) - Development roadmap