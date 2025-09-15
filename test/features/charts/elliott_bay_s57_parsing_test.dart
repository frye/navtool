/// Unit tests for Elliott Bay S-57 parsing validation
/// Tests the S-57 parsing pipeline in isolation for Elliott Bay charts
library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import '../../utils/s57_test_fixtures.dart';

void main() {
  group('Elliott Bay S-57 Parsing Unit Tests with Real Data', () {
    late List<int> realElliottBayData;
    bool hasRealCharts = false;

    setUpAll(() async {
      // Initialize binding for file system access
      TestWidgetsFlutterBinding.ensureInitialized();
      
      // Check if real S57 charts are available
      hasRealCharts = await S57TestFixtures.areChartsAvailable();
      
      if (hasRealCharts) {
        // Load real Elliott Bay chart data
        realElliottBayData = await S57TestFixtures.loadElliottBayChart();
        print('Elliott Bay S-57 Test: Using real NOAA ENC data (${realElliottBayData.length} bytes)');
      } else {
        print('Elliott Bay S-57 Test: Skipping - real chart data not available');
      }
    });

    test('Elliott Bay S-57 parsing produces expected feature types', () async {
      if (!hasRealCharts) {
        print('Elliott Bay S-57 Test: Skipping - real chart data not available');
        return;
      }
      
      // Act: Parse real S-57 chart data
      final s57Data = S57Parser.parse(realElliottBayData);
      
      // Assert: Verify S-57 parsing results
      expect(s57Data, isNotNull);
      expect(s57Data.features, isNotEmpty);
      expect(s57Data.bounds, isNotNull);
      
      print('Elliott Bay S-57 Test: Parsed ${s57Data.features.length} real S-57 features');
      
      // Log real S-57 feature breakdown
      final featureBreakdown = <String, int>{};
      for (final feature in s57Data.features) {
        final acronym = feature.featureType.acronym;
        featureBreakdown[acronym] = (featureBreakdown[acronym] ?? 0) + 1;
      }
      print('Elliott Bay S-57 Test: Real S-57 feature breakdown: $featureBreakdown');
      
      // Check for expected Elliott Bay S-57 feature types
      final featureAcronyms = s57Data.features.map((f) => f.featureType.acronym).toSet();
      print('Elliott Bay S-57 Test: Feature acronyms found: $featureAcronyms');
      
      // Elliott Bay should contain these real S-57 feature types
      expect(featureAcronyms, contains('DEPCNT'), reason: 'Elliott Bay should have depth contours');
      expect(featureAcronyms, contains('BOYLAT'), reason: 'Elliott Bay should have lateral buoys');
      expect(featureAcronyms, contains('LIGHTS'), reason: 'Elliott Bay should have navigation lights');
      
      print('Elliott Bay S-57 Test: SUCCESS - Found expected real S-57 feature types');
      
      // Validate against expectations
      final expectations = S57TestFixtures.getElliottBayExpectations();
      expect(s57Data.features.length, greaterThanOrEqualTo(expectations.minExpectedFeatures), 
        reason: 'Should have at least ${expectations.minExpectedFeatures} features');
      expect(s57Data.features.length, lessThan(1000), 
        reason: 'Feature count should be reasonable for harbor chart');
    });

    test('S-57 to Maritime conversion preserves critical features with real data', () async {
      if (!hasRealCharts) {
        print('S-57 Maritime Conversion Test: Skipping - real chart data not available');
        return;
      }
      
      // Act: Parse real S-57 data and convert to maritime features
      final s57Data = S57Parser.parse(realElliottBayData);
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Assert: Verify conversion results
      expect(maritimeFeatures, isNotEmpty);
      expect(maritimeFeatures.length, lessThanOrEqualTo(s57Data.features.length));
      
      print('S-57 Maritime Conversion Test: Converted ${s57Data.features.length} real S-57 features to ${maritimeFeatures.length} maritime features');
      
      // Log maritime feature breakdown
      final maritimeBreakdown = <String, int>{};
      for (final feature in maritimeFeatures) {
        final typeName = feature.type.toString().split('.').last;
        maritimeBreakdown[typeName] = (maritimeBreakdown[typeName] ?? 0) + 1;
      }
      print('S-57 Maritime Conversion Test: Maritime feature breakdown: $maritimeBreakdown');
      
      // Verify all maritime features have valid properties from real data
      for (final feature in maritimeFeatures) {
        expect(feature.type, isNotNull);
        expect(feature.id, isNotEmpty);
        expect(feature.position, isNotNull);
        
        // Verify coordinates are valid GPS coordinates in Elliott Bay area
        expect(feature.position.latitude, inInclusiveRange(-90, 90));
        expect(feature.position.longitude, inInclusiveRange(-180, 180));
        
        // Elliott Bay specific coordinate validation (broad range)
        expect(feature.position.latitude, inInclusiveRange(47.5, 47.8), 
          reason: 'Maritime feature should be in Seattle area');
        expect(feature.position.longitude, inInclusiveRange(-122.5, -122.0), 
          reason: 'Maritime feature should be in Seattle area');
      }
      
      // Log conversion efficiency
      final conversionRate = (maritimeFeatures.length / s57Data.features.length * 100).toStringAsFixed(1);
      print('S-57 Maritime Conversion Test: Conversion efficiency: $conversionRate%');
      
      // Verify reasonable conversion rate
      expect(maritimeFeatures.length / s57Data.features.length, greaterThan(0.01), 
        reason: 'Conversion rate should be at least 1%');
      
      print('S-57 Maritime Conversion Test: SUCCESS - Real S-57 to Maritime conversion validated');
    });

    test('Elliott Bay parsing handles coordinate systems correctly with real data', () async {
      if (!hasRealCharts) {
        print('Coordinate System Test: Skipping - real chart data not available');
        return;
      }
      
      // Parse real data and convert
      final s57Data = S57Parser.parse(realElliottBayData);
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      expect(maritimeFeatures, isNotEmpty);
      
      // Verify coordinates are in reasonable Elliott Bay area
      final positions = maritimeFeatures.map((f) => f.position).toList();
      final avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
      final avgLng = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
      
      print('Coordinate System Test: Average position: ${avgLat.toStringAsFixed(6)}, ${avgLng.toStringAsFixed(6)}');
      
      // Verify coordinates are valid GPS coordinates
      expect(avgLat, inInclusiveRange(-90, 90));
      expect(avgLng, inInclusiveRange(-180, 180));
      
      // Verify bounds are reasonable for Elliott Bay
      expect(positions.every((p) => p.latitude >= -90 && p.latitude <= 90), isTrue,
        reason: 'All latitudes should be valid GPS coordinates');
      expect(positions.every((p) => p.longitude >= -180 && p.longitude <= 180), isTrue,
        reason: 'All longitudes should be valid GPS coordinates');
      
      // Check against expected Elliott Bay bounds
      final expectations = S57TestFixtures.getElliottBayExpectations();
      final expectedBounds = expectations.bounds;
      
      // Most coordinates should be within or near expected bounds
      final inBoundsCount = positions.where((p) => 
        p.latitude >= expectedBounds.south - 0.1 && 
        p.latitude <= expectedBounds.north + 0.1 &&
        p.longitude >= expectedBounds.west - 0.1 && 
        p.longitude <= expectedBounds.east + 0.1
      ).length;
      
      final inBoundsPercentage = (inBoundsCount / positions.length * 100).toStringAsFixed(1);
      print('Coordinate System Test: ${inBoundsPercentage}% of coordinates within expected Elliott Bay bounds');
      
      // At least half should be within expected bounds (allowing for chart edges)
      expect(inBoundsCount / positions.length, greaterThan(0.5), 
        reason: 'Majority of coordinates should be within Elliott Bay bounds');
      
      print('Coordinate System Test: SUCCESS - All ${positions.length} positions validated for Elliott Bay');
    });
  });
}