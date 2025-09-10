/// Performance and conversion validation tests for Elliott Bay S-57 feature processing
/// 
/// Tests that the enhanced S57ToMaritimeAdapter meets the success criteria:
/// - 90%+ conversion rate for Elliott Bay features
/// - Attribute preservation for critical navigation data
/// - Performance within 2 seconds for Elliott Bay-sized datasets

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('Elliott Bay S-57 Conversion Validation', () {
    group('Conversion Rate Validation', () {
      test('achieves 90%+ conversion rate for Elliott Bay feature mix', () {
        // Create comprehensive Elliott Bay feature dataset
        final elliottBayFeatures = _createElliottBayFeatureDataset();
        
        final stopwatch = Stopwatch()..start();
        final convertedFeatures = S57ToMaritimeAdapter.convertFeatures(elliottBayFeatures);
        stopwatch.stop();
        
        // Validate conversion rate
        final conversionRate = convertedFeatures.length / elliottBayFeatures.length;
        expect(conversionRate, greaterThanOrEqualTo(0.90), 
               reason: 'Should achieve 90%+ conversion rate. Got ${(conversionRate * 100).toStringAsFixed(1)}%');
        
        // Validate performance requirement (2 seconds for Elliott Bay)
        expect(stopwatch.elapsedMilliseconds, lessThan(2000),
               reason: 'Conversion should complete within 2 seconds for Elliott Bay dataset');
        
        // Validate feature type coverage
        final convertedTypes = convertedFeatures.map((f) => f.type).toSet();
        expect(convertedTypes, contains(MaritimeFeatureType.depthArea));
        expect(convertedTypes, contains(MaritimeFeatureType.soundings));
        expect(convertedTypes, contains(MaritimeFeatureType.buoy));
        expect(convertedTypes, contains(MaritimeFeatureType.lighthouse));
        expect(convertedTypes, contains(MaritimeFeatureType.shoreline));
        expect(convertedTypes, contains(MaritimeFeatureType.landArea));
        expect(convertedTypes, contains(MaritimeFeatureType.shoreConstruction)); // NEW
        expect(convertedTypes, contains(MaritimeFeatureType.builtArea)); // NEW
      });
      
      test('preserves critical navigation attributes during conversion', () {
        final criticalFeatures = [
          // Depth area with critical depth values
          S57Feature(
            recordId: 1,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {
              'DRVAL1': 5.0, // Minimum depth - CRITICAL
              'DRVAL2': 15.0, // Maximum depth - CRITICAL
              'QUASOU': 6, // Quality of sounding - CRITICAL
              'OBJNAM': 'Elliott Bay Depth Area',
            },
          ),
          // Sounding with depth value
          S57Feature(
            recordId: 2,
            featureType: S57FeatureType.sounding,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.605, longitude: -122.325)],
            attributes: {
              'VALSOU': 8.5, // Sounding depth - CRITICAL
              'QUASOU': 7, // Quality - CRITICAL
            },
          ),
          // Buoy with navigation characteristics
          S57Feature(
            recordId: 3,
            featureType: S57FeatureType.buoyLateral,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.61, longitude: -122.32)],
            attributes: {
              'BOYSHP': 'cylindrical', // Shape - CRITICAL
              'COLOUR': 'red', // Color - CRITICAL for navigation
              'CATBOY': 'port', // Category - CRITICAL
            },
          ),
          // Shore construction with structural details
          S57Feature(
            recordId: 4,
            featureType: S57FeatureType.shoreConstruction,
            geometryType: S57GeometryType.line,
            coordinates: [
              S57Coordinate(latitude: 47.605, longitude: -122.325),
              S57Coordinate(latitude: 47.606, longitude: -122.324),
            ],
            attributes: {
              'CATSLC': 'pier', // Construction type - CRITICAL
              'CONRAD': 'concrete', // Material - CRITICAL for clearance
            },
          ),
        ];
        
        final converted = S57ToMaritimeAdapter.convertFeatures(criticalFeatures);
        expect(converted, hasLength(4));
        
        // Verify depth area attributes preserved
        final depthArea = converted.firstWhere((f) => f.type == MaritimeFeatureType.depthArea);
        expect(depthArea.attributes['depth_min'], equals(5.0));
        expect(depthArea.attributes['depth_max'], equals(15.0));
        expect(depthArea.attributes['QUASOU'], equals(6));
        expect(depthArea.attributes['original_s57_acronym'], equals('DEPARE'));
        
        // Verify sounding attributes preserved
        final sounding = converted.firstWhere((f) => f.type == MaritimeFeatureType.soundings);
        expect(sounding.attributes['depth'], equals(8.5));
        expect(sounding.attributes['QUASOU'], equals(7));
        
        // Verify buoy navigation attributes preserved
        final buoy = converted.firstWhere((f) => f.type == MaritimeFeatureType.buoy);
        expect(buoy.attributes['buoyShape'], equals('cylindrical'));
        expect(buoy.attributes['color'], equals('red'));
        expect(buoy.attributes['category'], equals('port'));
        
        // Verify shore construction attributes preserved
        final pier = converted.firstWhere((f) => f.type == MaritimeFeatureType.shoreConstruction);
        expect(pier.attributes['category'], equals('pier'));
        expect(pier.attributes['construction_material'], equals('concrete'));
      });
    });
    
    group('Elliott Bay Feature Distribution Validation', () {
      test('handles expected Elliott Bay feature distribution', () {
        final elliottBayMix = [
          // Depth areas (10-20 expected)
          ...List.generate(15, (i) => _createDepthArea(i)),
          // Soundings (100-200 expected) - use smaller sample for test
          ...List.generate(50, (i) => _createSounding(i)),
          // Buoys (5-15 expected)
          ...List.generate(8, (i) => _createBuoy(i)),
          // Lights (3-8 expected)
          ...List.generate(5, (i) => _createLight(i)),
          // Coastlines (20-40 expected) - sample
          ...List.generate(10, (i) => _createCoastline(i)),
          // Land areas (5-15 expected)
          ...List.generate(7, (i) => _createLandArea(i)),
          // Shore constructions (10-25 expected) - NEW
          ...List.generate(12, (i) => _createShoreConstruction(i)),
          // Built areas (5-10 expected) - NEW
          ...List.generate(6, (i) => _createBuiltArea(i)),
        ];
        
        final converted = S57ToMaritimeAdapter.convertFeatures(elliottBayMix);
        
        // Count feature types
        final typeCounts = <MaritimeFeatureType, int>{};
        for (final feature in converted) {
          typeCounts[feature.type] = (typeCounts[feature.type] ?? 0) + 1;
        }
        
        // Verify all expected Elliott Bay types are represented
        expect(typeCounts[MaritimeFeatureType.depthArea], equals(15));
        expect(typeCounts[MaritimeFeatureType.soundings], equals(50));
        expect(typeCounts[MaritimeFeatureType.buoy], equals(8));
        expect(typeCounts[MaritimeFeatureType.lighthouse], equals(5));
        expect(typeCounts[MaritimeFeatureType.shoreline], equals(10));
        expect(typeCounts[MaritimeFeatureType.landArea], equals(7));
        expect(typeCounts[MaritimeFeatureType.shoreConstruction], equals(12)); // NEW
        expect(typeCounts[MaritimeFeatureType.builtArea], equals(6)); // NEW
        
        // Verify high conversion rate
        expect(converted.length, equals(elliottBayMix.length));
      });
      
      test('handles large-scale Elliott Bay performance requirements', () {
        // Create realistic Elliott Bay dataset size
        final largeDataset = [
          ...List.generate(20, (i) => _createDepthArea(i)),
          ...List.generate(150, (i) => _createSounding(i)), // Realistic sounding count
          ...List.generate(12, (i) => _createBuoy(i)),
          ...List.generate(6, (i) => _createLight(i)),
          ...List.generate(30, (i) => _createCoastline(i)),
          ...List.generate(10, (i) => _createLandArea(i)),
          ...List.generate(20, (i) => _createShoreConstruction(i)),
          ...List.generate(8, (i) => _createBuiltArea(i)),
        ];
        
        final stopwatch = Stopwatch()..start();
        final converted = S57ToMaritimeAdapter.convertFeatures(largeDataset);
        stopwatch.stop();
        
        // Performance requirement: complete within 2 seconds for Elliott Bay
        expect(stopwatch.elapsedMilliseconds, lessThan(2000),
               reason: 'Large Elliott Bay dataset (${largeDataset.length} features) should convert in <2s. '
                      'Took ${stopwatch.elapsedMilliseconds}ms');
        
        // Verify conversion completeness
        expect(converted.length, equals(largeDataset.length),
               reason: 'Should convert all features without loss');
      });
    });
  });
}

