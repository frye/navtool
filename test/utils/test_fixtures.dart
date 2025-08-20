import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Comprehensive test utilities for NOAA testing
/// 
/// Provides fixtures, mock data generation, and helper functions
/// for testing all aspects of NOAA integration.
class TestFixtures {
  /// Load a test fixture from the fixtures directory
  static Future<String> loadTestFixture(String filename) async {
    final file = File('test/fixtures/$filename');
    if (!await file.exists()) {
      throw FileSystemException('Test fixture not found', file.path);
    }
    return await file.readAsString();
  }

  /// Load and parse JSON test fixture
  static Future<Map<String, dynamic>> loadJsonFixture(String filename) async {
    final jsonString = await loadTestFixture(filename);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// Create a test chart with customizable properties
  static Chart createTestChart({
    String? id,
    String? title,
    int? scale,
    GeographicBounds? bounds,
    DateTime? lastUpdate,
    String? state,
    ChartType? type,
    ChartSource? source,
    ChartStatus? status,
    int? edition,
    int? updateNumber,
    Map<String, dynamic>? metadata,
  }) {
    return Chart(
      id: id ?? 'TEST001',
      title: title ?? 'Test Chart',
      scale: scale ?? 25000,
      bounds: bounds ?? GeographicBounds(
        north: 25.0,
        south: 24.0,
        east: -80.0,
        west: -81.0,
      ),
      lastUpdate: lastUpdate ?? DateTime(2024, 1, 15),
      state: state ?? 'Florida',
      type: type ?? ChartType.harbor,
      source: source ?? ChartSource.noaa,
      status: status ?? ChartStatus.current,
      edition: edition ?? 1,
      updateNumber: updateNumber ?? 0,
      metadata: metadata ?? {},
    );
  }

  /// Create a test GeoJSON feature for NOAA chart data
  static Map<String, dynamic> createTestGeoJsonFeature({
    String? cellName,
    String? title,
    int? scale,
    String? usage,
    String? state,
    String? status,
    String? region,
    List<List<double>>? coordinates,
    String? editionNum,
    String? updateNum,
    String? lastUpdate,
  }) {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [coordinates ?? [
          [-81.0, 24.0],
          [-80.0, 24.0],
          [-80.0, 25.0],
          [-81.0, 25.0],
          [-81.0, 24.0]
        ]]
      },
      'properties': {
        'CELL_NAME': cellName ?? 'TEST001',
        'CHART': cellName ?? 'TEST001',
        'TITLE': title ?? 'Test Chart',
        'SCALE': scale ?? 25000,
        'USAGE': usage ?? 'Harbor',
        'STATE': state ?? 'Florida',
        'STATUS': status ?? 'Current',
        'REGION': region ?? 'Southeast Coast',
        'EDITION_NUM': editionNum ?? '1',
        'UPDATE_NUM': updateNum ?? '0',
        'LAST_UPDATE': lastUpdate ?? '2024-01-15T00:00:00Z',
        'RELEASE_DATE': lastUpdate ?? '2024-01-15T00:00:00Z',
        'COMPILATION_SCALE': scale?.toString() ?? '25000',
        'DT_PUB': '20240115',
        'ISSUE_DATE': '2024-01-15',
        'SOURCE_DATE_STRING': 'January 2024',
        'EDITION_DATE': '2024-01-15T00:00:00Z',
      }
    };
  }

  /// Create a complete GeoJSON FeatureCollection for testing
  static Map<String, dynamic> createTestCatalog({
    List<Map<String, dynamic>>? features,
    int? featureCount,
  }) {
    final catalogFeatures = features ?? 
        List.generate(featureCount ?? 5, (i) => createTestGeoJsonFeature(
          cellName: 'US5TEST${i.toString().padLeft(2, '0')}M',
          title: 'Test Chart $i',
          scale: 25000 + (i * 5000),
          state: ['Florida', 'California', 'New York', 'Texas'][i % 4],
          usage: ['Harbor', 'Approach', 'Coastal'][i % 3],
        ));

    return {
      'type': 'FeatureCollection',
      'features': catalogFeatures,
    };
  }
}

/// Mock data generators for testing different scenarios
class MockDataGenerators {
  static final _random = math.Random(42); // Fixed seed for reproducible tests

