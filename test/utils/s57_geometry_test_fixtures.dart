/// Test fixtures for S-57 geometry assembly testing
/// 
/// Loads primitive data (nodes, edges, FSPT pointers) from JSON fixtures
/// to test the geometry assembly pipeline

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';

/// Test fixture loader for S-57 geometry assembly tests
class S57GeometryTestFixtures {
  static const String _fixtureFile = 'test/fixtures/geometry/primitive_set.json';
  
  late Map<String, dynamic> _data;
  late PrimitiveStore _store;

  /// Load test fixtures from JSON file
  static Future<S57GeometryTestFixtures> load() async {
    final fixtures = S57GeometryTestFixtures._();
    await fixtures._loadFixtures();
    return fixtures;
  }

  S57GeometryTestFixtures._();

  /// Load and parse fixture data
  Future<void> _loadFixtures() async {
    final file = File(_fixtureFile);
    if (!await file.exists()) {
      throw TestFailure('Test fixture file not found: $_fixtureFile');
    }

    final jsonString = await file.readAsString();
    _data = json.decode(jsonString) as Map<String, dynamic>;
    
    _store = PrimitiveStore();
    _loadNodes();
    _loadEdges();
  }

  /// Load nodes into primitive store
  void _loadNodes() {
    final nodesData = _data['nodes'] as Map<String, dynamic>;
    
    for (final entry in nodesData.entries) {
      final nodeData = entry.value as Map<String, dynamic>;
      final node = S57Node(
        id: nodeData['id'] as int,
        x: (nodeData['x'] as num).toDouble(),
        y: (nodeData['y'] as num).toDouble(),
      );
      _store.addNode(node);
    }
  }

  /// Load edges into primitive store
  void _loadEdges() {
    final edgesData = _data['edges'] as Map<String, dynamic>;
    
    for (final entry in edgesData.entries) {
      final edgeData = entry.value as Map<String, dynamic>;
      final nodesData = edgeData['nodes'] as List<dynamic>;
      
      final nodes = nodesData.map((nodeData) {
        final nodeMap = nodeData as Map<String, dynamic>;
        return S57Node(
          id: nodeMap['id'] as int,
          x: (nodeMap['x'] as num).toDouble(),
          y: (nodeMap['y'] as num).toDouble(),
        );
      }).toList();

      final edge = S57Edge(
        id: edgeData['id'] as int,
        nodes: nodes,
      );
      _store.addEdge(edge);
    }
  }

  /// Get primitive store with loaded data
  PrimitiveStore get store => _store;

  /// Get spatial pointers for a feature
  List<S57SpatialPointer> getFeaturePointers(String featureName) {
    final featuresData = _data['features'] as Map<String, dynamic>;
    final featureData = featuresData[featureName] as Map<String, dynamic>?;
    
    if (featureData == null) {
      throw TestFailure('Feature $featureName not found in fixtures');
    }

    final pointersData = featureData['pointers'] as List<dynamic>;
    return pointersData.map((pointerData) {
      final pointerMap = pointerData as Map<String, dynamic>;
      return S57SpatialPointer(
        refId: pointerMap['refId'] as int,
        isEdge: pointerMap['isEdge'] as bool,
        reverse: pointerMap['reverse'] as bool,
      );
    }).toList();
  }

  /// Get expected coordinates for a feature
  List<List<double>> getExpectedCoordinates(String featureName) {
    final featuresData = _data['features'] as Map<String, dynamic>;
    final featureData = featuresData[featureName] as Map<String, dynamic>?;
    
    if (featureData == null) {
      throw TestFailure('Feature $featureName not found in fixtures');
    }

    final coordsData = featureData['expected_coordinates'] as List<dynamic>;
    return coordsData.map((coordData) {
      final coordList = coordData as List<dynamic>;
      return [
        (coordList[0] as num).toDouble(),
        (coordList[1] as num).toDouble(),
      ];
    }).toList();
  }

  /// Get expected geometry type for a feature
  String getExpectedGeometryType(String featureName) {
    final featuresData = _data['features'] as Map<String, dynamic>;
    final featureData = featuresData[featureName] as Map<String, dynamic>?;
    
    if (featureData == null) {
      throw TestFailure('Feature $featureName not found in fixtures');
    }

    return featureData['expected_geometry'] as String;
  }

  /// Create degenerate edge for testing
  S57Edge createDegenerateEdge() {
    final testData = _data['test_scenarios']['degenerate_edge'] as Map<String, dynamic>;
    final nodesData = testData['nodes'] as List<dynamic>;
    
    final nodes = nodesData.map((nodeData) {
      final nodeMap = nodeData as Map<String, dynamic>;
      return S57Node(
        id: nodeMap['id'] as int,
        x: (nodeMap['x'] as num).toDouble(),
        y: (nodeMap['y'] as num).toDouble(),
      );
    }).toList();

    return S57Edge(
      id: testData['id'] as int,
      nodes: nodes,
    );
  }

  /// Get pointers for missing primitive test
  List<S57SpatialPointer> getMissingPrimitivePointers() {
    final testData = _data['test_scenarios']['missing_primitive'] as Map<String, dynamic>;
    final pointersData = testData['pointers'] as List<dynamic>;
    
    return pointersData.map((pointerData) {
      final pointerMap = pointerData as Map<String, dynamic>;
      return S57SpatialPointer(
        refId: pointerMap['refId'] as int,
        isEdge: pointerMap['isEdge'] as bool,
        reverse: pointerMap['reverse'] as bool,
      );
    }).toList();
  }

  /// Create self-intersecting polygon for testing
  List<Coordinate> createSelfIntersectingPolygon() {
    final testData = _data['test_scenarios']['self_intersection_polygon'] as Map<String, dynamic>;
    final nodesData = testData['nodes'] as List<dynamic>;
    
    return nodesData.map((nodeData) {
      final nodeMap = nodeData as Map<String, dynamic>;
      return Coordinate(
        (nodeMap['x'] as num).toDouble(),
        (nodeMap['y'] as num).toDouble(),
      );
    }).toList();
  }

  /// Get stitching test coordinate that should not be duplicated
  List<double> getStitchingTestCoordinate() {
    final testData = _data['test_scenarios']['stitching_test'] as Map<String, dynamic>;
    final coord = testData['expected_no_duplicate_at'] as List<dynamic>;
    return [
      (coord[0] as num).toDouble(),
      (coord[1] as num).toDouble(),
    ];
  }

  /// Helper to convert coordinates to S57Coordinate list for assertions
  List<S57Coordinate> toS57Coordinates(List<List<double>> coords) {
    return coords.map((coord) => S57Coordinate(
      latitude: coord[1],
      longitude: coord[0],
    )).toList();
  }

  /// Helper to convert Coordinate to coordinate pair for assertions
  List<double> coordinateToList(Coordinate coord) {
    return [coord.x, coord.y];
  }

  /// Helper to convert coordinate lists for comparison
  List<List<double>> coordinateListToLists(List<Coordinate> coords) {
    return coords.map((coord) => [coord.x, coord.y]).toList();
  }
}