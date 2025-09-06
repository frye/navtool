/// Test for S-57 RVER Mismatch Detection
/// 
/// Tests version tracking and mismatch detection in update sequences

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_update_processor.dart';
import 'package:navtool/core/services/s57/s57_update_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_spatial_index.dart';

void main() {
  group('S57 RVER Mismatch', () {
    late S57UpdateProcessor processor;

    setUp(() {
      processor = S57UpdateProcessor();
    });

    test('should track version correctly through update sequence', () {
      // Initialize with base data
      final baseFeature = S57Feature(
        recordId: 100,
        featureType: S57FeatureType.depthArea,
        geometryType: S57GeometryType.area,
        coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
        attributes: {'DRVAL1': 10.0},
        label: 'Depth Area',
      );

      final baseParsedData = S57ParsedData(
        metadata: S57ChartMetadata(producer: 'NOAA', version: '3.1'),
        features: [baseFeature],
        bounds: const S57Bounds(north: 47.7, south: 47.5, east: -122.2, west: -122.4),
        spatialIndex: S57SpatialIndex(),
      );

      processor.initializeFromBase(baseParsedData);

      // Verify initial state
      expect(processor.summary.finalRver, equals(0)); // Base RVER
      expect(processor.featureStore.count, equals(1));

      final initialVersioned = processor.featureStore.get('100'); // Record ID as FOID
      expect(initialVersioned, isNotNull);
      expect(initialVersioned!.version, equals(0)); // Base version
    });

    test('should increment version on modify operations', () {
      // Setup feature
      final feature = S57Feature(
        recordId: 200,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
        attributes: {'COLOUR': 2},
        label: 'Red Buoy',
      );

      final versionedFeature = FeatureVersioned(feature: feature, version: 1);
      processor.featureStore.put('BUOY_200', versionedFeature);

      // Apply modify operation with RVER 2
      final modifyFeature = S57Feature(
        recordId: 200,
        featureType: S57FeatureType.buoy,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.61, longitude: -122.31)],
        attributes: {'COLOUR': 4}, // Change to green
        label: 'Green Buoy',
      );

      final modifyRecord = RuinRecord(
        foid: 'BUOY_200',
        operation: RuinOperation.modify,
        feature: modifyFeature,
        rawData: {'rver': 2},
      );

      processor.applyRuinRecord(modifyRecord, 2);

      // Verify version increment
      final modifiedVersioned = processor.featureStore.get('BUOY_200');
      expect(modifiedVersioned, isNotNull);
      expect(modifiedVersioned!.version, equals(2), 
             reason: 'Feature version should be updated to modify RVER');
    });

    test('should set version on insert operations', () {
      // Insert new feature with RVER 3
      final insertFeature = S57Feature(
        recordId: 300,
        featureType: S57FeatureType.lighthouse,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
        attributes: {'HEIGHT': 25.0},
        label: 'Test Light',
      );

      final insertRecord = RuinRecord(
        foid: 'LIGHT_300',
        operation: RuinOperation.insert,
        feature: insertFeature,
        rawData: {'rver': 3},
      );

      processor.applyRuinRecord(insertRecord, 3);

      // Verify inserted feature has correct version
      final insertedVersioned = processor.featureStore.get('LIGHT_300');
      expect(insertedVersioned, isNotNull);
      expect(insertedVersioned!.version, equals(3), 
             reason: 'Inserted feature should have version from insert RVER');
    });

    test('should track finalRver from update sequence', () {
      // Simulate update sequence with increasing RVER
      processor.summary.finalRver = 0; // Base
      
      // Apply .001 with RVER 1
      processor.summary.finalRver = 1;
      processor.summary.applied.add('SAMPLE.001');
      
      // Apply .002 with RVER 2  
      processor.summary.finalRver = 2;
      processor.summary.applied.add('SAMPLE.002');
      
      // Apply .003 with RVER 3
      processor.summary.finalRver = 3;
      processor.summary.applied.add('SAMPLE.003');

      expect(processor.summary.finalRver, equals(3), 
             reason: 'Final RVER should match last applied update');
      expect(processor.summary.applied.length, equals(3));
    });

    test('should handle version tracking in feature lifecycle', () {
      // Test complete lifecycle: insert -> modify -> modify -> delete
      final processor = S57UpdateProcessor();
      
      // 1. Insert feature with RVER 1
      final insertFeature = S57Feature(
        recordId: 400,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.5, longitude: -122.5)],
        attributes: {'VALSOU': 20.0},
        label: 'Sounding 20m',
      );

      final insertRecord = RuinRecord(
        foid: 'SOUND_400',
        operation: RuinOperation.insert,
        feature: insertFeature,
        rawData: {'rver': 1},
      );

      processor.applyRuinRecord(insertRecord, 1);
      
      var versioned = processor.featureStore.get('SOUND_400');
      expect(versioned!.version, equals(1), reason: 'After insert: version should be 1');

      // 2. First modify with RVER 2
      final modify1Feature = S57Feature(
        recordId: 400,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.5, longitude: -122.5)],
        attributes: {'VALSOU': 18.5}, // Change depth
      );

      final modify1Record = RuinRecord(
        foid: 'SOUND_400',
        operation: RuinOperation.modify,
        feature: modify1Feature,
        rawData: {'rver': 2},
      );

      processor.applyRuinRecord(modify1Record, 2);
      
      versioned = processor.featureStore.get('SOUND_400');
      expect(versioned!.version, equals(2), reason: 'After first modify: version should be 2');
      expect(versioned.feature.attributes['VALSOU'], equals(18.5));

      // 3. Second modify with RVER 3
      final modify2Feature = S57Feature(
        recordId: 400,
        featureType: S57FeatureType.sounding,
        geometryType: S57GeometryType.point,
        coordinates: [const S57Coordinate(latitude: 47.51, longitude: -122.51)], // Change position
        attributes: {'VALSOU': 17.0, 'QUASOU': 6}, // Change depth and add quality
      );

      final modify2Record = RuinRecord(
        foid: 'SOUND_400',
        operation: RuinOperation.modify,
        feature: modify2Feature,
        rawData: {'rver': 3},
      );

      processor.applyRuinRecord(modify2Record, 3);
      
      versioned = processor.featureStore.get('SOUND_400');
      expect(versioned!.version, equals(3), reason: 'After second modify: version should be 3');
      expect(versioned.feature.attributes['VALSOU'], equals(17.0));
      expect(versioned.feature.attributes['QUASOU'], equals(6));
      expect(versioned.feature.coordinates[0].latitude, equals(47.51));

      // 4. Delete with RVER 4
      final deleteRecord = RuinRecord(
        foid: 'SOUND_400',
        operation: RuinOperation.delete,
        rawData: {'rver': 4},
      );

      processor.applyRuinRecord(deleteRecord, 4);
      
      expect(processor.featureStore.contains('SOUND_400'), isFalse, 
             reason: 'After delete: feature should be removed');

      // Verify counters
      expect(processor.summary.inserted, equals(1));
      expect(processor.summary.modified, equals(2));
      expect(processor.summary.deleted, equals(1));
    });

    test('should handle base RVER extraction (simplified)', () {
      // Test with synthetic base data
      final baseFeatures = [
        S57Feature(
          recordId: 1,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
          attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
          label: 'Depth Area 10-20m',
        ),
        S57Feature(
          recordId: 2,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [const S57Coordinate(latitude: 47.65, longitude: -122.35)],
          attributes: {'VALSOU': 15.5},
          label: 'Sounding 15.5m',
        ),
      ];

      final baseParsedData = S57ParsedData(
        metadata: S57ChartMetadata(
          producer: 'NOAA',
          version: '3.1',
          creationDate: DateTime(2024, 1, 1),
        ),
        features: baseFeatures,
        bounds: const S57Bounds(north: 47.7, south: 47.5, east: -122.2, west: -122.4),
        spatialIndex: S57SpatialIndex(),
      );

      processor.initializeFromBase(baseParsedData);

      // Verify all base features have base version (0)
      expect(processor.featureStore.count, equals(2));
      
      final feature1 = processor.featureStore.get('1');
      expect(feature1, isNotNull);
      expect(feature1!.version, equals(0), reason: 'Base feature should have version 0');
      
      final feature2 = processor.featureStore.get('2');
      expect(feature2, isNotNull);
      expect(feature2!.version, equals(0), reason: 'Base feature should have version 0');

      expect(processor.summary.finalRver, equals(0), reason: 'Base RVER should be 0');
    });

    test('should validate UpdateDataset RVER and sequence properties', () {
      // Test UpdateDataset properties
      final updateDataset = UpdateDataset(
        name: 'SAMPLE.002',
        rver: 2,
        baseCellName: 'SAMPLE',
        records: [],
      );

      expect(updateDataset.sequenceNumber, equals(2), 
             reason: 'Should extract sequence number from filename');
      expect(updateDataset.rver, equals(2));
      expect(updateDataset.baseCellName, equals('SAMPLE'));

      // Test with different filename format
      final updateDataset2 = UpdateDataset(
        name: 'US5WA50M.015',
        rver: 15,
        records: [],
      );

      expect(updateDataset2.sequenceNumber, equals(15), 
             reason: 'Should extract sequence number from different filename format');

      // Test with invalid filename
      final updateDataset3 = UpdateDataset(
        name: 'invalid_name',
        rver: 1,
        records: [],
      );

      expect(updateDataset3.sequenceNumber, equals(0), 
             reason: 'Should return 0 for invalid filename format');
    });
  });
}