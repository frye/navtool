/// S-57 Test Fixtures Utility for Real NOAA ENC Data Usage
/// 
/// Provides consistent access to real S-57 chart data for testing and development.
/// Uses real NOAA ENC fixtures to ensure marine navigation accuracy.
library;

import 'dart:io';
import 'dart:typed_data';
import '../../lib/core/services/s57/s57_models.dart';
import '../../lib/core/services/s57/s57_parser.dart';
import '../../lib/core/utils/zip_extractor.dart';

/// Utility class for loading real S-57 test fixtures consistently
class S57TestFixtures {
  /// Base path to S-57 test data
  static const String fixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  /// Path to NOAA ENC ZIP files
  static const String zipFixturesPath = 'test/fixtures/charts/noaa_enc';
  
  /// Cache for parsed chart data (performance optimization)
  static final Map<String, S57Data> _parsedCache = {};
  
  /// Cache for raw chart bytes (performance optimization)
  static final Map<String, List<int>> _bytesCache = {};

  /// Load Elliott Bay harbor chart raw S-57 data (US5WA50M.000)
  /// Returns 411KB of real NOAA S-57 data for harbor-scale navigation
  static Future<List<int>> loadElliottBayChart() async {
    const cacheKey = 'US5WA50M_raw';
    
    if (_bytesCache.containsKey(cacheKey)) {
      print('[S57TestFixtures] Returning cached Elliott Bay raw data (${_bytesCache[cacheKey]!.length} bytes)');
      return _bytesCache[cacheKey]!;
    }
    
    try {
      // Try direct .000 file first (fastest)
      final directFile = File('$fixturesPath/US5WA50M/US5WA50M.000');
      if (await directFile.exists()) {
        final bytes = await directFile.readAsBytes();
        print('[S57TestFixtures] Loaded Elliott Bay from direct file: ${bytes.length} bytes');
        _bytesCache[cacheKey] = bytes;
        return bytes;
      }
      
      // Fallback: Extract from ZIP file
      final zipFile = File('$zipFixturesPath/US5WA50M_harbor_elliott_bay.zip');
      if (await zipFile.exists()) {
        final zipBytes = await zipFile.readAsBytes();
        final extractedBytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
        
        if (extractedBytes != null) {
          print('[S57TestFixtures] Extracted Elliott Bay from ZIP: ${extractedBytes.length} bytes');
          _bytesCache[cacheKey] = extractedBytes;
          return extractedBytes;
        }
      }
      
      throw Exception('Elliott Bay S-57 data not found in $fixturesPath or $zipFixturesPath');
      
    } catch (e) {
      print('[S57TestFixtures] ERROR loading Elliott Bay chart: $e');
      rethrow;
    }
  }

  /// Load Puget Sound coastal chart raw S-57 data (US3WA01M.000)  
  /// Returns 1.5MB of real NOAA S-57 data for coastal-scale navigation
  static Future<List<int>> loadPugetSoundChart() async {
    const cacheKey = 'US3WA01M_raw';
    
    if (_bytesCache.containsKey(cacheKey)) {
      print('[S57TestFixtures] Returning cached Puget Sound raw data (${_bytesCache[cacheKey]!.length} bytes)');
      return _bytesCache[cacheKey]!;
    }
    
    try {
      // Try direct .000 file first (fastest)
      final directFile = File('$fixturesPath/US3WA01M/US3WA01M.000');
      if (await directFile.exists()) {
        final bytes = await directFile.readAsBytes();
        print('[S57TestFixtures] Loaded Puget Sound from direct file: ${bytes.length} bytes');
        _bytesCache[cacheKey] = bytes;
        return bytes;
      }
      
      // Fallback: Extract from ZIP file
      final zipFile = File('$zipFixturesPath/US3WA01M_coastal_puget_sound.zip');
      if (await zipFile.exists()) {
        final zipBytes = await zipFile.readAsBytes();
        final extractedBytes = await ZipExtractor.extractS57FromZip(zipBytes, 'US3WA01M');
        
        if (extractedBytes != null) {
          print('[S57TestFixtures] Extracted Puget Sound from ZIP: ${extractedBytes.length} bytes');
          _bytesCache[cacheKey] = extractedBytes;
          return extractedBytes;
        }
      }
      
      throw Exception('Puget Sound S-57 data not found in $fixturesPath or $zipFixturesPath');
      
    } catch (e) {
      print('[S57TestFixtures] ERROR loading Puget Sound chart: $e');
      rethrow;
    }
  }

  /// Load parsed Elliott Bay chart (cached for performance)
  /// Returns complete S57Data with all maritime features parsed
  static Future<S57Data> loadParsedElliottBay() async {
    const cacheKey = 'US5WA50M_parsed';
    
    if (_parsedCache.containsKey(cacheKey)) {
      print('[S57TestFixtures] Returning cached Elliott Bay parsed data');
      return _parsedCache[cacheKey]!;
    }
    
    try {
      print('[S57TestFixtures] Parsing Elliott Bay S-57 data...');
      final rawBytes = await loadElliottBayChart();
      final parsedData = S57Parser.parse(rawBytes);
      
      print('[S57TestFixtures] Elliott Bay parsing complete:');
      print('[S57TestFixtures]   Features: ${parsedData.features.length}');
      print('[S57TestFixtures]   Bounds: ${parsedData.bounds.toMap()}');
      print('[S57TestFixtures]   Title: ${parsedData.metadata.title ?? 'Unknown'}');
      
      // Cache the parsed result for future use
      _parsedCache[cacheKey] = parsedData;
      return parsedData;
      
    } catch (e) {
      print('[S57TestFixtures] ERROR parsing Elliott Bay chart: $e');
      rethrow;
    }
  }

