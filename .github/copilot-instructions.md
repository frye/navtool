# Copilot Instructions for NavTool

## Project Overview

NavTool is a Flutter-based marine navigation chart viewer for Windows, macOS, Linux, iOS, and Android. It displays official NOAA chart data using a multi-layer approach:

1. **GSHHG** (Global) - Bundled crude resolution + on-demand higher resolutions
2. **NOAA ENC Direct** (Regional) - High-resolution US coastal data

## Critical Requirements

### NOAA Data Only

**This is a marine navigation application. All chart data MUST come from official NOAA sources.**

✅ **Approved Data Sources:**
- **NOAA ENC Direct to GIS** (https://encdirect.noaa.gov/) - Primary source for high-resolution coastline data
  - Uses ArcGIS REST services to download pre-converted shapefiles
  - No GDAL required - uses `pyshp` library
  - Provides ~1-5m resolution coastlines from official ENCs
  - Data updated weekly from official NOAA ENCs
  
- **NOAA GSHHG** (Global Self-consistent Hierarchical High-resolution Geography)
  - https://www.ngdc.noaa.gov/mgg/shorelines/
  - Global coverage at multiple resolutions (crude ~80m to full ~200m)
  - Crude resolution bundled with app for instant global display
  - Higher resolutions downloaded on-demand

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

## Architecture

### Multi-Layer Data System

```
┌─────────────────────────────────────────────────────────────────┐
│                     Chart Data Layers                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────┐  ┌────────────────────────────────────┐ │
│  │ GSHHG (Global)     │  │ NOAA ENC Direct (Regional)         │ │
│  │ • Bundled crude    │  │ • High resolution (~1-5m)          │ │
│  │ • On-demand higher │  │ • Downloaded per region            │ │
│  │ • ~80m resolution  │  │ • Harbor/Approach/Coastal scales   │ │
│  └────────────────────┘  └────────────────────────────────────┘ │
│                                                                  │
│  Priority: ENC (if available) > GSHHG (higher res) > GSHHG crude│
└─────────────────────────────────────────────────────────────────┘
```

### Manifest System

The app uses `assets/charts/manifest.json` for O(1) chart lookup - critical for low-power devices like Raspberry Pi:

```json
{
  "version": 1,
  "regions": {
    "gshhg_crude_global": {
      "name": "GSHHG Crude (Global)",
      "bounds": [-180, -90, 180, 90],
      "source": "gshhg",
      "gshhgResolution": "crude",
      "files": ["gshhg_crude.bin"]
    },
    "seattle": {
      "name": "Seattle / Puget Sound",
      "bounds": [-123.5, 47.0, -121.5, 48.5],
      "source": "enc",
      "lods": [0, 1, 2, 3, 4, 5],
      "files": ["seattle_coastline_lod0.bin", ...]
    }
  }
}
```

### Binary Format (NVTL)

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
│   ├── main.dart                    # App entry point
│   ├── models/
│   │   ├── geo_types.dart           # Geographic data structures
│   │   └── chart_manifest.dart      # Manifest model for chart regions
│   ├── parser/
│   │   └── coastline_parser.dart    # GeoJSON/binary parsing
│   ├── renderer/
│   │   └── coastline_renderer.dart  # Canvas rendering, LOD selection
│   └── services/
│       └── coastline_data_manager.dart  # Multi-source data manager
├── assets/
│   ├── charts/                      # ENC regional data
│   │   └── manifest.json            # Chart region index
│   └── gshhg/                       # Global GSHHG data
│       └── gshhg_crude.bin          # Bundled crude resolution
├── tools/
│   ├── download_enc_direct.py       # NOAA ENC Direct downloader
│   └── download_gshhg.py            # GSHHG global data downloader
└── ...
```

## Data Download Tools

### ENC Regional Data: `download_enc_direct.py`

Use this tool for high-resolution NOAA ENC coastline data:

```bash
# Download Seattle area (default: harbor + approach + coastal scales)
python tools/download_enc_direct.py --region seattle

# List available regions
python tools/download_enc_direct.py --list-regions

# Download from all scale bands for maximum coverage
python tools/download_enc_direct.py --region seattle --all-scale-bands
```

The script automatically:
- Downloads from multiple scale bands (harbor, approach, coastal)
- Merges overlapping polygons using Shapely to eliminate ENC cell boundaries
- Generates LOD0-LOD5 files with Douglas-Peucker simplification
- Updates the manifest.json file

### GSHHG Global Data: `download_gshhg.py`

Use for global coastline coverage:

```bash
# List available resolutions
python tools/download_gshhg.py --list-resolutions

# Download additional resolutions
python tools/download_gshhg.py --resolution low
python tools/download_gshhg.py --all
```

| Resolution | File Size | Zoom Range |
|------------|-----------|------------|
| crude | ~120 KB | 0-2 (bundled) |
| low | ~1 MB | 2-5 |
| intermediate | ~3.5 MB | 5-8 |
| high | ~12 MB | 8+ |

## LOD System

NavTool implements multi-level-of-detail rendering:

| LOD | Tolerance | Zoom Range | Detail Level |
|-----|-----------|------------|--------------|
| 0 | 0.0 | 15+ | Full source resolution |
| 1 | 0.00005° | 10-15 | Ultra-high |
| 2 | 0.0001° | 6-10 | Very high |
| 3 | 0.0003° | 3-6 | High |
| 4 | 0.0008° | 1.5-3 | Medium |
| 5 | 0.002° | 0-1.5 | Low (overview) |

## Key Services

### CoastlineDataManager

Manages multi-source coastline data:

```dart
final manager = CoastlineDataManager();
await manager.initialize(); // Loads manifest

// Get best data for visible region
final data = await manager.getCoastlineData(bounds, zoom);

// Get all LOD levels for a region
final lods = await manager.getCoastlineLods('seattle');

// Listen to download progress
manager.downloadProgress.listen((progress) {
  print('${progress.description}: ${progress.progress * 100}%');
});
```

### ChartManifest

Provides O(1) lookup for chart regions:

```dart
final manifest = ChartManifest.parse(jsonString);

// Find regions overlapping visible area
final encRegions = manifest.findEncRegions(visibleBounds);
final gshhgRegions = manifest.findGshhgRegions(visibleBounds);
```

## Flutter/Dart Guidelines

- Target Flutter 3.x
- Use `CustomPainter` for canvas rendering
- Binary assets loaded via `rootBundle`
- Coordinate system: WGS84 (EPSG:4326)
- Latitude correction: `cos(centerLat)` for proper aspect ratio at all latitudes

## Dependencies

### Dart/Flutter
- Standard Flutter SDK
- `path_provider` for app data directory
- `vector_math` for math operations

### Python (Data Tools)
- `pyshp` - Shapefile reading (required)
- `shapely` - Polygon merging for ENC data (auto-installed)
- Standard library for network/file operations

## Testing

When testing coastline rendering:
1. Verify coastlines match reference marine charts at all zoom levels
2. Check that no jagged edges appear at high zoom
3. Ensure LOD switching is smooth
4. Validate binary file parsing (check magic number "NVTL")
5. Test global view with GSHHG crude data
6. Test regional zoom with ENC data

## Common Issues

### "No coastline data available"
- Ensure GSHHG crude is bundled in `assets/gshhg/gshhg_crude.bin`
- Run `python tools/download_gshhg.py --bundle-crude` if missing

### "Coastline too coarse at high zoom"
- Download ENC data for the region: `python tools/download_enc_direct.py --region <name>`
- Ensure LOD0 is loading (check console for LOD switch messages)

### "ENC cell boundaries visible as rectangles"
- Re-download with polygon merging: `python tools/download_enc_direct.py --region <name>`
- Do NOT use `--no-merge` flag

### "Binary file format error"
- Magic number mismatch - should be ASCII "NVTL"
- Re-generate binary files with latest Python tools

## Important Notes

1. **This is a marine application** - data accuracy is critical for safety
2. **NOAA-only sources** - never use non-NOAA coastline data
3. **No smoothing** - preserve original geometry precision
4. **Manifest-based** - always update manifest.json when adding regions
5. **Not for navigation** - this is for GIS/planning purposes only
