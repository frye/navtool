#!/usr/bin/env python3
"""
NOAA ENC (Electronic Navigational Chart) Data Downloader and Converter

This script downloads high-resolution coastline data from NOAA Electronic
Navigational Charts (ENC) in S-57 format and converts it to GeoJSON/binary
format suitable for NavTool.

NOAA ENC data is the same data used by professional marine navigation systems
and provides much higher resolution than GSHHG (~1-5m vs ~80m).

Data Sources:
- NOAA ENC Direct: https://charts.noaa.gov/ENCs/ENCs.shtml
- NOAA Chart Catalog API

Requirements:
- Python 3.8+
- osgeo (GDAL/OGR) for S-57 parsing
- requests

Usage:
    python download_enc_data.py --region seattle --output assets/charts/
"""

import argparse
import json
import os
import struct
import sys
import math
import zipfile
import glob
from pathlib import Path
from typing import List, Tuple, Optional
from urllib.request import urlretrieve
import xml.etree.ElementTree as ET

# Try to import GDAL/OGR for S-57 support
try:
    from osgeo import ogr, osr
    HAS_GDAL = True
except ImportError:
    HAS_GDAL = False
    print("Warning: GDAL/OGR not available. Install with: pip install gdal")
    print("On Windows, you may need to install from: https://www.lfd.uci.edu/~gohlke/pythonlibs/#gdal")

# Region definitions with ENC chart numbers
# NOAA ENC charts follow naming: US{scale}XX{number}
# Scale codes: 1=Overview, 2=General, 3=Coastal, 4=Approach, 5=Harbor
REGIONS = {
    "seattle": {
        "name": "Seattle / Puget Sound",
        "bounds": (-123.5, 47.0, -121.5, 48.5),
        "description": "Puget Sound area including Seattle, Tacoma, and surrounding waters",
        # ENC chart numbers for Puget Sound area (harbor and approach scale)
        "enc_charts": [
            "US5WA18M",  # Puget Sound - Seattle
            "US5WA19M",  # Puget Sound - Shilshole Bay to Commencement Bay
            "US5WA22M",  # Puget Sound - Possession Sound
            "US5WA14M",  # Puget Sound - Hood Canal
            "US4WA18M",  # Approaches
            "US4WA11M",  # Juan de Fuca to Puget Sound
        ]
    },
    "san_francisco": {
        "name": "San Francisco Bay",
        "bounds": (-123.0, 37.4, -121.8, 38.2),
        "description": "San Francisco Bay Area",
        "enc_charts": [
            "US5CA13M",  # San Francisco Bay
            "US5CA12M",  # Oakland Inner Harbor
        ]
    },
    "chesapeake": {
        "name": "Chesapeake Bay", 
        "bounds": (-77.5, 36.5, -75.5, 39.5),
        "description": "Chesapeake Bay area",
        "enc_charts": [
            "US5MD23M",  # Chesapeake Bay - Annapolis
            "US5VA27M",  # Chesapeake Bay - Norfolk
        ]
    },
}

# NOAA ENC download base URL
ENC_BASE_URL = "https://charts.noaa.gov/ENCs"

# LOD simplification tolerances (degrees). Lower = more detailed.
LOD_LEVELS = [
    ("lod0", 0.0),         # Finest (full ENC detail)
    ("lod1", 0.00002),     # Ultra-high (ENC is much more detailed than GSHHG)
    ("lod2", 0.00005),     # Very high
    ("lod3", 0.0001),      # High
    ("lod4", 0.0003),      # Medium
    ("lod5", 0.001),       # Low
]