  /// Generate a large catalog for performance testing
  static Map<String, dynamic> generateLargeCatalog(int chartCount) {
    final features = List.generate(chartCount, (i) {
      final lat = 24.0 + (_random.nextDouble() * 20.0); // 24-44 degrees
      final lon = -125.0 + (_random.nextDouble() * 50.0); // -125 to -75 degrees
      
      return TestFixtures.createTestGeoJsonFeature(
        cellName: 'US5PERF${i.toString().padLeft(4, '0')}M',
        title: 'Performance Test Chart $i',
        scale: [10000, 15000, 20000, 25000, 30000, 40000, 50000][_random.nextInt(7)],
        state: _getRandomState(),
        usage: ['Harbor', 'Approach', 'Coastal', 'General'][_random.nextInt(4)],
        coordinates: _generateRandomCoordinates(lat, lon),
      );
    });

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// Generate charts for specific state testing
  static List<Chart> generateChartsForState(String state, int count) {
    final bounds = _getStateBounds(state);
    
    return List.generate(count, (i) {
      final chartBounds = _generateBoundsWithinState(bounds);
      
      return TestFixtures.createTestChart(
        id: 'US5${state.substring(0, 2).toUpperCase()}${i.toString().padLeft(2, '0')}M',
        title: '$state Chart $i',
        state: state,
        bounds: chartBounds,
        scale: [20000, 25000, 30000, 40000][_random.nextInt(4)],
        type: [ChartType.harbor, ChartType.approach, ChartType.coastal][_random.nextInt(3)],
      );
    });
  }

  /// Generate complex MultiPolygon geometry for testing
  static Map<String, dynamic> generateComplexGeometry() {
    final polygons = <List<List<List<double>>>>[];
    
    // Generate 3-5 polygons
    final polygonCount = 3 + _random.nextInt(3);
    for (int i = 0; i < polygonCount; i++) {
      final centerLat = 35.0 + (_random.nextDouble() * 10.0);
      final centerLon = -120.0 + (_random.nextDouble() * 20.0);
      final radius = 0.1 + (_random.nextDouble() * 0.2);
      
      final polygon = _generatePolygonAround(centerLat, centerLon, radius);
      polygons.add([polygon]);
    }

    return {
      'type': 'MultiPolygon',
      'coordinates': polygons,
    };
  }

  /// Generate charts with various statuses for testing
  static List<Chart> generateChartsWithMixedStatuses(int count) {
    final statuses = [
      ChartStatus.current,
      ChartStatus.superseded,
      ChartStatus.preliminary,
      ChartStatus.cancelled,
    ];

    return List.generate(count, (i) {
      return TestFixtures.createTestChart(
        id: 'US5STATUS${i.toString().padLeft(2, '0')}M',
        title: 'Status Test Chart $i',
        status: statuses[i % statuses.length],
        lastUpdate: DateTime.now().subtract(Duration(days: i * 30)),
      );
    });
  }

  static String _getRandomState() {
    final states = [
      'Florida', 'California', 'New York', 'Texas', 'Washington',
      'Massachusetts', 'Alabama', 'Maryland', 'Michigan', 'Hawaii'
    ];
    return states[_random.nextInt(states.length)];
  }

  static List<List<double>> _generateRandomCoordinates(double centerLat, double centerLon) {
    final size = 0.1 + (_random.nextDouble() * 0.2);
    return [
      [centerLon - size, centerLat - size],
      [centerLon + size, centerLat - size],
      [centerLon + size, centerLat + size],
      [centerLon - size, centerLat + size],
      [centerLon - size, centerLat - size], // Close the polygon
    ];
  }

  static GeographicBounds _getStateBounds(String state) {
    // Simplified state bounds for testing
    final stateBounds = {
      'Florida': GeographicBounds(north: 31.0, south: 24.4, east: -79.9, west: -87.6),
      'California': GeographicBounds(north: 42.0, south: 32.5, east: -114.1, west: -124.7),
      'New York': GeographicBounds(north: 45.0, south: 40.5, east: -71.9, west: -79.8),
      'Texas': GeographicBounds(north: 36.5, south: 25.8, east: -93.5, west: -106.6),
      'Washington': GeographicBounds(north: 49.0, south: 45.5, east: -116.9, west: -124.8),
    };
    
    return stateBounds[state] ?? GeographicBounds(
      north: 40.0, south: 30.0, east: -80.0, west: -90.0
    );
  }

  static GeographicBounds _generateBoundsWithinState(GeographicBounds stateBounds) {
    final latRange = stateBounds.north - stateBounds.south;
    final lonRange = stateBounds.east - stateBounds.west;
    
    final size = 0.1 + (_random.nextDouble() * 0.2);
    final centerLat = stateBounds.south + (_random.nextDouble() * latRange);
    final centerLon = stateBounds.west + (_random.nextDouble() * lonRange);
    
    return GeographicBounds(
      north: math.min(centerLat + size/2, stateBounds.north),
      south: math.max(centerLat - size/2, stateBounds.south),
      east: math.min(centerLon + size/2, stateBounds.east),
      west: math.max(centerLon - size/2, stateBounds.west),
    );
  }

  static List<List<double>> _generatePolygonAround(double centerLat, double centerLon, double radius) {
    final points = <List<double>>[];
    final numPoints = 8 + _random.nextInt(8); // 8-15 points
    
    for (int i = 0; i < numPoints; i++) {
      final angle = (i / numPoints) * 2 * math.pi;
      final r = radius * (0.8 + _random.nextDouble() * 0.4); // Vary radius
      final lat = centerLat + r * math.cos(angle);
      final lon = centerLon + r * math.sin(angle);
      points.add([lon, lat]);
    }
    
    // Close the polygon
    points.add(points.first);
    return points;
  }
}

/// Test assertion helpers for NOAA-specific validations
class NoaaTestAssertions {
  /// Assert that a chart has valid NOAA properties
  static void assertValidChart(Chart chart) {
    expect(chart.id, isNotEmpty);
    expect(chart.title, isNotEmpty);
    expect(chart.scale, greaterThan(0));
    expect(chart.bounds, isNotNull);
    expect(chart.bounds != null, isTrue);
    expect(chart.source, equals(ChartSource.noaa));
    expect(chart.state, isNotEmpty);
  }

