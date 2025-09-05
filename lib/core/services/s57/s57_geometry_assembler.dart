/// S-57 Geometry Assembly from Vector Primitives
/// 
/// Assembles canonical Point/Line/Polygon geometries for S-57 features using
/// decoded spatial primitives (nodes, edges) and feature spatial pointers (FSPT).
/// Handles orientation, polygon ring closure, and robust handling of degenerate primitives.

import 's57_models.dart';

/// Store for managing S-57 primitive lookups
class PrimitiveStore {
  final Map<int, S57Node> _nodes = {};
  final Map<int, S57Edge> _edges = {};
  final List<String> _warnings = [];

  /// Add node to store
  void addNode(S57Node node) {
    _nodes[node.id] = node;
  }

  /// Add edge to store  
  void addEdge(S57Edge edge) {
    _edges[edge.id] = edge;
  }

  /// Get node by ID, null if not found
  S57Node? node(int id) {
    return _nodes[id];
  }

  /// Get edge by ID, null if not found
  S57Edge? edge(int id) {
    return _edges[id];
  }

  /// Check if node exists
  bool hasNode(int id) => _nodes.containsKey(id);

  /// Check if edge exists
  bool hasEdge(int id) => _edges.containsKey(id);

  /// Get all warnings generated during assembly
  List<String> get warnings => List.unmodifiable(_warnings);

  /// Add warning message
  void addWarning(String message) {
    _warnings.add(message);
  }

  /// Clear all warnings
  void clearWarnings() {
    _warnings.clear();
  }

  /// Create synthetic fallback coordinate for missing primitives
  Coordinate syntheticFallback() {
    addWarning('Using synthetic fallback coordinate (0,0) due to missing primitives');
    return const Coordinate(0.0, 0.0);
  }

  /// Get store statistics
  Map<String, int> get stats => {
    'nodes': _nodes.length,
    'edges': _edges.length,
    'warnings': _warnings.length,
  };

  @override
  String toString() => 'PrimitiveStore(nodes: ${_nodes.length}, edges: ${_edges.length}, warnings: ${_warnings.length})';
}

/// S-57 Geometry Assembler
class S57GeometryAssembler {
  final PrimitiveStore _store;

  S57GeometryAssembler(this._store);

  /// Build geometry from spatial pointers following S-57 topology rules
  S57Geometry buildGeometry(List<S57SpatialPointer> pointers) {
    // Clear warnings before assembly
    _store.clearWarnings();

    if (pointers.isEmpty) {
      _store.addWarning('Empty spatial pointer list - using synthetic fallback');
      return S57Geometry.point(_store.syntheticFallback());
    }

    // Case 1: Single pointer referencing a node → Point
    if (pointers.length == 1 && !pointers.first.isEdge) {
      final nodeId = pointers.first.refId;
      final node = _store.node(nodeId);
      
      if (node == null) {
        _store.addWarning('Missing node $nodeId - using synthetic fallback');
        return S57Geometry.point(_store.syntheticFallback());
      }
      
      return S57Geometry.point(Coordinate(node.x, node.y));
    }

    // Collect coordinate chains from pointers
    final coords = <Coordinate>[];
    
    for (final pointer in pointers) {
      final chain = _buildCoordinateChain(pointer);
      if (chain.isEmpty) continue; // Skip invalid/missing primitives
      
      // Stitch: avoid duplicating shared boundary node
      if (coords.isNotEmpty && coords.last == chain.first) {
        coords.addAll(chain.skip(1));
      } else {
        coords.addAll(chain);
      }
    }

    if (coords.isEmpty) {
      _store.addWarning('No valid coordinates found in pointers - using synthetic fallback');
      return S57Geometry.point(_store.syntheticFallback());
    }

    // Determine geometry type and ensure proper closure
    return _determineGeometryType(coords);
  }