def download_enc_chart(chart_id: str, cache_dir: Path) -> Optional[Path]:
    """Download a single ENC chart ZIP file from NOAA."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    zip_filename = f"{chart_id}.zip"
    zip_path = cache_dir / zip_filename
    
    if zip_path.exists():
        print(f"  Using cached: {zip_path}")
        return zip_path
    
    # Try different URL patterns NOAA uses
    urls_to_try = [
        f"{ENC_BASE_URL}/{chart_id}.zip",
        f"{ENC_BASE_URL}/All_ENCs/{chart_id}.zip",
    ]
    
    for url in urls_to_try:
        try:
            print(f"  Downloading {chart_id} from {url}...")
            
            def progress_hook(block_num, block_size, total_size):
                if total_size > 0:
                    downloaded = block_num * block_size
                    percent = min(100, downloaded * 100 / total_size)
                    sys.stdout.write(f"\r    Progress: {percent:.1f}%")
                    sys.stdout.flush()
            
            urlretrieve(url, zip_path, progress_hook)
            print()  # newline after progress
            return zip_path
        except Exception as e:
            print(f"  Failed: {e}")
            continue
    
    print(f"  Could not download {chart_id}")
    return None


def extract_enc_chart(zip_path: Path, extract_dir: Path) -> Optional[Path]:
    """Extract ENC chart and find the .000 file (S-57 format)."""
    chart_name = zip_path.stem
    chart_dir = extract_dir / chart_name
    
    if chart_dir.exists():
        # Find existing .000 file
        s57_files = list(chart_dir.rglob("*.000"))
        if s57_files:
            return s57_files[0]
    
    print(f"  Extracting {zip_path.name}...")
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            zf.extractall(chart_dir)
    except Exception as e:
        print(f"  Extract failed: {e}")
        return None
    
    # Find the .000 file (S-57 cell file)
    s57_files = list(chart_dir.rglob("*.000"))
    if s57_files:
        return s57_files[0]
    
    print(f"  No S-57 file found in {chart_name}")
    return None


def extract_coastline_from_s57(s57_path: Path, bounds: Tuple[float, float, float, float]) -> List[dict]:
    """
    Extract coastline features from S-57 ENC file.
    
    S-57 feature codes for coastlines:
    - COALNE (Coastline)
    - LNDARE (Land area)
    - SLCONS (Shoreline construction)
    """
    if not HAS_GDAL:
        print("  GDAL not available, cannot parse S-57")
        return []
    
    min_lon, min_lat, max_lon, max_lat = bounds
    features = []
    
    try:
        # Open S-57 dataset
        ds = ogr.Open(str(s57_path))
        if ds is None:
            print(f"  Could not open {s57_path}")
            return []
        
        # Look for coastline-related layers
        coastline_layers = ["COALNE", "LNDARE", "SLCONS", "DEPARE"]
        
        for layer_name in coastline_layers:
            layer = ds.GetLayerByName(layer_name)
            if layer is None:
                continue
            
            print(f"    Processing layer {layer_name} ({layer.GetFeatureCount()} features)")
            
            # Set spatial filter
            layer.SetSpatialFilterRect(min_lon, min_lat, max_lon, max_lat)
            
            for feature in layer:
                geom = feature.GetGeometryRef()
                if geom is None:
                    continue
                
                geom_type = geom.GetGeometryType()
                
                # Convert to GeoJSON-compatible structure
                if geom_type == ogr.wkbPolygon or geom_type == ogr.wkbMultiPolygon:
                    geojson_geom = json.loads(geom.ExportToJson())
                    features.append({
                        "type": "Feature",
                        "properties": {"layer": layer_name},
                        "geometry": geojson_geom
                    })
                elif geom_type == ogr.wkbLineString or geom_type == ogr.wkbMultiLineString:
                    # Convert linestrings to thin polygons for consistent rendering
                    geojson_geom = json.loads(geom.ExportToJson())
                    features.append({
                        "type": "Feature", 
                        "properties": {"layer": layer_name, "type": "line"},
                        "geometry": geojson_geom
                    })
        
        ds = None  # Close dataset
        
    except Exception as e:
        print(f"  Error reading S-57: {e}")
    
    return features


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
    """Simplify a polyline using Douglas-Peucker."""
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
        geom_type = geom.get("type")
        
        if geom_type == "Polygon":
            new_coords = []
            for ring in geom.get("coordinates", []):
                simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
                if len(simplified) >= 4:
                    if simplified[0] != simplified[-1]:
                        simplified.append(simplified[0])
                    new_coords.append(simplified)
                else:
                    new_coords.append(ring)  # Keep original if too simplified
            
            out_features.append({
                "type": "Feature",
                "properties": feature.get("properties", {}),
                "geometry": {"type": "Polygon", "coordinates": new_coords}
            })
            
        elif geom_type == "MultiPolygon":
            new_polys = []
            for poly in geom.get("coordinates", []):
                new_rings = []
                for ring in poly:
                    simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
                    if len(simplified) >= 4:
                        if simplified[0] != simplified[-1]:
                            simplified.append(simplified[0])
                        new_rings.append(simplified)
                    else:
                        new_rings.append(ring)
                new_polys.append(new_rings)
            
            out_features.append({
                "type": "Feature",
                "properties": feature.get("properties", {}),
                "geometry": {"type": "MultiPolygon", "coordinates": new_polys}
            })
        else:
            out_features.append(feature)

    return {"type": "FeatureCollection", "features": out_features}


def geojson_to_binary(geojson: dict) -> bytes:
    """Convert GeoJSON to optimized binary format."""
    polygons = []
    min_lon = float('inf')
    min_lat = float('inf')
    max_lon = float('-inf')
    max_lat = float('-inf')
    
    def process_polygon(coords):
        nonlocal min_lon, min_lat, max_lon, max_lat
        if not coords:
            return None
        exterior = [(p[0], p[1]) for p in coords[0]]
        interiors = [[(p[0], p[1]) for p in ring] for ring in coords[1:]]
        
        for lon, lat in exterior:
            min_lon = min(min_lon, lon)
            min_lat = min(min_lat, lat)
            max_lon = max(max_lon, lon)
            max_lat = max(max_lat, lat)
        
        return (exterior, interiors)
    
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        geom_type = geom.get("type")
        
        if geom_type == "Polygon":
            result = process_polygon(geom.get("coordinates", []))
            if result:
                polygons.append(result)
        elif geom_type == "MultiPolygon":
            for poly_coords in geom.get("coordinates", []):
                result = process_polygon(poly_coords)
                if result:
                    polygons.append(result)
    
    # Handle edge case of no polygons
    if not polygons:
        min_lon = min_lat = max_lon = max_lat = 0.0
    
    # Build binary data
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


def main():
    parser = argparse.ArgumentParser(description="Download NOAA ENC data for high-resolution coastlines")
    parser.add_argument("--region", choices=list(REGIONS.keys()), default="seattle")
    parser.add_argument("--output", type=str, default="assets/charts")
    parser.add_argument("--cache-dir", type=str, default=".noaa_cache/enc")
    parser.add_argument("--list-regions", action="store_true")
    
    args = parser.parse_args()
    
    if args.list_regions:
        print("Available regions:")
        for key, info in REGIONS.items():
            print(f"  {key}: {info['name']}")
            print(f"    {info['description']}")
            print(f"    ENC charts: {', '.join(info.get('enc_charts', []))}")
        return
    
    if not HAS_GDAL:
        print("\nError: GDAL/OGR is required for S-57 ENC parsing.")
        print("Install options:")
        print("  - conda install gdal")
        print("  - pip install gdal (may require system GDAL installation)")
        print("  - Windows: Download from https://www.lfd.uci.edu/~gohlke/pythonlibs/#gdal")
        return
    
    region_info = REGIONS[args.region]
    print(f"Processing region: {region_info['name']}")
    print(f"Bounds: {region_info['bounds']}")
    print(f"ENC charts: {region_info.get('enc_charts', [])}")
    
    cache_dir = Path(args.cache_dir)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    all_features = []
    
    # Download and process each ENC chart
    for chart_id in region_info.get("enc_charts", []):
        print(f"\nProcessing chart: {chart_id}")
        
        zip_path = download_enc_chart(chart_id, cache_dir)
        if zip_path is None:
            continue
        
        s57_path = extract_enc_chart(zip_path, cache_dir)
        if s57_path is None:
            continue
        
        features = extract_coastline_from_s57(s57_path, region_info['bounds'])
        print(f"  Extracted {len(features)} features")
        all_features.extend(features)
    
    if not all_features:
        print("\nNo features extracted. Check if GDAL is properly installed.")
        return
    
    print(f"\nTotal features: {len(all_features)}")
    
    # Create GeoJSON
    geojson = {"type": "FeatureCollection", "features": all_features}
    
    # Save base files
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
        
        print(f"Saved {suffix} (tol={tolerance})")
    
    # Statistics
    total_points = sum(
        sum(len(ring) for ring in feat.get("geometry", {}).get("coordinates", [[]]))
        for feat in all_features
        if feat.get("geometry", {}).get("type") == "Polygon"
    )
    
    print(f"\nStatistics:")
    print(f"  Features: {len(all_features)}")
    print(f"  Approximate points: {total_points}")
    print(f"  GeoJSON size: {os.path.getsize(geojson_path) / 1024:.1f} KB")
    print(f"  Binary size: {os.path.getsize(binary_path) / 1024:.1f} KB")
    
    print(f"\nDone! ENC data saved to {output_dir}")


if __name__ == "__main__":
    main()
