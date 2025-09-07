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
- `LEADER_TRUNCATED`: Record header shorter than required 24 bytes
- `UPDATE_GAP`: Missing intermediate update file
- `FIELD_BOUNDS`: Data extends beyond record boundaries
- `FIELD_LEN_MISMATCH`: Declared field length doesn't match actual data
- `BAD_BASE_ADDR`: Invalid base address in record leader

### Warnings (Continue Processing)
- `UNKNOWN_OBJ_CODE`: Object type not in catalog
- `MISSING_REQUIRED_ATTR`: Required attribute missing from feature
- `DEPTH_OUT_OF_RANGE`: Depth value outside expected range (-100 to 15000m)
- `MISSING_FIELD_TERM`: Field terminator (0x1E) missing
- `INVALID_SUBFIELD_DELIM`: Unexpected subfield delimiter placement
- `DANGLING_POINTER`: Reference to non-existent record
- `COORD_COUNT_MISMATCH`: Coordinate count doesn't match declared value
- `EMPTY_REQUIRED_FIELD`: Required field contains no data
- `INVALID_RUIN_CODE`: Unsupported record update instruction

### Info Messages (Informational)
- `POLYGON_CLOSED_AUTO`: Polygon automatically closed
- `DEGENERATE_EDGE`: Geometry simplified due to invalid coordinates

## Malformed Record Resilience

NavTool's S-57 parser is designed to gracefully handle corrupted or malformed ENC files commonly encountered in marine environments. This section covers the parser's resilience features and diagnostic capabilities implemented in Issue 20.x.

### Parser Resilience Features

**Graceful Degradation**
- Parser continues processing despite structural corruption
- Malformed records are skipped with appropriate warnings
- Partial chart data remains usable for navigation

**Strict Mode Control**
- Development mode: Collect all warnings, continue parsing
- Production mode: Escalate critical errors to exceptions
- Testing mode: Fail fast with low warning threshold

**Warning Classification**
- Machine-actionable warning codes for automated handling
- Severity levels (Info, Warning, Error) for appropriate response
- Contextual information (record ID, feature ID) for debugging

### Common Malformed Record Scenarios

#### 1. Truncated Leader (LEADER_TRUNCATED)
**Cause**: Network transmission errors, disk corruption, incomplete file transfers
**Symptoms**: Records appear to be cut off at header level
**Resolution**: Parser skips truncated records, continues with remaining data

```dart
// Check for truncated leader warnings
final warnings = chart.warnings?.where((w) => 
  w.code == S57WarningCodes.leaderTruncated).toList() ?? [];
if (warnings.isNotEmpty) {
  print('Truncated records found: ${warnings.length}');
  // Consider re-downloading chart if many truncated records
}
```

#### 2. Directory Length Mismatch (FIELD_LEN_MISMATCH)
**Cause**: Corruption in record directory entries
**Symptoms**: Fields claim different length than actual data
**Resolution**: Parser uses actual field boundaries, warns about mismatch

#### 3. Missing Field Terminators (MISSING_FIELD_TERM)
**Cause**: Binary corruption affecting delimiter bytes
**Symptoms**: Fields run together without proper separation
**Resolution**: Parser attempts field boundary detection using context

#### 4. Invalid Subfield Delimiters (INVALID_SUBFIELD_DELIM)
**Cause**: Corruption in structured field data
**Symptoms**: Unexpected 0x1F bytes in field content
**Resolution**: Parser handles unexpected delimiters gracefully

#### 5. Dangling Spatial Pointers (DANGLING_POINTER)
**Cause**: Reference integrity corruption in spatial features
**Symptoms**: FSPT records point to non-existent VRID records
**Resolution**: Parser continues, warns about broken references

#### 6. Coordinate Count Mismatch (COORD_COUNT_MISMATCH)
**Cause**: Corruption in vector record point counts
**Symptoms**: VRPT declares N points but provides different count
**Resolution**: Parser uses actual coordinate data available

#### 7. Empty Required Fields (EMPTY_REQUIRED_FIELD)
**Cause**: Data corruption affecting essential chart metadata
**Symptoms**: DSID or DSPM fields contain no data
**Resolution**: Parser continues with reduced functionality

#### 8. Invalid Update Instructions (INVALID_RUIN_CODE)
**Cause**: Corruption in update file processing codes
**Symptoms**: RUIN field contains unsupported operation codes
**Resolution**: Parser skips invalid updates, preserves base data

### Diagnostic Commands for Malformed Records

```dart
// Test parsing resilience with development options
final options = S57ParseOptions.development(); // strictMode: false
final chart = S57Parser.parse(data, options: options);

// Analyze malformed record patterns
final malformedWarnings = chart.warnings?.where((w) => [
  S57WarningCodes.leaderTruncated,
  S57WarningCodes.fieldLenMismatch,
  S57WarningCodes.missingFieldTerminator,
  S57WarningCodes.invalidSubfieldDelim,
  S57WarningCodes.danglingPointer,
  S57WarningCodes.coordinateCountMismatch,
  S57WarningCodes.emptyRequiredField,
  S57WarningCodes.invalidRUINCode,
].contains(w.code)).toList() ?? [];

print('Malformed record issues: ${malformedWarnings.length}');
for (final warning in malformedWarnings.take(10)) {
  print('${warning.code}: ${warning.message}');
}

// Verify essential chart data integrity
if (chart.features.isNotEmpty) {
  print('Chart still usable: ${chart.features.length} features parsed');
  print('Navigation data available: ${chart.summary()}');
} else {
  print('Chart severely corrupted - consider re-downloading');
}
```

### Testing Parser Resilience

For comprehensive testing of parser resilience against corruption:

```bash
# Run malformed record tests (Issue 20.x test suite)
flutter test test/core/services/s57/malformed/ --timeout 30s

# Run fuzz tests for random corruption patterns
flutter test test/core/services/s57/malformed/fuzz_resilience_test.dart --tags fuzz

# Test strict mode error escalation
flutter test test/core/services/s57/malformed/ --name "strict mode"
```

### Recovery Strategies

**For Charts with Many Warnings:**
1. Check warning distribution - if concentrated in specific records, may indicate localized corruption
2. Verify chart source integrity - re-download if possible
3. Use bounds filtering to work around corrupted regions
4. Consider fallback to previous chart edition

**For Strict Mode Failures:**
1. Run in development mode to collect full warning list
2. Address first critical error shown in warning collector
3. Use custom parse options with higher warning thresholds
4. Implement graceful degradation in navigation application

**For Performance Impact:**
1. Warning collection has bounded limits (1000 max) to prevent memory issues
2. Parser implements early termination on excessive corruption
3. Use `maxWarnings` parameter to control warning overhead
4. Monitor parsing time and fail over to cached charts if needed

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