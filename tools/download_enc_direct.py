#!/usr/bin/env python3
"""
NOAA ENC Direct to GIS Downloader

This script downloads high-resolution coastline data from NOAA's ENC Direct to GIS
service. This provides official Electronic Navigational Chart (ENC) data converted
to shapefiles, with ~1-5m resolution suitable for marine navigation applications.

Data Source:
- NOAA ENC Direct to GIS: https://encdirect.noaa.gov/
- Uses ArcGIS REST services to extract and download coastline data
- Data is updated weekly from official NOAA ENCs
- NOTE: Not certified for actual navigation, for GIS/planning purposes only

Requirements:
- Python 3.8+
- requests
- shapefile (pyshp)

Usage:
    python download_enc_direct.py --region seattle --output assets/charts/
    python download_enc_direct.py --region seattle --scale-band harbor --output assets/charts/

Scale Bands (from most detailed to least):
- berthing: ~1:5,000 (extremely detailed, port facilities)
- harbor: ~1:10,000-1:50,000 (very detailed, harbor areas)
- approach: ~1:50,000-1:150,000 (detailed, approach channels)
- coastal: ~1:150,000-1:600,000 (medium detail)
- general: ~1:600,000-1:1,500,000 (low detail)
- overview: 1:1,500,000+ (very low detail)

For marine applications, use 'harbor' or 'berthing' for best detail.
"""

import argparse
import json
import os
import struct
import sys
import time
import math
import zipfile
from io import BytesIO
from pathlib import Path
from typing import List, Tuple, Optional, Dict
from urllib.request import urlopen, Request
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError

try:
    import shapefile
except ImportError:
    print("Installing required package: pyshp")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

try:
    from shapely.geometry import shape, mapping
    from shapely.ops import unary_union
    from shapely.validation import make_valid
    HAS_SHAPELY = True
except ImportError:
    print("Installing required package: shapely")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "shapely"])
    from shapely.geometry import shape, mapping
    from shapely.ops import unary_union
    from shapely.validation import make_valid
    HAS_SHAPELY = True

# ENC Direct to GIS REST Service endpoints
ENC_DIRECT_BASE = "https://encdirect.noaa.gov/arcgis/rest/services"

# Scale bands with their service paths and typical scales
# NOTE: Service names use lowercase (e.g., enc_harbour not ENC_Harbour)
SCALE_BANDS = {
    "berthing": {
        "service": "encdirect/enc_berthing/MapServer",
        "description": "Berthing scale (~1:5,000) - Most detailed, port facilities",
        "scale_range": (1, 5000),
        "coastline_layer_id": None,  # Will be discovered dynamically
        "land_area_layer_id": None,
    },
    "harbor": {
        "service": "encdirect/enc_harbour/MapServer",  # Note: British spelling
        "description": "Harbor scale (~1:10,000-1:50,000) - Very detailed, harbors",
        "scale_range": (5000, 50000),
        "coastline_layer_id": 84,  # Harbor.Coastline_line
        "land_area_layer_id": 233,  # Harbor.Land_Area
    },
    "approach": {
        "service": "encdirect/enc_approach/MapServer",
        "description": "Approach scale (~1:50,000-1:150,000) - Detailed approaches",
        "scale_range": (50000, 150000),
        "coastline_layer_id": None,
        "land_area_layer_id": None,
    },
    "coastal": {
        "service": "encdirect/enc_coastal/MapServer",
        "description": "Coastal scale (~1:150,000-1:600,000) - Medium detail",
        "scale_range": (150000, 600000),
        "coastline_layer_id": None,
        "land_area_layer_id": None,
    },
    "general": {
        "service": "encdirect/enc_general/MapServer",
        "description": "General scale (~1:600,000-1:1,500,000) - Low detail",
        "scale_range": (600000, 1500000),
        "coastline_layer_id": None,
        "land_area_layer_id": None,
    },
    "overview": {
        "service": "encdirect/enc_overview/MapServer",
        "description": "Overview scale (1:1,500,000+) - Lowest detail",
        "scale_range": (1500000, 10000000),
        "coastline_layer_id": None,
        "land_area_layer_id": None,
    },
}