  /// Load parsed Puget Sound chart (cached for performance)
  /// Returns complete S57Data with all maritime features parsed  
  static Future<S57Data> loadParsedPugetSound() async {
    const cacheKey = 'US3WA01M_parsed';
    
    if (_parsedCache.containsKey(cacheKey)) {
      print('[S57TestFixtures] Returning cached Puget Sound parsed data');
      return _parsedCache[cacheKey]!;
    }
    
    try {
      print('[S57TestFixtures] Parsing Puget Sound S-57 data...');
      final rawBytes = await loadPugetSoundChart();
      final parsedData = S57Parser.parse(rawBytes);
      
      print('[S57TestFixtures] Puget Sound parsing complete:');
      print('[S57TestFixtures]   Features: ${parsedData.features.length}');
      print('[S57TestFixtures]   Bounds: ${parsedData.bounds.toMap()}');
      print('[S57TestFixtures]   Title: ${parsedData.metadata.title ?? 'Unknown'}');
      
      // Cache the parsed result for future use
      _parsedCache[cacheKey] = parsedData;
      return parsedData;
      
    } catch (e) {
      print('[S57TestFixtures] ERROR parsing Puget Sound chart: $e');
      rethrow;
    }
  }

  /// Get chart metadata validation helper
  /// Validates that loaded charts have expected characteristics
  static Map<String, dynamic> validateChartMetadata(S57Data chartData, String expectedChartId) {
    final validation = <String, dynamic>{
      'chartId': expectedChartId,
      'valid': true,
      'issues': <String>[],
      'featureCount': chartData.features.length,
      'bounds': chartData.bounds.toMap(),
      'title': chartData.metadata.title,
    };
    
    // Validate minimum feature count for real charts
    if (chartData.features.length < 10) {
      validation['issues'].add('Low feature count: ${chartData.features.length} (expected 50+ for real charts)');
      validation['valid'] = false;
    }
    
    // Validate geographic bounds are reasonable for Pacific Northwest
    final bounds = chartData.bounds;
    if (bounds.west > -122.0 || bounds.east < -122.5 || bounds.north < 47.5 || bounds.south > 47.7) {
      validation['issues'].add('Geographic bounds outside expected Elliott Bay area');
      validation['valid'] = false;
    }
    
    // Check for key maritime feature types
    final featureTypes = chartData.features.map((f) => f.featureType.acronym).toSet();
    final expectedTypes = {'DEPCNT', 'DEPARE', 'COALNE', 'SOUNDG'};
    final missingTypes = expectedTypes.difference(featureTypes);
    if (missingTypes.isNotEmpty) {
      validation['issues'].add('Missing key feature types: ${missingTypes.join(', ')}');
    }
    
    validation['featureTypes'] = featureTypes.toList();
    validation['hasKeyFeatures'] = missingTypes.isEmpty;
    
    return validation;
  }

  /// Load chart by ID with error handling
  /// Provides unified interface for loading any supported test chart
  static Future<List<int>?> loadChartById(String chartId) async {
    try {
      switch (chartId) {
        case 'US5WA50M':
          return await loadElliottBayChart();
        case 'US3WA01M':  
          return await loadPugetSoundChart();
        default:
          print('[S57TestFixtures] Unsupported chart ID: $chartId');
          return null;
      }
    } catch (e) {
      print('[S57TestFixtures] ERROR loading chart $chartId: $e');
      return null;
    }
  }

  /// Load parsed chart by ID with error handling
  /// Provides unified interface for loading any supported parsed test chart
  static Future<S57Data?> loadParsedChartById(String chartId) async {
    try {
      switch (chartId) {
        case 'US5WA50M':
          return await loadParsedElliottBay();
        case 'US3WA01M':
          return await loadParsedPugetSound();
        default:
          print('[S57TestFixtures] Unsupported chart ID: $chartId');
          return null;
      }
    } catch (e) {
      print('[S57TestFixtures] ERROR loading parsed chart $chartId: $e');
      return null;
    }
  }

  /// Check if chart data is available for a given chart ID
  static Future<bool> isChartAvailable(String chartId) async {
    try {
      final data = await loadChartById(chartId);
      return data != null && data.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear all caches (for testing)
  static void clearCaches() {
    _parsedCache.clear();
    _bytesCache.clear();
    print('[S57TestFixtures] All caches cleared');
  }

  /// Get cache statistics  
  static Map<String, dynamic> getCacheStats() {
    return {
      'parsedCacheSize': _parsedCache.length,
      'bytesCacheSize': _bytesCache.length,
      'parsedCharts': _parsedCache.keys.toList(),
      'cachedCharts': _bytesCache.keys.toList(),
    };
  }

  /// Get available test charts
  static List<String> getAvailableCharts() {
    return ['US5WA50M', 'US3WA01M'];
  }

  /// Get chart description
  static String getChartDescription(String chartId) {
    return switch (chartId) {
      'US5WA50M' => 'Elliott Bay Harbor Chart - Harbor-scale (1:20,000) - Seattle/Elliott Bay region',
      'US3WA01M' => 'Puget Sound Coastal Chart - Coastal-scale (1:90,000) - Broader Puget Sound region',
      _ => 'Unknown chart ID: $chartId',
    };
  }
}