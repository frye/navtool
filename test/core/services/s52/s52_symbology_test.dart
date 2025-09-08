import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/s52/s52_color_tables.dart';
import 'package:navtool/core/services/s52/s52_symbol_catalog.dart';
import 'package:navtool/core/services/s52/s52_symbol_manager.dart';

void main() {
  group('S-52 Symbology Tests', () {
    setUp(() {
      // Initialize symbol system
      S52SymbolCatalog.initialize();
    });

    group('S-52 Color Tables', () {
      test('should provide all display modes', () {
        for (final mode in S52DisplayMode.values) {
          final colorTable = S52ColorTables.getColorTable(mode);
          expect(colorTable.mode, equals(mode));
          expect(colorTable.colors.isNotEmpty, isTrue);
        }
      });

      test('should have essential marine colors for day mode', () {
        final dayTable = S52ColorTables.getColorTable(S52DisplayMode.day);
        
        // Verify essential color tokens exist
        expect(dayTable.hasColor(S52ColorToken.depare1), isTrue, 
               reason: 'Day mode should have shallow water color');
        expect(dayTable.hasColor(S52ColorToken.landa), isTrue,
               reason: 'Day mode should have land area color');
        expect(dayTable.hasColor(S52ColorToken.lights), isTrue,
               reason: 'Day mode should have lights color');
        expect(dayTable.hasColor(S52ColorToken.danger), isTrue,
               reason: 'Day mode should have danger color');
      });

      test('should use red-shifted colors for night mode', () {
        final nightTable = S52ColorTables.getColorTable(S52DisplayMode.night);
        final dayTable = S52ColorTables.getColorTable(S52DisplayMode.day);
        
        // Night mode should be different from day mode
        expect(nightTable.getColor(S52ColorToken.chblk), 
               isNot(equals(dayTable.getColor(S52ColorToken.chblk))));
        
        // Night coastline should be reddish for visibility
        final nightCoastline = nightTable.getColor(S52ColorToken.cstln);
        expect(nightCoastline.red, greaterThan(nightCoastline.blue),
               reason: 'Night coastline should be red-shifted');
      });

      test('should provide intermediate colors for dusk mode', () {
        final duskTable = S52ColorTables.getColorTable(S52DisplayMode.dusk);
        final dayTable = S52ColorTables.getColorTable(S52DisplayMode.day);
        final nightTable = S52ColorTables.getColorTable(S52DisplayMode.night);
        
        // Dusk should be different from both day and night
        final duskSea = duskTable.getColor(S52ColorToken.depare3);
        final daySea = dayTable.getColor(S52ColorToken.depare3);
        final nightSea = nightTable.getColor(S52ColorToken.depare3);
        
        expect(duskSea, isNot(equals(daySea)));
        expect(duskSea, isNot(equals(nightSea)));
      });

      test('should handle color with alpha', () {
        final dayTable = S52ColorTables.getColorTable(S52DisplayMode.day);
        final colorWithAlpha = dayTable.getColorWithAlpha(S52ColorToken.lights, 128);
        
        expect(colorWithAlpha.alpha, equals(128));
        expect(colorWithAlpha.red, equals(dayTable.getColor(S52ColorToken.lights).red));
      });
    });

    group('S-52 Symbol Catalog', () {
      test('should be initialized properly', () {
        S52SymbolCatalog.initialize();
        
        // Should have symbols for common maritime features
        final lighthouseSymbols = S52SymbolCatalog.getSymbolsForFeatureType(
          MaritimeFeatureType.lighthouse,
        );
        expect(lighthouseSymbols.isNotEmpty, isTrue,
               reason: 'Should have lighthouse symbols');

        final buoySymbols = S52SymbolCatalog.getSymbolsForFeatureType(
          MaritimeFeatureType.buoy,
        );
        expect(buoySymbols.isNotEmpty, isTrue,
               reason: 'Should have buoy symbols');
      });

      test('should find symbols by code', () {
        final lighthouseSymbol = S52SymbolCatalog.getSymbolByCode('LIGHTS1');
        expect(lighthouseSymbol, isNotNull);
        expect(lighthouseSymbol!.name, equals('Light - Major'));
        expect(lighthouseSymbol.featureTypes, contains(MaritimeFeatureType.lighthouse));
      });

      test('should match symbols based on attributes', () {
        // Test lateral buoy matching
        final portBuoySymbol = S52SymbolCatalog.getBestSymbolForFeature(
          MaritimeFeatureType.buoy,
          {'CATBOY': '2', 'COLOUR': '3'}, // Port hand, green
        );
        expect(portBuoySymbol, isNotNull);

        final starboardBuoySymbol = S52SymbolCatalog.getBestSymbolForFeature(
          MaritimeFeatureType.buoy,
          {'CATBOY': '1', 'COLOUR': '4'}, // Starboard hand, red
        );
        expect(starboardBuoySymbol, isNotNull);
      });

      test('should respect scale visibility', () {
        final beaconSymbol = S52SymbolCatalog.getSymbolByCode('BEACON1');
        expect(beaconSymbol, isNotNull);
        
        // Should be visible at coastal scale
        expect(beaconSymbol!.isVisibleAtScale(50000), isTrue);
        
        // Should not be visible at very small scale
        expect(beaconSymbol.isVisibleAtScale(500000), isFalse);
      });
    });

    group('S-52 Symbol Manager', () {
      late S52SymbolManager symbolManager;

      setUp(() async {
        symbolManager = S52SymbolManager.instance;
        await symbolManager.initialize();
      });

      test('should initialize without errors', () async {
        expect(symbolManager, isNotNull);
        
        // Should have cached some common symbols
        final stats = symbolManager.getCacheStats();
        expect(stats['totalCached'], greaterThan(0));
      });

      test('should create symbol widgets', () {
        final lighthouse = PointFeature(
          id: 'test_lighthouse',
          type: MaritimeFeatureType.lighthouse,
          position: const LatLng(47.6062, -122.3321), // Seattle
        );

        final widget = symbolManager.getSymbolWidget(lighthouse, 24.0);
        expect(widget, isNotNull);
        expect(widget, isA<CustomPaint>());
      });

      test('should cache symbol widgets efficiently', () {
        final buoy = PointFeature(
          id: 'test_buoy',
          type: MaritimeFeatureType.buoy,
          position: const LatLng(47.6062, -122.3321),
          attributes: {'CATBOY': '1', 'COLOUR': '4'}, // Starboard lateral
        );

        // First call should create and cache
        final widget1 = symbolManager.getSymbolWidget(buoy, 16.0);
        final stats1 = symbolManager.getCacheStats();

        // Second call should return cached version  
        final widget2 = symbolManager.getSymbolWidget(buoy, 16.0);
        final stats2 = symbolManager.getCacheStats();

        expect(widget1, equals(widget2));
        expect(stats2['symbolWidgets'], equals(stats1['symbolWidgets']),
               reason: 'Should reuse cached widget');
      });

      test('should handle display mode changes', () {
        final beacon = PointFeature(
          id: 'test_beacon',
          type: MaritimeFeatureType.beacon,
          position: const LatLng(47.6062, -122.3321),
        );

        // Get widget in day mode
        symbolManager.setDisplayMode(S52DisplayMode.day);
        final dayWidget = symbolManager.getSymbolWidget(beacon, 20.0);

        // Get widget in night mode
        symbolManager.setDisplayMode(S52DisplayMode.night);
        final nightWidget = symbolManager.getSymbolWidget(beacon, 20.0);

        // Should be different widgets due to color changes
        expect(dayWidget, isNotNull);
        expect(nightWidget, isNotNull);
        expect(dayWidget, isNot(equals(nightWidget)));
      });

      test('should provide symbol painters for direct rendering', () {
        final obstruction = PointFeature(
          id: 'test_obstruction',
          type: MaritimeFeatureType.obstruction,
          position: const LatLng(47.6062, -122.3321),
        );

        final painter = symbolManager.getSymbolPainter(obstruction, 18.0);
        expect(painter, isNotNull);
        expect(painter, isA<CustomPainter>());
      });

      test('should optimize cache when it gets too large', () {
        // Fill cache with many symbols
        for (int i = 0; i < 600; i++) {
          final feature = PointFeature(
            id: 'test_$i',
            type: MaritimeFeatureType.buoy,
            position: LatLng(47.0 + i * 0.001, -122.0 + i * 0.001),
          );
          symbolManager.getSymbolWidget(feature, 16.0);
        }

        final statsBefore = symbolManager.getCacheStats();
        symbolManager.optimizeCache(maxSymbols: 500);
        final statsAfter = symbolManager.getCacheStats();

        expect(statsAfter['symbolWidgets']!, 
               lessThanOrEqualTo(statsBefore['symbolWidgets']!));
      });
    });

    group('S-52 Maritime Chart Integration', () {
      test('should render Elliott Bay test features with S-52 compliance', () {
        // Elliott Bay coordinates (from test data)
        const elliottBayCenter = LatLng(47.6062, -122.3321);
        
        // Create realistic maritime features for Elliott Bay
        final maritimeFeatures = [
          // Lighthouse at West Point  
          PointFeature(
            id: 'west_point_light',
            type: MaritimeFeatureType.lighthouse,
            position: const LatLng(47.6623, -122.4194),
            attributes: {'OBJNAM': 'West Point Light'},
          ),
          
          // Cardinal buoy
          PointFeature(
            id: 'elliott_cardinal',
            type: MaritimeFeatureType.buoy,
            position: const LatLng(47.6200, -122.3800),
            attributes: {'CATBOY': '2', 'COLOUR': '1'}, // Cardinal north
          ),
          
          // Port lateral buoy
          PointFeature(
            id: 'elliott_port_lateral',
            type: MaritimeFeatureType.buoy,
            position: const LatLng(47.6100, -122.3600),
            attributes: {'CATBOY': '2', 'COLOUR': '3'}, // Port hand, green
          ),
          
          // Wreck marker
          PointFeature(
            id: 'elliott_wreck',
            type: MaritimeFeatureType.wrecks,
            position: const LatLng(47.6000, -122.3500),
            attributes: {'WATLEV': '3'}, // Covers at high water
          ),
        ];

        final symbolManager = S52SymbolManager.instance;
        
        // Test that all features can be symbolized
        for (final feature in maritimeFeatures) {
          final symbolWidget = symbolManager.getSymbolWidget(feature, 20.0);
          expect(symbolWidget, isNotNull, 
                 reason: 'Feature ${feature.id} should have S-52 symbol');

          final symbolPainter = symbolManager.getSymbolPainter(feature, 20.0);
          expect(symbolPainter, isNotNull,
                 reason: 'Feature ${feature.id} should have S-52 painter');
        }
      });

      test('should handle scale-dependent symbol visibility', () {
        final symbolManager = S52SymbolManager.instance;
        
        final buoy = PointFeature(
          id: 'scale_test_buoy',
          type: MaritimeFeatureType.buoy,
          position: const LatLng(47.6062, -122.3321),
        );

        // Test at harbor scale (buoy should be visible)
        symbolManager.setScale(25000);
        final harborSymbol = symbolManager.getSymbolWidget(buoy, 16.0);
        expect(harborSymbol, isNotNull);

        // Test at overview scale (buoy should still be available, 
        // but visibility is handled by symbol definition)
        symbolManager.setScale(1000000);
        final overviewSymbol = symbolManager.getSymbolWidget(buoy, 16.0);
        expect(overviewSymbol, isNotNull);
      });

      test('should validate S-52 color compliance in different modes', () {
        final colorModes = [
          S52DisplayMode.day,
          S52DisplayMode.night,
          S52DisplayMode.dusk,
        ];

        for (final mode in colorModes) {
          final colorTable = S52ColorTables.getColorTable(mode);
          
          // Essential maritime colors should exist
          expect(colorTable.hasColor(S52ColorToken.danger), isTrue,
                 reason: '$mode should have danger color');
          expect(colorTable.hasColor(S52ColorToken.lights), isTrue,
                 reason: '$mode should have lights color');
          expect(colorTable.hasColor(S52ColorToken.cstln), isTrue,
                 reason: '$mode should have coastline color');
          
          // Colors should be appropriate for mode
          final dangerColor = colorTable.getColor(S52ColorToken.danger);
          if (mode == S52DisplayMode.night) {
            // Night mode danger should be red but not harsh white
            expect(dangerColor.red, greaterThan(dangerColor.blue));
            expect(dangerColor.red, greaterThan(dangerColor.green));
          }
        }
      });
    });

    group('S-52 Performance and Optimization', () {
      test('should handle large numbers of symbols efficiently', () {
        final symbolManager = S52SymbolManager.instance;
        final stopwatch = Stopwatch()..start();
        
        // Create 100 different maritime features
        for (int i = 0; i < 100; i++) {
          final feature = PointFeature(
            id: 'perf_test_$i',
            type: MaritimeFeatureType.values[i % MaritimeFeatureType.values.length],
            position: LatLng(47.0 + i * 0.01, -122.0 + i * 0.01),
          );
          
          symbolManager.getSymbolWidget(feature, 16.0);
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time (adjust threshold as needed)
        expect(stopwatch.elapsedMilliseconds, lessThan(5000),
               reason: 'Symbol creation should be performant');
      });

      test('should maintain cache efficiency', () {
        final symbolManager = S52SymbolManager.instance;
        
        // Clear cache to start fresh
        symbolManager.clearCache();
        
        final feature = PointFeature(
          id: 'cache_test',
          type: MaritimeFeatureType.lighthouse,
          position: const LatLng(47.6062, -122.3321),
        );

        // First access - should cache
        final widget1 = symbolManager.getSymbolWidget(feature, 24.0);
        final stats1 = symbolManager.getCacheStats();
        
        // Second access - should use cache
        final startTime = DateTime.now();
        final widget2 = symbolManager.getSymbolWidget(feature, 24.0);
        final endTime = DateTime.now();
        final stats2 = symbolManager.getCacheStats();
        
        expect(widget1, equals(widget2));
        expect(stats2['symbolWidgets'], equals(stats1['symbolWidgets']));
        
        // Cached access should be very fast
        final accessTime = endTime.difference(startTime).inMicroseconds;
        expect(accessTime, lessThan(1000), // Less than 1ms
               reason: 'Cached symbol access should be very fast');
      });
    });
  });
}