# S-57 object classes we're interested in for coastlines
COASTLINE_LAYERS = {
    "COALNE": "Coastline (natural and man-made shoreline)",
    "LNDARE": "Land Area (land polygons)",
    "SLCONS": "Shoreline Construction (piers, seawalls, etc.)",
    "LNDRGN": "Land Region (named land areas)",
    "LAKARE": "Lake Area",
    "RIVERS": "River",
}

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
    },
    "new_york": {
        "name": "New York Harbor",
        "bounds": (-74.3, 40.4, -73.7, 40.9),
        "description": "New York Harbor and approaches"
    },
    "los_angeles": {
        "name": "Los Angeles / Long Beach",
        "bounds": (-118.5, 33.5, -117.8, 34.1),
        "description": "Los Angeles and Long Beach Harbor area"
    },
}


def make_request(url: str, params: dict = None, max_retries: int = 3) -> bytes:
    """Make an HTTP request with retry logic."""
    if params:
        url = f"{url}?{urlencode(params)}"
    
    for attempt in range(max_retries):
        try:
            req = Request(url, headers={
                "User-Agent": "NavTool/1.0 (NOAA ENC Data Downloader)"
            })
            with urlopen(req, timeout=120) as response:
                return response.read()
        except (HTTPError, URLError) as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt
                print(f"  Request failed, retrying in {wait_time}s... ({e})")
                time.sleep(wait_time)
            else:
                raise


def get_map_service_info(service_path: str) -> dict:
    """Get information about available layers in a map service."""
    url = f"{ENC_DIRECT_BASE}/{service_path}"
    params = {"f": "json"}
    
    data = make_request(url, params)
    return json.loads(data)


def find_layer_id(service_info: dict, layer_name: str) -> Optional[int]:
    """Find the layer ID for a given S-57 object class name."""
    layers = service_info.get("layers", [])
    
    for layer in layers:
        name = layer.get("name", "")
        # Layer names might be like "Coastline" or "COALNE" or "Coastline_Line"
        if layer_name.upper() in name.upper() or name.upper() in layer_name.upper():
            return layer.get("id")
    
    return None


def query_features(
    service_path: str,
    layer_id: int,
    bounds: Tuple[float, float, float, float],
    geometry_type: str = "esriGeometryPolygon"
) -> dict:
    """Query features from a layer within bounds, handling pagination."""
    min_lon, min_lat, max_lon, max_lat = bounds
    
    url = f"{ENC_DIRECT_BASE}/{service_path}/{layer_id}/query"
    
    all_features = []
    offset = 0
    page_size = 1000  # ArcGIS REST default limit
    
    while True:
        params = {
            "f": "geojson",
            "geometry": f"{min_lon},{min_lat},{max_lon},{max_lat}",
            "geometryType": "esriGeometryEnvelope",
            "spatialRel": "esriSpatialRelIntersects",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",  # WGS84
            "resultOffset": offset,
            "resultRecordCount": page_size,
        }
        
        data = make_request(url, params)
        result = json.loads(data)
        features = result.get("features", [])
        
        if not features:
            break
        
        all_features.extend(features)
        
        # Check if we got a full page (might be more)
        if len(features) < page_size:
            break
        
        offset += page_size
        print(f"      Fetched {len(all_features)} features, continuing...")
    
    return {
        "type": "FeatureCollection",
        "features": all_features
    }


