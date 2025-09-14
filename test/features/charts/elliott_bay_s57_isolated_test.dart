/// Unit tests for Elliott Bay S-57 parsing in isolation
/// 
/// Tests validate that the S-57 parsing pipeline works correctly
/// for Elliott Bay charts using real NOAA ENC data.
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';
import '../../utils/s57_test_fixtures.dart';

void main() {
  group('Elliott Bay S-57 Parsing Isolated Tests', () {
    late FixtureAvailability availability;

    setUpAll(() async {
      availability = await S57TestFixtures.checkFixtureAvailability();
    });

    test('Elliott Bay S-57 parsing produces expected feature types', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      // Load real Elliott Bay S-57 data
      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Validate parsing results
      expect(s57Data, isNotNull);
      expect(s57Data.features, isNotEmpty, 
        reason: 'Elliott Bay chart should contain S-57 features');
      expect(s57Data.bounds, isNotNull);
      expect(s57Data.metadata, isNotNull);
      
      // Validate feature types - Elliott Bay should contain maritime navigation features
      final featureTypes = s57Data.features.map((f) => f.featureType.acronym).toSet();
      print('Elliott Bay S-57 feature types: $featureTypes');
      
      // Elliott Bay is a harbor chart, should contain navigation-relevant features
      expect(featureTypes, isNotEmpty);
      expect(s57Data.features.length, greaterThan(0));
      expect(s57Data.features.length, lessThan(50000), 
        reason: 'Harbor chart should have reasonable feature count');
    });

    test('Elliott Bay isolated component validation', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Test individual components in isolation
      
      // 1. Spatial indexing validation
      expect(s57Data.spatialIndex, isNotNull);
      expect(s57Data.spatialIndex.featureCount, equals(s57Data.features.length));
      
      // 2. Bounds validation
      expect(s57Data.bounds, isNotNull);
      expect(s57Data.bounds.minLatitude, lessThan(s57Data.bounds.maxLatitude));
      expect(s57Data.bounds.minLongitude, lessThan(s57Data.bounds.maxLongitude));
      
      // 3. Metadata validation
      expect(s57Data.metadata, isNotNull);
      expect(s57Data.metadata.producer, isNotEmpty);
      expect(s57Data.metadata.version, isNotEmpty);
      
      // 4. Feature coordinate validation
      var validCoordinatesCount = 0;
      for (final feature in s57Data.features) {
        expect(feature.coordinates, isNotEmpty);
        for (final coord in feature.coordinates) {
          if (coord.latitude >= -90 && coord.latitude <= 90 &&
              coord.longitude >= -180 && coord.longitude <= 180) {
            validCoordinatesCount++;
          }
        }
      }
      expect(validCoordinatesCount, greaterThan(0));
      
      print('Elliott Bay isolated validation: $validCoordinatesCount valid coordinates');
    });

    test('Elliott Bay maritime adapter integration', () async {
      if (!availability.elliottBayAvailable) {
        print('Elliott Bay fixture not available - skipping test');
        return;
      }

      final s57Data = await S57TestFixtures.loadParsedElliottBay();
      
      // Test S57 to Maritime adapter with real data
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Validate conversion
      expect(maritimeFeatures, isA<List<MaritimeFeature>>());
      expect(maritimeFeatures.length, lessThanOrEqualTo(s57Data.features.length));
      
      // Each converted feature should be valid
      for (final feature in maritimeFeatures) {
        expect(feature.type, isA<MaritimeFeatureType>());
        expect(feature.coordinates, isNotEmpty);
      }
      
      print('Elliott Bay maritime conversion: ${maritimeFeatures.length} features converted');
    });
  });
}
