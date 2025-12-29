#!/usr/bin/env python3
"""
NOAA Coastline Data Downloader and Converter

This script downloads coastline data from NOAA and converts it to GeoJSON format
suitable for use with NavTool. It also creates an optimized binary format for
faster loading.

Data Sources:
- NOAA GSHHG (Global Self-consistent, Hierarchical, High-resolution Geography)
- NOAA Shoreline Website: https://shoreline.noaa.gov/

Requirements:
- Python 3.8+
- requests
- shapefile (pyshp)
- json

Usage:
    python download_noaa_data.py --region seattle --output assets/charts/
"""

import argparse
import json
import os
import struct
import sys
import math
import zipfile
from pathlib import Path
from typing import List, Tuple
from urllib.request import urlretrieve

try:
    import shapefile
except ImportError:
    print("Installing required package: pyshp")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

# Region definitions (bounding boxes: min_lon, min_lat, max_lon, max_lat)
REGIONS = {
    "seattle": {
        "name": "Seattle / Puget Sound",
        "bounds": (-123.5, 47.0, -121.5, 48.5),
        "description": "Puget Sound area including Seattle, Tacoma, and surrounding waters"
    },
    "san_francisco": {
        "name": "San Francisco Bay",
        "bounds": (-123.0, 37.4, -121.8, 38.2),
        "description": "San Francisco Bay Area"
    },
    "chesapeake": {
        "name": "Chesapeake Bay",
        "bounds": (-77.5, 36.5, -75.5, 39.5),
        "description": "Chesapeake Bay area"
    },
    "florida_keys": {
        "name": "Florida Keys",
        "bounds": (-82.0, 24.3, -80.0, 25.5),
        "description": "Florida Keys and surrounding waters"
    }
}

# NOAA GSHHG data URL (hosted by NOAA/NGDC)
GSHHG_URL = "https://www.ngdc.noaa.gov/mgg/shorelines/data/gshhg/latest/gshhg-shp-2.3.7.zip"
GSHHG_FILENAME = "gshhg-shp-2.3.7.zip"

# LOD simplification tolerances (degrees). Lower = more detailed.
# Spread tolerances further apart so each level is visually distinct.
LOD_LEVELS = [
    ("lod0", 0.0),         # Finest (full source detail)
    ("lod1", 0.0002),      # Ultra-high
    ("lod2", 0.0005),      # Very high
    ("lod3", 0.0010),      # High
    ("lod4", 0.0030),      # Medium
    ("lod5", 0.0080),      # Low
]


