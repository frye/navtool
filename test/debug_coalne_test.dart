import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';

void main() {
  test('Debug COALNE coordinate assembly step by step', () {
    // Arrange - Set up the exact same data as fixtures
    final store = PrimitiveStore();
    
    // Add nodes as in fixture
    store.addNode(const S57Node(id: 1, x: 0.0, y: 0.0));
    store.addNode(const S57Node(id: 2, x: 10.0, y: 0.0));
    store.addNode(const S57Node(id: 3, x: 10.0, y: 10.0));
    
    // Add edges as in fixture
    final edge1 = const S57Edge(id: 1, nodes: [
      S57Node(id: 1, x: 0.0, y: 0.0),
      S57Node(id: 2, x: 10.0, y: 0.0),
    ]);
    final edge2 = const S57Edge(id: 2, nodes: [
      S57Node(id: 2, x: 10.0, y: 0.0),
      S57Node(id: 3, x: 10.0, y: 10.0),
    ]);
    
    store.addEdge(edge1);
    store.addEdge(edge2);
    
    print('Edge 1 nodes: ${edge1.nodes.map((n) => '(${n.x}, ${n.y})').join(' -> ')}');
    print('Edge 2 nodes: ${edge2.nodes.map((n) => '(${n.x}, ${n.y})').join(' -> ')}');
    
    final assembler = S57GeometryAssembler(store);
    
    // Test each pointer individually
    final pointer1 = const S57SpatialPointer(refId: 1, isEdge: true, reverse: false);
    final pointer2 = const S57SpatialPointer(refId: 2, isEdge: true, reverse: true);
    
    print('\n--- Testing E1 forward ---');
    final geom1 = assembler.buildGeometry([pointer1]);
    print('E1 forward result: ${geom1.rings.first.map((c) => '(${c.x}, ${c.y})').join(' -> ')}');
    
    print('\n--- Testing E2 reversed ---');
    final geom2 = assembler.buildGeometry([pointer2]);
    print('E2 reversed result: ${geom2.rings.first.map((c) => '(${c.x}, ${c.y})').join(' -> ')}');
    
    print('\n--- Testing E1 + E2 combined ---');
    final geometry = assembler.buildGeometry([pointer1, pointer2]);
    final coords = geometry.rings.first;
    print('Combined result: ${coords.map((c) => '(${c.x}, ${c.y})').join(' -> ')}');
    
    // What we expect:
    // E1 forward: (0,0) -> (10,0)
    // E2 reversed: (10,10) -> (10,0)
    // Combined: (0,0) -> (10,0) [shared] (10,10)
    // So result should be: (0,0) -> (10,0) -> (10,10)
  });
}