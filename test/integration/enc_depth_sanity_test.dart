import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/spatial_index_interface.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';
import '../utils/enc_test_utilities.dart';

@Tags(['integration'])
void main() {
  group('ENC Depth Sanity Tests', () {
    testWidgets('should validate depth range checking logic', (tester) async {
      // Create synthetic test data to demonstrate depth validation
      final testFeatures = [
        // Valid depth area
        S57Feature(
          recordId: 1,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.5, longitude: -122.3),
            S57Coordinate(latitude: 47.5, longitude: -122.2),
            S57Coordinate(latitude: 47.4, longitude: -122.2),
            S57Coordinate(latitude: 47.4, longitude: -122.3),
          ],
          attributes: {
            'DRVAL1': 5.0,  // Minimum depth: 5m
            'DRVAL2': 15.0, // Maximum depth: 15m
          },
        ),
        
        // Depth area with out-of-range values
        S57Feature(
          recordId: 2,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.6, longitude: -122.3),
            S57Coordinate(latitude: 47.6, longitude: -122.2),
          ],
          attributes: {
            'DRVAL1': -25.0, // Out of range (below -20m)
            'DRVAL2': 150.0, // Out of range (above 120m)
          },
        ),
        
        // Valid sounding
        S57Feature(
          recordId: 3,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [
            S57Coordinate(latitude: 47.5, longitude: -122.25),
          ],
          attributes: {
            'VALSOU': 12.5, // Valid depth: 12.5m
          },
        ),
        
        // Sounding with out-of-range value
        S57Feature(
          recordId: 4,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [
            S57Coordinate(latitude: 47.55, longitude: -122.25),
          ],
          attributes: {
            'VALSOU': 200.0, // Out of range (above 120m)
          },
        ),
        
        // Non-depth feature (should be ignored)
        S57Feature(
          recordId: 5,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [
            S57Coordinate(latitude: 47.5, longitude: -122.3),
          ],
          attributes: {
            'HEIGHT': 25.0,
          },
        ),
      ];
      
      // Create test parsed data
      final testParsedData = S57ParsedData(
        metadata: S57ChartMetadata(
          producer: 'TEST',
          version: '1.0',
          title: 'Test Chart',
        ),
        features: testFeatures,
        bounds: S57Bounds(north: 47.6, south: 47.4, east: -122.2, west: -122.3),
        spatialIndex: S57SpatialIndex()..addFeatures(testFeatures),
      );
      
      print('Testing depth validation with synthetic data:');
      print('Test features:');
      for (final feature in testFeatures) {
        if (feature.featureType == S57FeatureType.depthArea) {
          print('  DEPARE ${feature.recordId}: DRVAL1=${feature.attributes['DRVAL1']}, DRVAL2=${feature.attributes['DRVAL2']}');
        } else if (feature.featureType == S57FeatureType.sounding) {
          print('  SOUNDG ${feature.recordId}: VALSOU=${feature.attributes['VALSOU']}');
        }
      }
      
      // Validate depth ranges
      final depthValidation = EncTestUtilities.validateDepthRanges(testParsedData);
      
      print('Depth validation results:');
      print('  Total depth features: ${depthValidation.totalDepthFeatures}');
      print('  Out of range count: ${depthValidation.outOfRangeCount}');
      print('  Out of range percentage: ${depthValidation.outOfRangePercent.toStringAsFixed(1)}%');
      print('  Valid range: ${depthValidation.minDepth}m to ${depthValidation.maxDepth}m');
      
      if (depthValidation.warnings.isNotEmpty) {
        print('  Warnings:');
        for (final warning in depthValidation.warnings) {
          print('    $warning');
        }
      }
      
      // Validate results
    expect(depthValidation.totalDepthFeatures, equals(4), 
      reason: 'Should find 2 DEPARE + 2 SOUNDG features');
    expect(depthValidation.outOfRangeCount, equals(3), 
      reason: 'Should find 3 out-of-range values (DRVAL1=-25, DRVAL2=150, VALSOU=200)');
    expect(depthValidation.warnings.length, equals(3), 
      reason: 'Should generate 3 warnings for out-of-range values');
    expect(depthValidation.outOfRangePercent, closeTo(75.0, 1.0), 
      reason: '3 of 4 depth features are out of range (75%)');
    });
    
    testWidgets('should handle edge cases in depth validation', (tester) async {
      // Test edge cases: exactly at boundaries, missing values, etc.
      final edgeCaseFeatures = [
        // Exactly at minimum boundary
        S57Feature(
          recordId: 1,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.3)],
          attributes: {
            'DRVAL1': -20.0, // Exactly at minimum
            'DRVAL2': 120.0, // Exactly at maximum
          },
        ),
        
        // Missing depth values
        S57Feature(
          recordId: 2,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.3)],
          attributes: {
            // No DRVAL1 or DRVAL2
          },
        ),
        
        // Null values
        S57Feature(
          recordId: 3,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.3)],
          attributes: {
            'VALSOU': null,
          },
        ),
        
        // Non-numeric values
        S57Feature(
          recordId: 4,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.3)],
          attributes: {
            'VALSOU': 'invalid',
          },
        ),
      ];
      
      final testParsedData = S57ParsedData(
        metadata: S57ChartMetadata(producer: 'TEST', version: '1.0'),
        features: edgeCaseFeatures,
        bounds: S57Bounds(north: 47.6, south: 47.4, east: -122.2, west: -122.3),
        spatialIndex: S57SpatialIndex()..addFeatures(edgeCaseFeatures),
      );
      
      print('Testing edge cases in depth validation:');
      
      final validation = EncTestUtilities.validateDepthRanges(testParsedData);
      
      print('Edge case validation results:');
      print('  Total depth features: ${validation.totalDepthFeatures}');
      print('  Out of range count: ${validation.outOfRangeCount}');
      print('  Warnings: ${validation.warnings.length}');
      
      // Boundary values should be valid (within range)
      expect(validation.outOfRangeCount, equals(0), 
          reason: 'Boundary values (-20, 120) should be valid');
      
      // Should handle missing/invalid values gracefully without crashing
    expect(validation.totalDepthFeatures, equals(4), 
      reason: 'Should count all depth-related features (2 DEPARE + 2 SOUNDG)');
    });
    
    testWidgets('should calculate depth distribution statistics', (tester) async {
      // Create a variety of depth values for statistical analysis
      final depthTestFeatures = <S57Feature>[];
      
      // Generate various depth areas with different ranges
      final depthRanges = [
        [0.0, 5.0],   // Shallow water
        [5.0, 10.0],  // Medium shallow
        [10.0, 20.0], // Medium depth
        [20.0, 50.0], // Deeper water
        [50.0, 100.0], // Deep water
      ];
      
      for (int i = 0; i < depthRanges.length; i++) {
        depthTestFeatures.add(S57Feature(
          recordId: i + 1,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.3 + i * 0.01)],
          attributes: {
            'DRVAL1': depthRanges[i][0],
            'DRVAL2': depthRanges[i][1],
          },
        ));
      }
      
      // Add some soundings
      final soundingDepths = [2.5, 7.5, 15.0, 35.0, 75.0];
      for (int i = 0; i < soundingDepths.length; i++) {
        depthTestFeatures.add(S57Feature(
          recordId: i + 10,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.5, longitude: -122.25 + i * 0.01)],
          attributes: {
            'VALSOU': soundingDepths[i],
          },
        ));
      }
      
      final testParsedData = S57ParsedData(
        metadata: S57ChartMetadata(producer: 'TEST', version: '1.0'),
        features: depthTestFeatures,
        bounds: S57Bounds(north: 47.6, south: 47.4, east: -122.2, west: -122.3),
        spatialIndex: S57SpatialIndex()..addFeatures(depthTestFeatures),
      );
      
      print('Testing depth distribution analysis:');
      print('Depth areas:');
      for (int i = 0; i < depthRanges.length; i++) {
        print('  ${depthRanges[i][0]}m - ${depthRanges[i][1]}m');
      }
      print('Soundings:');
      for (final depth in soundingDepths) {
        print('  ${depth}m');
      }
      
      final validation = EncTestUtilities.validateDepthRanges(testParsedData);
      
      print('Distribution analysis results:');
      print('  Total depth features: ${validation.totalDepthFeatures}');
      print('  Out of range: ${validation.outOfRangeCount}');
      print('  Valid percentage: ${(100.0 - validation.outOfRangePercent).toStringAsFixed(1)}%');
      
      // All our test values should be in the valid range
      expect(validation.outOfRangeCount, equals(0), 
          reason: 'All test depth values should be within valid range');
      expect(validation.totalDepthFeatures, equals(10), 
          reason: 'Should find 5 DEPARE + 5 SOUNDG features');
    });
    
    testWidgets('should demonstrate depth sanity checking for different chart types', (tester) async {
      print('Depth sanity checking guidelines for different chart types:');
      print('');
      
      print('Harbor Charts (Usage Band 5):');
      print('  - Expected depth range: 0-30 meters typically');
      print('  - High density of soundings and depth areas');
      print('  - Critical for navigation safety');
      print('  - Should have very few out-of-range values');
      print('');
      
      print('Coastal Charts (Usage Band 3):');
      print('  - Expected depth range: 0-100+ meters');
      print('  - Medium density of depth features');
      print('  - May have more varied depth ranges');
      print('  - Some out-of-range values acceptable for deep areas');
      print('');
      
      print('Validation Range (Conservative):');
      print('  - Minimum: -20m (20m above sea level)');
      print('  - Maximum: 120m (120m below sea level)');
      print('  - Purpose: Catch obvious data errors');
      print('  - Not meant to validate all possible depths');
      print('');
      
      print('Warning Thresholds:');
      print('  - < 5% out-of-range: Excellent data quality');
      print('  - 5-10% out-of-range: Good data quality');
      print('  - 10-20% out-of-range: Acceptable with review');
      print('  - > 20% out-of-range: Requires investigation');
      
      // This test documents the expected behavior
      expect(true, isTrue);
    });
  });
}