  /// Assert that a GeoJSON feature has required NOAA properties
  static void assertValidGeoJsonFeature(Map<String, dynamic> feature) {
    expect(feature['type'], equals('Feature'));
    expect(feature['geometry'], isA<Map<String, dynamic>>());
    expect(feature['properties'], isA<Map<String, dynamic>>());
    
    final properties = feature['properties'] as Map<String, dynamic>;
    final requiredFields = ['CHART', 'TITLE', 'SCALE', 'STATE', 'USAGE'];
    
    for (final field in requiredFields) {
      expect(properties.containsKey(field), isTrue, 
          reason: 'Missing required field: $field');
      expect(properties[field], isNotNull,
          reason: 'Required field $field is null');
    }
  }

  /// Assert that a catalog has the expected structure
  static void assertValidCatalog(Map<String, dynamic> catalog) {
    expect(catalog['type'], equals('FeatureCollection'));
    expect(catalog['features'], isA<List>());
    
    final features = catalog['features'] as List;
    expect(features, isNotEmpty);
    
    for (final feature in features) {
      assertValidGeoJsonFeature(feature as Map<String, dynamic>);
    }
  }

  /// Assert that charts are within geographic bounds
  static void assertChartsInBounds(List<Chart> charts, GeographicBounds bounds) {
    for (final chart in charts) {
      expect(chart.bounds, isNotNull);
      expect(chart.bounds!.overlaps(bounds), isTrue,
          reason: 'Chart ${chart.id} is outside expected bounds');
    }
  }

  /// Assert performance requirements are met
  static void assertPerformanceRequirements({
    required int elapsedMs,
    required int maxAllowedMs,
    required int itemCount,
    String? operation,
  }) {
    expect(elapsedMs, lessThan(maxAllowedMs),
        reason: '${operation ?? 'Operation'} took ${elapsedMs}ms for $itemCount items, '
               'expected < ${maxAllowedMs}ms');
    
    if (itemCount > 0) {
      final msPerItem = elapsedMs / itemCount;
      print('Performance: ${operation ?? 'Operation'} processed $itemCount items '
            'in ${elapsedMs}ms (${msPerItem.toStringAsFixed(2)}ms per item)');
    }
  }

  /// Assert memory usage is within acceptable limits
  static void assertMemoryUsage({
    required int memoryBytes,
    required int maxAllowedBytes,
    String? operation,
  }) {
    expect(memoryBytes, lessThan(maxAllowedBytes),
        reason: '${operation ?? 'Operation'} used ${memoryBytes} bytes, '
               'expected < ${maxAllowedBytes} bytes');
    
    final mb = memoryBytes / (1024 * 1024);
    print('Memory: ${operation ?? 'Operation'} used ${mb.toStringAsFixed(2)}MB');
  }
}

/// Mock response builders for testing API interactions
class MockResponseBuilders {
  /// Build a successful catalog response
  static String buildCatalogResponse({int chartCount = 10}) {
    final catalog = MockDataGenerators.generateLargeCatalog(chartCount);
    return jsonEncode(catalog);
  }

