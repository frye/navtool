import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/geo_types.dart';

/// Parser for GeoJSON coastline data from NOAA.
/// 
/// Supports standard GeoJSON format with Polygon and MultiPolygon geometries.
/// Can also read/write an optimized binary format for faster loading.
class CoastlineParser {
  /// Parse GeoJSON from a string.
  static CoastlineData parseGeoJson(String jsonString, {String? name}) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return _parseGeoJsonMap(json, name: name);
  }

  /// Parse GeoJSON from a file.
  static Future<CoastlineData> parseGeoJsonFile(String filePath, {String? name}) async {
    final file = File(filePath);
    final contents = await file.readAsString();
    return parseGeoJson(contents, name: name ?? filePath);
  }

  /// Parse GeoJSON from a Flutter asset.
  static Future<CoastlineData> parseGeoJsonAsset(String assetPath, {String? name}) async {
    final contents = await rootBundle.loadString(assetPath);
    return parseGeoJson(contents, name: name ?? assetPath);
  }

  static CoastlineData _parseGeoJsonMap(Map<String, dynamic> json, {String? name}) {
    final List<CoastlinePolygon> polygons = [];
    
    final type = json['type'] as String?;
    
    if (type == 'FeatureCollection') {
      final features = json['features'] as List<dynamic>;
      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry != null) {
          polygons.addAll(_parseGeometry(geometry));
        }
      }
    } else if (type == 'Feature') {
      final geometry = json['geometry'] as Map<String, dynamic>?;
      if (geometry != null) {
        polygons.addAll(_parseGeometry(geometry));
      }
    } else if (type == 'Polygon' || type == 'MultiPolygon') {
      polygons.addAll(_parseGeometry(json));
    }

    if (polygons.isEmpty) {
      throw FormatException('No valid polygon geometries found in GeoJSON');
    }

    // Calculate overall bounds
    double minLon = double.infinity;
    double minLat = double.infinity;
    double maxLon = double.negativeInfinity;
    double maxLat = double.negativeInfinity;

    for (final polygon in polygons) {
      final bounds = polygon.bounds;
      if (bounds.minLon < minLon) minLon = bounds.minLon;
      if (bounds.minLat < minLat) minLat = bounds.minLat;
      if (bounds.maxLon > maxLon) maxLon = bounds.maxLon;
      if (bounds.maxLat > maxLat) maxLat = bounds.maxLat;
    }

    return CoastlineData(
      polygons: polygons,
      bounds: GeoBounds(
        minLon: minLon,
        minLat: minLat,
        maxLon: maxLon,
        maxLat: maxLat,
      ),
      name: name,
      lastUpdated: DateTime.now(),
    );
  }

  static List<CoastlinePolygon> _parseGeometry(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String;
    final coordinates = geometry['coordinates'];

    switch (type) {
      case 'Polygon':
        return [_parsePolygon(coordinates as List<dynamic>)];
      case 'MultiPolygon':
        return _parseMultiPolygon(coordinates as List<dynamic>);
      default:
        return [];
    }
  }

  static CoastlinePolygon _parsePolygon(List<dynamic> rings) {
    if (rings.isEmpty) {
      throw FormatException('Polygon must have at least one ring');
    }

    final exteriorRing = _parseRing(rings[0] as List<dynamic>);
    final interiorRings = <List<GeoPoint>>[];

    for (int i = 1; i < rings.length; i++) {
      interiorRings.add(_parseRing(rings[i] as List<dynamic>));
    }

    return CoastlinePolygon(
      exteriorRing: exteriorRing,
      interiorRings: interiorRings,
    );
  }

  static List<CoastlinePolygon> _parseMultiPolygon(List<dynamic> polygons) {
    return polygons.map((p) => _parsePolygon(p as List<dynamic>)).toList();
  }

  static List<GeoPoint> _parseRing(List<dynamic> coordinates) {
    return coordinates
        .map((coord) => GeoPoint.fromJson(coord as List<dynamic>))
        .toList();
  }

  // ============ Binary Format for Performance ============
  // 
  // Binary format structure:
  // Header (20 bytes):
  //   - Magic: 4 bytes "NVTL"
  //   - Version: 2 bytes (uint16)
  //   - Polygon count: 4 bytes (uint32)
  //   - Bounds: 4 x float64 (32 bytes)
  // For each polygon:
  //   - Exterior ring point count: 4 bytes (uint32)
  //   - Interior ring count: 4 bytes (uint32)
  //   - Exterior ring points: N x 2 x float64
  //   - For each interior ring:
  //     - Point count: 4 bytes (uint32)
  //     - Points: N x 2 x float64

  static const _magic = 0x4E56544C; // "NVTL"
  static const _version = 1;

  /// Convert coastline data to optimized binary format.
  static Uint8List toBinary(CoastlineData data) {
    // Calculate buffer size
    int size = 4 + 2 + 4 + 32; // Header
    for (final polygon in data.polygons) {
      size += 4 + 4; // Ring counts
      size += polygon.exteriorRing.length * 16; // Points
      for (final ring in polygon.interiorRings) {
        size += 4 + ring.length * 16;
      }
    }

    final buffer = ByteData(size);
    int offset = 0;

    // Write header
    buffer.setUint32(offset, _magic, Endian.little);
    offset += 4;
    buffer.setUint16(offset, _version, Endian.little);
    offset += 2;
    buffer.setUint32(offset, data.polygons.length, Endian.little);
    offset += 4;
    
    // Write bounds
    buffer.setFloat64(offset, data.bounds.minLon, Endian.little);
    offset += 8;
    buffer.setFloat64(offset, data.bounds.minLat, Endian.little);
    offset += 8;
    buffer.setFloat64(offset, data.bounds.maxLon, Endian.little);
    offset += 8;
    buffer.setFloat64(offset, data.bounds.maxLat, Endian.little);
    offset += 8;

    // Write polygons
    for (final polygon in data.polygons) {
      buffer.setUint32(offset, polygon.exteriorRing.length, Endian.little);
      offset += 4;
      buffer.setUint32(offset, polygon.interiorRings.length, Endian.little);
      offset += 4;

      for (final point in polygon.exteriorRing) {
        buffer.setFloat64(offset, point.longitude, Endian.little);
        offset += 8;
        buffer.setFloat64(offset, point.latitude, Endian.little);
        offset += 8;
      }

      for (final ring in polygon.interiorRings) {
        buffer.setUint32(offset, ring.length, Endian.little);
        offset += 4;
        for (final point in ring) {
          buffer.setFloat64(offset, point.longitude, Endian.little);
          offset += 8;
          buffer.setFloat64(offset, point.latitude, Endian.little);
          offset += 8;
        }
      }
    }

    return buffer.buffer.asUint8List();
  }

  /// Parse coastline data from optimized binary format.
  static CoastlineData fromBinary(Uint8List bytes, {String? name}) {
    final buffer = ByteData.view(bytes.buffer);
    int offset = 0;

    // Read header
    final magic = buffer.getUint32(offset, Endian.little);
    offset += 4;
    if (magic != _magic) {
      throw FormatException('Invalid binary format: bad magic number');
    }

    final version = buffer.getUint16(offset, Endian.little);
    offset += 2;
    if (version > _version) {
      throw FormatException('Unsupported binary format version: $version');
    }

    final polygonCount = buffer.getUint32(offset, Endian.little);
    offset += 4;

    // Read bounds
    final minLon = buffer.getFloat64(offset, Endian.little);
    offset += 8;
    final minLat = buffer.getFloat64(offset, Endian.little);
    offset += 8;
    final maxLon = buffer.getFloat64(offset, Endian.little);
    offset += 8;
    final maxLat = buffer.getFloat64(offset, Endian.little);
    offset += 8;

    final bounds = GeoBounds(
      minLon: minLon,
      minLat: minLat,
      maxLon: maxLon,
      maxLat: maxLat,
    );

    // Read polygons
    final polygons = <CoastlinePolygon>[];
    for (int i = 0; i < polygonCount; i++) {
      final exteriorCount = buffer.getUint32(offset, Endian.little);
      offset += 4;
      final interiorRingCount = buffer.getUint32(offset, Endian.little);
      offset += 4;

      final exteriorRing = <GeoPoint>[];
      for (int j = 0; j < exteriorCount; j++) {
        final lon = buffer.getFloat64(offset, Endian.little);
        offset += 8;
        final lat = buffer.getFloat64(offset, Endian.little);
        offset += 8;
        exteriorRing.add(GeoPoint(lon, lat));
      }

      final interiorRings = <List<GeoPoint>>[];
      for (int r = 0; r < interiorRingCount; r++) {
        final ringCount = buffer.getUint32(offset, Endian.little);
        offset += 4;
        final ring = <GeoPoint>[];
        for (int j = 0; j < ringCount; j++) {
          final lon = buffer.getFloat64(offset, Endian.little);
          offset += 8;
          final lat = buffer.getFloat64(offset, Endian.little);
          offset += 8;
          ring.add(GeoPoint(lon, lat));
        }
        interiorRings.add(ring);
      }

      polygons.add(CoastlinePolygon(
        exteriorRing: exteriorRing,
        interiorRings: interiorRings,
      ));
    }

    return CoastlineData(
      polygons: polygons,
      bounds: bounds,
      name: name,
      lastUpdated: DateTime.now(),
    );
  }

  /// Save coastline data to binary file.
  static Future<void> saveBinary(CoastlineData data, String filePath) async {
    final bytes = toBinary(data);
    await File(filePath).writeAsBytes(bytes);
  }

  /// Load coastline data from binary file.
  static Future<CoastlineData> loadBinary(String filePath, {String? name}) async {
    final bytes = await File(filePath).readAsBytes();
    return fromBinary(bytes, name: name ?? filePath);
  }

  /// Load coastline data from binary asset.
  static Future<CoastlineData> loadBinaryAsset(String assetPath, {String? name}) async {
    final data = await rootBundle.load(assetPath);
    return fromBinary(data.buffer.asUint8List(), name: name ?? assetPath);
  }
}
