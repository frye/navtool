# S-57 Format Overview

## Introduction

S-57 is the IHO (International Hydrographic Organization) standard for Electronic Navigational Chart (ENC) data exchange. This document provides a technical overview of the S-57 format as implemented in NavTool, focusing on the key concepts needed to understand chart parsing and data extraction.

## Record Flow Diagram (ISO 8211)

S-57 files use the ISO/IEC 8211 data description file standard as their underlying format:

```
S-57 File (.000)
├── Data Descriptive Record (DDR)
│   ├── Leader (24 bytes)
│   ├── Directory 
│   └── Field Area
│       ├── Data Set Identification (DSID)
│       ├── Data Set Structure Information (DSSI)  
│       └── Field Control Fields
└── Data Records (DR)
    ├── Feature Records
    │   ├── Feature Record Identifier (FRID)
    │   ├── Feature Object Identifier (FOID)
    │   └── Attributes (ATTF/NATF)
    ├── Spatial Records
    │   ├── Vector Record Identifier (VRID)
    │   ├── Vector Record Pointer (VRPT)
    │   └── Spatial Geometry (SG2D/SG3D)
    └── Update Records (.001+)
        ├── Insert/Delete/Modify
        └── Record Version (RVER)
```

## Object Catalog Subset Table

NavTool implements the following S-57 object classes commonly found in navigational charts:

| Acronym | Code | Object Class | Typical Attributes |
|---------|------|--------------|-------------------|
| DEPARE  | 42   | Depth Area   | DRVAL1, DRVAL2, QUASOU |
| SOUNDG  | 129  | Sounding     | VALSOU, QUASOU, TECSOU |
| COALNE  | 30   | Coastline    | CATCOA, CONRAD, OBJNAM |
| LIGHTS  | 75   | Light        | COLOUR, HEIGHT, LITCHR, SIGGRP |
| BOYLAT  | 58   | Lateral Buoy | CATBOY, COLOUR, COLPAT, BOYSHP |
| BOYCAR  | 59   | Cardinal Buoy| CATBOY, COLOUR, COLPAT, BOYSHP |
| BOYSAW  | 61   | Safe Water Buoy | CATBOY, COLOUR, COLPAT |
| BCNCAR  | 57   | Cardinal Beacon | CATBCN, COLOUR, COLPAT |
| OBSTRN  | 104  | Obstruction  | CATOBS, VALSOU, WATLEV |
| WRECKS  | 159  | Wreck        | CATWRK, VALSOU, WATLEV |
| UWTROC  | 158  | Underwater Rock | VALSOU, WATLEV, QUASOU |

## Attribute Types Table

S-57 attributes follow strict typing rules:

| Type | Format | Example Values | Usage |
|------|--------|----------------|-------|
| **Real** | IEEE floating point | 12.5, -23.456 | Depths (VALSOU), coordinates |
| **Integer** | Signed 32-bit | 1, 42, -10 | Object codes, enumerated values |
| **Coded String** | Enumerated values | 1,2,3 | Categories (CATBOY: 1=port, 2=starboard) |
| **Free Text** | UTF-8 string | "Pier A", "Local knowledge required" | Names (OBJNAM), information (INFORM) |
| **List** | Comma-separated | "1,3,5" | Multiple categories or colors |

## Geometry Assembly Overview

S-57 geometry is constructed through spatial record references:

### Point Geometry
```
Feature (SOUNDG) → Spatial Record (SG2D) → Coordinates
FRID: Feature ID
FOID: Object identifier  
SG2D: lat/lon coordinates
```

### Line Geometry  
```
Feature (COALNE) → Edge References → Node Chain
FRID: Feature ID
FOID: Object identifier
VRPT: Vector record pointers to edges
Edges: Connected nodes forming coastline
```

### Area Geometry
```
Feature (DEPARE) → Face Reference → Edge Ring
FRID: Feature ID  
FOID: Object identifier
VRPT: Pointer to face record
Face: Collection of edges forming closed polygon
```

## Update Sequencing

S-57 charts use incremental updates to maintain current information:

1. **Base Chart** (.000): Complete chart dataset
2. **Update 1** (.001): Changes since base chart
3. **Update N** (.00N): Changes since update N-1

### Update Processing Rules
- Updates must be applied in sequence (no gaps)
- Each update increments the Record Version (RVER)
- Three update operations: Insert, Delete, Modify
- Missing intermediate updates trigger `UPDATE_GAP` warning

### Update Validation
```dart
// Example update sequence validation
if (currentRver + 1 != updateRver) {
  warnings.error(
    S57WarningCodes.updateGap,
    'Update gap: expected RVER ${currentRver + 1}, got $updateRver'
  );
}
```

## Spatial Index Summary

NavTool uses an R-tree spatial index for efficient geographic queries:

### Index Structure
- **R-tree nodes**: Hierarchical bounding rectangles
- **Leaf nodes**: Individual feature bounding boxes
- **Internal nodes**: Aggregate bounding boxes

### Performance Characteristics
- **Point queries**: O(log n) typical, O(n) worst case
- **Bounds queries**: O(log n + k) where k = results
- **Build time**: O(n log n) for bulk loading
- **Memory usage**: ~40 bytes per feature

### Query Types
```dart
// Spatial query examples
final nearbyFeatures = chart.findFeatures(
  bounds: S57Bounds(north: 47.61, south: 47.60, east: -122.33, west: -122.34)
);

final soundingsInArea = chart.findFeatures(
  types: {'SOUNDG'}, 
  bounds: harborBounds,
  limit: 100
);
```

## Warning Severity Table

The parser generates structured warnings with three severity levels:

| Severity | Description | Action | Examples |
|----------|-------------|--------|----------|
| **Info** | Minor issues, auto-corrections | Continue processing | POLYGON_CLOSED_AUTO, DEPTH_OUT_OF_RANGE |
| **Warning** | Non-critical issues | Continue with caution | UNKNOWN_OBJ_CODE, MISSING_REQUIRED_ATTR |
| **Error** | Critical data integrity issues | Stop in strict mode | LEADER_LEN_MISMATCH, UPDATE_GAP |

### Strict Mode Behavior
- **Development**: All warnings logged, processing continues
- **Production**: Error-level warnings throw `S57StrictModeException`
- **Testing**: Configurable warning threshold for validation

### Warning Code Categories
- **ISO 8211 Parsing**: LEADER_LEN_MISMATCH, DIR_TRUNCATED, FIELD_BOUNDS
- **S-57 Validation**: UNKNOWN_OBJ_CODE, MISSING_REQUIRED_ATTR
- **Geometry Processing**: DEGENERATE_EDGE, POLYGON_CLOSED_AUTO  
- **Update Processing**: UPDATE_GAP, UPDATE_RVER_MISMATCH
- **Data Sanity**: DEPTH_OUT_OF_RANGE

## Performance Targets

For production marine navigation use:

| Operation | Target | Typical |
|-----------|--------|---------|
| Chart parsing (5MB) | < 2 seconds | 800ms |
| Spatial query (100 results) | < 10ms | 3ms |
| Feature extraction (1000 features) | < 50ms | 25ms |
| GeoJSON export (1000 features) | < 100ms | 60ms |
| Update application | < 500ms | 200ms |

## Integration Patterns

### Basic Parsing
```dart
import 'package:navtool/s57.dart';

final data = await File('US5WA50M.000').readAsBytes();
final chart = S57Parser.parse(data);
```

### Production Configuration
```dart
final options = S57ParseOptions.production(); // Strict mode enabled
final chart = S57Parser.parse(data, options: options);
```

### Warning Collection
```dart
final collector = S57WarningCollector(
  options: S57ParseOptions(strictMode: false, maxWarnings: 100)
);
// Warnings accessible via collector.warnings
```

## References

- [IHO S-57 Edition 3.1 Specification](https://iho.int/publications/standards-and-specifications/)
- [ISO/IEC 8211:1994 Data Description File Standard](https://www.iso.org/standard/15224.html)
- [NavTool S-57 Implementation Analysis](../S57_IMPLEMENTATION_ANALYSIS.md)
- [S-57 Troubleshooting Guide](s57_troubleshooting.md)