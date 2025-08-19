import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/metadata_parsing_exceptions.dart';

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
      throw MetadataParsingException('Invalid GeoJSON: Expected FeatureCollection');
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
        
        // Parse date with error handling
        DateTime lastUpdate;
        try {
          lastUpdate = DateTime.parse(properties['LAST_UPDATE'] as String);
        } catch (e) {
          throw DateParsingException(
            properties['LAST_UPDATE'] as String,
            data: {'chartId': properties['CHART']},
          );
        }

        // Parse edition number with fallback
        int edition = 0;
        if (properties['EDITION_NUM'] != null) {
          try {
            edition = int.parse(properties['EDITION_NUM'].toString());
          } catch (e) {
            _logger.warning('Invalid edition number for chart ${properties['CHART']}: ${properties['EDITION_NUM']}');
          }
        }

        // Parse update number with fallback
        int updateNumber = 0;
        if (properties['UPDATE_NUM'] != null) {
          try {
            updateNumber = int.parse(properties['UPDATE_NUM'].toString());
          } catch (e) {
            _logger.warning('Invalid update number for chart ${properties['CHART']}: ${properties['UPDATE_NUM']}');
          }
        }

        // Parse chart status
        ChartStatus status = ChartStatus.current;
        if (properties['STATUS'] != null) {
          status = _parseChartStatus(properties['STATUS'] as String);
        }

        // Build metadata map
        final metadata = _buildMetadataMap(properties);

        final chart = Chart(
          id: properties['CHART'] as String,
          title: properties['TITLE'] as String,
          scale: properties['SCALE'] as int,
          bounds: bounds,
          lastUpdate: lastUpdate,
          state: properties['STATE'] as String,
          type: parseChartUsageToType(properties['USAGE'] as String),
          edition: edition,
          updateNumber: updateNumber,
          source: ChartSource.noaa,
          status: status,
          metadata: metadata,
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
        throw InvalidGeometryException(
          'Unsupported geometry type: $type',
          data: {'geometryType': type}
        );
      }

      return GeographicBounds(
        north: maxLat,
        south: minLat,
        east: maxLng,
        west: minLng,
      );
    } catch (error) {
      if (error is InvalidGeometryException) {
        rethrow;
      }
      throw InvalidGeometryException(
        'Failed to extract bounds from geometry: $error',
        data: {'geometryType': type, 'originalError': error.toString()}
      );
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

  /// Parses NOAA chart status string to ChartStatus enum
  ChartStatus _parseChartStatus(String status) {
    switch (status.toLowerCase()) {
      case 'current':
        return ChartStatus.current;
      case 'superseded':
        return ChartStatus.superseded;
      case 'cancelled':
        return ChartStatus.cancelled;
      case 'preliminary':
        return ChartStatus.preliminary;
      default:
        return ChartStatus.current; // Default fallback
    }
  }

  /// Builds metadata map from NOAA properties
  Map<String, dynamic> _buildMetadataMap(Map<String, dynamic> properties) {
    final metadata = <String, dynamic>{};
    
    // Add all NOAA-specific fields to metadata
    final metadataFields = [
      'CELL_NAME',
      'REGION',
      'COMPILATION_SCALE',
      'DT_PUB',
      'ISSUE_DATE',
      'SOURCE_DATE_STRING',
      'EDITION_DATE',
      'RELEASE_DATE'
    ];
    
    for (final field in metadataFields) {
      if (properties.containsKey(field) && properties[field] != null) {
        // Convert field names to camelCase for consistency
        final camelCaseField = _toCamelCase(field);
        metadata[camelCaseField] = properties[field];
      }
    }
    
    return metadata;
  }

  /// Converts snake_case to camelCase
  String _toCamelCase(String snakeCase) {
    final parts = snakeCase.toLowerCase().split('_');
    if (parts.isEmpty) return snakeCase;
    
    return parts[0] + parts.skip(1).map((part) => 
      part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1)
    ).join('');
  }
}