def extract_data_gp_service(
    scale_band: str,
    bounds: Tuple[float, float, float, float],
    layer_names: List[str],
    output_format: str = "Shapefile"
) -> Optional[bytes]:
    """
    Use the Geoprocessing service to extract data as a shapefile.
    
    This is the preferred method as it provides complete, clipped data.
    """
    band_info = SCALE_BANDS[scale_band]
    
    # The GP service URL pattern
    gp_url = f"{ENC_DIRECT_BASE}/encdirect/Extractor/GPServer/Extract"
    
    min_lon, min_lat, max_lon, max_lat = bounds
    
    # Build the extraction request
    params = {
        "f": "json",
        "Layers": json.dumps(layer_names),
        "Area_of_Interest": json.dumps({
            "spatialReference": {"wkid": 4326},
            "rings": [[[min_lon, min_lat], [max_lon, min_lat], 
                      [max_lon, max_lat], [min_lon, max_lat], [min_lon, min_lat]]]
        }),
        "Feature_Format": output_format,
    }
    
    try:
        print(f"  Submitting extraction job...")
        data = make_request(gp_url + "/submitJob", params)
        job_info = json.loads(data)
        
        job_id = job_info.get("jobId")
        if not job_id:
            print(f"  Failed to get job ID: {job_info}")
            return None
        
        # Poll for job completion
        status_url = f"{gp_url}/jobs/{job_id}"
        while True:
            data = make_request(status_url, {"f": "json"})
            status_info = json.loads(data)
            status = status_info.get("jobStatus", "")
            
            if status == "esriJobSucceeded":
                break
            elif status in ("esriJobFailed", "esriJobCancelled"):
                print(f"  Job failed: {status_info}")
                return None
            
            print(f"  Job status: {status}...")
            time.sleep(2)
        
        # Get the result
        result_url = f"{gp_url}/jobs/{job_id}/results/Output_File"
        data = make_request(result_url, {"f": "json"})
        result_info = json.loads(data)
        
        # Download the shapefile ZIP
        file_url = result_info.get("value", {}).get("url")
        if file_url:
            print(f"  Downloading result...")
            return make_request(file_url)
        
    except Exception as e:
        print(f"  GP extraction failed: {e}")
    
    return None


def is_rectangular_feature(feature: dict, tolerance: float = 0.001) -> bool:
    """
    Check if a feature is a rectangular polygon (likely an ENC cell boundary).
    
    Rectangular features typically have 4-8 points and axis-aligned edges.
    Also checks for near-rectangular bounding box ratio.
    """
    geom = feature.get("geometry", {})
    geom_type = geom.get("type", "")
    
    if geom_type != "Polygon":
        return False
    
    coords = geom.get("coordinates", [])
    if not coords:
        return False
    
    exterior = coords[0]
    
    # Skip if too few points or too many (complex shapes are not cell boundaries)
    if len(exterior) < 4 or len(exterior) > 10:
        return False
    
    # Calculate bounding box
    lons = [p[0] for p in exterior]
    lats = [p[1] for p in exterior]
    min_lon, max_lon = min(lons), max(lons)
    min_lat, max_lat = min(lats), max(lats)
    
    bbox_width = max_lon - min_lon
    bbox_height = max_lat - min_lat
    
    if bbox_width < 0.0001 or bbox_height < 0.0001:
        return False
    
    # Calculate polygon area vs bounding box area
    # Rectangles will have area ratio close to 1.0
    # Use shoelace formula for polygon area
    n = len(exterior) - 1  # Exclude closing point
    polygon_area = 0.0
    for i in range(n):
        j = (i + 1) % n
        polygon_area += exterior[i][0] * exterior[j][1]
        polygon_area -= exterior[j][0] * exterior[i][1]
    polygon_area = abs(polygon_area) / 2.0
    
    bbox_area = bbox_width * bbox_height
    area_ratio = polygon_area / bbox_area if bbox_area > 0 else 0
    
    # If polygon fills >95% of its bounding box, it's likely a rectangle
    if area_ratio > 0.95:
        return True
    
    # Also check for axis-aligned edges (original check)
    if len(exterior) == 5:
        axis_aligned_count = 0
        for i in range(4):
            p1 = exterior[i]
            p2 = exterior[i + 1]
            dx = abs(p1[0] - p2[0])
            dy = abs(p1[1] - p2[1])
            if dx < tolerance or dy < tolerance:
                axis_aligned_count += 1
        if axis_aligned_count == 4:
            return True
    
    return False


