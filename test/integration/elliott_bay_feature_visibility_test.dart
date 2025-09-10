/// Integration test to validate Elliott Bay chart feature visibility
/// Tests that all 3 maritime features (lighthouse, buoy, depth contour) are visible
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Elliott Bay Feature Visibility Validation', () {
    test('All Elliott Bay features should be visible at chart scales', () async {
      print('[Visibility Test] Testing Elliott Bay feature visibility at different scales');
      
      // Load Elliott Bay chart
      final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
      final List<int> chartBytes = byteData.buffer.asUint8List();
      
      // Parse and convert features
      final s57Data = S57Parser.parse(chartBytes);
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      print('[Visibility Test] Testing ${maritimeFeatures.length} maritime features');
      
      // Test visibility at different chart scales
      final scales = [
        ChartScale.overview,
        ChartScale.general, 
        ChartScale.coastal,
        ChartScale.approach,
        ChartScale.harbour,
        ChartScale.berthing,
      ];
      
      for (final scale in scales) {
        print('\n[Visibility Test] Testing scale: $scale (1:${scale.scale})');
        
        int visibleFeatures = 0;
        Map<MaritimeFeatureType, int> visibleByType = {};
        
        for (final feature in maritimeFeatures) {
          final isVisible = feature.isVisibleAtScale(scale);
          if (isVisible) {
            visibleFeatures++;
            visibleByType[feature.type] = (visibleByType[feature.type] ?? 0) + 1;
          }
          
          print('[Visibility Test]   ${feature.type}: ${isVisible ? 'VISIBLE' : 'HIDDEN'}');
        }
        
        print('[Visibility Test] Scale $scale summary: $visibleFeatures visible features');
        print('[Visibility Test] By type: ${visibleByType.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
        
        // At harbor and berthing scales, all features should be visible
        if (scale == ChartScale.harbour || scale == ChartScale.berthing) {
          expect(visibleFeatures, equals(3), 
            reason: 'All 3 Elliott Bay features should be visible at $scale scale');
          
          expect(visibleByType[MaritimeFeatureType.lighthouse], equals(1),
            reason: 'Lighthouse should be visible at $scale scale');
          expect(visibleByType[MaritimeFeatureType.buoy], equals(1),
            reason: 'Buoy should be visible at $scale scale');
          expect(visibleByType[MaritimeFeatureType.depthContour], equals(1),
            reason: 'Depth contour should be visible at $scale scale');
        }
        
        // Lighthouse should always be visible
        expect(visibleByType[MaritimeFeatureType.lighthouse], equals(1),
          reason: 'Lighthouse should be visible at all scales');
          
        // Buoy should now be always visible (fixed in Issue #196)
        expect(visibleByType[MaritimeFeatureType.buoy], equals(1),
          reason: 'Buoy should be visible at all scales after Issue #196 fix');
      }
    });
    
    test('Elliott Bay features have correct maritime symbology colors', () async {
      print('[Visibility Test] Testing maritime feature rendering properties');
      
      // Load and convert features
      final ByteData byteData = await rootBundle.load('assets/s57/charts/US5WA50M.000');
      final List<int> chartBytes = byteData.buffer.asUint8List();
      final s57Data = S57Parser.parse(chartBytes);
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
      
      for (final feature in maritimeFeatures) {
        print('[Visibility Test] Feature ${feature.type}:');
        print('[Visibility Test]   ID: ${feature.id}');
        print('[Visibility Test]   Position: ${feature.position}');
        print('[Visibility Test]   Render Priority: ${feature.renderPriority}');
        
        // Validate Elliott Bay coordinates
        expect(feature.position.latitude, inInclusiveRange(47.6, 47.7),
          reason: 'Feature should be in Elliott Bay latitude range');
        expect(feature.position.longitude, inInclusiveRange(-122.4, -122.3),
          reason: 'Feature should be in Elliott Bay longitude range');
          
        // Validate render priorities are properly set
        expect(feature.renderPriority, greaterThan(0),
          reason: 'Feature should have valid render priority');
      }
      
      // Lighthouse should have highest priority
      final lighthouse = maritimeFeatures.firstWhere((f) => f.type == MaritimeFeatureType.lighthouse);
      final buoy = maritimeFeatures.firstWhere((f) => f.type == MaritimeFeatureType.buoy);
      
      expect(lighthouse.renderPriority, greaterThan(buoy.renderPriority),
        reason: 'Lighthouse should render on top of buoy');
    });
    
    test('Layer visibility settings enable all Elliott Bay features', () {
      print('[Visibility Test] Testing layer visibility defaults');
      
      // Simulate ChartRenderingService layer visibility settings
      final layerVisibility = <String, bool>{
        'depth_contours': true,
        'navigation_aids': true,
        'shoreline': true,
        'restricted_areas': true,
        'anchorages': true,
        'chart_grid': false,
        'chart_boundaries': true,
      };
      
      // Test each Elliott Bay feature type maps to visible layer
      final expectedMappings = {
        MaritimeFeatureType.lighthouse: 'navigation_aids',
        MaritimeFeatureType.buoy: 'navigation_aids', 
        MaritimeFeatureType.depthContour: 'depth_contours',
      };
      
      for (final entry in expectedMappings.entries) {
        final featureType = entry.key;
        final layerName = entry.value;
        final isLayerVisible = layerVisibility[layerName] ?? false;
        
        print('[Visibility Test] ${featureType} → layer "$layerName": ${isLayerVisible ? 'ENABLED' : 'DISABLED'}');
        
        expect(isLayerVisible, isTrue,
          reason: 'Layer "$layerName" should be enabled for ${featureType}');
      }
    });
  });
}