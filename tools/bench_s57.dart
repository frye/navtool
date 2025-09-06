import 'dart:convert';
import 'dart:math';

import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_spatial_tree.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import 'package:navtool/core/services/s57/spatial_index_interface.dart';

/// S-57 Spatial Index Performance Benchmark Harness
/// 
/// Validates performance targets for R-tree implementation:
/// - <10ms spatial queries for real-time navigation
/// - Sub-linear performance improvement over linear baseline
/// - Deterministic bulk load performance
void main() async {
  print('S-57 Spatial Index Performance Benchmark');
  print('==========================================');
  
  final sizes = [1000, 5000, 10000, 25000];
  
  for (final n in sizes) {
    print('\nBenchmarking dataset size: $n features');
    await _benchmarkDatasetSize(n);
  }
  
  print('\nBenchmark Summary');
  print('=================');
  print('All tests completed. See individual results above.');
  print('Performance targets:');
  print('- Bounds Query: <10ms (p95)');
  print('- Point Query: <5ms (p95)'); 
  print('- Build Time: <1000ms for 10k features');
}

Future<void> _benchmarkDatasetSize(int n) async {
  // Generate diverse feature set
  final features = _synthesizeFeatures(n);
  
  // Benchmark R-tree construction
  final buildWatch = Stopwatch()..start();
  final rtreeIndex = S57SpatialTree.bulkLoad(features);
  buildWatch.stop();
  final rtreeBuildMs = buildWatch.elapsedMilliseconds;
  
  // Benchmark linear construction for comparison
  buildWatch.reset();
  buildWatch.start();
  final linearIndex = S57SpatialIndex();
  linearIndex.addFeatures(features);
  buildWatch.stop();
  final linearBuildMs = buildWatch.elapsedMilliseconds;
  
  // Generate query workloads
  final boundsQueries = _generateBoundsQueries(rtreeIndex, 100);
  final pointQueries = _generatePointQueries(rtreeIndex, 200);
  
  // Benchmark R-tree queries
  final rtreeBoundsTimes = _benchmarkBoundsQueries(rtreeIndex, boundsQueries);
  final rtreePointTimes = _benchmarkPointQueries(rtreeIndex, pointQueries);
  
  // Benchmark linear queries for comparison
  final linearBoundsTimes = _benchmarkBoundsQueries(linearIndex, boundsQueries);
  final linearPointTimes = _benchmarkPointQueries(linearIndex, pointQueries);
  
  // Calculate statistics
  final rtreeBoundsStats = _calculateStats(rtreeBoundsTimes);
  final rtreePointStats = _calculateStats(rtreePointTimes);
  final linearBoundsStats = _calculateStats(linearBoundsTimes);
  final linearPointStats = _calculateStats(linearPointTimes);
  
  // Output results as JSON
  final results = {
    'dataset_size': n,
    'build_performance': {
      'rtree_build_ms': rtreeBuildMs,
      'linear_build_ms': linearBuildMs,
      'rtree_vs_linear_ratio': linearBuildMs > 0 ? rtreeBuildMs / linearBuildMs : null,
    },
    'bounds_query_performance': {
      'rtree': rtreeBoundsStats,
      'linear': linearBoundsStats,
      'speedup_factor': (linearBoundsStats['p50'] ?? 0) > 0 && (rtreeBoundsStats['p50'] ?? 0) > 0 
          ? (linearBoundsStats['p50']! / rtreeBoundsStats['p50']!) 
          : null,
    },
    'point_query_performance': {
      'rtree': rtreePointStats,
      'linear': linearPointStats,
      'speedup_factor': (linearPointStats['p50'] ?? 0) > 0 && (rtreePointStats['p50'] ?? 0) > 0 
          ? (linearPointStats['p50']! / rtreePointStats['p50']!) 
          : null,
    },
    'performance_targets': {
      'bounds_p95_under_10ms': (rtreeBoundsStats['p95'] ?? double.infinity) < 10.0,
      'point_p95_under_5ms': (rtreePointStats['p95'] ?? double.infinity) < 5.0,
      'build_time_acceptable': rtreeBuildMs < (n / 10), // <100ms per 1k features rule of thumb
    },
  };
  
  print(const JsonEncoder.withIndent('  ').convert(results));
}