def merge_land_polygons(features: List[dict]) -> List[dict]:
    """
    Merge overlapping land polygons to eliminate ENC cell boundaries.
    
    ENC data stores land areas clipped to chart cell boundaries, creating
    rectangular edges where polygons meet. This function unions all land
    polygons into a single continuous landmass.
    """
    print("  Merging overlapping land polygons...")
    
    # Separate polygons from other geometry types
    polygons = []
    other_features = []
    
    for feature in features:
        geom = feature.get("geometry", {})
        geom_type = geom.get("type", "")
        
        if geom_type in ("Polygon", "MultiPolygon"):
            try:
                geom_obj = shape(geom)
                if not geom_obj.is_valid:
                    geom_obj = make_valid(geom_obj)
                if geom_obj.is_valid and not geom_obj.is_empty:
                    polygons.append(geom_obj)
            except Exception as e:
                print(f"    Warning: Could not parse polygon: {e}")
        else:
            other_features.append(feature)
    
    if not polygons:
        print("    No polygons to merge")
        return features
    
    print(f"    Merging {len(polygons)} polygons...")
    
    try:
        # Union all polygons - this eliminates internal boundaries
        merged = unary_union(polygons)
        
        # Convert back to GeoJSON features
        result = []
        
        if merged.geom_type == "Polygon":
            result.append({
                "type": "Feature",
                "properties": {"merged": True},
                "geometry": mapping(merged)
            })
        elif merged.geom_type == "MultiPolygon":
            for poly in merged.geoms:
                result.append({
                    "type": "Feature",
                    "properties": {"merged": True},
                    "geometry": mapping(poly)
                })
        elif merged.geom_type == "GeometryCollection":
            for geom in merged.geoms:
                if geom.geom_type in ("Polygon", "MultiPolygon"):
                    result.append({
                        "type": "Feature",
                        "properties": {"merged": True},
                        "geometry": mapping(geom)
                    })
        
        print(f"    Merged into {len(result)} polygon(s)")
        
        # Return merged polygons plus any non-polygon features
        return result + other_features
        
    except Exception as e:
        print(f"    Warning: Merge failed: {e}")
        print("    Returning original features")
        return features


def discover_coastline_layers(service_path: str) -> Dict[str, int]:
    """Discover layer IDs for coastline-related layers in a service."""
    try:
        # Get detailed layer info
        url = f"{ENC_DIRECT_BASE}/{service_path}/layers?f=json"
        data = make_request(url)
        info = json.loads(data)
        layers = info.get("layers", [])
        
        discovered = {}
        for layer in layers:
            name = layer.get("name", "")
            layer_id = layer.get("id")
            geom_type = layer.get("geometryType", "")
            
            # Skip group layers (no geometry)
            if not geom_type:
                continue
            
            # Look for coastline line layer
            if "Coastline" in name and "_line" in name:
                discovered["coastline_line"] = layer_id
            # Look for land area polygon
            elif "Land_Area" in name and "esriGeometryPolygon" in geom_type:
                discovered["land_area"] = layer_id
            # Look for shoreline construction
            elif "Shoreline_Construction" in name and "_line" in name:
                discovered["shoreline_construction"] = layer_id
        
        return discovered
    except Exception as e:
        print(f"  Layer discovery failed: {e}")
        return {}


