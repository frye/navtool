#!/usr/bin/env python3
"""
OpenStreetMap Coastline Data Downloader

Downloads high-resolution coastline data from OpenStreetMap, which provides
very detailed coastlines suitable for marine applications. OSM coastline data
is derived from multiple sources including satellite imagery and is continuously
updated by the community.

Resolution: typically 1-10 meters for populated coastal areas.

Data Source:
- OpenStreetMap coastline extracts from osmdata.openstreetmap.de

Requirements:
- Python 3.8+
- requests
- shapefile (pyshp)

Usage:
    python download_osm_coastline.py --region seattle --output assets/charts/
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

# Region definitions
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

# OSM coastline data - water polygons (preprocessed, split version for faster processing)
OSM_WATER_POLYGONS_URL = "https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip"
OSM_LAND_POLYGONS_URL = "https://osmdata.openstreetmap.de/download/land-polygons-split-4326.zip"

# LOD simplification tolerances (degrees). Lower = more detailed.
# OSM data is much more detailed than GSHHG, so use finer tolerances
LOD_LEVELS = [
    ("lod0", 0.0),          # Finest (full OSM detail)
    ("lod1", 0.000005),     # Ultra-high (~0.5m at equator)
    ("lod2", 0.00002),      # Very high (~2m)
    ("lod3", 0.00005),      # High (~5m)
    ("lod4", 0.0002),       # Medium (~20m)
    ("lod5", 0.0008),       # Low (~80m)
]


def download_osm_data(cache_dir: Path, use_land: bool = True) -> Path:
    """Download OSM land or water polygon data."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    
    if use_land:
        url = OSM_LAND_POLYGONS_URL
        filename = "land-polygons-split-4326.zip"
    else:
        url = OSM_WATER_POLYGONS_URL
        filename = "water-polygons-split-4326.zip"
    
    zip_path = cache_dir / filename
    
    if zip_path.exists():
        print(f"Using cached OSM data: {zip_path}")
        return zip_path
    
    print(f"Downloading OSM coastline data...")
    print(f"URL: {url}")
    print("(This is a large file ~700MB, please wait...)")
    
    def progress_hook(block_num, block_size, total_size):
        if total_size > 0:
            downloaded = block_num * block_size
            percent = min(100, downloaded * 100 / total_size)
            mb_downloaded = downloaded / 1024 / 1024
            mb_total = total_size / 1024 / 1024
            sys.stdout.write(f"\rProgress: {percent:.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)")
            sys.stdout.flush()
    
    urlretrieve(url, zip_path, progress_hook)
    print("\nDownload complete!")
    return zip_path


def extract_osm_data(zip_path: Path, extract_dir: Path) -> Path:
    """Extract OSM shapefile data."""
    # Determine expected folder name
    if "land-polygons" in zip_path.name:
        folder_name = "land-polygons-split-4326"
    else:
        folder_name = "water-polygons-split-4326"
    
    shp_dir = extract_dir / folder_name
    
    if shp_dir.exists():
        print(f"Using cached extracted data: {shp_dir}")
        return shp_dir
    
    print(f"Extracting OSM data...")
    with zipfile.ZipFile(zip_path, 'r') as zf:
        zf.extractall(extract_dir)
    
    return shp_dir


def load_osm_shapefile(shp_dir: Path) -> shapefile.Reader:
    """Load OSM land or water polygons shapefile."""
    # Find the shapefile
    shp_files = list(shp_dir.rglob("*.shp"))
    if not shp_files:
        raise FileNotFoundError(f"No shapefile found in {shp_dir}")
    
    shp_path = shp_files[0]
    print(f"Loading shapefile: {shp_path}")
    return shapefile.Reader(str(shp_path))


def filter_shapes_by_bounds(
    sf: shapefile.Reader,
    bounds: Tuple[float, float, float, float]
) -> List:
    """Filter shapefile records by bounding box with detailed progress."""
    min_lon, min_lat, max_lon, max_lat = bounds
    filtered_shapes = []
    
    total = len(sf)
    print(f"Scanning {total} shapes for region intersection...")
    
    for idx, shape_rec in enumerate(sf.iterShapeRecords()):
        if idx % 10000 == 0:
            sys.stdout.write(f"\r  Processed {idx}/{total} shapes, found {len(filtered_shapes)} matches")
            sys.stdout.flush()
        
        shape = shape_rec.shape
        
        if shape.shapeType == shapefile.POLYGON:
            shape_bounds = shape.bbox  # (min_x, min_y, max_x, max_y)
            
            # Check for intersection with region
            if (shape_bounds[0] <= max_lon and shape_bounds[2] >= min_lon and
                shape_bounds[1] <= max_lat and shape_bounds[3] >= min_lat):
                filtered_shapes.append(shape)
    
    print(f"\r  Processed {total}/{total} shapes, found {len(filtered_shapes)} matches")
    return filtered_shapes