/// Generate synthetic S-57 features with realistic marine distribution
List<S57Feature> _synthesizeFeatures(int count) {
  final features = <S57Feature>[];
  final random = Random(42); // Deterministic seed for reproducible benchmarks
  
  // Elliott Bay / Puget Sound area (realistic marine coordinates)
  const baseLat = 47.65;
  const baseLon = -122.35;
  const latRange = 0.1; // ~11km range
  const lonRange = 0.1; // ~8km range at this latitude
  
  // Feature type distribution based on real marine charts
  final featureTypes = [
    S57FeatureType.sounding,        // 40% - Most common
    S57FeatureType.depthContour,    // 20%
    S57FeatureType.buoy,            // 15%
    S57FeatureType.beacon,          // 10%
    S57FeatureType.depthArea,       // 8%
    S57FeatureType.coastline,       // 4%
    S57FeatureType.lighthouse,      // 2%
    S57FeatureType.wreck,          // 1%
  ];
  final typeWeights = [40, 20, 15, 10, 8, 4, 2, 1];
  
  for (int i = 0; i < count; i++) {
    // Select feature type based on weights
    final typeIndex = _selectWeightedRandom(typeWeights, random);
    final featureType = featureTypes[typeIndex];
    
    // Generate coordinates based on feature type
    final coords = _generateFeatureCoordinates(
      featureType, baseLat, baseLon, latRange, lonRange, random);
    
    final geometryType = _getGeometryTypeForFeature(featureType);
    
    features.add(S57Feature(
      recordId: i,
      featureType: featureType,
      geometryType: geometryType,
      coordinates: coords,
      attributes: _generateFeatureAttributes(featureType, random),
    ));
  }
  
  return features;
}

/// Generate realistic coordinates for a feature type
List<S57Coordinate> _generateFeatureCoordinates(
    S57FeatureType type, double baseLat, double baseLon, 
    double latRange, double lonRange, Random random) {
  
  switch (type) {
    case S57FeatureType.sounding:
    case S57FeatureType.buoy:
    case S57FeatureType.beacon:
    case S57FeatureType.lighthouse:
    case S57FeatureType.wreck:
      // Point features
      return [S57Coordinate(
        latitude: baseLat + (random.nextDouble() - 0.5) * latRange,
        longitude: baseLon + (random.nextDouble() - 0.5) * lonRange,
      )];
      
    case S57FeatureType.depthContour:
    case S57FeatureType.coastline:
      // Line features (3-8 points)
      final numPoints = 3 + random.nextInt(6);
      final coords = <S57Coordinate>[];
      
      final startLat = baseLat + (random.nextDouble() - 0.5) * latRange;
      final startLon = baseLon + (random.nextDouble() - 0.5) * lonRange;
      
      for (int i = 0; i < numPoints; i++) {
        final lat = startLat + (random.nextDouble() - 0.5) * latRange * 0.1;
        final lon = startLon + i * lonRange * 0.02;
        coords.add(S57Coordinate(latitude: lat, longitude: lon));
      }
      
      return coords;
      
    case S57FeatureType.depthArea:
      // Area features (4-6 points forming polygon)
      final numPoints = 4 + random.nextInt(3);
      final coords = <S57Coordinate>[];
      
      final centerLat = baseLat + (random.nextDouble() - 0.5) * latRange;
      final centerLon = baseLon + (random.nextDouble() - 0.5) * lonRange;
      final radius = latRange * 0.01;
      
      for (int i = 0; i < numPoints; i++) {
        final angle = (i / numPoints) * 2 * pi;
        final lat = centerLat + radius * sin(angle);
        final lon = centerLon + radius * cos(angle);
        coords.add(S57Coordinate(latitude: lat, longitude: lon));
      }
      
      // Close polygon
      coords.add(coords.first);
      return coords;
      
    default:
      // Default point
      return [S57Coordinate(
        latitude: baseLat + (random.nextDouble() - 0.5) * latRange,
        longitude: baseLon + (random.nextDouble() - 0.5) * lonRange,
      )];
  }
}

S57GeometryType _getGeometryTypeForFeature(S57FeatureType type) {
  switch (type) {
    case S57FeatureType.depthContour:
    case S57FeatureType.coastline:
      return S57GeometryType.line;
    case S57FeatureType.depthArea:
      return S57GeometryType.area;
    default:
      return S57GeometryType.point;
  }
}

Map<String, dynamic> _generateFeatureAttributes(S57FeatureType type, Random random) {
  switch (type) {
    case S57FeatureType.sounding:
      return {'depth': (random.nextDouble() * 50).toStringAsFixed(1)};
    case S57FeatureType.depthContour:
      return {'depth': (5 + random.nextInt(20) * 5).toString()};
    case S57FeatureType.buoy:
      return {'color': ['red', 'green', 'yellow'][random.nextInt(3)]};
    case S57FeatureType.lighthouse:
      return {'range': (10 + random.nextInt(15)).toString()};
    default:
      return {};
  }
}

