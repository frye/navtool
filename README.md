# NavTool - NOAA Chart Viewer

A cross-platform marine chart viewer for displaying official NOAA nautical chart data. Features multi-layer coastline rendering with global GSHHG coverage and high-resolution regional ENC data.

## Features

- **Cross-Platform**: Windows, Linux, macOS, iOS, and Android
- **Multi-Layer Data**: Global GSHHG + Regional NOAA ENC data
- **Level-of-Detail (LOD)**: Automatic detail switching based on zoom level
- **Interactive Navigation**: Pan, zoom, and double-tap to center
- **Optimized Format**: Custom binary format (NVTL) for fast loading
- **Manifest-Based**: O(1) chart lookup, optimized for low-power devices

## Data Architecture

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

### Data Sources

| Source | Resolution | Coverage | Use Case |
|--------|-----------|----------|----------|
| **GSHHG Crude** | ~80m | Global | Bundled, zoom 0-0.5 |
| **GSHHG Low** | ~40m | Global | On-demand, zoom 0.5-2 |
| **GSHHG Intermediate** | ~20m | Global | On-demand, zoom 2-5 |
| **GSHHG High** | ~10m | Global | On-demand, zoom 5-8 |
| **GSHHG Full** | ~200m | Global | On-demand, zoom 8+ |
| **NOAA ENC** | ~1-5m | US Coastal | Regional, zoom 0.5+ (overlays GSHHG) |

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+)
- Python 3.8+ (for data download scripts)
- `pyshp` Python package

### Quick Start

```bash
# 1. Clone and enter the repository
cd navtool

# 2. Install Flutter dependencies
flutter pub get

# 3. GSHHG crude data is bundled - run immediately!
flutter run -d windows

# 4. (Optional) Download high-resolution ENC data for a region
pip install pyshp shapely
python tools/download_enc_direct.py --region seattle
```

### Download Regional ENC Data

For high-resolution regional charts, use the ENC download script:

```bash
# List available regions
python tools/download_enc_direct.py --list-regions

# Download Seattle/Puget Sound (default)
python tools/download_enc_direct.py --region seattle

# Download San Francisco Bay
python tools/download_enc_direct.py --region san_francisco

# Download with all scale bands
python tools/download_enc_direct.py --region seattle --all-scale-bands
```

### Download Additional GSHHG Resolutions

```bash
# List GSHHG resolutions
python tools/download_gshhg.py --list-resolutions

# Download low resolution (~1 MB)
python tools/download_gshhg.py --resolution low

# Download all resolutions
python tools/download_gshhg.py --all
```

> **⚠️ IMPORTANT**: This is a **native-only application**. Do NOT run on web platforms. See [PLATFORMS.md](PLATFORMS.md) for details.

## Project Structure

```
navtool/
├── lib/
│   ├── main.dart                    # Application entry point
│   ├── models/
│   │   ├── geo_types.dart           # Geographic data types
│   │   └── chart_manifest.dart      # Manifest model for chart regions
│   ├── parser/
│   │   └── coastline_parser.dart    # GeoJSON and binary parser
│   ├── renderer/
│   │   └── coastline_renderer.dart  # CustomPainter for chart rendering
│   └── services/
│       └── coastline_data_manager.dart  # Multi-source data manager
├── assets/
│   ├── charts/                      # ENC regional data + manifest.json
│   │   └── manifest.json            # Chart region index
│   └── gshhg/                       # Global GSHHG data
│       └── gshhg_crude.bin          # Bundled crude resolution
├── tools/
│   ├── download_enc_direct.py       # NOAA ENC Direct downloader
│   └── download_gshhg.py            # GSHHG global data downloader
└── pubspec.yaml
```

## Manifest System

The app uses a manifest file for efficient chart discovery:

