# Copilot Instructions for NavTool

## Project Overview

NavTool is a Flutter-based marine navigation chart viewer for Windows, macOS, Linux, iOS, and Android. It displays official NOAA Electronic Navigational Chart (ENC) data for coastal areas of the United States.

## Critical Requirements

### NOAA Data Only

**This is a marine navigation application. All chart data MUST come from official NOAA sources.**

✅ **Approved Data Sources:**
- **NOAA ENC Direct to GIS** (https://encdirect.noaa.gov/) - Primary source for high-resolution coastline data
  - Uses ArcGIS REST services to download pre-converted shapefiles
  - No GDAL required - uses `pyshp` library
  - Provides ~1-5m resolution coastlines from official ENCs
  - Data updated weekly from official NOAA ENCs
  
- **NOAA Electronic Navigational Charts (ENCs)** - Official S-57 format charts
  - https://nauticalcharts.noaa.gov/charts/noaa-enc.html
  - If processing S-57 directly, prefer using NOAA ENC Direct to GIS instead

- **NOAA GSHHG** (Global Self-consistent Hierarchical High-resolution Geography)
  - https://www.ngdc.noaa.gov/mgg/shorelines/
  - Lower resolution (~80m), use only as fallback or for overview scales

❌ **Prohibited Data Sources:**
- OpenStreetMap coastlines or any OSM data
- OpenSeaMap or community-sourced marine data
- Any non-NOAA coastline or chart data
- Synthetic or interpolated coastline data

### Data Accuracy

**Marine applications require extreme accuracy. Never compromise coastline precision.**

- ❌ **NO smoothing or interpolation** of coastline geometry
- ❌ **NO spline curves or Bezier interpolation**
- ✅ **Douglas-Peucker simplification** is acceptable for LOD (level-of-detail) optimization
- ✅ Points may be reduced at low zoom levels, but original source accuracy must be preserved

### Binary Format

NavTool uses a custom binary format (`.bin` files) for optimized coastline loading:

```
Header:
  Magic:    4 bytes ASCII "NVTL"
  Version:  2 bytes uint16 (little-endian)
  Count:    4 bytes uint32 (polygon count)
  Bounds:   4 x float64 (min_lon, min_lat, max_lon, max_lat)

Per Polygon:
  Exterior point count: uint32
  Interior ring count:  uint32
  Exterior points:      N x 2 x float64 (lon, lat)
  Per Interior Ring:
    Point count: uint32
    Points:      N x 2 x float64 (lon, lat)
```

## Project Structure

```
navtool/
├── lib/
│   ├── main.dart              # App entry, LOD loading
│   ├── navtool.dart           # Main widget
│   ├── models/
│   │   └── geo_types.dart     # Geographic data structures
│   ├── parser/
│   │   └── coastline_parser.dart  # GeoJSON/binary parsing
│   └── renderer/
│       └── coastline_renderer.dart # Canvas rendering, LOD selection
├── assets/
│   └── charts/                # Chart data files (.bin, .geojson)
├── tools/
│   ├── download_enc_direct.py # PRIMARY: NOAA ENC Direct downloader
│   ├── download_noaa_data.py  # GSHHG downloader (lower resolution)
│   └── download_enc_data.py   # S-57 direct parser (requires GDAL)
└── ...
```

## Data Download Tools

### Recommended: `download_enc_direct.py`

Use this tool for high-resolution NOAA ENC coastline data:

```bash
# Download Seattle area (harbor scale - highest detail)
python tools/download_enc_direct.py --region seattle --scale-band harbor

# List available regions
python tools/download_enc_direct.py --list-regions

# List scale bands
python tools/download_enc_direct.py --list-scale-bands

# Download from all scale bands for maximum coverage
python tools/download_enc_direct.py --region seattle --all-scale-bands
```

Scale bands (most to least detailed):
- `berthing` - ~1:5,000 (port facilities)
- `harbor` - ~1:10,000-1:50,000 (harbors) **← Recommended**
- `approach` - ~1:50,000-1:150,000 (approaches)
- `coastal` - ~1:150,000-1:600,000 (coastal)
- `general` - ~1:600,000-1:1,500,000 (general)
- `overview` - 1:1,500,000+ (overview)

### Fallback: `download_noaa_data.py`

Use for GSHHG data (lower resolution, ~80m):

```bash
python tools/download_noaa_data.py --region seattle --resolution f
```

## LOD System

NavTool implements multi-level-of-detail rendering:

- `lod0` - Full source resolution (highest detail)
- `lod1` - Ultra-high detail
- `lod2` - Very high detail
- `lod3` - High detail
- `lod4` - Medium detail
- `lod5` - Low detail (overview)

LOD files are named: `{region}_coastline_lod{N}.bin`

The renderer automatically selects appropriate LOD based on zoom level.

## Flutter/Dart Guidelines

- Target Flutter 3.x
- Use `CustomPainter` for canvas rendering
- Binary assets are loaded via `rootBundle`
- Coordinate system: WGS84 (EPSG:4326)
- Rendering: lon/lat to screen pixel transformation

## Dependencies

### Dart/Flutter
- Standard Flutter SDK
- No additional packages required for core functionality

### Python (Data Tools)
- `pyshp` - Shapefile reading (required)
- Standard library only for network/file operations
- **GDAL is NOT required** for ENC Direct downloads

## Testing

When testing coastline rendering:
1. Verify coastlines match reference marine charts at all zoom levels
2. Check that no jagged edges appear at high zoom
3. Ensure LOD switching is smooth
4. Validate binary file parsing (check magic number "NVTL")

## Common Issues

### "Coastline too coarse at high zoom"
- Source data resolution is insufficient
- Use `download_enc_direct.py` with `--scale-band harbor` for higher resolution
- Ensure LOD0 is loading (check console for "Using LOD: 0")

### "Binary file format error"
- Magic number mismatch - should be ASCII "NVTL"
- Re-generate binary files with latest Python tools

### "No features found"
- Region may not have ENC coverage at selected scale band
- Try `--all-scale-bands` option
- Check NOAA ENC Direct viewer to verify coverage

## Important Notes

1. **This is a marine application** - data accuracy is critical for safety
2. **NOAA-only sources** - never use non-NOAA coastline data
3. **No smoothing** - preserve original geometry precision
4. **Weekly updates** - NOAA ENC Direct data is updated weekly
5. **Not for navigation** - ENC Direct data is for GIS purposes only; official ENCs required for actual navigation
