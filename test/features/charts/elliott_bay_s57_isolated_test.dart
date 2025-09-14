/// Unit tests for Elliott Bay S-57 parsing in isolation
/// 
/// These tests validate that the S-57 parsing pipeline works correctly
/// for Elliott Bay charts by testing each component separately.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/utils/zip_extractor.dart';

void main() {
  group('Elliott Bay S-57 Parsing Isolated Tests', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('Elliott Bay S-57 parsing produces expected feature types', () async {
      // Load Elliott Bay S-57 data from assets
      List<int>? chartData;
      
      try {
        final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
        chartData = byteData.buffer.asUint8List();
      } catch (e) {
        fail('Failed to load Elliott Bay S-57 asset: $e');
      }
      
      expect(chartData, isNotNull);
      expect(chartData!.length, greaterThan(1000), 
        reason: 'Elliott Bay S-57 file should be substantial');
      
      // Parse S-57 data
      final s57Data = S57Parser.parse(chartData);
      
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
      
      // Validate coordinates are in Elliott Bay area (approximately)
      // Elliott Bay bounds: roughly 47.5-47.7N, 122.2-122.4W
      for (final feature in s57Data.features) {
        for (final coord in feature.coordinates) {
          expect(coord.latitude, inInclusiveRange(47.0, 48.0), 
            reason: 'Elliott Bay features should have Seattle-area latitude');
          expect(coord.longitude, inInclusiveRange(-123.0, -122.0), 
            reason: 'Elliott Bay features should have Seattle-area longitude');
        }
      }
      
      print('Elliott Bay S-57 parsing test: ${s57Data.features.length} features validated');
    });

    test('S-57 to Maritime conversion preserves critical features', () async {
      // Load and parse Elliott Bay chart
      final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
      final chartData = byteData.buffer.asUint8List();
      final s57Data = S57Parser.parse(chartData);
      
      // Convert to maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      // Validate conversion results
      expect(maritimeFeatures, isNotEmpty);
      expect(maritimeFeatures.length, lessThanOrEqualTo(s57Data.features.length),
        reason: 'Maritime features should not exceed S-57 features');
      
      // Validate all maritime features have required properties
      for (final feature in maritimeFeatures) {
        expect(feature.id, isNotEmpty);
        expect(feature.type, isNotNull);
        expect(feature.position, isNotNull);
        expect(feature.attributes, isNotNull);
        
        // Validate coordinates are reasonable
        expect(feature.position.latitude, inInclusiveRange(-90, 90));
        expect(feature.position.longitude, inInclusiveRange(-180, 180));
        
        // Features converted from S-57 should have origin data
        expect(feature.attributes, containsPair('original_s57_code', isA<int>()), 
          reason: 'Maritime features should track S-57 origin');
        expect(feature.attributes, containsPair('original_s57_acronym', isA<String>()), 
          reason: 'Maritime features should track S-57 acronym');
      }
      
      print('Maritime conversion test: ${maritimeFeatures.length} features validated');
    });

    test('Elliott Bay parsing handles coordinate systems correctly', () async {
      // Load Elliott Bay chart data
      final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
      final chartData = byteData.buffer.asUint8List();
      
      // Parse S-57 data
      final s57Data = S57Parser.parse(chartData);
      
      // Convert to maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      expect(maritimeFeatures, isNotEmpty);
      
      // Validate all coordinates are in Elliott Bay geographic area
      for (final feature in maritimeFeatures) {
        final pos = feature.position;
        
        // Elliott Bay area validation (approximate bounds)
        expect(pos.latitude, inInclusiveRange(47.5, 47.8), 
          reason: 'Feature ${feature.id} latitude ${pos.latitude} should be in Elliott Bay area');
        expect(pos.longitude, inInclusiveRange(-122.5, -122.2), 
          reason: 'Feature ${feature.id} longitude ${pos.longitude} should be in Elliott Bay area');
      }
      
      // Calculate center of all features - should be roughly in Elliott Bay
      final positions = maritimeFeatures.map((f) => f.position).toList();
      final avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
      final avgLng = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
      
      print('Elliott Bay coordinate center: ${avgLat.toStringAsFixed(6)}, ${avgLng.toStringAsFixed(6)}');
      
      // Average should be roughly in Elliott Bay center
      expect(avgLat, inInclusiveRange(47.6, 47.7), 
        reason: 'Average latitude should be in Elliott Bay center');
      expect(avgLng, inInclusiveRange(-122.4, -122.3), 
        reason: 'Average longitude should be in Elliott Bay center');
    });

    test('Elliott Bay ZIP extraction and S-57 parsing integration', () async {
      // This test uses the test fixture ZIP files if available
      final elliottBayZip = File('test/fixtures/charts/s57_data/US5WA50M_harbor_elliott_bay.zip');
      
      if (!await elliottBayZip.exists()) {
        print('Elliott Bay ZIP test fixture not available, skipping integration test');
        return;
      }
      
      // Extract S-57 data from ZIP
      final zipBytes = await elliottBayZip.readAsBytes();
      final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
      
      expect(s57Bytes, isNotNull, reason: 'Should extract S-57 data from Elliott Bay ZIP');
      expect(s57Bytes!.length, greaterThan(1000), reason: 'Extracted S-57 data should be substantial');
      
      // Parse extracted S-57 data
      final s57Data = S57Parser.parse(s57Bytes);
      
      expect(s57Data.features, isNotEmpty, reason: 'Should parse features from extracted S-57 data');
      
      // Convert to maritime features
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      expect(maritimeFeatures, isNotEmpty, reason: 'Should convert S-57 features to maritime features');
      
      print('ZIP integration test: ${s57Data.features.length} S-57 → ${maritimeFeatures.length} maritime features');
    });

    test('Elliott Bay S-57 parsing performance validation', () async {
      // Load Elliott Bay chart data
      final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
      final chartData = byteData.buffer.asUint8List();
      
      // Measure parsing performance
      final stopwatch = Stopwatch()..start();
      
      final s57Data = S57Parser.parse(chartData);
      final parseTime = stopwatch.elapsedMilliseconds;
      
      stopwatch.reset();
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      final convertTime = stopwatch.elapsedMilliseconds;
      
      stopwatch.stop();
      
      // Validate performance is reasonable (should complete in reasonable time)
      expect(parseTime, lessThan(5000), reason: 'S-57 parsing should complete in under 5 seconds');
      expect(convertTime, lessThan(1000), reason: 'Maritime conversion should complete in under 1 second');
      
      print('Elliott Bay parsing performance:');
      print('  S-57 parsing: ${parseTime}ms (${s57Data.features.length} features)');
      print('  Maritime conversion: ${convertTime}ms (${maritimeFeatures.length} features)');
      print('  Total pipeline: ${parseTime + convertTime}ms');
    });
  });
}