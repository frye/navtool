/// Test for S-57 Modify Merge Strategy
///
/// Tests partial attribute modification preserving untouched attributes

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_update_processor.dart';
import 'package:navtool/core/services/s57/s57_update_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 Update Modify Merge', () {
    late S57UpdateProcessor processor;

    setUp(() {
      processor = S57UpdateProcessor();
    });

    test('should merge attributes preserving unspecified ones', () {
      // Setup: Create a feature with multiple attributes
      final originalFeature = S57Feature(
        recordId: 100,
        featureType: S57FeatureType.depthArea,
        geometryType: S57GeometryType.area,
        coordinates: [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
          const S57Coordinate(latitude: 47.61, longitude: -122.31),
          const S57Coordinate(latitude: 47.62, longitude: -122.32),
        ],
        attributes: {
          'DRVAL1': 10.0, // Minimum depth
          'DRVAL2': 20.0, // Maximum depth
          'QUASOU': 6, // Quality of sounding
          'OBJNAM': 'Test Depth Area',
          'TECSOU': 3, // Source technique
          'VALDCO': 15.0, // Depth contour value
        },
        label: 'Original Depth Area',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('DEPTH_100', versionedFeature);

      // Create partial modification - only change DRVAL1 and add new attribute
      final modificationFeature = S57Feature(
        recordId: 100,
        featureType: S57FeatureType.depthArea,
        geometryType: S57GeometryType.area,
        coordinates: [], // No coordinate changes
        attributes: {
          'DRVAL1': 5.0, // Modified: changed from 10.0 to 5.0
          'NEW_ATTR': 'added', // Added: new attribute
          // Note: DRVAL2, QUASOU, OBJNAM, TECSOU, VALDCO are NOT specified
        },
        label: 'Modified Depth Area',
      );

      final modifyRecord = RuinRecord(
        foid: 'DEPTH_100',
        operation: RuinOperation.modify,
        feature: modificationFeature,
        rawData: {'operation': 'partial_modify'},
      );

      // Apply modification
      processor.applyRuinRecord(modifyRecord, 1);

      // Verify modification
      expect(processor.summary.modified, equals(1));
      final modifiedVersioned = processor.featureStore.get('DEPTH_100');
      expect(modifiedVersioned, isNotNull);
      expect(modifiedVersioned!.version, equals(1));

      final mergedAttributes = modifiedVersioned.feature.attributes;

      // Verify modified attribute
      expect(
        mergedAttributes['DRVAL1'],
        equals(5.0),
        reason: 'DRVAL1 should be updated to new value',
      );

      // Verify preserved attributes (not mentioned in modification)
      expect(
        mergedAttributes['DRVAL2'],
        equals(20.0),
        reason: 'DRVAL2 should be preserved from original',
      );
      expect(
        mergedAttributes['QUASOU'],
        equals(6),
        reason: 'QUASOU should be preserved from original',
      );
      expect(
        mergedAttributes['OBJNAM'],
        equals('Test Depth Area'),
        reason: 'OBJNAM should be preserved from original',
      );
      expect(
        mergedAttributes['TECSOU'],
        equals(3),
        reason: 'TECSOU should be preserved from original',
      );
      expect(
        mergedAttributes['VALDCO'],
        equals(15.0),
        reason: 'VALDCO should be preserved from original',
      );

      // Verify added attribute
      expect(
        mergedAttributes['NEW_ATTR'],
        equals('added'),
        reason: 'NEW_ATTR should be added',
      );

      // Verify total attribute count
      // Original: DRVAL1, DRVAL2, QUASOU, OBJNAM, TECSOU, VALDCO (6)
      // Modification: DRVAL1 (replaces), NEW_ATTR (adds)
      // Expected: 6 attributes total
      print('Merged attributes: $mergedAttributes');
      expect(
        mergedAttributes.length,
        equals(7),
        reason:
            'Actually expecting 7 attributes: 5 preserved + 1 modified + 1 new',
      );
    });

    test('should preserve geometry when no new geometry provided', () {
      // Setup feature with specific geometry
      final originalFeature = S57Feature(
        recordId: 200,
        featureType: S57FeatureType.coastline,
        geometryType: S57GeometryType.line,
        coordinates: [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
          const S57Coordinate(latitude: 47.61, longitude: -122.31),
          const S57Coordinate(latitude: 47.62, longitude: -122.32),
        ],
        attributes: {'CATCOA': 6, 'WATLEV': 3},
        label: 'Original Coastline',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('COAST_200', versionedFeature);

      // Modify only attributes, no geometry change
      final modificationFeature = S57Feature(
        recordId: 200,
        featureType: S57FeatureType.coastline,
        geometryType: S57GeometryType.line,
        coordinates: [], // Empty coordinates - should preserve original
        attributes: {'CATCOA': 7}, // Only change category
        label: 'Modified Coastline',
      );

      final modifyRecord = RuinRecord(
        foid: 'COAST_200',
        operation: RuinOperation.modify,
        feature: modificationFeature,
        rawData: {'operation': 'attribute_only_modify'},
      );

      processor.applyRuinRecord(modifyRecord, 1);

      final modifiedVersioned = processor.featureStore.get('COAST_200');
      expect(modifiedVersioned, isNotNull);

      // Verify coordinates are preserved
      expect(
        modifiedVersioned!.feature.coordinates.length,
        equals(3),
        reason: 'Original coordinate count should be preserved',
      );
      expect(modifiedVersioned.feature.coordinates[0].latitude, equals(47.6));
      expect(modifiedVersioned.feature.coordinates[1].latitude, equals(47.61));
      expect(modifiedVersioned.feature.coordinates[2].latitude, equals(47.62));

      // Verify attributes are merged
      expect(
        modifiedVersioned.feature.attributes['CATCOA'],
        equals(7),
        reason: 'CATCOA should be updated',
      );
      expect(
        modifiedVersioned.feature.attributes['WATLEV'],
        equals(3),
        reason: 'WATLEV should be preserved',
      );
    });

    test('should update geometry when new geometry provided', () {
      // Setup feature
      final originalFeature = S57Feature(
        recordId: 300,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
        attributes: {'VALSOU': 15.5, 'QUASOU': 6},
        label: 'Original Sounding',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('SOUND_300', versionedFeature);

      // Modify with new geometry and attributes
      final modificationFeature = S57Feature(
        recordId: 300,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [
          const S57Coordinate(latitude: 47.65, longitude: -122.35),
        ], // New position
        attributes: {'VALSOU': 12.3}, // New depth value
        label: 'Updated Sounding',
      );

      final modifyRecord = RuinRecord(
        foid: 'SOUND_300',
        operation: RuinOperation.modify,
        feature: modificationFeature,
        rawData: {'operation': 'geometry_and_attribute_modify'},
      );

      processor.applyRuinRecord(modifyRecord, 1);

      final modifiedVersioned = processor.featureStore.get('SOUND_300');
      expect(modifiedVersioned, isNotNull);

      // Verify new geometry
      expect(modifiedVersioned!.feature.coordinates.length, equals(1));
      expect(
        modifiedVersioned.feature.coordinates[0].latitude,
        equals(47.65),
        reason: 'Latitude should be updated to new value',
      );
      expect(
        modifiedVersioned.feature.coordinates[0].longitude,
        equals(-122.35),
        reason: 'Longitude should be updated to new value',
      );

      // Verify merged attributes
      expect(
        modifiedVersioned.feature.attributes['VALSOU'],
        equals(12.3),
        reason: 'VALSOU should be updated',
      );
      expect(
        modifiedVersioned.feature.attributes['QUASOU'],
        equals(6),
        reason: 'QUASOU should be preserved',
      );
    });

    test('should handle null/missing feature data gracefully', () {
      // Setup feature to modify
      final originalFeature = S57Feature(
        recordId: 400,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.0, longitude: -122.0)],
        attributes: {'COLOUR': 2},
        label: 'Test Buoy',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('BUOY_400', versionedFeature);

      // Create modify record with null feature
      final modifyRecord = RuinRecord(
        foid: 'BUOY_400',
        operation: RuinOperation.modify,
        feature: null, // No feature data provided
        rawData: {'operation': 'null_feature_modify'},
      );

      processor.applyRuinRecord(modifyRecord, 1);

      // Should generate warning and not modify anything
      expect(
        processor.summary.modified,
        equals(0),
        reason: 'Should not count as modified when no feature data',
      );
      expect(
        processor.summary.warnings.any(
          (w) => w.contains('MODIFY_MISSING_FEATURE'),
        ),
        isTrue,
        reason: 'Should warn about missing feature data',
      );

      // Original feature should be unchanged
      final unchangedVersioned = processor.featureStore.get('BUOY_400');
      expect(unchangedVersioned, isNotNull);
      expect(
        unchangedVersioned!.version,
        equals(0),
        reason: 'Version should remain unchanged',
      );
      expect(
        unchangedVersioned.feature.attributes['COLOUR'],
        equals(2),
        reason: 'Attributes should remain unchanged',
      );
    });

    test('should preserve feature type when modification type is unknown', () {
      // Setup feature
      final originalFeature = S57Feature(
        recordId: 500,
        featureType: S57FeatureType.lighthouse,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.68, longitude: -122.32)],
        attributes: {'HEIGHT': 25.0, 'VALNMR': 15.0},
        label: 'West Point Light',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('LIGHT_500', versionedFeature);

      // Modify with unknown feature type
      final modificationFeature = S57Feature(
        recordId: 500,
        featureType: S57FeatureType.unknown, // Unknown type
        geometryType: S57GeometryType.point,
        coordinates: [],
        attributes: {'HEIGHT': 30.0}, // Just change height
      );

      final modifyRecord = RuinRecord(
        foid: 'LIGHT_500',
        operation: RuinOperation.modify,
        feature: modificationFeature,
        rawData: {'operation': 'unknown_type_modify'},
      );

      processor.applyRuinRecord(modifyRecord, 1);

      final modifiedVersioned = processor.featureStore.get('LIGHT_500');
      expect(modifiedVersioned, isNotNull);

      // Should preserve original feature type
      expect(
        modifiedVersioned!.feature.featureType,
        equals(S57FeatureType.lighthouse),
        reason:
            'Should preserve original feature type when modification type is unknown',
      );

      // Should update specified attributes
      expect(
        modifiedVersioned.feature.attributes['HEIGHT'],
        equals(30.0),
        reason: 'HEIGHT should be updated',
      );
      expect(
        modifiedVersioned.feature.attributes['VALNMR'],
        equals(15.0),
        reason: 'VALNMR should be preserved',
      );
    });
  });
}
