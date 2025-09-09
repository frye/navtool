import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../database_storage_service.dart';
import '../s57/s57_parser.dart';
import '../compression_service.dart';
import '../../models/chart.dart';
import '../../models/geographic_bounds.dart';
import '../../logging/app_logger.dart';

/// Chart Storage Analysis Results
class ChartStorageAnalysis {
  final String chartId;
  final int originalSize;
  final int storedSize;
  final int featureCount;
  final Duration parseTime;
  final Duration storeTime;
  final Duration retrievalTime;
  final double compressionRatio;
  final Map<String, int> featureDistribution;
  final StorageEfficiencyMetrics efficiency;

  const ChartStorageAnalysis({
    required this.chartId,
    required this.originalSize,
    required this.storedSize,
    required this.featureCount,
    required this.parseTime,
    required this.storeTime,
    required this.retrievalTime,
    required this.compressionRatio,
    required this.featureDistribution,
    required this.efficiency,
  });

  /// Calculate storage efficiency score (0-100)
  double get efficiencyScore {
    final compressionScore = (1.0 - compressionRatio) * 40; // 40% weight
    final speedScore = _calculateSpeedScore() * 30; // 30% weight
    final structureScore = _calculateStructureScore() * 30; // 30% weight
    
    return (compressionScore + speedScore + structureScore).clamp(0.0, 100.0);
  }

  double _calculateSpeedScore() {
    // Score based on sub-100ms lookup requirement
    final retrievalMs = retrievalTime.inMilliseconds;
    if (retrievalMs <= 50) return 100.0;
    if (retrievalMs <= 100) return 80.0;
    if (retrievalMs <= 200) return 60.0;
    return 40.0;
  }

  double _calculateStructureScore() {
    // Score based on feature organization efficiency
    final avgFeaturesPerType = featureCount / featureDistribution.length;
    if (avgFeaturesPerType > 10) return 100.0;
    if (avgFeaturesPerType > 5) return 80.0;
    return 60.0;
  }

