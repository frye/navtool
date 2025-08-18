import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/services/noaa/chart_catalog_service.dart';
import 'package:navtool/core/services/noaa/state_region_mapping_service.dart';
import 'package:navtool/core/services/noaa/noaa_metadata_parser.dart';
import 'package:navtool/core/state/providers.dart';

/// Provider for NOAA metadata parser
final noaaMetadataParserProvider = Provider<NoaaMetadataParser>((ref) {
  return NoaaMetadataParserImpl(
    logger: ref.read(loggerProvider),
  );
});

/// Provider for chart catalog service
final chartCatalogServiceProvider = Provider<ChartCatalogService>((ref) {
  return ChartCatalogServiceImpl(
    cacheService: ref.read(cacheServiceProvider),
    logger: ref.read(loggerProvider),
  );
});

/// Provider for state region mapping service
final stateRegionMappingServiceProvider = Provider<StateRegionMappingService>((ref) {
  return StateRegionMappingServiceImpl(
    cacheService: ref.read(cacheServiceProvider),
    logger: ref.read(loggerProvider),
  );
});

/// Provider for NOAA chart discovery service
final noaaChartDiscoveryServiceProvider = Provider<NoaaChartDiscoveryService>((ref) {
  return NoaaChartDiscoveryServiceImpl(
    catalogService: ref.read(chartCatalogServiceProvider),
    mappingService: ref.read(stateRegionMappingServiceProvider),
    logger: ref.read(loggerProvider),
  );
});