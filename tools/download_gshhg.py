#!/usr/bin/env python3
"""
GSHHG (Global Self-consistent Hierarchical High-resolution Geography) Downloader

Downloads global coastline data from NOAA GSHHG database and converts to
NavTool's NVTL binary format.

Data Source:
- NOAA GSHHG: https://www.ngdc.noaa.gov/mgg/shorelines/data/gshhg/latest/
- License: GNU Lesser General Public License (LGPL)
- Maintained by Paul Wessel (U. Hawaii) and Walter H.F. Smith (NOAA)

Resolution Levels:
- crude (c): ~300 KB - Global overview, zoom 0-2
- low (l): ~1 MB - Default detail, zoom 2-5  
- intermediate (i): ~3.5 MB - Regional detail, zoom 5-8
- high (h): ~12 MB - Detailed coastlines, zoom 8+
- full (f): ~56 MB - Maximum detail

Usage:
    python download_gshhg.py --resolution crude --output assets/gshhg/
    python download_gshhg.py --all --output assets/gshhg/
    python download_gshhg.py --bundle-crude  # Prepare crude for app bundling
"""

import argparse
import json
import os
import struct
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import HTTPError, URLError

try:
    import shapefile
except ImportError:
    print("Installing required package: pyshp")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

# GSHHG download URLs
GSHHG_BASE_URL = "https://www.ngdc.noaa.gov/mgg/shorelines/data/gshhg/latest"
GSHHG_SHAPEFILE_ZIP = "gshhg-shp-2.3.7.zip"

# Resolution codes and their properties
RESOLUTIONS = {
    "crude": {
        "code": "c",
        "description": "Crude resolution (~300 KB) - Global overview",
        "zoom_range": (0, 2),
        "lod": 5,
    },
    "low": {
        "code": "l",
        "description": "Low resolution (~1 MB) - Default detail",
        "zoom_range": (2, 5),
        "lod": 4,
    },
    "intermediate": {
        "code": "i",
        "description": "Intermediate resolution (~3.5 MB) - Regional detail",
        "zoom_range": (5, 8),
        "lod": 3,
    },
    "high": {
        "code": "h",
        "description": "High resolution (~12 MB) - Detailed coastlines",
        "zoom_range": (8, 12),
        "lod": 2,
    },
    "full": {
        "code": "f",
        "description": "Full resolution (~56 MB) - Maximum detail",
        "zoom_range": (12, 20),
        "lod": 0,
    },
}


def download_file(url: str, dest_path: Path, show_progress: bool = True) -> bool:
    """Download a file with progress indicator."""
    try:
        req = Request(url, headers={
            "User-Agent": "NavTool/1.0 (GSHHG Data Downloader)"
        })
        
        with urlopen(req, timeout=300) as response:
            total_size = int(response.headers.get('content-length', 0))
            
            with open(dest_path, 'wb') as f:
                downloaded = 0
                block_size = 8192
                
                while True:
                    buffer = response.read(block_size)
                    if not buffer:
                        break
                    
                    f.write(buffer)
                    downloaded += len(buffer)
                    
                    if show_progress and total_size > 0:
                        percent = (downloaded / total_size) * 100
                        bar_len = 40
                        filled = int(bar_len * downloaded / total_size)
                        bar = '█' * filled + '░' * (bar_len - filled)
                        print(f'\r  [{bar}] {percent:.1f}% ({downloaded // 1024} KB)', end='')
                
                if show_progress:
                    print()
        
        return True
        
    except (HTTPError, URLError) as e:
        print(f"\nError downloading: {e}")
        return False


def extract_coastline_shapefile(zip_path: Path, resolution_code: str, temp_dir: Path) -> Path:
    """Extract the coastline shapefile for a given resolution from the ZIP."""
    # GSHHG shapefile naming: GSHHS_{resolution}_L1.shp (L1 = coastlines)
    shp_name = f"GSHHS_{resolution_code}_L1"
    
    with zipfile.ZipFile(zip_path, 'r') as zf:
        # Files are in subdirectory by resolution
        prefix = f"GSHHS_shp/{resolution_code}/"
        
        # Extract all parts of the shapefile
        for ext in ['.shp', '.shx', '.dbf', '.prj']:
            member = f"{prefix}{shp_name}{ext}"
            try:
                zf.extract(member, temp_dir)
            except KeyError:
                if ext in ['.shp', '.shx', '.dbf']:
                    raise FileNotFoundError(f"Required file not found in ZIP: {member}")
    
    return temp_dir / prefix / f"{shp_name}.shp"


def shapefile_to_geojson(shp_path: Path) -> dict:
    """Convert a shapefile to GeoJSON format."""
    features = []
    
    with shapefile.Reader(str(shp_path)) as sf:
        for shape_rec in sf.iterShapeRecords():
            shape = shape_rec.shape
            
            if shape.shapeType == shapefile.POLYGON:
                # Handle polygon with potential multiple parts
                coords = []
                parts = list(shape.parts) + [len(shape.points)]
                
                for i in range(len(parts) - 1):
                    ring = [
                        [p[0], p[1]] 
                        for p in shape.points[parts[i]:parts[i+1]]
                    ]
                    coords.append(ring)
                
                features.append({
                    "type": "Feature",
                    "properties": {},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": coords
                    }
                })
    
    return {
        "type": "FeatureCollection",
        "features": features
    }