def clip_ring_to_bounds(
    ring_points: List[Tuple[float, float]],
    bounds: Tuple[float, float, float, float]
) -> List[Tuple[float, float]]:
    """Clip ring points to bounding box (simple clamping)."""
    min_lon, min_lat, max_lon, max_lat = bounds
    clipped = []
    
    for lon, lat in ring_points:
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
        
        # Handle multi-part polygons
        parts = list(shape.parts) + [len(shape.points)]
        
        polygon_rings = []
        for i in range(len(parts) - 1):
            ring_points = shape.points[parts[i]:parts[i+1]]
            clipped = clip_ring_to_bounds(ring_points, bounds)
            
            if len(clipped) >= 3:
                # Ensure ring is closed
                if clipped[0] != clipped[-1]:
                    clipped.append(clipped[0])
                polygon_rings.append(clipped)
        
        if polygon_rings:
            # First ring is exterior, rest are holes
            feature = {
                "type": "Feature",
                "properties": {},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": polygon_rings
                }
            }
            features.append(feature)
    
    return {
        "type": "FeatureCollection",
        "features": features
    }


def _perpendicular_distance(point, start, end) -> float:
    """Perpendicular distance from point to line segment."""
    (px, py), (sx, sy), (ex, ey) = point, start, end
    line_mag = math.hypot(ex - sx, ey - sy)
    if line_mag == 0:
        return math.hypot(px - sx, py - sy)
    u = max(0.0, min(1.0, ((px - sx) * (ex - sx) + (py - sy) * (ey - sy)) / (line_mag ** 2)))
    ix = sx + u * (ex - sx)
    iy = sy + u * (ey - sy)
    return math.hypot(px - ix, py - iy)


def douglas_peucker(points: List[Tuple[float, float]], tolerance: float) -> List[Tuple[float, float]]:
    """Simplify a polyline using Douglas-Peucker algorithm."""
    if len(points) <= 2 or tolerance <= 0:
        return points

    is_closed = len(points) > 2 and points[0] == points[-1]
    working = points[:-1] if is_closed else points

    def _simplify(segment):
        if len(segment) <= 2:
            return segment
        start, end = segment[0], segment[-1]
        max_dist = -1.0
        index = 0
        for i in range(1, len(segment) - 1):
            dist = _perpendicular_distance(segment[i], start, end)
            if dist > max_dist:
                max_dist = dist
                index = i
        if max_dist > tolerance:
            left = _simplify(segment[:index + 1])
            right = _simplify(segment[index:])
            return left[:-1] + right
        else:
            return [start, end]

    simplified = _simplify(working)
    if is_closed and simplified[0] != simplified[-1]:
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
            out_features.append(feature)
            continue
        
        new_coords = []
        for ring in geom.get("coordinates", []):
            simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
            if len(simplified) >= 4:
                if simplified[0] != simplified[-1]:
                    simplified.append(simplified[0])
                new_coords.append(simplified)
            elif ring:
                new_coords.append(ring)  # Keep original if over-simplified
        
        if new_coords:
            out_features.append({
                "type": "Feature",
                "properties": feature.get("properties", {}),
                "geometry": {"type": "Polygon", "coordinates": new_coords}
            })

    return {"type": "FeatureCollection", "features": out_features}


