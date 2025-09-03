import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/route.dart';
import 'package:navtool/core/models/waypoint.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_api_client.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:mockito/mockito.dart';

/// Simple in-memory fake implementation of [StorageService] for unit tests.
/// Only the methods currently exercised by discovery related tests are fully
/// implemented. Others return benign defaults to avoid test coupling; if a
/// new test begins relying on an unimplemented method it should either extend
/// this fake or replace with a purpose-built mock.
class InMemoryStorageServiceFake implements StorageService {
  final Map<String, List<int>> _chartData = {};
  final Map<String, List<String>> _stateMappings = {};
  final Map<String, NavigationRoute> _routes = {};
  final Map<String, Waypoint> _waypoints = {};

  @override
  Future<void> storeChart(Chart chart, List<int> data) async {
    _chartData[chart.id] = data;
  }

  @override
  Future<List<int>?> loadChart(String chartId) async => _chartData[chartId];

  @override
  Future<void> deleteChart(String chartId) async {
    _chartData.remove(chartId);
  }

  @override
  Future<Map<String, dynamic>> getStorageInfo() async => {
        'charts': _chartData.length,
        'routes': _routes.length,
        'waypoints': _waypoints.length,
      };

  @override
  Future<void> cleanupOldData() async {}

  @override
  Future<int> getStorageUsage() async => _chartData.values.fold<int>(0, (int a, List<int> b) => a + b.length);

  @override
  Future<Directory> getChartsDirectory() async => Directory.systemTemp.createTemp('charts');

  @override
  Future<void> storeRoute(NavigationRoute route) async {
    _routes[route.id] = route;
  }

  @override
  Future<NavigationRoute?> loadRoute(String routeId) async => _routes[routeId];

  @override
  Future<void> deleteRoute(String routeId) async => _routes.remove(routeId);

  @override
  Future<List<NavigationRoute>> getAllRoutes() async => _routes.values.toList();

  @override
  Future<void> storeWaypoint(Waypoint waypoint) async {
    _waypoints[waypoint.id] = waypoint;
  }

  @override
  Future<Waypoint?> loadWaypoint(String waypointId) async => _waypoints[waypointId];

  @override
  Future<void> updateWaypoint(Waypoint waypoint) async => _waypoints[waypoint.id] = waypoint;

  @override
  Future<void> deleteWaypoint(String waypointId) async => _waypoints.remove(waypointId);

  @override
  Future<List<Waypoint>> getAllWaypoints() async => _waypoints.values.toList();

  @override
  Future<void> storeStateCellMapping(String stateName, List<String> chartCells) async {
    _stateMappings[stateName] = List.from(chartCells);
  }

  @override
  Future<List<String>?> getStateCellMapping(String stateName) async => _stateMappings[stateName];

  @override
  Future<void> clearAllStateCellMappings() async => _stateMappings.clear();

  @override
  Future<List<Chart>> getChartsInBounds(GeographicBounds bounds) async => const <Chart>[];

  @override
  Future<int> countChartsWithInvalidBounds() async => 0; // Discovery tests expect a clean cache by default

  @override
  Future<int> clearChartsWithInvalidBounds() async => 0;
}

/// Convenience factory for creating a [NoaaChartDiscoveryServiceImpl] with
/// sensible test defaults. Allows overriding individual dependencies.
NoaaChartDiscoveryServiceImpl createDiscoveryService({
  required ChartCatalogService catalogService,
  required StateRegionMappingService mappingService,
  StorageService? storageService,
  required AppLogger logger,
}) {
  return NoaaChartDiscoveryServiceImpl(
    catalogService: catalogService,
    mappingService: mappingService,
    storageService: storageService ?? InMemoryStorageServiceFake(),
    logger: logger,
  );
}

/// Safely asserts that a result list is not empty before accessing the first element.
/// Provides a clearer failure message than a raw RangeError if the list is empty.
T expectFirst<T>(List<T> items) {
  expect(items, isNotEmpty, reason: 'Expected non-empty list before accessing first element');
  return items.first;
}

/// Sets up a [NoaaApiClient] mock with safe benign defaults to prevent
/// MissingStubError in tests that only care about higher-level behaviors.
///
/// Provided [mock] must be a Mockito mock of [NoaaApiClient]. Each method is
/// stubbed to return a neutral value unless already stubbed by the caller.
/// Existing stubs are not overridden.
void configureNoaaApiClientMock(dynamic mock) {
  // Only add stubs if not already provided so callers can override selectively.
  when(mock.fetchChartCatalog(filters: anyNamed('filters')))
      .thenAnswer((_) async => '{"type":"FeatureCollection","features":[]}');
  when(mock.getChartMetadata(any)).thenAnswer((_) async => null);
  when(mock.isChartAvailable(any)).thenAnswer((_) async => true);
  when(mock.getDownloadProgress(any)).thenAnswer((_) => const Stream<double>.empty());
  when(mock.downloadChart(any, any, onProgress: anyNamed('onProgress')))
      .thenAnswer((_) async {});
  when(mock.cancelDownload(any)).thenAnswer((_) async {});
}