def geojson_to_binary(geojson: dict) -> bytes:
    """Convert GeoJSON to NVTL binary format."""
    polygons = []
    min_lon = float('inf')
    min_lat = float('inf')
    max_lon = float('-inf')
    max_lat = float('-inf')
    
    for feature in geojson.get("features", []):
        geom = feature.get("geometry", {})
        geom_type = geom.get("type", "")
        
        if geom_type == "Polygon":
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
                
        elif geom_type == "MultiPolygon":
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
    
    # Handle empty data
    if not polygons:
        min_lon = min_lat = max_lon = max_lat = 0.0
    
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


def update_manifest(manifest_path: Path, resolution: str, output_file: str):
    """Update or create manifest.json with GSHHG entry."""
    res_info = RESOLUTIONS[resolution]
    region_id = f"gshhg_{resolution}_global"
    
    # Load existing manifest or create new
    if manifest_path.exists():
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
    else:
        manifest = {
            "version": 1,
            "lastUpdated": datetime.now().isoformat(),
            "regions": {}
        }
    
    # Add/update GSHHG entry
    manifest["regions"][region_id] = {
        "name": f"GSHHG {resolution.capitalize()} (Global)",
        "bounds": [-180, -90, 180, 90],
        "source": "gshhg",
        "gshhgResolution": resolution,
        "lods": [res_info["lod"]],
        "files": [output_file],
        "lastUpdated": datetime.now().isoformat()
    }
    
    manifest["lastUpdated"] = datetime.now().isoformat()
    
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)


def process_resolution(resolution: str, zip_path: Path, output_dir: Path, manifest_path: Path = None):
    """Process a single resolution level."""
    res_info = RESOLUTIONS[resolution]
    print(f"\nProcessing {resolution} resolution...")
    print(f"  {res_info['description']}")
    
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Extract shapefile
        print(f"  Extracting shapefile...")
        shp_path = extract_coastline_shapefile(zip_path, res_info["code"], temp_path)
        
        # Convert to GeoJSON
        print(f"  Converting to GeoJSON...")
        geojson = shapefile_to_geojson(shp_path)
        
        # Count features and points
        num_features = len(geojson.get("features", []))
        total_points = 0
        for feature in geojson.get("features", []):
            geom = feature.get("geometry", {})
            for ring in geom.get("coordinates", []):
                total_points += len(ring)
        
        print(f"  Found {num_features} features with {total_points:,} points")
        
        # Convert to binary
        print(f"  Converting to binary format...")
        binary_data = geojson_to_binary(geojson)
        
        # Save files
        output_file = f"gshhg_{resolution}.bin"
        binary_path = output_dir / output_file
        with open(binary_path, 'wb') as f:
            f.write(binary_data)
        
        print(f"  Saved: {binary_path} ({len(binary_data) / 1024:.1f} KB)")
        
        # Optionally save GeoJSON for debugging
        geojson_path = output_dir / f"gshhg_{resolution}.geojson"
        with open(geojson_path, 'w') as f:
            json.dump(geojson, f)
        
        # Update manifest if path provided
        if manifest_path:
            update_manifest(manifest_path, resolution, output_file)
            print(f"  Updated manifest: {manifest_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Download and convert GSHHG coastline data to NVTL format"
    )
    parser.add_argument(
        "--resolution",
        choices=list(RESOLUTIONS.keys()),
        help="Resolution level to download"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Download all resolution levels"
    )
    parser.add_argument(
        "--bundle-crude",
        action="store_true",
        help="Download only crude resolution for app bundling"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="assets/gshhg",
        help="Output directory (default: assets/gshhg)"
    )
    parser.add_argument(
        "--manifest",
        type=str,
        default="assets/charts/manifest.json",
        help="Path to manifest.json to update"
    )
    parser.add_argument(
        "--list-resolutions",
        action="store_true",
        help="List available resolutions and exit"
    )
    parser.add_argument(
        "--cache-zip",
        type=str,
        help="Path to cached GSHHG ZIP file (skip download)"
    )
    
    args = parser.parse_args()
    
    if args.list_resolutions:
        print("Available GSHHG resolutions:")
        for name, info in RESOLUTIONS.items():
            print(f"  {name}: {info['description']}")
        return
    
    # Determine which resolutions to process
    if args.bundle_crude:
        resolutions = ["crude"]
    elif args.all:
        resolutions = list(RESOLUTIONS.keys())
    elif args.resolution:
        resolutions = [args.resolution]
    else:
        parser.print_help()
        return
    
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    manifest_path = Path(args.manifest) if args.manifest else None
    
    # Download or use cached ZIP
    if args.cache_zip:
        zip_path = Path(args.cache_zip)
        if not zip_path.exists():
            print(f"Error: Cached ZIP not found: {zip_path}")
            return
    else:
        # Download GSHHG shapefile ZIP
        zip_url = f"{GSHHG_BASE_URL}/{GSHHG_SHAPEFILE_ZIP}"
        zip_path = output_dir / GSHHG_SHAPEFILE_ZIP
        
        if zip_path.exists():
            print(f"Using existing ZIP: {zip_path}")
        else:
            print(f"Downloading GSHHG shapefiles from NOAA...")
            print(f"  URL: {zip_url}")
            
            if not download_file(zip_url, zip_path):
                print("Download failed!")
                return
    
    # Process each resolution
    for resolution in resolutions:
        process_resolution(resolution, zip_path, output_dir, manifest_path)
    
    print(f"\n{'='*60}")
    print("Done! GSHHG coastline data saved to", output_dir)
    print(f"{'='*60}")
    
    if manifest_path:
        print(f"\nManifest updated: {manifest_path}")
    
    print("\nNote: GSHHG data is released under LGPL license.")
    print("Data maintained by Paul Wessel (U. Hawaii) and Walter H.F. Smith (NOAA)")


if __name__ == "__main__":
    main()