/// Helper functions to create realistic Elliott Bay S-57 features

List<S57Feature> _createElliottBayFeatureDataset() {
  return [
    // Sample depth areas
    _createDepthArea(1),
    _createDepthArea(2),
    // Sample soundings
    _createSounding(1),
    _createSounding(2),
    // Sample buoys
    _createBuoy(1),
    // Sample lighthouse
    _createLight(1),
    // Sample coastline
    _createCoastline(1),
    // Sample land area
    _createLandArea(1),
    // NEW: Sample shore construction
    _createShoreConstruction(1),
    // NEW: Sample built area
    _createBuiltArea(1),
  ];
}

S57Feature _createDepthArea(int id) {
  return S57Feature(
    recordId: id,
    featureType: S57FeatureType.depthArea,
    geometryType: S57GeometryType.area,
    coordinates: [
      S57Coordinate(latitude: 47.60 + id * 0.001, longitude: -122.33 + id * 0.001),
      S57Coordinate(latitude: 47.61 + id * 0.001, longitude: -122.33 + id * 0.001),
      S57Coordinate(latitude: 47.61 + id * 0.001, longitude: -122.32 + id * 0.001),
      S57Coordinate(latitude: 47.60 + id * 0.001, longitude: -122.32 + id * 0.001),
    ],
    attributes: {
      'DRVAL1': 5.0 + id,
      'DRVAL2': 15.0 + id,
      'QUASOU': 6,
    },
  );
}