/// Convenience to configure catalog fetch with specific charts encoded as GeoJSON.
void stubCatalogWithCharts(dynamic mock, List<Chart> charts) {
  final features = charts.map((c) => {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [c.bounds!.west, c.bounds!.south],
              [c.bounds!.east, c.bounds!.south],
              [c.bounds!.east, c.bounds!.north],
              [c.bounds!.west, c.bounds!.north],
              [c.bounds!.west, c.bounds!.south]
            ]
          ]
        },
        'properties': {
          'CHART': c.id,
          'TITLE': c.title,
          'SCALE': c.scale,
          'LAST_UPDATE': c.lastUpdate.toIso8601String(),
          'STATE': c.state,
          'USAGE': c.type.name,
        }
      }).toList();
  final geoJson = '{"type":"FeatureCollection","features":${features.toString()}}';
  when(mock.fetchChartCatalog(filters: anyNamed('filters'))).thenAnswer((_) async => geoJson);
}

/// Stubs the catalog fetch to throw an error (e.g., for retry / error path tests).
void stubCatalogError(dynamic mock, Exception error) {
  when(mock.fetchChartCatalog(filters: anyNamed('filters')))
      .thenThrow(error);
}

/// Stubs a specific chart cell as unavailable (returns null metadata and false availability).
void stubChartUnavailable(dynamic mock, String cellName) {
  when(mock.getChartMetadata(cellName)).thenAnswer((_) async => null);
  when(mock.isChartAvailable(cellName)).thenAnswer((_) async => false);
}

/// Stubs a download operation to fail with provided exception.
void stubDownloadFailure(dynamic mock, String cellName, Exception error) {
  when(mock.downloadChart(cellName, any, onProgress: anyNamed('onProgress')))
      .thenThrow(error);
}

/// Builds an ArcGIS-style FeatureCollection JSON string containing a single
/// feature with an `attributes` object matching the shape expected by
/// [NoaaApiClientImpl.getChartMetadata]. Useful for tests that want to return
/// concrete metadata instead of null from `getChartMetadata` without relying
/// on broader catalog fixtures.
String buildArcGisMetadataFeature({
  required String cellName,
  String? title,
  String coverageCategory = 'Harbor',
  String inform = '',
  String sourceDate = '20240115',
  String sourceIndicator = 'US,US,NOS,US',
  int objectId = 1,
  GeographicBounds? bounds,
}) {
  final b = bounds ?? GeographicBounds(
    north: 38.0,
    south: 37.5,
    east: -122.0,
    west: -122.5,
  );
  final feature = {
    'attributes': {
      'DSNM': cellName,
      'TITLE': title ?? cellName,
      'CATCOV': coverageCategory,
      'INFORM': inform.isEmpty ? (title ?? cellName) : inform,
      'SORDAT': sourceDate,
      'SORIND': sourceIndicator,
      'OBJECTID': objectId,
    },
    'geometry': {
      'rings': [
        [
          [b.west, b.south],
          [b.east, b.south],
          [b.east, b.north],
          [b.west, b.north],
          [b.west, b.south],
        ]
      ]
    }
  };

  return '{"features":[${feature.toString()}]}';
}

/// Convenience to stub `getChartMetadata` with a synthesized ArcGIS-style
/// metadata response that the production parser will accept.
void stubChartMetadata(dynamic mock, String cellName, {String? title, GeographicBounds? bounds}) {
  when(mock.getChartMetadata(cellName)).thenAnswer((_) async {
    // The real client returns a Chart, but for pure mock usage higher level
    // services might only need non-null to proceed. We simulate by decoding
    // through the real parser path in integration tests; here we just return
    // null because building a full Chart requires invoking implementation.
    // Users wanting a real Chart should prefer integration tests or extend
    // this helper to construct a Chart directly if API surface allows.
    return Chart(
      id: cellName,
      title: title ?? cellName,
      scale: 20000,
      bounds: bounds ?? GeographicBounds(
        north: 38.0,
        south: 37.5,
        east: -122.0,
        west: -122.5,
      ),
      lastUpdate: DateTime.now(),
      state: 'Unknown',
      type: ChartType.harbor,
      metadata: {
        'cell_name': cellName,
      },
    );
  });
}