def query_all_coastline_features(
    scale_band: str,
    bounds: Tuple[float, float, float, float]
) -> dict:
    """Query coastline features from the map service using REST queries."""
    band_info = SCALE_BANDS[scale_band]
    service_path = band_info["service"]
    
    print(f"Getting service info for {scale_band}...")
    
    all_features = []
    
    # First try known layer IDs
    coastline_layer_id = band_info.get("coastline_layer_id")
    land_area_layer_id = band_info.get("land_area_layer_id")
    
    # If no known IDs, discover them
    if coastline_layer_id is None:
        print("  Discovering layer IDs...")
        discovered = discover_coastline_layers(service_path)
        coastline_layer_id = discovered.get("coastline_line")
        land_area_layer_id = discovered.get("land_area")
        print(f"  Discovered: coastline={coastline_layer_id}, land_area={land_area_layer_id}")
    
    # Query coastline line layer
    if coastline_layer_id is not None:
        print(f"  Querying coastline layer (ID: {coastline_layer_id})...")
        try:
            result = query_features(service_path, coastline_layer_id, bounds)
            features = result.get("features", [])
            print(f"    Found {len(features)} coastline features")
            all_features.extend(features)
        except Exception as e:
            print(f"    Coastline query failed: {e}")
    
    # Query land area polygon layer
    # NOTE: We filter these to remove ENC cell boundary rectangles
    if land_area_layer_id is not None:
        print(f"  Querying land area layer (ID: {land_area_layer_id})...")
        try:
            result = query_features(service_path, land_area_layer_id, bounds)
            features = result.get("features", [])
            # Filter out rectangular cell boundaries
            filtered = [f for f in features if not is_rectangular_feature(f)]
            print(f"    Found {len(features)} land area features, kept {len(filtered)} (filtered {len(features) - len(filtered)} rectangles)")
            all_features.extend(filtered)
        except Exception as e:
            print(f"    Land area query failed: {e}")
    
    if not all_features:
        print("  No features found via known layers, trying layer discovery...")
        # Fallback: search only polygon/area layers
        try:
            service_info = get_map_service_info(service_path)
            layers = service_info.get("layers", [])
            print(f"  Found {len(layers)} total layers")
            
            # Only query area (polygon) layers - not point or line layers
            # Area layers end with "_area" or have no suffix (like "Land_Area")
            target_patterns = ["Land_Area", "Shoreline_Construction_area"]
            
            for layer in layers:
                layer_name = layer.get("name", "")
                layer_id = layer.get("id")
                
                # Only match actual data layers (not group layers)
                if layer.get("subLayerIds") is not None:
                    continue
                
                # Skip point and line layers
                if "_point" in layer_name or "_line" in layer_name:
                    continue
                
                is_target = any(p in layer_name for p in target_patterns)
                if not is_target:
                    continue
                
                print(f"  Querying layer: {layer_name} (ID: {layer_id})")
                try:
                    result = query_features(service_path, layer_id, bounds)
                    features = result.get("features", [])
                    # Filter out rectangular cell boundaries
                    filtered = [f for f in features if not is_rectangular_feature(f)]
                    print(f"    Found {len(features)} features, kept {len(filtered)} (filtered {len(features) - len(filtered)} rectangles)")
                    all_features.extend(filtered)
                except Exception as e:
                    print(f"    Query failed: {e}")
                    
        except Exception as e:
            print(f"  Fallback search failed: {e}")
    
    return {
        "type": "FeatureCollection",
        "features": all_features
    }


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
                    
        elif geom_type == "LineString":
            # LineStrings (coastlines) should NOT be converted to filled polygons
            # as they represent lines, not areas. Skip them for now.
            # The renderer will only fill polygon geometries.
            # TODO: Implement separate line rendering if needed
            pass
                
        elif geom_type == "MultiLineString":
            for line_coords in geom.get("coordinates", []):
                if len(line_coords) >= 2:
                    points = [(p[0], p[1]) for p in line_coords]
                    for lon, lat in points:
                        min_lon = min(min_lon, lon)
                        min_lat = min(min_lat, lat)
                        max_lon = max(max_lon, lon)
                        max_lat = max(max_lat, lat)
                    if points[0] != points[-1]:
                        points.append(points[0])
                    polygons.append((points, []))
    
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
        geom_type = geom.get("type", "")
        
        if geom_type == "Polygon":
            new_coords = []
            for ring in geom.get("coordinates", []):
                simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
                if len(simplified) < 4:
                    simplified = ring
                if simplified[0] != simplified[-1]:
                    simplified.append(simplified[0])
                new_coords.append([(p[0], p[1]) for p in simplified])

            out_features.append({
                "type": "Feature",
                "properties": feature.get("properties", {}),
                "geometry": {"type": "Polygon", "coordinates": new_coords}
            })
            
        elif geom_type == "LineString":
            coords = geom.get("coordinates", [])
            simplified = douglas_peucker([(p[0], p[1]) for p in coords], tolerance)
            if len(simplified) >= 2:
                out_features.append({
                    "type": "Feature",
                    "properties": feature.get("properties", {}),
                    "geometry": {"type": "LineString", "coordinates": simplified}
                })
                
        elif geom_type == "MultiPolygon":
            new_multi = []
            for poly in geom.get("coordinates", []):
                new_poly = []
                for ring in poly:
                    simplified = douglas_peucker([(p[0], p[1]) for p in ring], tolerance)
                    if len(simplified) >= 4:
                        if simplified[0] != simplified[-1]:
                            simplified.append(simplified[0])
                        new_poly.append(simplified)
                if new_poly:
                    new_multi.append(new_poly)
            if new_multi:
                out_features.append({
                    "type": "Feature",
                    "properties": feature.get("properties", {}),
                    "geometry": {"type": "MultiPolygon", "coordinates": new_multi}
                })
        else:
            out_features.append(feature)

    return {"type": "FeatureCollection", "features": out_features}


