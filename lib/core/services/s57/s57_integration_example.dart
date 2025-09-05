/// Integration example showing how to use S57GeometryAssembler with existing S57Parser
/// 
/// This demonstrates the pattern for integrating the new geometry assembly functionality
/// with the existing S-57 parsing pipeline without breaking backward compatibility.

import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_geometry_assembler.dart';

/// Enhanced S-57 feature factory using geometry assembly
class S57FeatureFactory {
  final PrimitiveStore _primitiveStore;
  final S57GeometryAssembler _assembler;

  S57FeatureFactory() 
    : _primitiveStore = PrimitiveStore(),
      _assembler = S57GeometryAssembler(PrimitiveStore());

  /// Build S-57 feature with assembled geometry from primitives
  S57Feature? buildFeatureWithAssembledGeometry({
    required int recordId,
    required S57FeatureType featureType,
    required Map<String, dynamic> attributes,
    required List<S57SpatialPointer> spatialPointers,
    String? label,
  }) {
    // Assemble geometry from spatial pointers
    final assembledGeometry = _assembler.buildGeometry(spatialPointers);
    
    // Convert to legacy coordinate format for backward compatibility
    final coordinates = assembledGeometry.toS57Coordinates();
    
    // Map assembled geometry type to S57GeometryType
    final geometryType = assembledGeometry.type;
    
    // Log any warnings from assembly process
    for (final warning in _primitiveStore.warnings) {
      print('Geometry assembly warning: $warning');
    }
    
    return S57Feature(
      recordId: recordId,
      featureType: featureType,
      geometryType: geometryType,
      coordinates: coordinates,
      attributes: attributes,
      label: label,
    );
  }

  /// Add primitive to store for later geometry assembly
  void addNode(S57Node node) {
    _primitiveStore.addNode(node);
  }

  /// Add edge primitive to store
  void addEdge(S57Edge edge) {
    _primitiveStore.addEdge(edge);
  }

  /// Create spatial pointer from parsed FSPT data
  S57SpatialPointer createSpatialPointer(Map<String, dynamic> fsptData) {
    return S57SpatialPointer.fromFspt(fsptData);
  }

  /// Get assembly statistics
  Map<String, int> get assemblyStats => _primitiveStore.stats;
}

/// Example usage pattern for integration with existing S57Parser
class S57IntegrationExample {
  static void demonstrateIntegration() {
    final factory = S57FeatureFactory();
    
    // Step 1: Add primitives parsed from S-57 vector records
    factory.addNode(const S57Node(id: 1, x: 0.0, y: 0.0));
    factory.addNode(const S57Node(id: 2, x: 10.0, y: 0.0));
    factory.addNode(const S57Node(id: 3, x: 10.0, y: 10.0));
    
    // Step 2: Add edges from spatial records
    factory.addEdge(const S57Edge(id: 1, nodes: [
      S57Node(id: 1, x: 0.0, y: 0.0),
      S57Node(id: 2, x: 10.0, y: 0.0),
    ]));
    
    // Step 3: Create spatial pointers from FSPT/VRPT field data
    final spatialPointers = [
      const S57SpatialPointer(refId: 1, isEdge: false, reverse: false), // Point to node 1
    ];
    
    // Step 4: Build feature with assembled geometry
    final feature = factory.buildFeatureWithAssembledGeometry(
      recordId: 12345,
      featureType: S57FeatureType.sounding,
      attributes: {'VALSOU': 15.2, 'QUASOU': 6},
      spatialPointers: spatialPointers,
      label: 'Sounding 15.2m',
    );
    
    if (feature != null) {
      print('Created feature: ${feature.featureType} at ${feature.coordinates.first}');
      print('Assembly stats: ${factory.assemblyStats}');
    }
  }
}

/// Integration points for existing S57Parser
extension S57ParserIntegration on Map<String, dynamic> {
  /// Extract spatial pointers from parsed FSPT fields
  List<S57SpatialPointer> extractSpatialPointers() {
    final fsptFields = this['FSPT'] as List<dynamic>? ?? [];
    return fsptFields
        .map((fspt) => S57SpatialPointer.fromFspt(fspt as Map<String, dynamic>))
        .toList();
  }
  
  /// Extract nodes from parsed vector records  
  List<S57Node> extractNodes() {
    final sg2dData = this['SG2D'] as List<dynamic>? ?? [];
    final nodes = <S57Node>[];
    
    for (int i = 0; i < sg2dData.length; i++) {
      final coordData = sg2dData[i] as Map<String, dynamic>;
      nodes.add(S57Node(
        id: i + 1, // Generate sequential IDs
        x: (coordData['longitude'] as num).toDouble(),
        y: (coordData['latitude'] as num).toDouble(),
      ));
    }
    
    return nodes;
  }
}

/// Example of enhanced S57ParsedData with geometry assembly metadata
class S57ParsedDataWithAssembly extends S57ParsedData {
  final List<String> assemblyWarnings;
  final Map<String, int> assemblyStats;

  const S57ParsedDataWithAssembly({
    required super.metadata,
    required super.features,
    required super.bounds,
    required super.spatialIndex,
    required this.assemblyWarnings,
    required this.assemblyStats,
  });

  /// Convert to enhanced format with assembly information
  @override
  Map<String, dynamic> toChartServiceFormat() {
    final baseFormat = super.toChartServiceFormat();
    baseFormat['geometry_assembly'] = {
      'warnings': assemblyWarnings,
      'stats': assemblyStats,
      'primitive_count': assemblyStats['nodes']! + assemblyStats['edges']!,
    };
    return baseFormat;
  }
}