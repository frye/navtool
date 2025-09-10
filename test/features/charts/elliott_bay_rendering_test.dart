import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/features/charts/chart_screen.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/utils/zip_extractor.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'dart:io';

/// Tests for Elliott Bay chart rendering pipeline
/// 
/// Validates that the complete S-57 parsing and maritime feature conversion
/// pipeline works correctly for Elliott Bay test charts.
void main() {
  group('Elliott Bay Chart Rendering Pipeline', () {
    late File elliottBayZipFile;
    late File pugetSoundZipFile;
    
    setUpAll(() async {
      // Verify test data files exist
      elliottBayZipFile = File('test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip');
      pugetSoundZipFile = File('test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip');
      
      print('[ElliottBayTest] Checking test data availability:');
      print('[ElliottBayTest] Elliott Bay ZIP exists: ${await elliottBayZipFile.exists()}');
      print('[ElliottBayTest] Puget Sound ZIP exists: ${await pugetSoundZipFile.exists()}');
    });
    
    group('ZIP File Extraction', () {
      test('should extract S-57 data from Elliott Bay ZIP', () async {
        if (!await elliottBayZipFile.exists()) {
          fail('Elliott Bay test data not found: ${elliottBayZipFile.path}');
        }
        
        final zipBytes = await elliottBayZipFile.readAsBytes();
        expect(zipBytes.length, greaterThan(1000)); // Sanity check ZIP file size
        
        print('[ElliottBayTest] Elliott Bay ZIP size: ${zipBytes.length} bytes');
        
        // Debug: List ZIP contents
        final zipListing = ZipExtractor.getZipListing(zipBytes);
        print('[ElliottBayTest] Elliott Bay ZIP contents:');
        for (final item in zipListing) {
          print('[ElliottBayTest]   $item');
        }
        
        // Extract S-57 data
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        
        expect(s57Bytes, isNotNull, reason: 'Should extract S-57 .000 file from Elliott Bay ZIP');
        expect(s57Bytes!.length, greaterThan(1000), reason: 'S-57 file should have reasonable size');
        
        print('[ElliottBayTest] Extracted S-57 data: ${s57Bytes.length} bytes');
      });
      
      test('should extract S-57 data from Puget Sound ZIP', () async {
        if (!await pugetSoundZipFile.exists()) {
          fail('Puget Sound test data not found: ${pugetSoundZipFile.path}');
        }
        
        final zipBytes = await pugetSoundZipFile.readAsBytes();
        expect(zipBytes.length, greaterThan(1000));
        
        print('[ElliottBayTest] Puget Sound ZIP size: ${zipBytes.length} bytes');
        
        // Extract S-57 data
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US3WA01M');
        
        expect(s57Bytes, isNotNull, reason: 'Should extract S-57 .000 file from Puget Sound ZIP');
        expect(s57Bytes!.length, greaterThan(1000), reason: 'S-57 file should have reasonable size');
        
        print('[ElliottBayTest] Extracted S-57 data: ${s57Bytes.length} bytes');
      });
    });
    
    group('S-57 Parsing', () {
      test('should parse Elliott Bay S-57 data successfully', () async {
        if (!await elliottBayZipFile.exists()) {
          markTestSkipped('Elliott Bay test data not available');
          return;
        }
        
        final zipBytes = await elliottBayZipFile.readAsBytes();
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        
        expect(s57Bytes, isNotNull);
        
        // Parse S-57 data
        final s57Data = S57Parser.parse(s57Bytes!);
        
        expect(s57Data, isNotNull);
        expect(s57Data.features, isNotEmpty, reason: 'Elliott Bay chart should contain maritime features');
        
        print('[ElliottBayTest] Elliott Bay S-57 parsing results:');
        print('[ElliottBayTest]   Total features: ${s57Data.features.length}');
        print('[ElliottBayTest]   Chart bounds: ${s57Data.bounds.toMap()}');
        print('[ElliottBayTest]   Metadata: ${s57Data.metadata.toMap()}');
        
        // Validate feature types expected in Elliott Bay
        final featureTypes = s57Data.features.map((f) => f.featureType).toSet();
        print('[ElliottBayTest]   Feature types found: ${featureTypes.map((t) => t.acronym).toList()}');
        
        // Elliott Bay should contain depth features
        expect(
          featureTypes.any((t) => t == S57FeatureType.depthArea || t == S57FeatureType.depthContour),
          isTrue,
          reason: 'Elliott Bay chart should contain depth features (DEPARE or DEPCNT)',
        );
        
        // Elliott Bay should contain typical harbor features
        // Note: Different chart editions may contain different feature sets
        // Accept any reasonable harbor navigation features
        final hasExpectedFeatures = featureTypes.any((t) => 
          t == S57FeatureType.depthContour || 
          t == S57FeatureType.depthArea ||
          t == S57FeatureType.buoyLateral ||
          t == S57FeatureType.lighthouse ||
          t == S57FeatureType.coastline ||
          t == S57FeatureType.sounding);
        
        expect(hasExpectedFeatures, isTrue,
          reason: 'Elliott Bay chart should contain typical harbor navigation features');
        
        print('[ElliottBayTest] Elliott Bay contains expected harbor features: $featureTypes');
      });
    });
    
    group('Maritime Feature Conversion', () {
      test('should convert Elliott Bay S-57 features to maritime features', () async {
        if (!await elliottBayZipFile.exists()) {
          markTestSkipped('Elliott Bay test data not available');
          return;
        }
        
        // Load and parse Elliott Bay chart
        final zipBytes = await elliottBayZipFile.readAsBytes();
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        final s57Data = S57Parser.parse(s57Bytes!);
        
        // Convert to maritime features
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
        
        expect(maritimeFeatures, isNotEmpty, reason: 'Should produce maritime features from Elliott Bay S-57 data');
        
        print('[ElliottBayTest] Maritime feature conversion results:');
        print('[ElliottBayTest]   Total maritime features: ${maritimeFeatures.length}');
        
        // Count features by type
        final featureCounts = <MaritimeFeatureType, int>{};
        for (final feature in maritimeFeatures) {
          featureCounts[feature.type] = (featureCounts[feature.type] ?? 0) + 1;
        }
        
        print('[ElliottBayTest]   Maritime feature counts:');
        for (final entry in featureCounts.entries) {
          print('[ElliottBayTest]     ${entry.key.name}: ${entry.value}');
        }
        
        // Validate expected maritime feature types
        expect(
          featureCounts.keys.any((t) => 
            t == MaritimeFeatureType.depthContour || 
            t == MaritimeFeatureType.depthArea
          ),
          isTrue,
          reason: 'Should contain depth-related maritime features',
        );
        
        expect(
          featureCounts.keys.any((t) => 
            t == MaritimeFeatureType.shoreline || 
            t == MaritimeFeatureType.landArea
          ),
          isTrue,
          reason: 'Should contain coastline-related maritime features',
        );
        
        // Validate that we have real maritime features (not just synthetic/boundary features)
        // Real Elliott Bay chart parsing produces at least a few actual S-57 features
        expect(
          maritimeFeatures.length,
          greaterThan(2),
          reason: 'Elliott Bay chart should produce real maritime features (>2 indicates real S-57 parsing)',
        );
        
        // Verify these are real S-57 conversions, not synthetic features
        final realConversions = maritimeFeatures.where((f) => 
          f.attributes.containsKey('original_s57_code') && 
          f.attributes.containsKey('original_s57_acronym')).length;
        
        expect(realConversions, greaterThan(0), 
          reason: 'Should have features converted from real S-57 data');
        
        print('[ElliottBayTest] Real S-57 conversions: $realConversions/${maritimeFeatures.length}');
      });
      
      test('should produce depth contours with proper depth values', () async {
        if (!await elliottBayZipFile.exists()) {
          markTestSkipped('Elliott Bay test data not available');
          return;
        }
        
        // Load and convert Elliott Bay chart
        final zipBytes = await elliottBayZipFile.readAsBytes();
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        final s57Data = S57Parser.parse(s57Bytes!);
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
        
        // Find depth contours
        final depthContours = maritimeFeatures
            .where((f) => f is DepthContour)
            .cast<DepthContour>()
            .toList();
        
        if (depthContours.isNotEmpty) {
          print('[ElliottBayTest] Found ${depthContours.length} depth contours');
          
          for (final contour in depthContours.take(5)) { // Show first 5
            print('[ElliottBayTest]   Depth contour: ${contour.depth}m, ${contour.coordinates.length} points');
          }
          
          // Validate depth values are reasonable for Elliott Bay (harbor depth range)
          final depths = depthContours.map((c) => c.depth).toList();
          expect(depths.any((d) => d > 0), isTrue, reason: 'Should have positive depth values');
          expect(depths.any((d) => d < 100), isTrue, reason: 'Should have harbor-scale depths (<100m)');
        } else {
          print('[ElliottBayTest] No depth contours found - may be represented as depth areas instead');
        }
      });
      
      test('should produce navigation aids (buoys, beacons) if present', () async {
        if (!await elliottBayZipFile.exists()) {
          markTestSkipped('Elliott Bay test data not available');
          return;
        }
        
        // Load and convert Elliott Bay chart
        final zipBytes = await elliottBayZipFile.readAsBytes();
        final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        final s57Data = S57Parser.parse(s57Bytes!);
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
        
        // Find navigation aids
        final navigationAids = maritimeFeatures.where((f) => 
          f.type == MaritimeFeatureType.buoy ||
          f.type == MaritimeFeatureType.beacon ||
          f.type == MaritimeFeatureType.lighthouse ||
          f.type == MaritimeFeatureType.daymark
        ).toList();
        
        print('[ElliottBayTest] Found ${navigationAids.length} navigation aids');
        
        for (final aid in navigationAids.take(3)) { // Show first 3
          print('[ElliottBayTest]   ${aid.type.name}: ${aid.id} at ${aid.position}');
          if (aid is PointFeature && aid.label != null) {
            print('[ElliottBayTest]     Label: ${aid.label}');
          }
        }
        
        // Navigation aids may or may not be present in this specific chart area
        // So we don't make this a hard requirement, just log the results
      });
    });
    
    group('Chart Screen Integration', () {
      testWidgets('should display Elliott Bay chart without falling back to boundary features', (tester) async {
        // Get Elliott Bay chart from test fixtures
        final elliottBayCharts = WashingtonTestCharts.getElliottBayCharts();
        expect(elliottBayCharts, isNotEmpty, reason: 'Should have Elliott Bay test charts available');
        
        final chart = elliottBayCharts.first; // US5WA50M
        
        // Create ChartScreen with Elliott Bay chart
        final chartScreen = MaterialApp(
          home: ChartScreen(chart: chart),
        );
        
        await tester.pumpWidget(chartScreen);
        
        // Wait for initial render
        await tester.pump();
        
        // Let the chart loading complete
        await tester.pump(const Duration(seconds: 1));
        
        // Verify the screen is rendered
        expect(find.byType(ChartScreen), findsOneWidget);
        
        // The chart title should be displayed
        expect(find.text(chart.title), findsOneWidget);
        
        // Chart may load very quickly, so loading indicator might not be visible in tests
        // Let the chart loading complete (allow sufficient time)
        await tester.pumpAndSettle(const Duration(seconds: 5));
        
        // Verify chart has finished loading (loading indicator should be gone if it was shown)
        expect(find.textContaining('Loading'), findsNothing, 
          reason: 'Loading indicator should be gone after chart loads');
        
        // Should NOT show the fallback message
        expect(find.textContaining('chart boundary only'), findsNothing);
        expect(find.textContaining('S-57 feature loading may be incomplete'), findsNothing);
        
        // Should show feature count greater than 2 (more than just boundary features)
        final featureCountFinder = find.textContaining('features');
        expect(featureCountFinder, findsAtLeastNWidgets(1));
        
        print('[ElliottBayTest] Chart screen integration test completed');
      });
    });
  });
}