def update_manifest(
    manifest_path: Path,
    region_id: str,
    region_name: str,
    bounds: Tuple[float, float, float, float],
    lod_files: List[str]
):
    """Update or create manifest.json with ENC region entry."""
    from datetime import datetime
    
    # Load existing manifest or create new
    if manifest_path.exists():
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
    else:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest = {
            "version": 1,
            "lastUpdated": datetime.now().isoformat(),
            "regions": {}
        }
    
    # Extract LOD numbers from filenames
    lods = []
    for f in lod_files:
        for i in range(6):
            if f"lod{i}" in f:
                lods.append(i)
                break
    
    # Add/update ENC region entry
    manifest["regions"][region_id] = {
        "name": region_name,
        "bounds": list(bounds),
        "source": "enc",
        "lods": sorted(set(lods)),
        "files": lod_files,
        "lastUpdated": datetime.now().isoformat()
    }
    
    manifest["lastUpdated"] = datetime.now().isoformat()
    
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)


# LOD simplification tolerances (degrees). Lower = more detailed.
LOD_LEVELS = [
    ("lod0", 0.0),         # Finest (full source detail)
    ("lod1", 0.00005),     # Ultra-high (ENC data is very detailed)
    ("lod2", 0.0001),      # Very high
    ("lod3", 0.0003),      # High
    ("lod4", 0.0008),      # Medium
    ("lod5", 0.002),       # Low
]