def geojson_to_binary(geojson: dict) -> bytes:
    """Convert GeoJSON to optimized binary format."""
    polygons = []
    min_lon = float('inf')
    min_lat = float('inf')
    max_lon = float('-inf')
    max_lat = float('-inf')
    
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        if geom.get("type") != "Polygon":
            continue
        
        coords = geom.get("coordinates", [])
        if not coords:
            continue
        
        exterior = [(p[0], p[1]) for p in coords[0]]
        interiors = [[(p[0], p[1]) for p in ring] for ring in coords[1:]]
        
        for lon, lat in exterior:
            min_lon = min(min_lon, lon)
            min_lat = min(min_lat, lat)
            max_lon = max(max_lon, lon)
            max_lat = max(max_lat, lat)
        
        polygons.append((exterior, interiors))
    
    # Handle empty case
    if not polygons:
        min_lon = min_lat = max_lon = max_lat = 0.0
    
    data = bytearray()
    data.extend(b'NVTL')
    data.extend(struct.pack('<H', 1))
    data.extend(struct.pack('<I', len(polygons)))
    data.extend(struct.pack('<d', min_lon))
    data.extend(struct.pack('<d', min_lat))
    data.extend(struct.pack('<d', max_lon))
    data.extend(struct.pack('<d', max_lat))
    
    for exterior, interiors in polygons:
        data.extend(struct.pack('<I', len(exterior)))
        data.extend(struct.pack('<I', len(interiors)))
        for lon, lat in exterior:
            data.extend(struct.pack('<d', lon))
            data.extend(struct.pack('<d', lat))
        for interior in interiors:
            data.extend(struct.pack('<I', len(interior)))
            for lon, lat in interior:
                data.extend(struct.pack('<d', lon))
                data.extend(struct.pack('<d', lat))
    
    return bytes(data)


def count_points(geojson: dict) -> int:
    """Count total points in GeoJSON."""
    total = 0
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        if geom.get("type") == "Polygon":
            for ring in geom.get("coordinates", []):
                total += len(ring)
    return total


def main():
    parser = argparse.ArgumentParser(description="Download OSM high-resolution coastline data")
    parser.add_argument("--region", choices=list(REGIONS.keys()), default="seattle")
    parser.add_argument("--output", type=str, default="assets/charts")
    parser.add_argument("--cache-dir", type=str, default=".noaa_cache/osm")
    parser.add_argument("--list-regions", action="store_true")
    parser.add_argument("--use-water", action="store_true", 
                        help="Use water polygons instead of land polygons")
    
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
    
    # Download and extract OSM data
    zip_path = download_osm_data(cache_dir, use_land=not args.use_water)
    shp_dir = extract_osm_data(zip_path, cache_dir)
    
    # Load shapefile
    sf = load_osm_shapefile(shp_dir)
    
    # Filter shapes by region
    shapes = filter_shapes_by_bounds(sf, region_info['bounds'])
    print(f"Found {len(shapes)} shapes in region")
    
    if not shapes:
        print("Warning: No shapes found in region.")
        return
    
    # Convert to GeoJSON
    print("Converting to GeoJSON...")
    geojson = shapes_to_geojson(shapes, region_info['bounds'])
    
    total_points = count_points(geojson)
    print(f"Total points in full detail: {total_points:,}")
    
    # Save base files
    geojson_path = output_dir / f"{args.region}_coastline.geojson"
    with open(geojson_path, 'w') as f:
        json.dump(geojson, f)
    
    binary_path = output_dir / f"{args.region}_coastline.bin"
    with open(binary_path, 'wb') as f:
        f.write(geojson_to_binary(geojson))
    
    print(f"Saved base GeoJSON: {geojson_path}")
    print(f"Saved base binary: {binary_path}")
    
    # Generate LOD variants
    for suffix, tolerance in LOD_LEVELS:
        lod_geojson = geojson if tolerance == 0 else simplify_geojson(geojson, tolerance)
        lod_points = count_points(lod_geojson)
        
        lod_geojson_path = output_dir / f"{args.region}_coastline_{suffix}.geojson"
        with open(lod_geojson_path, 'w') as f:
            json.dump(lod_geojson, f)
        
        lod_binary_path = output_dir / f"{args.region}_coastline_{suffix}.bin"
        with open(lod_binary_path, 'wb') as f:
            f.write(geojson_to_binary(lod_geojson))
        
        print(f"Saved {suffix} (tol={tolerance}, points={lod_points:,})")
    
    # Statistics
    print(f"\nStatistics:")
    print(f"  Features: {len(geojson['features'])}")
    print(f"  Total points: {total_points:,}")
    print(f"  GeoJSON size: {os.path.getsize(geojson_path) / 1024:.1f} KB")
    print(f"  Binary size: {os.path.getsize(binary_path) / 1024:.1f} KB")
    
    print(f"\nDone! OSM coastline data saved to {output_dir}")


if __name__ == "__main__":
    main()
