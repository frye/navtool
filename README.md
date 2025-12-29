# NavTool - NOAA Chart Viewer

A minimal cross-platform application for downloading and displaying free NOAA nautical charts. Currently focused on coastline rendering.

## Features

- **Cross-Platform**: Runs on Windows, Linux, macOS, iOS, and Android
- **Coastline Rendering**: Displays land (teal) and water (blue) areas
- **Interactive Navigation**: Pan and zoom support with touch/mouse gestures
- **Optimized Format**: Binary format for fast chart loading
- **GeoJSON Support**: Standard GeoJSON format for coastline data

## Screenshots

The application displays coastline data with:
- Water areas in blue (#1E88E5)
- Land areas in teal (#26A69A)
- Coastline stroke in dark teal (#004D40)

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+)
- For mobile: Android Studio / Xcode
- Python 3.8+ (for downloading NOAA data)

### Installation

1. Clone the repository:
   ```bash
   cd navtool
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Download NOAA coastline data (optional - app includes demo data):
   ```bash
   pip install pyshp
   python tools/download_noaa_data.py --region seattle --output assets/charts/
   ```

4. Run the application:
   ```bash
   # Desktop (Windows/Linux/macOS)
   flutter run -d windows
   flutter run -d linux
   flutter run -d macos

   # Mobile
   flutter run -d android
   flutter run -d ios
   ```

> **⚠️ IMPORTANT**: This is a **native-only application**. Do NOT run on web, web-server, or any browser platform. See [PLATFORMS.md](PLATFORMS.md) for details.

## Project Structure

```
navtool/
├── lib/
│   ├── main.dart                    # Application entry point
│   ├── models/
│   │   └── geo_types.dart           # Geographic data types (GeoPoint, GeoBounds, etc.)
│   ├── parser/
│   │   └── coastline_parser.dart    # GeoJSON and binary format parser
│   └── renderer/
│       └── coastline_renderer.dart  # CustomPainter for chart rendering
├── assets/
│   └── charts/                      # Chart data files (.geojson, .bin)
├── tools/
│   └── download_noaa_data.py        # NOAA data download script
└── pubspec.yaml                     # Flutter dependencies
```

## Data Format

### GeoJSON (Standard)

The app accepts standard GeoJSON with Polygon/MultiPolygon geometries:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [[-122.5, 47.6], [-122.4, 47.7], [-122.3, 47.6], [-122.5, 47.6]]
        ]
      }
    }
  ]
}
```

### Binary Format (Optimized)

For better performance, the app supports a custom binary format:

- **Magic**: "NVTL" (4 bytes)
- **Version**: uint16
- **Polygon count**: uint32
- **Bounds**: 4 × float64 (minLon, minLat, maxLon, maxLat)
- **Polygons**: Each with exterior ring and optional interior rings (holes)

The binary format is typically 30-50% smaller and loads significantly faster.

## NOAA Data Sources

### GSHHG (Global Self-consistent, Hierarchical, High-resolution Geography)

The download script uses NOAA's GSHHG database:
- **URL**: https://www.ngdc.noaa.gov/mgg/shorelines/
- **Resolution Options**: Full, High, Intermediate, Low, Crude
- **License**: Public domain

### Available Regions

```bash
python tools/download_noaa_data.py --list-regions
```

- `seattle` - Puget Sound area
- `san_francisco` - San Francisco Bay
- `chesapeake` - Chesapeake Bay
- `florida_keys` - Florida Keys

### Adding Custom Regions

Edit `tools/download_noaa_data.py` and add to the `REGIONS` dictionary:

```python
REGIONS = {
    "my_region": {
        "name": "My Custom Region",
        "bounds": (min_lon, min_lat, max_lon, max_lat),
        "description": "Description of the region"
    }
}
```

## Controls

| Action | Desktop | Mobile |
|--------|---------|--------|
| Pan | Click + Drag | Touch + Drag |
| Zoom In | Scroll Up / + Button | Pinch Out / + Button |
| Zoom Out | Scroll Down / - Button | Pinch In / - Button |
| Reset View | Center Button | Center Button |

## Architecture

### Rendering Pipeline

1. **Data Loading**: GeoJSON/Binary parsed into `CoastlineData`
2. **Coordinate Transformation**: Geographic → Screen coordinates
3. **Path Building**: Polygons converted to Flutter `Path` objects
4. **Rendering**: `CustomPainter` draws water background, then land fills

### Coordinate System

- Uses a simple Mercator-like projection
- Geographic coordinates (longitude/latitude) mapped to screen pixels
- Pan offset and zoom factor applied for navigation

## Future Roadmap

- [ ] Additional chart layers (depth contours, navigation aids)
- [ ] In-app chart downloading
- [ ] Offline chart storage
- [ ] GPS integration for position display
- [ ] Route planning
- [ ] S-57/ENC chart support

## License

This project is open source. NOAA chart data is public domain.

## Acknowledgments

- NOAA for providing free nautical chart data
- GSHHG database maintained by Paul Wessel and Walter H.F. Smith