def main():
    parser = argparse.ArgumentParser(
        description="Download high-resolution coastline data from NOAA ENC Direct to GIS"
    )
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
        "--scale-band",
        choices=list(SCALE_BANDS.keys()),
        default="harbor",
        help="ENC scale band to use (default: harbor)"
    )
    parser.add_argument(
        "--list-regions",
        action="store_true",
        help="List available regions and exit"
    )
    parser.add_argument(
        "--list-scale-bands",
        action="store_true",
        help="List available scale bands and exit"
    )
    parser.add_argument(
        "--all-scale-bands",
        action="store_true",
        help="Download from all scale bands and merge"
    )
    parser.add_argument(
        "--no-merge",
        action="store_true",
        help="Disable polygon merging (keeps ENC cell boundaries)"
    )
    parser.add_argument(
        "--manifest",
        type=str,
        default="assets/charts/manifest.json",
        help="Path to manifest.json to update (default: assets/charts/manifest.json)"
    )
    parser.add_argument(
        "--no-manifest",
        action="store_true",
        help="Skip updating manifest.json"
    )
    
    args = parser.parse_args()
    
    if args.list_regions:
        print("Available regions:")
        for key, info in REGIONS.items():
            print(f"  {key}: {info['name']}")
            print(f"    {info['description']}")
            print(f"    Bounds: {info['bounds']}")
        return
    
    if args.list_scale_bands:
        print("Available scale bands (from most to least detailed):")
        for key, info in SCALE_BANDS.items():
            print(f"  {key}: {info['description']}")
        return
    
    region_info = REGIONS[args.region]
    print(f"Processing region: {region_info['name']}")
    print(f"Bounds: {region_info['bounds']}")
    
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    all_features = []
    
    # Default to using multiple scale bands for complete coverage
    if args.all_scale_bands or args.scale_band == "harbor":
        # Download from multiple scale bands for complete coastline coverage
        # Harbor provides detail, approach/coastal fill in gaps
        scale_priority = ["harbor", "approach", "coastal"]
        print(f"\nDownloading from multiple scale bands for complete coverage...")
        for scale_band in scale_priority:
            print(f"\n{'='*60}")
            print(f"Querying {scale_band} scale band...")
            print(f"{'='*60}")
            result = query_all_coastline_features(scale_band, region_info['bounds'])
            features = result.get("features", [])
            print(f"  Retrieved {len(features)} features")
            all_features.extend(features)
    else:
        print(f"\nUsing scale band: {args.scale_band}")
        print(f"  {SCALE_BANDS[args.scale_band]['description']}")
        result = query_all_coastline_features(args.scale_band, region_info['bounds'])
        all_features = result.get("features", [])
    
    if not all_features:
        print("\nNo features found! Try a different scale band or check the region bounds.")
        print("Hint: Use --all-scale-bands to try multiple scale bands.")
        return
    
    print(f"\nTotal features collected: {len(all_features)}")
    
    # Merge overlapping land polygons to eliminate cell boundaries
    if not args.no_merge:
        print("\nMerging land polygons to eliminate cell boundaries...")
        all_features = merge_land_polygons(all_features)
        print(f"After merge: {len(all_features)} features")
    
    # Combine into final GeoJSON
    geojson = {
        "type": "FeatureCollection",
        "features": all_features
    }
    
    # Count total points
    total_points = 0
    for feature in all_features:
        geom = feature.get("geometry", {})
        geom_type = geom.get("type", "")
        if geom_type == "Polygon":
            for ring in geom.get("coordinates", []):
                total_points += len(ring)
        elif geom_type == "MultiPolygon":
            for poly in geom.get("coordinates", []):
                for ring in poly:
                    total_points += len(ring)
        elif geom_type == "LineString":
            total_points += len(geom.get("coordinates", []))
        elif geom_type == "MultiLineString":
            for line in geom.get("coordinates", []):
                total_points += len(line)
    
    print(f"Total points: {total_points:,}")
    
    # Save base files with legacy names
    geojson_path = output_dir / f"{args.region}_coastline.geojson"
    with open(geojson_path, 'w') as f:
        json.dump(geojson, f)
    
    binary_data = geojson_to_binary(geojson)
    binary_path = output_dir / f"{args.region}_coastline.bin"
    with open(binary_path, 'wb') as f:
        f.write(binary_data)
    
    print(f"\nSaved base GeoJSON: {geojson_path}")
    print(f"Saved base binary: {binary_path}")
    
    # Generate LOD variants
    for suffix, tolerance in LOD_LEVELS:
        lod_geojson = geojson if tolerance == 0 else simplify_geojson(geojson, tolerance)
        
        # Count simplified points
        lod_points = 0
        for feature in lod_geojson.get("features", []):
            geom = feature.get("geometry", {})
            geom_type = geom.get("type", "")
            if geom_type == "Polygon":
                for ring in geom.get("coordinates", []):
                    lod_points += len(ring)
            elif geom_type == "MultiPolygon":
                for poly in geom.get("coordinates", []):
                    for ring in poly:
                        lod_points += len(ring)
            elif geom_type == "LineString":
                lod_points += len(geom.get("coordinates", []))
            elif geom_type == "MultiLineString":
                for line in geom.get("coordinates", []):
                    lod_points += len(line)
        
        lod_geojson_path = output_dir / f"{args.region}_coastline_{suffix}.geojson"
        with open(lod_geojson_path, 'w') as f:
            json.dump(lod_geojson, f)
        
        lod_binary_path = output_dir / f"{args.region}_coastline_{suffix}.bin"
        with open(lod_binary_path, 'wb') as f:
            f.write(geojson_to_binary(lod_geojson))
        
        print(f"Saved {suffix} (tol={tolerance}): {lod_points:,} points")
    
    # Print statistics
    print(f"\n{'='*60}")
    print(f"Statistics:")
    print(f"{'='*60}")
    print(f"  Features: {len(all_features)}")
    print(f"  Source points: {total_points:,}")
    print(f"  GeoJSON size: {os.path.getsize(geojson_path) / 1024:.1f} KB")
    print(f"  Binary size: {os.path.getsize(binary_path) / 1024:.1f} KB")
    
    # Update manifest
    if not args.no_manifest:
        manifest_path = Path(args.manifest)
        update_manifest(
            manifest_path=manifest_path,
            region_id=args.region,
            region_name=region_info['name'],
            bounds=region_info['bounds'],
            lod_files=[f"{args.region}_coastline_{suffix}.bin" for suffix, _ in LOD_LEVELS]
        )
        print(f"\n  Manifest updated: {manifest_path}")
    
    print(f"\n{'='*60}")
    print(f"Done! ENC coastline data saved to {output_dir}")
    print(f"{'='*60}")
    print("\nNOTE: This data is derived from NOAA ENCs but is NOT certified")
    print("for navigation. Use official NOAA ENC products for navigation.")


if __name__ == "__main__":
    main()