  /// Build an error response for testing error handling
  static String buildErrorResponse({
    required String errorCode,
    required String message,
    Map<String, dynamic>? details,
  }) {
    return jsonEncode({
      'error': {
        'code': errorCode,
        'message': message,
        'details': details ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      }
    });
  }

  /// Build a chart metadata response
  static String buildChartMetadataResponse(Chart chart) {
    final feature = TestFixtures.createTestGeoJsonFeature(
      cellName: chart.id,
      title: chart.title,
      scale: chart.scale,
      state: chart.state,
      usage: chart.type.toString().split('.').last,
    );
    
    return jsonEncode(feature);
  }
}

/// Test environment helpers
class TestEnvironment {
  /// Check if integration tests should be skipped
  static bool get shouldSkipIntegrationTests {
    return Platform.environment['SKIP_INTEGRATION_TESTS'] == 'true' ||
           Platform.environment['CI'] == 'true';
  }

  /// Check if performance tests should be skipped
  static bool get shouldSkipPerformanceTests {
    return Platform.environment['SKIP_PERFORMANCE_TESTS'] == 'true';
  }

  /// Get test timeout based on environment
  static Duration get testTimeout {
    if (Platform.environment['CI'] == 'true') {
      return const Duration(minutes: 5); // Longer timeout for CI
    }
    return const Duration(minutes: 2);
  }

  /// Print test environment information
  static void printEnvironmentInfo() {
    print('Test Environment:');
    print('  Platform: ${Platform.operatingSystem}');
    print('  CI: ${Platform.environment['CI'] ?? 'false'}');
    print('  Skip Integration: $shouldSkipIntegrationTests');
    print('  Skip Performance: $shouldSkipPerformanceTests');
    print('  Timeout: $testTimeout');
  }
}

/// Marine-specific test utilities
class MarineTestUtils {
  /// Generate coordinates in known marine areas
  static List<GeographicBounds> getMarineTestAreas() {
    return [
      // Gulf of Mexico
      GeographicBounds(north: 30.0, south: 18.0, east: -80.0, west: -98.0),
      // US East Coast
      GeographicBounds(north: 45.0, south: 25.0, east: -65.0, west: -85.0),
      // US West Coast  
      GeographicBounds(north: 49.0, south: 32.0, east: -115.0, west: -130.0),
      // Great Lakes
      GeographicBounds(north: 49.0, south: 41.0, east: -76.0, west: -95.0),
      // Alaska
      GeographicBounds(north: 71.0, south: 54.0, east: -130.0, west: -180.0),
      // Hawaii
      GeographicBounds(north: 29.0, south: 18.0, east: -154.0, west: -179.0),
    ];
  }

  /// Check if coordinates are in US navigable waters
  static bool isInNavigableWaters(double lat, double lon) {
    for (final area in getMarineTestAreas()) {
      if (area.contains(lat, lon)) {
        return true;
      }
    }
    return false;
  }

  /// Generate realistic marine chart scales
  static List<int> getRealisticChartScales() {
    return [
      10000,  // Harbor scale
      15000,  // Harbor/Approach
      20000,  // Harbor/Approach
      25000,  // Approach
      30000,  // Approach
      40000,  // Coastal
      50000,  // Coastal
      80000,  // General
      100000, // General
      200000, // Overview
    ];
  }
}

extension GeographicBoundsTestHelpers on GeographicBounds {
  /// Check if bounds are valid for marine navigation
  bool get isValidForMarine {
    return (south >= -90.0 && north <= 90.0) &&
           (west >= -180.0 && east <= 180.0) &&
           (north - south) >= 0.001 && // Minimum size
           (east - west) >= 0.001;
  }

  /// Check if point is contained within bounds
  bool contains(double lat, double lon) {
    return lat >= south && lat <= north &&
           lon >= west && lon <= east;
  }

  /// Check if bounds overlap with another bounds
  bool overlaps(GeographicBounds other) {
    return !(east < other.west || west > other.east ||
             north < other.south || south > other.north);
  }
}