  /// Build coordinate chain from single spatial pointer
  List<Coordinate> _buildCoordinateChain(S57SpatialPointer pointer) {
    final coords = <Coordinate>[];

    if (pointer.isEdge) {
      final edge = _store.edge(pointer.refId);
      if (edge == null) {
        _store.addWarning('Missing edge ${pointer.refId} - skipping pointer');
        return coords;
      }

      if (edge.isDegenerate) {
        _store.addWarning('Degenerate edge ${pointer.refId} with ${edge.nodes.length} nodes - skipping');
        return coords;
      }

      // Convert edge nodes to coordinates
      final edgeCoords = edge.nodes.map((node) => Coordinate(node.x, node.y)).toList();
      
      // Apply orientation
      if (pointer.reverse) {
        coords.addAll(edgeCoords.reversed);
      } else {
        coords.addAll(edgeCoords);
      }
    } else {
      // Single node pointer
      final node = _store.node(pointer.refId);
      if (node == null) {
        _store.addWarning('Missing node ${pointer.refId} - skipping pointer');
        return coords;
      }
      
      coords.add(Coordinate(node.x, node.y));
    }

    return coords;
  }

  /// Determine geometry type and apply closure rules
  S57Geometry _determineGeometryType(List<Coordinate> coords) {
    if (coords.length == 1) {
      return S57Geometry.point(coords.first);
    }

    // Check if coordinates form a closed ring
    final isClosed = coords.length > 2 && coords.first == coords.last;
    
    if (isClosed) {
      // Ensure proper closure
      final closedCoords = ensureClosed(coords);
      return S57Geometry.polygon([closedCoords]);
    } else {
      // Check if we should auto-close based on proximity
      if (coords.length > 2 && _isNearClosed(coords)) {
        _store.addWarning('Auto-closing polygon - first and last coordinates are very close');
        final closedCoords = ensureClosed(coords);
        return S57Geometry.polygon([closedCoords]);
      }
      
      return S57Geometry.line(coords);
    }
  }

  /// Check if coordinates are nearly closed (within tolerance)
  bool _isNearClosed(List<Coordinate> coords, {double tolerance = 1e-6}) {
    if (coords.length < 3) return false;
    
    final first = coords.first;
    final last = coords.last;
    final dx = (first.x - last.x).abs();
    final dy = (first.y - last.y).abs();
    
    return dx < tolerance && dy < tolerance;
  }

