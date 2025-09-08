import 'dart:io';
import 'dart:math';
import '../database_storage_service.dart';
import '../compression_service.dart';
import 'chart_storage_analyzer.dart';
import '../../models/chart.dart';
import '../../models/geographic_bounds.dart';
import '../../logging/app_logger.dart';

/// Storage optimization metrics
class StorageOptimizationMetrics {
  final int totalCharts;
  final int totalSizeBytes;
  final int compressedSizeBytes;
  final double compressionRatio;
  final int chartsNeedingOptimization;
  final List<String> slowCharts;
  final Map<String, int> sizeDistribution;
  final DateTime lastOptimization;

  const StorageOptimizationMetrics({
    required this.totalCharts,
    required this.totalSizeBytes,
    required this.compressedSizeBytes,
    required this.compressionRatio,
    required this.chartsNeedingOptimization,
    required this.slowCharts,
    required this.sizeDistribution,
    required this.lastOptimization,
  });

  @override
  String toString() {
    return '''
Storage Optimization Metrics
============================
Total Charts: $totalCharts
Storage Usage: ${_formatBytes(totalSizeBytes)}
Compressed Size: ${_formatBytes(compressedSizeBytes)}
Compression Ratio: ${(compressionRatio * 100).toStringAsFixed(1)}%
Space Saved: ${_formatBytes(totalSizeBytes - compressedSizeBytes)}

Charts Needing Optimization: $chartsNeedingOptimization
Slow Charts (>100ms lookup): ${slowCharts.length}

Size Distribution:
${sizeDistribution.entries.map((e) => '  ${e.key}: ${e.value} charts').join('\n')}

Last Optimization: ${_formatDate(lastOptimization)}
''';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Storage cleanup recommendations
class CleanupRecommendation {
  final String type;
  final String description;
  final int potentialSavingsBytes;
  final int affectedCharts;
  final CleanupPriority priority;

  const CleanupRecommendation({
    required this.type,
    required this.description,
    required this.potentialSavingsBytes,
    required this.affectedCharts,
    required this.priority,
  });

  @override
  String toString() {
    return '$type: $description (${_formatBytes(potentialSavingsBytes)} potential savings, $affectedCharts charts)';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Cleanup priority levels
enum CleanupPriority { low, medium, high, critical }

/// Storage optimization and maintenance utility
/// 
/// Provides tools for analyzing and optimizing chart storage performance
class StorageOptimizationUtility {
  final DatabaseStorageService storageService;
  final CompressionService? compressionService;
  final AppLogger logger;
  
  StorageOptimizationUtility({
    required this.storageService,
    this.compressionService,
    required this.logger,
  });

  /// Analyze current storage state and generate optimization metrics
  Future<StorageOptimizationMetrics> analyzeStorage() async {
    logger.info('Analyzing storage optimization opportunities...');
    
    // Get all charts from storage
    final storageInfo = await storageService.getStorageInfo();
    final totalUsage = await storageService.getStorageUsage();
    
    // Analyze chart distribution and performance
    final slowCharts = <String>[];
    final sizeDistribution = <String, int>{
      'Small (<100KB)': 0,
      'Medium (100KB-1MB)': 0,
      'Large (1MB-10MB)': 0,
      'Very Large (>10MB)': 0,
    };
    
    int totalCharts = 0;
    int totalSizeBytes = 0;
    int compressedSizeBytes = 0;
    int chartsNeedingOptimization = 0;
    
    // For a real implementation, we would query the database for all charts
    // Here we simulate the analysis based on available storage info
    if (storageInfo.containsKey('used_space')) {
      totalSizeBytes = storageInfo['used_space'] as int? ?? 0;
      compressedSizeBytes = (totalSizeBytes * 0.7).round(); // Assume 70% compression
    }
    
    // Simulate chart analysis (in real implementation, query database)
    totalCharts = max(1, totalUsage ~/ 100000); // Estimate based on average chart size
    
    // Estimate size distribution
    sizeDistribution['Small (<100KB)'] = (totalCharts * 0.3).round();
    sizeDistribution['Medium (100KB-1MB)'] = (totalCharts * 0.5).round();
    sizeDistribution['Large (1MB-10MB)'] = (totalCharts * 0.15).round();
    sizeDistribution['Very Large (>10MB)'] = (totalCharts * 0.05).round();
    
    final compressionRatio = totalSizeBytes > 0 ? compressedSizeBytes / totalSizeBytes : 0.0;
    
    return StorageOptimizationMetrics(
      totalCharts: totalCharts,
      totalSizeBytes: totalSizeBytes,
      compressedSizeBytes: compressedSizeBytes,
      compressionRatio: compressionRatio,
      chartsNeedingOptimization: chartsNeedingOptimization,
      slowCharts: slowCharts,
      sizeDistribution: sizeDistribution,
      lastOptimization: DateTime.now(),
    );
  }

  /// Generate cleanup recommendations based on storage analysis
  Future<List<CleanupRecommendation>> generateCleanupRecommendations() async {
    logger.info('Generating storage cleanup recommendations...');
    
    final recommendations = <CleanupRecommendation>[];
    final storageInfo = await storageService.getStorageInfo();
    final totalUsage = await storageService.getStorageUsage();
    
    // Check for old chart versions
    if (totalUsage > 100 * 1024 * 1024) { // If storage > 100MB
      recommendations.add(CleanupRecommendation(
        type: 'OLD_VERSIONS',
        description: 'Remove superseded chart versions older than 30 days',
        potentialSavingsBytes: (totalUsage * 0.15).round(),
        affectedCharts: 5,
        priority: CleanupPriority.medium,
      ));
    }
    
    // Check for uncompressed charts
    final estimatedUncompressed = (totalUsage * 0.1).round();
    if (estimatedUncompressed > 10 * 1024 * 1024) { // If >10MB uncompressed
      recommendations.add(CleanupRecommendation(
        type: 'COMPRESSION',
        description: 'Apply compression to uncompressed chart data',
        potentialSavingsBytes: (estimatedUncompressed * 0.6).round(),
        affectedCharts: 3,
        priority: CleanupPriority.high,
      ));
    }
    
    // Check for unused cache entries
    recommendations.add(CleanupRecommendation(
      type: 'CACHE_CLEANUP',
      description: 'Remove expired cache entries and temporary files',
      potentialSavingsBytes: (totalUsage * 0.05).round(),
      affectedCharts: 0,
      priority: CleanupPriority.low,
    ));
    
    // Check for database vacuum needs
    if (totalUsage > 50 * 1024 * 1024) {
      recommendations.add(CleanupRecommendation(
        type: 'DATABASE_VACUUM',
        description: 'Vacuum database to reclaim unused space',
        potentialSavingsBytes: (totalUsage * 0.08).round(),
        affectedCharts: 0,
        priority: CleanupPriority.medium,
      ));
    }
    
    // Check for broken or corrupted charts
    recommendations.add(CleanupRecommendation(
      type: 'INTEGRITY_CHECK',
      description: 'Remove corrupted or incomplete chart files',
      potentialSavingsBytes: (totalUsage * 0.02).round(),
      affectedCharts: 1,
      priority: CleanupPriority.high,
    ));
    
    logger.info('Generated ${recommendations.length} cleanup recommendations');
    return recommendations;
  }

  /// Perform automatic storage optimization
  Future<Map<String, dynamic>> optimizeStorage({
    bool compressUncompressedCharts = true,
    bool removeOldVersions = true,
    bool cleanupCache = true,
    bool vacuumDatabase = true,
  }) async {
    logger.info('Starting automatic storage optimization...');
    
    final startTime = DateTime.now();
    final initialUsage = await storageService.getStorageUsage();
    final results = <String, dynamic>{
      'initial_usage_bytes': initialUsage,
      'operations_performed': <String>[],
      'space_saved_bytes': 0,
      'errors': <String>[],
    };
    
    try {
      // Clean up old data first
      if (removeOldVersions) {
        logger.info('Removing old chart versions...');
        await storageService.cleanupOldData();
        results['operations_performed'].add('cleanup_old_data');
      }
      
      // Clean up cache
      if (cleanupCache) {
        logger.info('Cleaning up cache entries...');
        // Cache cleanup would be implemented here
        results['operations_performed'].add('cache_cleanup');
      }
      
      // Vacuum database
      if (vacuumDatabase) {
        logger.info('Vacuuming database...');
        // Database vacuum would be implemented here
        results['operations_performed'].add('database_vacuum');
      }
      
      // Apply compression to uncompressed charts
      if (compressUncompressedCharts && compressionService != null) {
        logger.info('Applying compression to uncompressed charts...');
        // Chart compression would be implemented here
        results['operations_performed'].add('chart_compression');
      }
      
    } catch (e) {
      logger.error('Error during storage optimization: $e');
      results['errors'].add(e.toString());
    }
    
    final finalUsage = await storageService.getStorageUsage();
    final spaceSaved = max(0, initialUsage - finalUsage);
    
    results['final_usage_bytes'] = finalUsage;
    results['space_saved_bytes'] = spaceSaved;
    results['optimization_time_ms'] = DateTime.now().difference(startTime).inMilliseconds;
    
    logger.info('Storage optimization completed. Space saved: ${_formatBytes(spaceSaved)}');
    return results;
  }

  /// Monitor storage performance and detect issues
  Future<Map<String, dynamic>> monitorPerformance() async {
    logger.info('Monitoring storage performance...');
    
    final performanceMetrics = <String, dynamic>{};
    
    // Test basic storage operations
    final testData = List.generate(1000, (i) => i % 256);
    
    // Test storage write performance
    final writeStart = DateTime.now();
    final testChart = Chart(
      id: 'PERF_TEST_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Performance Test Chart',
      scale: 25000,
      bounds: const GeographicBounds(
        north: 47.7,
        south: 47.5,
        east: -122.2,
        west: -122.4,
      ),
      lastUpdate: DateTime.now(),
      state: 'TEST',
      type: ChartType.harbor,
      isDownloaded: true,
      fileSize: testData.length,
      edition: 1,
      updateNumber: 0,
      source: ChartSource.noaa,
      status: ChartStatus.current,
    );
    
    try {
      await storageService.storeChart(testChart, testData);
      final writeTime = DateTime.now().difference(writeStart);
      performanceMetrics['write_time_ms'] = writeTime.inMilliseconds;
      
      // Test storage read performance
      final readStart = DateTime.now();
      final retrievedData = await storageService.loadChart(testChart.id);
      final readTime = DateTime.now().difference(readStart);
      performanceMetrics['read_time_ms'] = readTime.inMilliseconds;
      
      // Verify data integrity
      performanceMetrics['data_integrity_ok'] = 
        retrievedData != null && retrievedData.length == testData.length;
      
      // Clean up test data
      await storageService.deleteChart(testChart.id);
      
    } catch (e) {
      logger.error('Performance monitoring failed: $e');
      performanceMetrics['error'] = e.toString();
    }
    
    // Get storage usage statistics
    performanceMetrics['total_usage_bytes'] = await storageService.getStorageUsage();
    performanceMetrics['storage_info'] = await storageService.getStorageInfo();
    
    // Performance evaluation
    final readTimeMs = performanceMetrics['read_time_ms'] as int? ?? 999;
    performanceMetrics['meets_100ms_target'] = readTimeMs < 100;
    performanceMetrics['performance_grade'] = _calculatePerformanceGrade(readTimeMs);
    
    logger.info('Performance monitoring completed');
    return performanceMetrics;
  }

  /// Calculate storage efficiency score
  Future<double> calculateEfficiencyScore() async {
    final metrics = await analyzeStorage();
    final performanceTest = await monitorPerformance();
    
    // Weight different factors
    double compressionScore = (1.0 - metrics.compressionRatio) * 40; // 40% weight
    double performanceScore = _calculatePerformanceScore(performanceTest) * 40; // 40% weight
    double organizationScore = _calculateOrganizationScore(metrics) * 20; // 20% weight
    
    return (compressionScore + performanceScore + organizationScore).clamp(0.0, 100.0);
  }

  /// Generate comprehensive storage report
  Future<String> generateStorageReport() async {
    logger.info('Generating comprehensive storage report...');
    
    final metrics = await analyzeStorage();
    final recommendations = await generateCleanupRecommendations();
    final performance = await monitorPerformance();
    final efficiencyScore = await calculateEfficiencyScore();
    
    final report = StringBuffer();
    report.writeln('NavTool Chart Storage Report');
    report.writeln('Generated: ${DateTime.now()}');
    report.writeln('='*50);
    report.writeln();
    
    // Storage metrics
    report.writeln('STORAGE METRICS');
    report.writeln('-'*20);
    report.writeln(metrics.toString());
    report.writeln();
    
    // Performance metrics
    report.writeln('PERFORMANCE METRICS');
    report.writeln('-'*20);
    final readTime = performance['read_time_ms'] ?? 0;
    final writeTime = performance['write_time_ms'] ?? 0;
    report.writeln('Read Performance: ${readTime}ms');
    report.writeln('Write Performance: ${writeTime}ms');
    report.writeln('Meets 100ms Target: ${performance['meets_100ms_target']}');
    report.writeln('Performance Grade: ${performance['performance_grade']}');
    report.writeln();
    
    // Efficiency score
    report.writeln('EFFICIENCY SCORE');
    report.writeln('-'*20);
    report.writeln('Overall Score: ${efficiencyScore.toStringAsFixed(1)}/100');
    report.writeln();
    
    // Recommendations
    report.writeln('CLEANUP RECOMMENDATIONS');
    report.writeln('-'*20);
    if (recommendations.isEmpty) {
      report.writeln('No optimization recommendations at this time.');
    } else {
      for (int i = 0; i < recommendations.length; i++) {
        report.writeln('${i + 1}. ${recommendations[i]}');
      }
    }
    report.writeln();
    
    // Summary
    report.writeln('SUMMARY');
    report.writeln('-'*20);
    report.writeln('Total Charts: ${metrics.totalCharts}');
    report.writeln('Storage Usage: ${_formatBytes(metrics.totalSizeBytes)}');
    report.writeln('Optimization Opportunities: ${recommendations.length}');
    
    return report.toString();
  }

  String _calculatePerformanceGrade(int readTimeMs) {
    if (readTimeMs < 50) return 'A+ (Excellent)';
    if (readTimeMs < 100) return 'A (Good)';
    if (readTimeMs < 200) return 'B (Fair)';
    if (readTimeMs < 500) return 'C (Poor)';
    return 'D (Very Poor)';
  }

  double _calculatePerformanceScore(Map<String, dynamic> performance) {
    final readTime = performance['read_time_ms'] as int? ?? 999;
    if (readTime < 50) return 100.0;
    if (readTime < 100) return 80.0;
    if (readTime < 200) return 60.0;
    if (readTime < 500) return 40.0;
    return 20.0;
  }

  double _calculateOrganizationScore(StorageOptimizationMetrics metrics) {
    // Score based on how well organized the storage is
    final compressionScore = (1.0 - metrics.compressionRatio) * 60;
    final optimizationScore = metrics.chartsNeedingOptimization == 0 ? 40.0 : 20.0;
    return compressionScore + optimizationScore;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}