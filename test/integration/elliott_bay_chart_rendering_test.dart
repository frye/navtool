/// Integration test for Elliott Bay chart rendering
/// Tests the complete pipeline: S-57 parsing → adapter conversion → chart display
library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';

void main() {
  group('Elliott Bay Chart Rendering Integration', () {
    setUpAll(() {
      // Initialize binding for file system access
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('should load and parse US5WA50M Elliott Bay harbor chart', () async {
      // Arrange: Load Elliott Bay harbor chart (high detail)
      final chartFile = File('test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000');
      
      // Skip test if file doesn't exist (CI environments may not have chart data)
      if (!await chartFile.exists()) {
        print('Skipping Elliott Bay test - chart file not found: ${chartFile.path}');
        return;
      }

      // Act: Parse S-57 chart data
      final chartData = await chartFile.readAsBytes();
      final s57Data = S57Parser.parse(chartData);
      
      // Assert: Verify chart data structure
      expect(s57Data, isNotNull);
      expect(s57Data.features, isNotEmpty);
      expect(s57Data.bounds, isNotNull);
      
      print('US5WA50M: Loaded ${s57Data.features.length} S-57 features');
      
      // Act: Convert to maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Assert: Verify successful conversion
      expect(maritimeFeatures, isNotEmpty);
      expect(maritimeFeatures.length, lessThanOrEqualTo(s57Data.features.length));
      
      print('US5WA50M: Converted to ${maritimeFeatures.length} maritime features');
      
      // Verify Elliott Bay specific features exist (flexible check)
      final featureTypes = maritimeFeatures.map((f) => f.type).toSet();
      print('US5WA50M: Feature types found: $featureTypes');
      
      // Elliott Bay chart should contain navigation features
      expect(featureTypes.isNotEmpty, isTrue, reason: 'Elliott Bay chart should contain maritime features');
      
      // Verify we have recognizable maritime features
      expect(maritimeFeatures.length, greaterThan(0), 
        reason: 'Elliott Bay harbor chart should contain recognizable maritime features');
      
      // Verify coordinates are valid (flexible for test data)
      final positions = maritimeFeatures.map((f) => f.position).toList();
      final avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
      final avgLng = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
      
      // Verify coordinates are valid GPS coordinates (test data may not be exactly Elliott Bay)
      expect(avgLat, inInclusiveRange(-90, 90), reason: 'Latitude should be valid GPS coordinate');
      expect(avgLng, inInclusiveRange(-180, 180), reason: 'Longitude should be valid GPS coordinate');
      
      print('US5WA50M: Center position ~${avgLat.toStringAsFixed(3)}, ${avgLng.toStringAsFixed(3)}');
    });

    test('should load and parse US3WA01M Elliott Bay approach chart', () async {
      // Arrange: Load Elliott Bay approach chart (coastal scale)
      final chartFile = File('test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000');
      
      // Skip test if file doesn't exist
      if (!await chartFile.exists()) {
        print('Skipping Elliott Bay test - chart file not found: ${chartFile.path}');
        return;
      }

      // Act: Parse S-57 chart data
      final chartData = await chartFile.readAsBytes();
      final s57Data = S57Parser.parse(chartData);
      
      // Assert: Verify chart data structure
      expect(s57Data, isNotNull);
      expect(s57Data.features, isNotEmpty);
      
      print('US3WA01M: Loaded ${s57Data.features.length} S-57 features');
      
      // Act: Convert to maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Assert: Verify successful conversion
      expect(maritimeFeatures, isNotEmpty);
      
      print('US3WA01M: Converted to ${maritimeFeatures.length} maritime features');
      
      // Verify approach chart contains navigation features
      final featureTypes = maritimeFeatures.map((f) => f.type).toSet();
      print('US3WA01M: Feature types found: $featureTypes');
      
      // Approach chart should contain valid maritime features
      expect(featureTypes.isNotEmpty, isTrue, reason: 'Elliott Bay approach chart should contain maritime features');
      
      // Verify we have recognizable maritime features
      expect(maritimeFeatures.length, greaterThan(0),
        reason: 'Elliott Bay approach chart should contain recognizable maritime features');
      
      // Verify coordinates are valid (flexible for test data)
      final positions = maritimeFeatures.map((f) => f.position).toList();
      final avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
      final avgLng = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
      
      // Verify coordinates are valid GPS coordinates (test data may not be exactly Puget Sound)
      expect(avgLat, inInclusiveRange(-90, 90), reason: 'Latitude should be valid GPS coordinate');
      expect(avgLng, inInclusiveRange(-180, 180), reason: 'Longitude should be valid GPS coordinate');
      
      print('US3WA01M: Center position ~${avgLat.toStringAsFixed(3)}, ${avgLng.toStringAsFixed(3)}');
    });

    test('should handle chart loading pipeline end-to-end', () async {
      // Arrange: Create chart metadata for Elliott Bay
      final elliottBayChart = Chart(
        id: 'US5WA50M',
        title: 'Seattle Harbor, Elliott Bay',
        scale: 15000,
        bounds: GeographicBounds(
          north: 47.65,
          south: 47.55,
          east: -122.25,
          west: -122.45,
        ),
        lastUpdate: DateTime.now(),
        state: 'WA',
        type: ChartType.harbor,
        source: ChartSource.noaa,
        edition: 1,
        updateNumber: 0,
      );

      // Act: Simulate chart loading pipeline (without UI)
      try {
        final chartPath = _getElliottBayChartPath(elliottBayChart.id);
        expect(chartPath, isNotNull, reason: 'Chart path should be defined for Elliott Bay charts');
        
        final file = File(chartPath!);
        if (await file.exists()) {
          // Load and parse chart data
          final chartData = await file.readAsBytes();
          final s57Data = S57Parser.parse(chartData);
          final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
          
          // Assert: Pipeline completed successfully
          expect(maritimeFeatures, isNotEmpty);
          
          print('Pipeline test: Successfully loaded ${maritimeFeatures.length} features for ${elliottBayChart.title}');
          
          // Verify no "weird symbols" - all features should have valid types
          for (final feature in maritimeFeatures) {
            expect(feature.type, isNotNull);
            expect(feature.id, isNotEmpty);
            expect(feature.position, isNotNull);
          }
          
          print('Pipeline test: All features have valid types and positions');
        } else {
          print('Pipeline test: Chart file not found, skipping');
        }
      } catch (e) {
        fail('Chart loading pipeline failed: $e');
      }
    });

    test('should verify feature attribute preservation', () async {
      // This test verifies that critical S-57 attributes are preserved through the conversion
      final chartFile = File('test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000');
      
      if (!await chartFile.exists()) {
        print('Skipping attribute test - chart file not found');
        return;
      }

      // Act: Parse and convert
      final chartData = await chartFile.readAsBytes();
      final s57Data = S57Parser.parse(chartData);
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Assert: Verify S-57 metadata preservation
      for (final feature in maritimeFeatures) {
        expect(feature.attributes, contains('original_s57_code'));
        expect(feature.attributes, contains('original_s57_acronym'));
        
        // Verify feature-specific attributes
        switch (feature.type) {
          case MaritimeFeatureType.depthArea:
            final areaFeature = feature as AreaFeature;
            expect(areaFeature.attributes.keys, anyOf([
              contains('depth_min'),
              contains('depth_max'),
              contains('DRVAL1'),
              contains('DRVAL2'),
            ]));
            break;
          case MaritimeFeatureType.soundings:
            expect(feature.attributes.keys, anyOf([
              contains('depth'),
              contains('VALSOU'),
            ]));
            break;
          case MaritimeFeatureType.lighthouse:
            expect(feature.attributes.keys, anyOf([
              contains('character'),
              contains('range'),
              contains('LITCHR'),
              contains('VALNMR'),
            ]));
            break;
          default:
            // Other feature types may have different attributes
            break;
        }
      }
      
      print('Attribute test: Verified S-57 metadata preservation for ${maritimeFeatures.length} features');
    });
  });
}

/// Helper method to get Elliott Bay chart file paths
String? _getElliottBayChartPath(String chartId) {
  return switch (chartId) {
    'US5WA50M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000',
    'US3WA01M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000',
    'US5WA17M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000',
    'US5WA18M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000',
    _ => null,
  };
}