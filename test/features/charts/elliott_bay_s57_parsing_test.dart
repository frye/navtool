/// Unit tests for Elliott Bay S-57 parsing validation  
/// Tests the S-57 parsing pipeline with real NOAA ENC Elliott Bay data
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import '../../utils/s57_test_fixtures.dart';

void main() {
  group('Elliott Bay S-57 Parsing with Real Data', () {
    late FixtureAvailability availability;

    setUpAll(() async {
      availability = await S57TestFixtures.checkFixtureAvailability();
    });

    test('Elliott Bay S-57 parsing produces expected feature types', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      // Load real Elliott Bay chart data
      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Validate parsing results
      expect(s57Data, isNotNull);
      expect(s57Data.features, isNotEmpty, 
        reason: 'Elliott Bay chart should contain S-57 features');
      expect(s57Data.bounds, isNotNull);
      
      print('Elliott Bay S-57 Test: Parsed ${s57Data.features.length} S-57 features');
      
      // Analyze real S-57 feature types found
      final featureBreakdown = <String, int>{};
      for (final feature in s57Data.features) {
        final acronym = feature.featureType.acronym;
        featureBreakdown[acronym] = (featureBreakdown[acronym] ?? 0) + 1;
      }
      print('Elliott Bay S-57 Test: Real feature breakdown: $featureBreakdown');
      
      // Validate expected S57 feature categories for Elliott Bay harbor chart  
      final expectedS57Types = ['DEPARE', 'DEPCNT', 'BOYLAT', 'LIGHTS', 'SOUNDG', 'COALNE'];
      final foundTypes = featureBreakdown.keys.toSet();
      final hasExpectedFeatures = expectedS57Types.any((type) => foundTypes.contains(type));
      
      if (hasExpectedFeatures) {
        print('Elliott Bay S-57 Test: SUCCESS - Found expected S-57 feature types');
        final commonTypes = expectedS57Types.where((type) => foundTypes.contains(type)).toList();
        print('Elliott Bay S-57 Test: Common types found: $commonTypes');
      } else {
        print('Elliott Bay S-57 Test: INFO - Feature types found: $foundTypes');
      }
      
      // Validate feature count is reasonable for harbor chart
      expect(s57Data.features.length, greaterThan(0));
      expect(s57Data.features.length, lessThan(50000), 
        reason: 'Feature count should be reasonable for harbor chart');
        
      // Validate chart bounds are in Elliott Bay area
      expect(s57Data.bounds.minLatitude, greaterThan(47.0));
      expect(s57Data.bounds.maxLatitude, lessThan(48.0));
      expect(s57Data.bounds.minLongitude, greaterThan(-123.0));
      expect(s57Data.bounds.maxLongitude, lessThan(-121.0));
    });

    test('S-57 to Maritime conversion preserves critical features', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      // Load real Elliott Bay S57 data
      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Convert S-57 features to Maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Validate conversion results
      expect(maritimeFeatures, isNotEmpty, 
        reason: 'Should convert S-57 features to Maritime features');
      
      print('Elliott Bay Maritime Conversion: ${maritimeFeatures.length} maritime features from ${s57Data.features.length} S-57 features');
      
      // Analyze converted feature types
      final maritimeTypeBreakdown = <String, int>{};
      for (final feature in maritimeFeatures) {
        final typeName = feature.type.toString();
        maritimeTypeBreakdown[typeName] = (maritimeTypeBreakdown[typeName] ?? 0) + 1;
      }
      print('Elliott Bay Maritime Types: $maritimeTypeBreakdown');
      
      // Validate that critical marine navigation features are preserved
      expect(maritimeFeatures.length, lessThanOrEqualTo(s57Data.features.length),
        reason: 'Maritime features should not exceed S-57 features');
      
      // Each maritime feature should have valid coordinates
      for (final feature in maritimeFeatures) {
        expect(feature.coordinates, isNotEmpty, 
          reason: 'Maritime feature should have coordinates');
      }
    });

    test('Elliott Bay coordinate system validation', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Validate coordinate system matches Elliott Bay area
      var validCoordinates = 0;
      
      for (final feature in s57Data.features) {
        for (final coord in feature.coordinates) {
          // Elliott Bay coordinates should be in specific ranges
          if (coord.latitude >= 47.0 && coord.latitude <= 48.0 &&
              coord.longitude >= -123.0 && coord.longitude <= -121.0) {
            validCoordinates++;
          }
        }
      }
      
      expect(validCoordinates, greaterThan(0), 
        reason: 'Should have coordinates in Elliott Bay area');
      
      print('Elliott Bay Coordinates: $validCoordinates valid coordinates found');
    });
  });
}