def download_gshhg(cache_dir: Path) -> Path:
    """Download GSHHG shapefile data from NOAA."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    zip_path = cache_dir / GSHHG_FILENAME
    
    if zip_path.exists():
        print(f"Using cached GSHHG data: {zip_path}")
        return zip_path
    
    print(f"Downloading GSHHG data from NOAA...")
    print(f"URL: {GSHHG_URL}")
    
    def progress_hook(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            percent = min(100, downloaded * 100 / total_size)
            sys.stdout.write(f"\rProgress: {percent:.1f}% ({downloaded / 1024 / 1024:.1f} MB)")
            sys.stdout.flush()
    
    urlretrieve(GSHHG_URL, zip_path, progress_hook)
    print("\nDownload complete!")
    return zip_path


def extract_gshhg(zip_path: Path, extract_dir: Path) -> Path:
    """Extract GSHHG shapefile data."""
    if (extract_dir / "GSHHS_shp").exists():
        print(f"Using cached extracted data: {extract_dir}")
        return extract_dir / "GSHHS_shp"
    
    print(f"Extracting GSHHG data...")
    with zipfile.ZipFile(zip_path, 'r') as zf:
        zf.extractall(extract_dir)
    
    return extract_dir / "GSHHS_shp"


def load_coastline_shapefile(shp_dir: Path, resolution: str = "h") -> shapefile.Reader:
    """
    Load coastline shapefile at specified resolution.
    
    Resolutions:
    - f: full (highest resolution)
    - h: high
    - i: intermediate
    - l: low
    - c: crude (lowest resolution)
    """
    # GSHHS Level 1 = coastline (boundary between land and ocean)
    shp_path = shp_dir / resolution / f"GSHHS_{resolution}_L1.shp"
    
    if not shp_path.exists():
        raise FileNotFoundError(f"Shapefile not found: {shp_path}")
    
    print(f"Loading shapefile: {shp_path}")
    return shapefile.Reader(str(shp_path))


def filter_shapes_by_bounds(
    sf: shapefile.Reader,
    bounds: Tuple[float, float, float, float]
) -> List[dict]:
    """Filter shapefile records by bounding box."""
    min_lon, min_lat, max_lon, max_lat = bounds
    filtered_shapes = []
    
    for shape_rec in sf.iterShapeRecords():
        shape = shape_rec.shape
        
        # Check if shape's bounding box intersects with our region
        if shape.shapeType == shapefile.POLYGON:
            shape_bounds = shape.bbox  # (min_x, min_y, max_x, max_y)
            
            # Check for intersection
            if (shape_bounds[0] <= max_lon and shape_bounds[2] >= min_lon and
                shape_bounds[1] <= max_lat and shape_bounds[3] >= min_lat):
                filtered_shapes.append(shape)
    
    return filtered_shapes


def clip_polygon_to_bounds(
    polygon_points: List[Tuple[float, float]],
    bounds: Tuple[float, float, float, float]
) -> List[Tuple[float, float]]:
    """Simple polygon clipping to bounding box."""
    min_lon, min_lat, max_lon, max_lat = bounds
    clipped = []
    
    for lon, lat in polygon_points:
        # Clamp points to bounds
        clamped_lon = max(min_lon, min(max_lon, lon))
        clamped_lat = max(min_lat, min(max_lat, lat))
        clipped.append((clamped_lon, clamped_lat))
    
    return clipped


def shapes_to_geojson(shapes: List, bounds: Tuple[float, float, float, float]) -> dict:
    """Convert shapefile shapes to GeoJSON format."""
    features = []
    
    for shape in shapes:
        if shape.shapeType != shapefile.POLYGON:
            continue
        
        # Handle parts (multiple rings in a polygon)
        parts = list(shape.parts) + [len(shape.points)]
        
        for i in range(len(parts) - 1):
            ring_points = shape.points[parts[i]:parts[i+1]]
            
            # Clip to bounds
            clipped_points = clip_polygon_to_bounds(ring_points, bounds)
            
            if len(clipped_points) >= 3:
                # Close the ring if needed
                if clipped_points[0] != clipped_points[-1]:
                    clipped_points.append(clipped_points[0])
                
                feature = {
                    "type": "Feature",
                    "properties": {},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [clipped_points]
                    }
                }
                features.append(feature)
    
    return {
        "type": "FeatureCollection",
        "features": features
    }


def _perpendicular_distance(point, start, end) -> float:
    """Perpendicular distance from point to line segment (lon/lat)."""
    (px, py), (sx, sy), (ex, ey) = point, start, end
    line_mag = math.hypot(ex - sx, ey - sy)
    if line_mag == 0:
        return math.hypot(px - sx, py - sy)
    u = max(0.0, min(1.0, ((px - sx) * (ex - sx) + (py - sy) * (ey - sy)) / (line_mag ** 2)))
    ix = sx + u * (ex - sx)
    iy = sy + u * (ey - sy)
    return math.hypot(px - ix, py - iy)


def douglas_peucker(points: List[Tuple[float, float]], tolerance: float) -> List[Tuple[float, float]]:
    """Simplify a polyline using Douglas-Peucker. Points may already be closed."""
    if len(points) <= 2 or tolerance <= 0:
        return points

    # If closed ring, keep closure for later
    is_closed = points[0] == points[-1]
    working = points[:-1] if is_closed else points

    def _simplify(segment):
        start, end = segment[0], segment[-1]
        max_dist = -1.0
        index = 0
        for i in range(1, len(segment) - 1):
                        dist = _perpendicular_distance(segment[i], start, end)
                        if dist > max_dist:
                                max_dist = dist
                                index = i
        if max_dist > tolerance:
                        left = _simplify(segment[: index + 1])
                        right = _simplify(segment[index:])
                        return left[:-1] + right
        else:
                        return [start, end]

    simplified = _simplify(working)
    if is_closed:
        if simplified[0] != simplified[-1]:
            simplified.append(simplified[0])
    return simplified


def simplify_geojson(geojson: dict, tolerance: float) -> dict:
    """Return a simplified copy of a GeoJSON FeatureCollection."""
    if tolerance <= 0:
        return geojson

    out_features = []
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        if geom.get("type") != "Polygon":
            continue
        new_coords = []
        for ring in geom.get("coordinates", []):
            simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
            if len(simplified) < 4:
                simplified = ring  # fallback to original ring
            if simplified[0] != simplified[-1]:
                simplified.append(simplified[0])
            new_coords.append([(p[0], p[1]) for p in simplified])

        out_features.append({
            "type": "Feature",
            "properties": feature.get("properties", {}),
            "geometry": {
                "type": "Polygon",
                "coordinates": new_coords
            }
        })

    return {"type": "FeatureCollection", "features": out_features}


def geojson_to_binary(geojson: dict) -> bytes:
    """
    Convert GeoJSON to optimized binary format.
    
    Format:
    - Magic: 4 bytes "NVTL"
    - Version: 2 bytes (uint16)
    - Polygon count: 4 bytes (uint32)
    - Bounds: 4 x float64 (32 bytes)
    - For each polygon:
        - Exterior ring point count: 4 bytes (uint32)
        - Interior ring count: 4 bytes (uint32)
        - Exterior ring points: N x 2 x float64
        - For each interior ring:
            - Point count: 4 bytes (uint32)
            - Points: N x 2 x float64
    """
    polygons = []
    min_lon = float('inf')
    min_lat = float('inf')
    max_lon = float('-inf')
    max_lat = float('-inf')
    
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        if geom.get("type") == "Polygon":
            coords = geom.get("coordinates", [])
            if coords:
                exterior = [(p[0], p[1]) for p in coords[0]]
                interiors = [[(p[0], p[1]) for p in ring] for ring in coords[1:]]
                
                for lon, lat in exterior:
                    min_lon = min(min_lon, lon)
                    min_lat = min(min_lat, lat)
                    max_lon = max(max_lon, lon)
                    max_lat = max(max_lat, lat)
                
                polygons.append((exterior, interiors))
        elif geom.get("type") == "MultiPolygon":
            for poly_coords in geom.get("coordinates", []):
                if poly_coords:
                    exterior = [(p[0], p[1]) for p in poly_coords[0]]
                    interiors = [[(p[0], p[1]) for p in ring] for ring in poly_coords[1:]]
                    
                    for lon, lat in exterior:
                        min_lon = min(min_lon, lon)
                        min_lat = min(min_lat, lat)
                        max_lon = max(max_lon, lon)
                        max_lat = max(max_lat, lat)
                    
                    polygons.append((exterior, interiors))
    
    # Build binary data
    data = bytearray()
    
    # Header
    data.extend(b'NVTL')  # Magic
    data.extend(struct.pack('<H', 1))  # Version
    data.extend(struct.pack('<I', len(polygons)))  # Polygon count
    
    # Bounds
    data.extend(struct.pack('<d', min_lon))
    data.extend(struct.pack('<d', min_lat))
    data.extend(struct.pack('<d', max_lon))
    data.extend(struct.pack('<d', max_lat))
    
    # Polygons
    for exterior, interiors in polygons:
        data.extend(struct.pack('<I', len(exterior)))  # Exterior point count
        data.extend(struct.pack('<I', len(interiors)))  # Interior ring count
        
        for lon, lat in exterior:
            data.extend(struct.pack('<d', lon))
            data.extend(struct.pack('<d', lat))
        
        for interior in interiors:
            data.extend(struct.pack('<I', len(interior)))
            for lon, lat in interior:
                data.extend(struct.pack('<d', lon))
                data.extend(struct.pack('<d', lat))
    
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description="Download and convert NOAA coastline data")
    parser.add_argument(
        "--region",
        choices=list(REGIONS.keys()),
        default="seattle",
        help="Region to download (default: seattle)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="assets/charts",
        help="Output directory for chart files"
    )
    parser.add_argument(
        "--resolution",
        choices=["f", "h", "i", "l", "c"],
        default="h",
        help="Resolution: f=full, h=high, i=intermediate, l=low, c=crude (default: h)"
    )
    parser.add_argument(
        "--cache-dir",
        type=str,
        default=".noaa_cache",
        help="Cache directory for downloaded files"
    )
    parser.add_argument(
        "--list-regions",
        action="store_true",
        help="List available regions and exit"
    )
    
    args = parser.parse_args()
    
    if args.list_regions:
        print("Available regions:")
        for key, info in REGIONS.items():
            print(f"  {key}: {info['name']}")
            print(f"    {info['description']}")
            print(f"    Bounds: {info['bounds']}")
        return
    
    region_info = REGIONS[args.region]
    print(f"Processing region: {region_info['name']}")
    print(f"Bounds: {region_info['bounds']}")
    
    cache_dir = Path(args.cache_dir)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Download and extract GSHHG data
    zip_path = download_gshhg(cache_dir)
    shp_dir = extract_gshhg(zip_path, cache_dir)
    
    # Load shapefile
    sf = load_coastline_shapefile(shp_dir, args.resolution)
    
    # Filter shapes by region
    print(f"Filtering shapes for region...")
    shapes = filter_shapes_by_bounds(sf, region_info['bounds'])
    print(f"Found {len(shapes)} shapes in region")
    
    if not shapes:
        print("Warning: No shapes found in region. Try a different resolution or check bounds.")
        return
    
    # Convert to GeoJSON
    print("Converting to GeoJSON...")
    geojson = shapes_to_geojson(shapes, region_info['bounds'])
    
    # Save base (full detail) with legacy names
    geojson_path = output_dir / f"{args.region}_coastline.geojson"
    with open(geojson_path, 'w') as f:
        json.dump(geojson, f)
    binary_data = geojson_to_binary(geojson)
    binary_path = output_dir / f"{args.region}_coastline.bin"
    with open(binary_path, 'wb') as f:
        f.write(binary_data)

    print(f"Saved base GeoJSON: {geojson_path}")
    print(f"Saved base binary: {binary_path}")

    # Generate LOD variants
    for suffix, tolerance in LOD_LEVELS:
        lod_geojson = geojson if tolerance == 0 else simplify_geojson(geojson, tolerance)
        lod_geojson_path = output_dir / f"{args.region}_coastline_{suffix}.geojson"
        with open(lod_geojson_path, 'w') as f:
            json.dump(lod_geojson, f)

        lod_binary_path = output_dir / f"{args.region}_coastline_{suffix}.bin"
        with open(lod_binary_path, 'wb') as f:
            f.write(geojson_to_binary(lod_geojson))

        print(f"Saved {suffix} GeoJSON (tol={tolerance}): {lod_geojson_path}")
        print(f"Saved {suffix} binary: {lod_binary_path}")

    # Print statistics for base file
    print(f"\nStatistics (base):")
    print(f"  Features: {len(geojson['features'])}")
    print(f"  GeoJSON size: {os.path.getsize(geojson_path) / 1024:.1f} KB")
    print(f"  Binary size: {os.path.getsize(binary_path) / 1024:.1f} KB")
    print(f"  Compression: {os.path.getsize(binary_path) / os.path.getsize(geojson_path) * 100:.1f}%")

    print(f"\nDone! Chart data saved to {output_dir}")


if __name__ == "__main__":
    main()
