# S-57 Troubleshooting Guide

This guide provides solutions to common issues encountered when parsing and working with S-57 Electronic Navigational Chart (ENC) files in NavTool.

## Quick Diagnostic Commands

```dart
// Check parsing with warnings
final chart = S57Parser.parse(data, options: S57ParseOptions(strictMode: false));
print('Warnings: ${chart.warnings?.length ?? 0}');

// Validate chart content
print('Features: ${chart.summary()}');
print('Bounds: ${chart.bounds}');

// Test spatial indexing
final testQuery = chart.findFeatures(limit: 1);
print('Spatial index working: ${testQuery.isNotEmpty}');
```

## Common Issues and Solutions

| Symptom | Likely Cause | Resolution |
|---------|--------------|-----------|
| **Missing DEPARE features** | Incorrect object catalog load | Verify `object_classes.json` path & integrity. Check if chart uses non-standard DEPARE codes. Enable debug logging to see parsed object codes. |
| **Many UNKNOWN_OBJ_CODE warnings** | Incomplete catalog subset | Extend catalog or verify codes from chart. Run `chart.summary()` to see actual object types. Consider using permissive mode for regional charts. |
| **UPDATE_GAP error** | Skipped intermediate update file | Ensure sequential .00X files present. Check file naming: .000 (base), .001, .002, etc. Verify no missing updates in sequence. |
| **DEPTH_OUT_OF_RANGE warnings** | Non-coastal cell or scaling factor issue | Check COMF/SOMF scaling factors in metadata. Verify chart usage band matches area (harbor vs ocean). Review VALSOU attribute ranges. |
| **Strict mode exception early** | Error-severity warning encountered | Run without strict mode: `S57ParseOptions(strictMode: false)` to inspect full warning list. Check first error in warning collector. |
| **Performance slower than targets** | Linear fallback triggered | Confirm feature count > threshold & spatial index enabled. Check memory constraints. Use bounds filtering for large charts. |

## Detailed Troubleshooting

### Missing DEPARE Features

**Symptoms:**
- `chart.findFeatures(types: {'DEPARE'})` returns empty
- GeoJSON export missing depth areas  
- Navigation software shows no depth contours

**Diagnosis:**
```dart
// Check what object types are actually present
final summary = chart.summary();
print('Available types: ${summary.keys}');

// Look for depth-related objects with similar codes
final depthObjects = chart.findFeatures().where((f) => 
  f.featureType.acronym.contains('DEP') || 
  f.attributes.containsKey('VALSOU')
);
print('Depth objects found: ${depthObjects.length}');
```

**Solutions:**
1. **Verify catalog integrity**: Check that `assets/s57/object_classes.json` contains DEPARE definition
2. **Check regional variations**: Some charts use local DEPARE codes (40-45 range)
3. **Inspect raw data**: Enable debug logging to see actual object codes parsed
4. **Use permissive parsing**: `S57ParseOptions(strictMode: false)` to see all warnings

### Many UNKNOWN_OBJ_CODE Warnings

**Symptoms:**
- Warning output filled with "Unknown object code XXX"
- Features not appearing in navigation display
- Reduced chart functionality

**Diagnosis:**
```dart
// Collect and analyze unknown codes
final options = S57ParseOptions(strictMode: false);
final chart = S57Parser.parse(data, options: options);

// Check warning patterns
for (final warning in chart.warnings ?? []) {
  if (warning.code == S57WarningCodes.unknownObjCode) {
    print('Unknown code: ${warning.message}');
  }
}
```

**Solutions:**
1. **Update object catalog**: Add missing codes to catalog or use more complete catalog
2. **Regional chart handling**: Some charts include national or regional object extensions
3. **Graceful degradation**: Use `S57ParseOptions.development()` to continue parsing with warnings
4. **Chart validation**: Verify chart is standard S-57 format, not proprietary variant

### UPDATE_GAP Error

**Symptoms:**
- Exception: "Update gap detected"
- Chart updates fail to apply
- Navigation data becomes outdated

**Diagnosis:**
```dart
// Check update sequence in directory
final chartFiles = Directory('charts/').listSync()
  .where((f) => f.path.contains('US5WA50M'))
  .map((f) => f.path)
  .toList()..sort();

print('Available files: $chartFiles');
// Should see: US5WA50M.000, US5WA50M.001, US5WA50M.002, etc.
```

**Solutions:**
1. **Download missing updates**: Ensure all intermediate .00X files are present
2. **Check file naming**: Updates must be sequential (.000, .001, .002...)
3. **Verify file integrity**: Corrupted update files can cause gaps
4. **Reset to base**: If gaps persist, start with base .000 file only

### DEPTH_OUT_OF_RANGE Warnings

**Symptoms:**
- Info warnings about depth values outside normal range
- Soundings appear incorrect in navigation display
- Bathymetry data seems unrealistic