  @override
  String toString() {
    return '''
Chart Storage Analysis: $chartId
================================
Size Metrics:
  Original: ${_formatBytes(originalSize)}
  Stored: ${_formatBytes(storedSize)}
  Compression Ratio: ${(compressionRatio * 100).toStringAsFixed(1)}%
  
Performance Metrics:
  Parse Time: ${parseTime.inMilliseconds}ms
  Store Time: ${storeTime.inMilliseconds}ms
  Retrieval Time: ${retrievalTime.inMilliseconds}ms
  
Feature Distribution:
${featureDistribution.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}
  
Efficiency Score: ${efficiencyScore.toStringAsFixed(1)}/100
Storage Overhead: ${efficiency.storageOverheadPercent.toStringAsFixed(1)}%
''';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Storage efficiency metrics
class StorageEfficiencyMetrics {
  final double storageOverheadPercent;
  final double spatialIndexEfficiency;
  final int metadataSize;
  final bool meetsPerformanceTargets;

  const StorageEfficiencyMetrics({
    required this.storageOverheadPercent,
    required this.spatialIndexEfficiency,
    required this.metadataSize,
    required this.meetsPerformanceTargets,
  });
}

/// Batch analysis results for multiple charts
class BatchStorageAnalysis {
  final List<ChartStorageAnalysis> analyses;
  final DateTime analysisTime;

  const BatchStorageAnalysis({
    required this.analyses,
    required this.analysisTime,
  });

  /// Calculate overall efficiency statistics
  Map<String, dynamic> get summary {
    if (analyses.isEmpty) return {};

    final totalOriginalSize = analyses.fold<int>(0, (sum, a) => sum + a.originalSize);
    final totalStoredSize = analyses.fold<int>(0, (sum, a) => sum + a.storedSize);
    final avgCompressionRatio = analyses.fold<double>(0, (sum, a) => sum + a.compressionRatio) / analyses.length;
    final avgRetrievalTime = analyses.fold<int>(0, (sum, a) => sum + a.retrievalTime.inMilliseconds) / analyses.length;
    final avgEfficiencyScore = analyses.fold<double>(0, (sum, a) => sum + a.efficiencyScore) / analyses.length;
    
    final chartsUnder100ms = analyses.where((a) => a.retrievalTime.inMilliseconds < 100).length;
    final performanceCompliance = (chartsUnder100ms / analyses.length) * 100;

    return {
      'charts_analyzed': analyses.length,
      'total_original_size': totalOriginalSize,
      'total_stored_size': totalStoredSize,
      'overall_compression_ratio': avgCompressionRatio,
      'avg_retrieval_time_ms': avgRetrievalTime.round(),
      'avg_efficiency_score': avgEfficiencyScore,
      'performance_compliance_percent': performanceCompliance,
      'charts_meeting_100ms_target': chartsUnder100ms,
    };
  }

  @override
  String toString() {
    final s = summary;
    return '''
Batch Storage Analysis Report
=============================
Analysis Time: $analysisTime
Charts Analyzed: ${s['charts_analyzed']}

Storage Summary:
  Total Original Size: ${_formatBytes(s['total_original_size'])}
  Total Stored Size: ${_formatBytes(s['total_stored_size'])}
  Overall Compression: ${(s['overall_compression_ratio'] * 100).toStringAsFixed(1)}%

Performance Summary:
  Average Retrieval Time: ${s['avg_retrieval_time_ms']}ms
  Charts Meeting 100ms Target: ${s['charts_meeting_100ms_target']}/${s['charts_analyzed']} (${s['performance_compliance_percent'].toStringAsFixed(1)}%)
  Average Efficiency Score: ${s['avg_efficiency_score'].toStringAsFixed(1)}/100

Individual Chart Results:
${analyses.map((a) => '  ${a.chartId}: ${a.efficiencyScore.toStringAsFixed(1)}/100 (${a.retrievalTime.inMilliseconds}ms)').join('\n')}
''';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Chart Storage Analyzer
/// 
/// Analyzes chart storage efficiency, performance, and optimization
/// for marine navigation requirements
class ChartStorageAnalyzer {
  final DatabaseStorageService storageService;
  final CompressionService? compressionService;
  final AppLogger logger;

  ChartStorageAnalyzer({
    required this.storageService,
    this.compressionService,
    required this.logger,
  });

  /// Analyze chart storage efficiency with real test data
  Future<ChartStorageAnalysis> analyzeChart(String chartFilePath, Chart chartMetadata) async {
    logger.info('Analyzing chart storage: ${chartMetadata.id}');
    
    // Load chart data
    final chartFile = File(chartFilePath);
    if (!await chartFile.exists()) {
      throw ArgumentError('Chart file not found: $chartFilePath');
    }

    List<int> chartData;
    if (chartFilePath.endsWith('.zip')) {
      // Extract from ZIP archive
      final archiveBytes = await chartFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      final chartEntry = archive.files.firstWhere(
        (file) => file.name.endsWith('.000'),
        orElse: () => throw StateError('No .000 chart file found in archive'),
      );
      chartData = chartEntry.content as List<int>;
    } else {
      chartData = await chartFile.readAsBytes();
    }

    final originalSize = chartData.length;
    logger.info('Chart data size: ${originalSize} bytes');

    // Parse chart to analyze features
    final parseStartTime = DateTime.now();
    final parsedData = S57Parser.parse(chartData);
    final parseTime = DateTime.now().difference(parseStartTime);

    // Analyze feature distribution
    final featureDistribution = <String, int>{};
    for (final feature in parsedData.features) {
      final typeKey = feature.featureType.acronym;
      featureDistribution[typeKey] = (featureDistribution[typeKey] ?? 0) + 1;
    }

    logger.info('Features parsed: ${parsedData.features.length}');
    logger.info('Parse time: ${parseTime.inMilliseconds}ms');

    // Test storage performance
    final storeStartTime = DateTime.now();
    await storageService.storeChart(chartMetadata, chartData);
    final storeTime = DateTime.now().difference(storeStartTime);

    // Test retrieval performance
    final retrievalStartTime = DateTime.now();
    final retrievedData = await storageService.loadChart(chartMetadata.id);
    final retrievalTime = DateTime.now().difference(retrievalStartTime);

    if (retrievedData == null) {
      throw StateError('Failed to retrieve stored chart data');
    }

    // Calculate storage metrics
    final storedSize = retrievedData.length;
    final compressionRatio = storedSize / originalSize;
    
    // Calculate efficiency metrics
    final storageOverheadPercent = ((storedSize - originalSize) / originalSize) * 100;
    final meetsPerformanceTargets = retrievalTime.inMilliseconds < 100;
    
    final efficiency = StorageEfficiencyMetrics(
      storageOverheadPercent: storageOverheadPercent,
      spatialIndexEfficiency: _calculateSpatialIndexEfficiency(parsedData.features),
      metadataSize: _estimateMetadataSize(chartMetadata),
      meetsPerformanceTargets: meetsPerformanceTargets,
    );

    return ChartStorageAnalysis(
      chartId: chartMetadata.id,
      originalSize: originalSize,
      storedSize: storedSize,
      featureCount: parsedData.features.length,
      parseTime: parseTime,
      storeTime: storeTime,
      retrievalTime: retrievalTime,
      compressionRatio: compressionRatio,
      featureDistribution: featureDistribution,
      efficiency: efficiency,
    );
  }

  /// Analyze multiple charts in batch
  Future<BatchStorageAnalysis> analyzeBatch(Map<String, Chart> chartFiles) async {
    logger.info('Starting batch analysis of ${chartFiles.length} charts');
    
    final analyses = <ChartStorageAnalysis>[];
    
    for (final entry in chartFiles.entries) {
      try {
        final analysis = await analyzeChart(entry.key, entry.value);
        analyses.add(analysis);
        logger.info('Completed analysis: ${entry.value.id}');
      } catch (e) {
        logger.error('Failed to analyze chart ${entry.value.id}: $e');
      }
    }

    return BatchStorageAnalysis(
      analyses: analyses,
      analysisTime: DateTime.now(),
    );
  }

  /// Generate storage optimization recommendations
  List<String> generateOptimizationRecommendations(ChartStorageAnalysis analysis) {
    final recommendations = <String>[];
    
    // Performance recommendations
    if (analysis.retrievalTime.inMilliseconds > 100) {
      recommendations.add(
        'PERFORMANCE: Retrieval time (${analysis.retrievalTime.inMilliseconds}ms) exceeds 100ms target. '
        'Consider implementing memory caching for frequently accessed charts.',
      );
    }
    
    // Compression recommendations
    if (analysis.compressionRatio > 0.8) {
      recommendations.add(
        'COMPRESSION: Low compression ratio (${(analysis.compressionRatio * 100).toStringAsFixed(1)}%). '
        'Consider using higher compression levels or different algorithms.',
      );
    }
    
    // Storage efficiency recommendations
    if (analysis.efficiency.storageOverheadPercent > 20) {
      recommendations.add(
        'STORAGE: High storage overhead (${analysis.efficiency.storageOverheadPercent.toStringAsFixed(1)}%). '
        'Review metadata storage and indexing structures.',
      );
    }
    
    // Feature distribution recommendations
    if (analysis.featureDistribution.length < 3) {
      recommendations.add(
        'FEATURES: Limited feature diversity detected. '
        'Verify chart parsing is extracting all expected feature types.',
      );
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('OPTIMAL: Chart storage configuration meets all performance and efficiency targets.');
    }
    
    return recommendations;
  }

  /// Calculate spatial index efficiency based on feature distribution
  double _calculateSpatialIndexEfficiency(List<dynamic> features) {
    if (features.isEmpty) return 0.0;
    
    // Simple heuristic: more features with spatial distribution = better efficiency
    final featureCount = features.length;
    
    if (featureCount > 1000) return 95.0;
    if (featureCount > 500) return 85.0;
    if (featureCount > 100) return 75.0;
    return 60.0;
  }

  /// Estimate metadata storage size
  int _estimateMetadataSize(Chart chart) {
    // Rough estimate of metadata size in bytes
    int size = 0;
    size += chart.id.length * 2; // UTF-16 approximate
    size += chart.title.length * 2;
    size += chart.description?.length ?? 0 * 2;
    size += 100; // Fixed overhead for numeric fields, timestamps, etc.
    return size;
  }
}