/// Mock spatial index for testing purposes
class MockSpatialIndex implements SpatialIndex {
  final List<S57Feature> _features;
  
  MockSpatialIndex(this._features);
  
  @override
  List<S57Feature> getAllFeatures() => _features;
  
  @override
  int get featureCount => _features.length;
  
  @override
  Set<S57FeatureType> get presentFeatureTypes => 
      _features.map((f) => f.featureType).toSet();
  
  // Implement other required methods as no-ops for testing
  @override
  void addFeature(S57Feature feature) {}
  
  @override
  void addFeatures(List<S57Feature> features) {}
  
  @override
  void clear() {}
  
  @override
  List<S57Feature> queryBounds(S57Bounds bounds) => _features;
  
  @override
  List<S57Feature> queryPoint(double lat, double lon, {double radiusDegrees = 0.01}) => _features;
  
  @override
  List<S57Feature> queryTypes(Set<S57FeatureType> types, {S57Bounds? bounds}) {
    final filtered = _features.where((f) => types.contains(f.featureType));
    if (bounds == null) return filtered.toList();
    return filtered.where((f) => f.coordinates.any((c) =>
      c.latitude >= bounds.south && c.latitude <= bounds.north &&
      c.longitude >= bounds.west && c.longitude <= bounds.east)).toList();
  }
  
  @override
  List<S57Feature> queryNavigationAids() => 
      _features.where((f) => [
        S57FeatureType.lighthouse,
        S57FeatureType.beacon,
        S57FeatureType.buoy,
      ].contains(f.featureType)).toList();
  
  @override
  List<S57Feature> queryDepthFeatures() => 
      _features.where((f) => [
        S57FeatureType.depthArea,
        S57FeatureType.sounding,
        S57FeatureType.depthContour,
      ].contains(f.featureType)).toList();

  @override
  List<S57Feature> queryByType(S57FeatureType featureType) =>
      _features.where((f) => f.featureType == featureType).toList();
  
  @override
  S57Bounds? calculateBounds() => S57Bounds(north: 48, south: 47, east: -122, west: -123);
}