```json
{
  "version": 1,
  "lastUpdated": "2025-12-29T00:00:00Z",
  "regions": {
    "gshhg_crude_global": {
      "name": "GSHHG Crude (Global)",
      "bounds": [-180, -90, 180, 90],
      "source": "gshhg",
      "gshhgResolution": "crude",
      "lods": [5],
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

## Controls

| Action | Desktop | Mobile |
|--------|---------|--------|
| Pan | Click + Drag | Touch + Drag |
| Zoom In | Scroll Up / + Button | Pinch Out / + Button |
| Zoom Out | Scroll Down / - Button | Pinch In / - Button |
| Center on Point | Double-click | Double-tap |
| Reset View | Center Button | Center Button |

## Binary Format (NVTL)

Custom binary format for optimized loading:

```
Header:
  Magic:    4 bytes ASCII "NVTL"
  Version:  2 bytes uint16 (little-endian)
  Count:    4 bytes uint32 (polygon count)
  Bounds:   4 × float64 (min_lon, min_lat, max_lon, max_lat)

Per Polygon:
  Exterior point count: uint32
  Interior ring count:  uint32
  Exterior points:      N × 2 × float64 (lon, lat)
  Per Interior Ring:
    Point count: uint32
    Points:      N × 2 × float64 (lon, lat)
```

## LOD (Level of Detail) System

The app uses 6 LOD levels for smooth zoom transitions:

| LOD | Tolerance | Zoom Range | Detail Level |
|-----|-----------|------------|--------------|
| 0 | 0.0 | 10+ | Full source resolution |
| 1 | 0.00005° | 6-10 | Ultra-high |
| 2 | 0.0001° | 4-6 | Very high |
| 3 | 0.0003° | 2-4 | High |
| 4 | 0.0008° | 1-2 | Medium |
| 5 | 0.002° | 0.5-1 | Low (overview) |

Below zoom 0.5, ENC regional data hands off to GSHHG global data.

## Adding Custom Regions

### ENC Regions

Edit `tools/download_enc_direct.py` and add to `REGIONS`:

```python
REGIONS = {
    "my_harbor": {
        "name": "My Harbor",
        "bounds": (min_lon, min_lat, max_lon, max_lat),
        "description": "My harbor area"
    }
}
```

Then download:
```bash
python tools/download_enc_direct.py --region my_harbor
```

## Technical Details

### Coordinate System

- **Projection**: Equirectangular with latitude correction
- **Latitude Correction**: `cos(centerLat)` factor for proper aspect ratio
- **Coordinate System**: WGS84 (EPSG:4326)

### Multi-Layer Rendering

The app uses a seamless multi-layer approach:

1. **GSHHG Background**: Draws as fill-only (no stroke) providing base land mass
2. **ENC Overlay**: Draws on top with fill + stroke for detailed coastlines
3. **Same Land Color**: Both layers use identical color so overlap is invisible
4. **LOD0 Optimization**: GSHHG disabled at highest zoom (user zoomed into ENC only)

This approach eliminates double-coastline artifacts since:
- GSHHG provides land fill everywhere (no visible stroke)
- ENC provides the accurate detailed coastline on top
- View bounds expanded 100% to show GSHHG context around ENC regions

### Rendering Pipeline

1. **Manifest Load**: Read `manifest.json` for available regions (O(1) lookup)
2. **Data Selection**: Select best ENC (regional) and GSHHG (global) for zoom
3. **LOD Selection**: Pick appropriate detail level for each layer
4. **Binary Parse**: Load NVTL format into `CoastlineData`
5. **Path Building**: Convert polygons to Flutter `Path` objects
6. **Rendering**: `CustomPainter` draws water → GSHHG fill → ENC fill + stroke

## Future Roadmap

- [ ] In-app GSHHG download (currently Python-based)
- [ ] Automatic download when panning to uncovered areas
- [ ] Additional chart layers (depth contours, navigation aids)
- [ ] GPS integration for position display
- [ ] Route planning
- [ ] Offline chart management UI

## License

This project is open source. 

**Data Licenses:**
- NOAA ENC data: Public domain (US Government)
- GSHHG: GNU Lesser General Public License (LGPL)

## Acknowledgments

- **NOAA** for providing free nautical chart data via ENC Direct to GIS
- **GSHHG database** maintained by Paul Wessel (U. Hawaii) and Walter H.F. Smith (NOAA)
- **Shapely** for polygon merging operations