S57Feature _createSounding(int id) {
  return S57Feature(
    recordId: id + 100,
    featureType: S57FeatureType.sounding,
    geometryType: S57GeometryType.point,
    coordinates: [S57Coordinate(latitude: 47.605 + id * 0.0001, longitude: -122.325 + id * 0.0001)],
    attributes: {'VALSOU': 8.0 + (id % 20)},
  );
}

S57Feature _createBuoy(int id) {
  final colors = ['red', 'green', 'yellow'];
  final shapes = ['cylindrical', 'conical', 'spherical'];
  return S57Feature(
    recordId: id + 200,
    featureType: S57FeatureType.buoyLateral,
    geometryType: S57GeometryType.point,
    coordinates: [S57Coordinate(latitude: 47.61 + id * 0.001, longitude: -122.32 + id * 0.001)],
    attributes: {
      'BOYSHP': shapes[id % shapes.length],
      'COLOUR': colors[id % colors.length],
      'CATBOY': 'lateral',
    },
  );
}

S57Feature _createLight(int id) {
  return S57Feature(
    recordId: id + 300,
    featureType: S57FeatureType.lighthouse,
    geometryType: S57GeometryType.point,
    coordinates: [S57Coordinate(latitude: 47.608 + id * 0.001, longitude: -122.330 + id * 0.001)],
    attributes: {
      'LITCHR': 'F',
      'VALNMR': 15.0 + id,
      'COLOUR': 'white',
    },
  );
}

S57Feature _createCoastline(int id) {
  return S57Feature(
    recordId: id + 400,
    featureType: S57FeatureType.coastline,
    geometryType: S57GeometryType.line,
    coordinates: [
      S57Coordinate(latitude: 47.60 + id * 0.001, longitude: -122.35 + id * 0.001),
      S57Coordinate(latitude: 47.605 + id * 0.001, longitude: -122.345 + id * 0.001),
    ],
    attributes: {'CATCOA': 'natural'},
  );
}

S57Feature _createLandArea(int id) {
  return S57Feature(
    recordId: id + 500,
    featureType: S57FeatureType.landArea,
    geometryType: S57GeometryType.area,
    coordinates: [
      S57Coordinate(latitude: 47.61 + id * 0.001, longitude: -122.35 + id * 0.001),
      S57Coordinate(latitude: 47.615 + id * 0.001, longitude: -122.35 + id * 0.001),
      S57Coordinate(latitude: 47.615 + id * 0.001, longitude: -122.345 + id * 0.001),
      S57Coordinate(latitude: 47.61 + id * 0.001, longitude: -122.345 + id * 0.001),
    ],
    attributes: {'CATLND': 'natural'},
  );
}

S57Feature _createShoreConstruction(int id) {
  final categories = ['pier', 'dock', 'wharf', 'breakwater'];
  final materials = ['concrete', 'steel', 'wood', 'stone'];
  return S57Feature(
    recordId: id + 600,
    featureType: S57FeatureType.shoreConstruction,
    geometryType: S57GeometryType.line,
    coordinates: [
      S57Coordinate(latitude: 47.605 + id * 0.0005, longitude: -122.325 + id * 0.0005),
      S57Coordinate(latitude: 47.606 + id * 0.0005, longitude: -122.324 + id * 0.0005),
    ],
    attributes: {
      'CATSLC': categories[id % categories.length],
      'CONRAD': materials[id % materials.length],
    },
  );
}

S57Feature _createBuiltArea(int id) {
  final categories = ['industrial', 'residential', 'port', 'commercial'];
  final functions = ['port facilities', 'warehouse', 'terminal', 'office'];
  return S57Feature(
    recordId: id + 700,
    featureType: S57FeatureType.builtArea,
    geometryType: S57GeometryType.area,
    coordinates: [
      S57Coordinate(latitude: 47.608 + id * 0.001, longitude: -122.328 + id * 0.001),
      S57Coordinate(latitude: 47.609 + id * 0.001, longitude: -122.328 + id * 0.001),
      S57Coordinate(latitude: 47.609 + id * 0.001, longitude: -122.327 + id * 0.001),
      S57Coordinate(latitude: 47.608 + id * 0.001, longitude: -122.327 + id * 0.001),
    ],
    attributes: {
      'CATBUA': categories[id % categories.length],
      'FUNCTN': functions[id % functions.length],
    },
  );
}