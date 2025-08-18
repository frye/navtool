import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/models/chart.dart';

void main() {
  group('NOAA Providers Registration Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('should register noaaMetadataParserProvider successfully', () {
      // Act
      final parser = container.read(noaaMetadataParserProvider);
      
      // Assert
      expect(parser, isA<NoaaMetadataParser>());
      expect(parser, isNotNull);
    });

    test('should register chartCatalogServiceProvider successfully', () {
      // Act
      final catalogService = container.read(chartCatalogServiceProvider);
      
      // Assert
      expect(catalogService, isA<ChartCatalogService>());
      expect(catalogService, isNotNull);
    });

    test('should register stateRegionMappingServiceProvider successfully', () {
      // Act
      final mappingService = container.read(stateRegionMappingServiceProvider);
      
      // Assert
      expect(mappingService, isA<StateRegionMappingService>());
      expect(mappingService, isNotNull);
    });

    test('should register noaaChartDiscoveryServiceProvider successfully', () {
      // Act
      final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
      
      // Assert
      expect(discoveryService, isA<NoaaChartDiscoveryService>());
      expect(discoveryService, isNotNull);
    });

    test('should properly inject dependencies in discovery service', () {
      // Act
      final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
      final catalogService = container.read(chartCatalogServiceProvider);
      final mappingService = container.read(stateRegionMappingServiceProvider);
      
      // Assert
      expect(discoveryService, isNotNull);
      expect(catalogService, isNotNull);
      expect(mappingService, isNotNull);
      
      // Verify that the discovery service uses the injected dependencies
      expect(discoveryService, isA<NoaaChartDiscoveryServiceImpl>());
    });

    test('should create singleton instances', () {
      // Act
      final parser1 = container.read(noaaMetadataParserProvider);
      final parser2 = container.read(noaaMetadataParserProvider);
      
      final catalog1 = container.read(chartCatalogServiceProvider);
      final catalog2 = container.read(chartCatalogServiceProvider);
      
      final mapping1 = container.read(stateRegionMappingServiceProvider);
      final mapping2 = container.read(stateRegionMappingServiceProvider);
      
      final discovery1 = container.read(noaaChartDiscoveryServiceProvider);
      final discovery2 = container.read(noaaChartDiscoveryServiceProvider);
      
      // Assert
      expect(identical(parser1, parser2), isTrue);
      expect(identical(catalog1, catalog2), isTrue);
      expect(identical(mapping1, mapping2), isTrue);
      expect(identical(discovery1, discovery2), isTrue);
    });

    test('should handle provider disposal correctly', () {
      // Act
      final discoveryService = container.read(noaaChartDiscoveryServiceProvider);
      
      // Assert - Should not throw when container is disposed
      expect(discoveryService, isNotNull);
      expect(() => container.dispose(), returnsNormally);
    });

    test('should allow provider override for testing', () {
      // Arrange
      final mockDiscoveryService = MockNoaaChartDiscoveryService();
      final testContainer = ProviderContainer(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWith((ref) => mockDiscoveryService),
        ],
      );

      try {
        // Act
        final discoveryService = testContainer.read(noaaChartDiscoveryServiceProvider);
        
        // Assert
        expect(discoveryService, equals(mockDiscoveryService));
      } finally {
        testContainer.dispose();
      }
    });
  });
}

// Mock class for testing provider overrides
class MockNoaaChartDiscoveryService implements NoaaChartDiscoveryService {
  @override
  Future<List<Chart>> discoverChartsByState(String state) async => [];
  
  @override
  Future<List<Chart>> searchCharts(String query, {Map<String, String>? filters}) async => [];
  
  @override
  Future<Chart?> getChartMetadata(String chartId) async => null;
  
  @override
  Stream<List<Chart>> watchChartsForState(String state) => Stream.value([]);
  
  @override
  Future<bool> refreshCatalog({bool force = false}) async => true;
}