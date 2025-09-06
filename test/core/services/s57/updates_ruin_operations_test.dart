/// Test for S-57 RUIN Operations (Insert/Delete/Modify)
///
/// Tests RUIN operation handlers without relying on binary file parsing

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_update_processor.dart';
import 'package:navtool/core/services/s57/s57_update_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';

void main() {
  group('S57 RUIN Operations', () {
    late S57UpdateProcessor processor;

    setUp(() {
      processor = S57UpdateProcessor();
    });

    test('should handle INSERT operation', () {
      // Setup: Empty feature store
      expect(processor.featureStore.count, equals(0));

      // Create feature to insert
      final feature = S57Feature(
        recordId: 100,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
        attributes: {'COLOUR': 2, 'CATBOY': 1},
        label: 'Red Buoy',
      );

      final insertRecord = RuinRecord(
        foid: 'FOID_100',
        operation: RuinOperation.insert,
        feature: feature,
        rawData: {'operation': 'insert'},
      );

      // Apply insert operation
      processor.applyRuinRecord(insertRecord, 1);

      // Verify insertion
      expect(processor.featureStore.count, equals(1));
      expect(processor.featureStore.contains('FOID_100'), isTrue);
      expect(processor.summary.inserted, equals(1));

      final insertedFeature = processor.featureStore.get('FOID_100');
      expect(insertedFeature, isNotNull);
      expect(insertedFeature!.version, equals(1));
      expect(insertedFeature.feature.featureType, equals(S57FeatureType.buoy));
    });

    test('should handle DELETE operation', () {
      // Setup: Add a feature to delete
      final feature = S57Feature(
        recordId: 200,
        featureType: S57FeatureType.lighthouse,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
        attributes: {'HEIGHT': 25.0},
        label: 'Test Light',
      );

      final versionedFeature = FeatureVersioned(feature: feature, version: 0);
      processor.featureStore.put('FOID_200', versionedFeature);

      expect(processor.featureStore.count, equals(1));

      // Create delete record
      final deleteRecord = RuinRecord(
        foid: 'FOID_200',
        operation: RuinOperation.delete,
        rawData: {'operation': 'delete'},
      );

      // Apply delete operation
      processor.applyRuinRecord(deleteRecord, 1);

      // Verify deletion
      expect(processor.featureStore.count, equals(0));
      expect(processor.featureStore.contains('FOID_200'), isFalse);
      expect(processor.summary.deleted, equals(1));
    });

    test('should handle MODIFY operation', () {
      // Setup: Add a feature to modify
      final originalFeature = S57Feature(
        recordId: 300,
        featureType: S57FeatureType.depthArea,
        geometryType: S57GeometryType.area,
        coordinates: [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
          const S57Coordinate(latitude: 47.61, longitude: -122.31),
        ],
        attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0, 'QUASOU': 6},
        label: 'Depth Area 10-20m',
      );

      final versionedFeature = FeatureVersioned(
        feature: originalFeature,
        version: 0,
      );
      processor.featureStore.put('FOID_300', versionedFeature);

      // Create modification (change DRVAL1 and add new attribute)
      final modifiedFeature = S57Feature(
        recordId: 300,
        featureType: S57FeatureType.depthArea,
        geometryType: S57GeometryType.area,
        coordinates: [
          const S57Coordinate(latitude: 47.62, longitude: -122.32),
          const S57Coordinate(latitude: 47.63, longitude: -122.33),
        ],
        attributes: {
          'DRVAL1': 5.0,
          'MODIFIED': true,
        }, // Changed DRVAL1, added MODIFIED
        label: 'Modified Depth Area',
      );

      final modifyRecord = RuinRecord(
        foid: 'FOID_300',
        operation: RuinOperation.modify,
        feature: modifiedFeature,
        rawData: {'operation': 'modify'},
      );

      // Apply modify operation
      processor.applyRuinRecord(modifyRecord, 2);

      // Verify modification
      expect(processor.featureStore.count, equals(1));
      expect(processor.summary.modified, equals(1));

      final modifiedVersioned = processor.featureStore.get('FOID_300');
      expect(modifiedVersioned, isNotNull);
      expect(modifiedVersioned!.version, equals(2));

      // Check merged attributes
      final attributes = modifiedVersioned.feature.attributes;
      expect(attributes['DRVAL1'], equals(5.0)); // Modified
      expect(attributes['DRVAL2'], equals(20.0)); // Preserved from original
      expect(attributes['QUASOU'], equals(6)); // Preserved from original
      expect(attributes['MODIFIED'], equals(true)); // New attribute

      // Check updated coordinates
      expect(modifiedVersioned.feature.coordinates.length, equals(2));
      expect(modifiedVersioned.feature.coordinates[0].latitude, equals(47.62));
    });

    test('should warn on INSERT_EXISTS', () {
      // Setup: Add a feature
      final feature = S57Feature(
        recordId: 400,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.0, longitude: -122.0)],
        attributes: {'VALSOU': 15.5},
        label: 'Sounding',
      );

      final versionedFeature = FeatureVersioned(feature: feature, version: 0);
      processor.featureStore.put('FOID_400', versionedFeature);

      // Try to insert the same FOID again
      final duplicateInsert = RuinRecord(
        foid: 'FOID_400',
        operation: RuinOperation.insert,
        feature: feature,
        rawData: {'operation': 'duplicate_insert'},
      );

      processor.applyRuinRecord(duplicateInsert, 1);

      // Verify warning and no change
      expect(processor.featureStore.count, equals(1)); // Still only one feature
      expect(processor.summary.inserted, equals(0)); // No new insertion
      expect(
        processor.summary.warnings.any((w) => w.contains('INSERT_EXISTS')),
        isTrue,
      );
    });

    test('should warn on DELETE_MISSING', () {
      // Try to delete non-existent feature
      final deleteRecord = RuinRecord(
        foid: 'NONEXISTENT',
        operation: RuinOperation.delete,
        rawData: {'operation': 'delete_missing'},
      );

      processor.applyRuinRecord(deleteRecord, 1);

      // Verify warning
      expect(processor.summary.deleted, equals(0));
      expect(
        processor.summary.warnings.any((w) => w.contains('DELETE_MISSING')),
        isTrue,
      );
    });

    test('should warn on MODIFY_MISSING', () {
      // Try to modify non-existent feature
      final feature = S57Feature(
        recordId: 999,
        featureType: S57FeatureType.unknown,
        geometryType: S57GeometryType.point,
        coordinates: [],
        attributes: {},
      );

      final modifyRecord = RuinRecord(
        foid: 'NONEXISTENT',
        operation: RuinOperation.modify,
        feature: feature,
        rawData: {'operation': 'modify_missing'},
      );

      processor.applyRuinRecord(modifyRecord, 1);

      // Verify warning
      expect(processor.summary.modified, equals(0));
      expect(
        processor.summary.warnings.any((w) => w.contains('MODIFY_MISSING')),
        isTrue,
      );
    });

    test('should test RuinOperation enum', () {
      // Test enum from string codes
      expect(RuinOperation.fromCode('I'), equals(RuinOperation.insert));
      expect(RuinOperation.fromCode('D'), equals(RuinOperation.delete));
      expect(RuinOperation.fromCode('M'), equals(RuinOperation.modify));
      expect(
        RuinOperation.fromCode('i'),
        equals(RuinOperation.insert),
      ); // Case insensitive

      // Test enum from integer codes
      expect(RuinOperation.fromInt(1), equals(RuinOperation.insert));
      expect(RuinOperation.fromInt(2), equals(RuinOperation.delete));
      expect(RuinOperation.fromInt(3), equals(RuinOperation.modify));

      // Test invalid codes
      expect(() => RuinOperation.fromCode('X'), throwsArgumentError);
      expect(() => RuinOperation.fromInt(99), throwsArgumentError);

      // Test string representation
      expect(RuinOperation.insert.code, equals('I'));
      expect(RuinOperation.delete.code, equals('D'));
      expect(RuinOperation.modify.code, equals('M'));
    });

    test('should test FeatureStore operations', () {
      final store = FeatureStore();

      // Test empty store
      expect(store.count, equals(0));
      expect(store.contains('test'), isFalse);
      expect(store.get('test'), isNull);
      expect(store.allFeatures, isEmpty);
      expect(store.allFoids, isEmpty);

      // Add feature
      final feature = S57Feature(
        recordId: 1,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [],
        attributes: {},
      );
      final versioned = FeatureVersioned(feature: feature, version: 1);

      store.put('test1', versioned);
      expect(store.count, equals(1));
      expect(store.contains('test1'), isTrue);
      expect(store.get('test1'), equals(versioned));

      // Test insert (should succeed for new FOID)
      final feature2 = S57Feature(
        recordId: 2,
        featureType: S57FeatureType.lighthouse,
        geometryType: S57GeometryType.point,
        coordinates: [],
        attributes: {},
      );
      final versioned2 = FeatureVersioned(feature: feature2, version: 1);

      expect(store.insert('test2', versioned2), isTrue);
      expect(store.count, equals(2));

      // Test insert failure (FOID already exists)
      expect(store.insert('test1', versioned2), isFalse);
      expect(store.count, equals(2)); // No change

      // Test remove
      expect(store.remove('test1'), isTrue);
      expect(store.count, equals(1));
      expect(store.remove('nonexistent'), isFalse);

      // Test clear
      store.clear();
      expect(store.count, equals(0));
    });
  });
}
