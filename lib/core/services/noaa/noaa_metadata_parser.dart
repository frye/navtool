import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';

/// Abstract interface for parsing NOAA metadata into Chart objects
abstract class NoaaMetadataParser {
  /// Parses GeoJSON feature collection into Chart objects
  Future<List<Chart>> parseGeoJsonToCharts(Map<String, dynamic> geoJsonData);

  /// Converts NOAA usage string to ChartType enum
  ChartType parseChartUsageToType(String usage);

  /// Extracts geographic bounds from GeoJSON geometry
  GeographicBounds extractBoundsFromGeometry(Map<String, dynamic> geometry);

  /// Validates that required properties are present in feature
  bool validateRequiredProperties(Map<String, dynamic> properties);
}

/// Implementation of NOAA metadata parser
class NoaaMetadataParserImpl implements NoaaMetadataParser {
  final AppLogger _logger;

  NoaaMetadataParserImpl({required AppLogger logger}) : _logger = logger;

  @override
  Future<List<Chart>> parseGeoJsonToCharts(Map<String, dynamic> geoJsonData) async {
    if (geoJsonData['type'] != 'FeatureCollection') {
      throw AppError.parsing('Invalid GeoJSON: Expected FeatureCollection');
    }

    final features = geoJsonData['features'] as List<dynamic>? ?? [];
    final charts = <Chart>[];

    for (final feature in features) {
      try {
        final properties = feature['properties'] as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;

        if (!validateRequiredProperties(properties)) {
          _logger.warning('Skipping chart feature with missing required properties: ${properties['CHART']}');
          continue;
        }

        if (geometry['type'] != 'Polygon' && geometry['type'] != 'MultiPolygon') {
          _logger.warning('Skipping chart feature with invalid geometry: ${properties['CHART']}');
          continue;
        }

        final bounds = extractBoundsFromGeometry(geometry);
        final lastUpdate = DateTime.parse(properties['LAST_UPDATE'] as String);

        final chart = Chart(
          id: properties['CHART'] as String,
          title: properties['TITLE'] as String,
          scale: properties['SCALE'] as int,
          bounds: bounds,
          lastUpdate: lastUpdate,
          state: properties['STATE'] as String,
          type: parseChartUsageToType(properties['USAGE'] as String),
        );

        charts.add(chart);
      } catch (error) {
        _logger.warning('Failed to parse chart feature', exception: error);
        continue;
      }
    }

    _logger.info('Parsed ${charts.length} charts from GeoJSON data');
    return charts;
  }

  @override
  ChartType parseChartUsageToType(String usage) {
    switch (usage.toLowerCase()) {
      case 'harbor':
        return ChartType.harbor;
      case 'approach':
        return ChartType.approach;
      case 'coastal':
        return ChartType.coastal;
      case 'general':
        return ChartType.general;
      case 'overview':
        return ChartType.overview;
      case 'berthing':
        return ChartType.berthing;
      default:
        return ChartType.harbor; // Default fallback
    }
  }

  @override
  GeographicBounds extractBoundsFromGeometry(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String;
    final coordinates = geometry['coordinates'] as List<dynamic>;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;

    try {
      if (type == 'Polygon') {
        final ring = coordinates[0] as List<dynamic>;
        for (final coord in ring) {
          final lng = (coord[0] as num).toDouble();
          final lat = (coord[1] as num).toDouble();
          
          minLat = lat < minLat ? lat : minLat;
          maxLat = lat > maxLat ? lat : maxLat;
          minLng = lng < minLng ? lng : minLng;
          maxLng = lng > maxLng ? lng : maxLng;
        }
      } else if (type == 'MultiPolygon') {
        for (final polygon in coordinates) {
          final ring = polygon[0] as List<dynamic>;
          for (final coord in ring) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            
            minLat = lat < minLat ? lat : minLat;
            maxLat = lat > maxLat ? lat : maxLat;
            minLng = lng < minLng ? lng : minLng;
            maxLng = lng > maxLng ? lng : maxLng;
          }
        }
      } else {
        throw AppError.parsing('Unsupported geometry type: $type');
      }

      return GeographicBounds(
        north: maxLat,
        south: minLat,
        east: maxLng,
        west: minLng,
      );
    } catch (error) {
      throw AppError.parsing('Failed to extract bounds from geometry', originalError: error);
    }
  }

  @override
  bool validateRequiredProperties(Map<String, dynamic> properties) {
    final requiredFields = ['CHART', 'TITLE', 'SCALE', 'LAST_UPDATE', 'STATE', 'USAGE'];
    
    for (final field in requiredFields) {
      final value = properties[field];
      if (value == null || (value is String && value.trim().isEmpty)) {
        return false;
      }
    }
    
    return true;
  }
}