int _selectWeightedRandom(List<int> weights, Random random) {
  final totalWeight = weights.reduce((a, b) => a + b);
  final randomValue = random.nextInt(totalWeight);
  
  int currentWeight = 0;
  for (int i = 0; i < weights.length; i++) {
    currentWeight += weights[i];
    if (randomValue < currentWeight) {
      return i;
    }
  }
  
  return weights.length - 1; // Fallback
}

/// Generate diverse bounds queries
List<S57Bounds> _generateBoundsQueries(SpatialIndex index, int count) {
  final bounds = index.calculateBounds();
  if (bounds == null) return [];
  
  final random = Random(43); // Different seed for queries
  final queries = <S57Bounds>[];
  
  final latRange = bounds.north - bounds.south;
  final lonRange = bounds.east - bounds.west;
  
  for (int i = 0; i < count; i++) {
    // Generate query bounds of varying sizes
    final sizeMultiplier = 0.01 + random.nextDouble() * 0.2; // 1% to 20% of total bounds
    
    final queryLatRange = latRange * sizeMultiplier;
    final queryLonRange = lonRange * sizeMultiplier;
    
    final centerLat = bounds.south + queryLatRange/2 + 
                     random.nextDouble() * (latRange - queryLatRange);
    final centerLon = bounds.west + queryLonRange/2 + 
                     random.nextDouble() * (lonRange - queryLonRange);
    
    queries.add(S57Bounds(
      north: centerLat + queryLatRange/2,
      south: centerLat - queryLatRange/2,
      east: centerLon + queryLonRange/2,
      west: centerLon - queryLonRange/2,
    ));
  }
  
  return queries;
}

/// Generate diverse point queries  
List<Map<String, double>> _generatePointQueries(SpatialIndex index, int count) {
  final bounds = index.calculateBounds();
  if (bounds == null) return [];
  
  final random = Random(44); // Different seed for point queries
  final queries = <Map<String, double>>[];
  
  final latRange = bounds.north - bounds.south;
  final lonRange = bounds.east - bounds.west;
  
  for (int i = 0; i < count; i++) {
    final lat = bounds.south + random.nextDouble() * latRange;
    final lon = bounds.west + random.nextDouble() * lonRange;
    
    // Vary radius from very small to moderate
    final radius = 0.001 + random.nextDouble() * 0.02; // 0.1% to 2% range
    
    queries.add({
      'lat': lat,
      'lon': lon,
      'radius': radius,
    });
  }
  
  return queries;
}

/// Benchmark bounds queries and return timing results
List<double> _benchmarkBoundsQueries(SpatialIndex index, List<S57Bounds> queries) {
  final times = <double>[];
  
  for (final bounds in queries) {
    final watch = Stopwatch()..start();
    final results = index.queryBounds(bounds);
    watch.stop();
    
    times.add(watch.elapsedMicroseconds / 1000.0); // Convert to milliseconds
    
    // Consume results to prevent optimization
    if (results.isNotEmpty) {
      results.first.recordId;
    }
  }
  
  return times;
}

/// Benchmark point queries and return timing results
List<double> _benchmarkPointQueries(SpatialIndex index, List<Map<String, double>> queries) {
  final times = <double>[];
  
  for (final query in queries) {
    final watch = Stopwatch()..start();
    final results = index.queryPoint(
      query['lat']!, 
      query['lon']!, 
      radiusDegrees: query['radius']!
    );
    watch.stop();
    
    times.add(watch.elapsedMicroseconds / 1000.0); // Convert to milliseconds
    
    // Consume results to prevent optimization
    if (results.isNotEmpty) {
      results.first.recordId;
    }
  }
  
  return times;
}

/// Calculate percentile statistics from timing measurements
Map<String, double> _calculateStats(List<double> times) {
  if (times.isEmpty) {
    return {'count': 0, 'min': 0, 'max': 0, 'mean': 0, 'p50': 0, 'p95': 0, 'p99': 0};
  }
  
  final sorted = List<double>.from(times)..sort();
  final count = sorted.length;
  
  return {
    'count': count.toDouble(),
    'min': sorted.first,
    'max': sorted.last,
    'mean': sorted.reduce((a, b) => a + b) / count,
    'p50': _percentile(sorted, 50),
    'p95': _percentile(sorted, 95),
    'p99': _percentile(sorted, 99),
  };
}

double _percentile(List<double> sorted, int percentile) {
  if (sorted.isEmpty) return 0.0;
  
  final index = (sorted.length - 1) * percentile / 100.0;
  final lower = index.floor();
  final upper = index.ceil();
  
  if (lower == upper) {
    return sorted[lower];
  }
  
  final weight = index - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}