**Diagnosis:**
```dart
// Analyze depth distribution
final soundings = chart.findFeatures(types: {'SOUNDG'});
final depths = soundings
  .map((f) => f.attributes['VALSOU'] as double?)
  .where((d) => d != null)
  .toList();

print('Depth range: ${depths.reduce(math.min)} to ${depths.reduce(math.max)}');
print('Suspicious depths: ${depths.where((d) => d! < -100 || d! > 15000)}');
```

**Solutions:**
1. **Check chart scale**: Ocean charts may have very deep soundings (>1000m)
2. **Verify units**: Ensure depths are in meters, not feet or fathoms
3. **Review metadata**: Check COMF/SOMF coordinate scaling factors
4. **Chart type validation**: Ensure chart matches expected geographic area

### Strict Mode Exception Early

**Symptoms:**
- Parsing stops immediately with `S57StrictModeException`
- Limited diagnostic information available
- Cannot inspect full chart content

**Diagnosis:**
```dart
// Disable strict mode to collect all warnings
try {
  final chart = S57Parser.parse(data, options: S57ParseOptions(strictMode: false));
  
  // Analyze first few errors
  final errors = chart.warnings
    ?.where((w) => w.severity == S57WarningSeverity.error)
    .take(5)
    .toList() ?? [];
    
  for (final error in errors) {
    print('Error: ${error.code} - ${error.message}');
  }
} catch (e) {
  print('Parse failed even in permissive mode: $e');
}
```

**Solutions:**
1. **Use development mode**: `S57ParseOptions.development()` for initial debugging
2. **Fix critical errors**: Address the first error-level warning shown
3. **Gradual strictness**: Use custom options with higher warning threshold
4. **Chart validation**: Verify chart file is not corrupted

### Performance Slower Than Targets

**Symptoms:**
- Chart parsing takes >5 seconds
- Spatial queries slow (>100ms)
- UI becomes unresponsive during chart operations

**Diagnosis:**
```dart
// Measure parsing performance
final stopwatch = Stopwatch()..start();
final chart = S57Parser.parse(data);
stopwatch.stop();

print('Parse time: ${stopwatch.elapsedMilliseconds}ms');
print('Feature count: ${chart.features.length}');
print('Index type: ${chart.spatialIndex.runtimeType}');

// Test query performance
stopwatch.reset()..start();
final results = chart.findFeatures(
  bounds: S57Bounds(north: 47.61, south: 47.60, east: -122.33, west: -122.34),
  limit: 100
);
stopwatch.stop();
print('Query time: ${stopwatch.elapsedMilliseconds}ms for ${results.length} results');
```

**Solutions:**
1. **Enable spatial indexing**: Verify R-tree index is being used, not linear fallback
2. **Optimize queries**: Use bounds filtering to reduce search space
3. **Memory constraints**: Increase available memory for large charts (>10MB)
4. **Background processing**: Parse charts asynchronously to avoid UI blocking
5. **Chart segmentation**: Split very large charts into smaller tiles

## Error Code Reference

### Critical Errors (Stop Processing)
- `LEADER_LEN_MISMATCH`: ISO 8211 record header corruption
- `UPDATE_GAP`: Missing intermediate update file
- `FIELD_BOUNDS`: Data extends beyond record boundaries

### Warnings (Continue Processing)
- `UNKNOWN_OBJ_CODE`: Object type not in catalog
- `MISSING_REQUIRED_ATTR`: Required attribute missing from feature
- `DEPTH_OUT_OF_RANGE`: Depth value outside expected range (-100 to 15000m)

### Info Messages (Informational)
- `POLYGON_CLOSED_AUTO`: Polygon automatically closed
- `DEGENERATE_EDGE`: Geometry simplified due to invalid coordinates

## Performance Tuning

### For Large Charts (>5MB)
```dart
// Use streaming parser for memory efficiency
final options = S57ParseOptions(
  strictMode: false,
  maxWarnings: 1000  // Limit warning collection
);

// Enable spatial index for queries
final chart = S57Parser.parse(data, options: options);
// Spatial index automatically enabled for >1000 features
```

### For Real-Time Updates
```dart
// Quick validation mode
final options = S57ParseOptions(
  strictMode: true,
  maxWarnings: 10  // Fail fast on major issues
);
```

## Getting Help

If these solutions don't resolve your issue:

1. **Enable debug logging**: Set logging level to debug to see detailed parsing steps
2. **Collect warnings**: Run in development mode and save all warnings to a file
3. **Chart information**: Note chart cell ID, edition number, and file size
4. **Minimal reproduction**: Create smallest possible chart file that reproduces issue
5. **System information**: Include platform (Linux/Windows/macOS) and memory constraints

## Related Documentation

- [S-57 Format Overview](s57_format_overview.md) - Technical format details
- [S-57 Implementation Analysis](../S57_IMPLEMENTATION_ANALYSIS.md) - Current implementation status
- [Performance Benchmarks](benchmarks/s57_benchmarks.md) - Expected performance targets