  /// Detect self-intersection in polygon (optional sophisticated check)
  bool detectSelfIntersection(List<Coordinate> coords) {
    // Simple O(n²) check for basic self-intersection
    // For production, consider sweep-line algorithm for better performance
    if (coords.length < 4) return false;

    for (int i = 0; i < coords.length - 1; i++) {
      final seg1Start = coords[i];
      final seg1End = coords[i + 1];

      for (int j = i + 2; j < coords.length - 1; j++) {
        final seg2Start = coords[j];
        final seg2End = coords[j + 1];

        // Skip adjacent segments
        if (j == i + 1 || (i == 0 && j == coords.length - 2)) continue;

        if (_segmentsIntersect(seg1Start, seg1End, seg2Start, seg2End)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Check if two line segments intersect
  bool _segmentsIntersect(Coordinate p1, Coordinate q1, Coordinate p2, Coordinate q2) {
    final o1 = _orientation(p1, q1, p2);
    final o2 = _orientation(p1, q1, q2);
    final o3 = _orientation(p2, q2, p1);
    final o4 = _orientation(p2, q2, q1);

    // General case
    if (o1 != o2 && o3 != o4) return true;

    // Special cases for collinear points
    if (o1 == 0 && _onSegment(p1, p2, q1)) return true;
    if (o2 == 0 && _onSegment(p1, q2, q1)) return true;
    if (o3 == 0 && _onSegment(p2, p1, q2)) return true;
    if (o4 == 0 && _onSegment(p2, q1, q2)) return true;

    return false;
  }

  /// Get orientation of ordered triplet (p, q, r)
  int _orientation(Coordinate p, Coordinate q, Coordinate r) {
    final val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    if (val == 0) return 0; // Collinear
    return (val > 0) ? 1 : 2; // Clockwise or counterclockwise
  }

  /// Check if point q lies on segment pr
  bool _onSegment(Coordinate p, Coordinate q, Coordinate r) {
    return q.x <= [p.x, r.x].reduce((a, b) => a > b ? a : b) &&
           q.x >= [p.x, r.x].reduce((a, b) => a < b ? a : b) &&
           q.y <= [p.y, r.y].reduce((a, b) => a > b ? a : b) &&
           q.y >= [p.y, r.y].reduce((a, b) => a < b ? a : b);
  }
}

/// Polygon closure utility
List<Coordinate> ensureClosed(List<Coordinate> coords) {
  if (coords.isEmpty) return coords;
  
  if (coords.first != coords.last) {
    return [...coords, coords.first];
  }
  
  return coords;
}

/// Geometry validation warnings
class GeometryWarning {
  final String message;
  final String type;
  final Map<String, dynamic> context;

  const GeometryWarning({
    required this.message,
    required this.type,
    this.context = const {},
  });

  @override
  String toString() => 'GeometryWarning($type): $message';
}

/// Geometry validation result
class GeometryValidationResult {
  final bool isValid;
  final List<GeometryWarning> warnings;
  final S57Geometry geometry;

  const GeometryValidationResult({
    required this.isValid,
    required this.warnings,
    required this.geometry,
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

/// S-57 Geometry Validator
class S57GeometryValidator {
  /// Validate assembled geometry and generate warnings
  static GeometryValidationResult validate(S57Geometry geometry, {bool checkSelfIntersection = false}) {
    final warnings = <GeometryWarning>[];
    bool isValid = true;

    // Check for empty geometry
    if (geometry.rings.isEmpty || geometry.rings.every((ring) => ring.isEmpty)) {
      warnings.add(const GeometryWarning(
        message: 'Geometry contains no coordinates',
        type: 'empty_geometry',
      ));
      isValid = false;
    }

    // Check for degenerate coordinates
    for (int ringIndex = 0; ringIndex < geometry.rings.length; ringIndex++) {
      final ring = geometry.rings[ringIndex];
      
      // Check for duplicate consecutive points
      for (int i = 1; i < ring.length; i++) {
        if (ring[i] == ring[i - 1]) {
          warnings.add(GeometryWarning(
            message: 'Duplicate consecutive coordinates at ring $ringIndex, position $i',
            type: 'duplicate_coordinates',
            context: {'ring': ringIndex, 'position': i},
          ));
        }
      }

      // Check minimum coordinate requirements
      if (geometry.type == S57GeometryType.line && ring.length < 2) {
        warnings.add(GeometryWarning(
          message: 'Line geometry requires at least 2 coordinates, found ${ring.length}',
          type: 'insufficient_coordinates',
          context: {'ring': ringIndex, 'count': ring.length},
        ));
        isValid = false;
      }

      if (geometry.type == S57GeometryType.area && ring.length < 3) {
        warnings.add(GeometryWarning(
          message: 'Polygon ring requires at least 3 coordinates, found ${ring.length}',
          type: 'insufficient_coordinates',
          context: {'ring': ringIndex, 'count': ring.length},
        ));
        isValid = false;
      }
    }

    // Optional self-intersection check for polygons
    if (checkSelfIntersection && geometry.type == S57GeometryType.area) {
      final assembler = S57GeometryAssembler(PrimitiveStore());
      for (int ringIndex = 0; ringIndex < geometry.rings.length; ringIndex++) {
        final ring = geometry.rings[ringIndex];
        if (assembler.detectSelfIntersection(ring)) {
          warnings.add(GeometryWarning(
            message: 'Self-intersection detected in polygon ring $ringIndex',
            type: 'self_intersection',
            context: {'ring': ringIndex},
          ));
        }
      }
    }

    return GeometryValidationResult(
      isValid: isValid,
      warnings: warnings,
      geometry: geometry,
    );
  }
}