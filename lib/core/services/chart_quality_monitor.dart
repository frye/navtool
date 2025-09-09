import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../logging/app_logger.dart';
import '../models/chart.dart';
import '../models/geographic_bounds.dart';
import 'storage_service.dart';
import 'cache_service.dart';
import 'noaa/state_region_mapping_service.dart';

/// Quality levels for chart data
enum ChartQualityLevel {
  /// Excellent quality - all metrics meet standards
  excellent,
  
  /// Good quality - minor issues that don't affect navigation
  good,
  
  /// Fair quality - some issues present but usable
  fair,
  
  /// Poor quality - significant issues affecting usability
  poor,
  
  /// Critical quality - major issues requiring immediate attention
  critical,
}

/// Types of quality issues
enum QualityIssueType {
  /// Chart metadata is missing or incomplete
  missingMetadata,
  
  /// Chart coverage has gaps
  coverageGaps,
  
  /// Chart is outdated
  outdatedChart,
  
  /// Duplicate charts exist
  duplicateCharts,
  
  /// Invalid coordinate bounds
  invalidBounds,
  
  /// Inconsistent scale information
  inconsistentScale,
  
  /// Chart file corruption
  corruption,
  
  /// Missing required charts for region
  missingRequiredCharts,
}

/// Severity levels for quality alerts
enum AlertSeverity {
  /// Informational alert
  info,
  
  /// Warning that needs attention
  warning,
  
  /// Error requiring action
  error,
  
  /// Critical error requiring immediate action
  critical,
}

/// Individual quality issue
class QualityIssue {
  const QualityIssue({
    required this.type,
    required this.severity,
    required this.description,
    required this.chartId,
    required this.detectedAt,
    this.affectedRegion,
    this.recommendedAction,
    this.metadata = const {},
  });

  /// Type of quality issue
  final QualityIssueType type;
  
  /// Severity of the issue
  final AlertSeverity severity;
  
  /// Human-readable description
  final String description;
  
  /// Chart ID affected
  final String chartId;
  
  /// When the issue was detected
  final DateTime detectedAt;
  
  /// Geographic region affected
  final String? affectedRegion;
  
  /// Recommended action to resolve
  final String? recommendedAction;
  
  /// Additional metadata
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'severity': severity.toString(),
    'description': description,
    'chartId': chartId,
    'detectedAt': detectedAt.toIso8601String(),
    'affectedRegion': affectedRegion,
    'recommendedAction': recommendedAction,
    'metadata': metadata,
  };

  factory QualityIssue.fromJson(Map<String, dynamic> json) => QualityIssue(
    type: QualityIssueType.values.firstWhere(
      (e) => e.toString() == json['type'],
    ),
    severity: AlertSeverity.values.firstWhere(
      (e) => e.toString() == json['severity'],
    ),
    description: json['description'],
    chartId: json['chartId'],
    detectedAt: DateTime.parse(json['detectedAt']),
    affectedRegion: json['affectedRegion'],
    recommendedAction: json['recommendedAction'],
    metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
  );
}

/// Quality report for charts
class QualityReport {
  QualityReport({
    required this.generatedAt,
    required this.overallQuality,
    required this.totalChartsAnalyzed,
    required this.issues,
    required this.regionReports,
    required this.recommendations,
  });

  /// When the report was generated
  final DateTime generatedAt;
  
  /// Overall quality assessment
  final ChartQualityLevel overallQuality;
  
  /// Total number of charts analyzed
  final int totalChartsAnalyzed;
  
  /// List of quality issues found
  final List<QualityIssue> issues;
  
  /// Quality reports by region
  final Map<String, RegionQualityReport> regionReports;
  
  /// Quality improvement recommendations
  final List<String> recommendations;

  /// Gets issues by severity
  List<QualityIssue> getIssuesBySeverity(AlertSeverity severity) =>
      issues.where((issue) => issue.severity == severity).toList();

  /// Gets critical issues requiring immediate attention
  List<QualityIssue> get criticalIssues => getIssuesBySeverity(AlertSeverity.critical);

  /// Gets number of issues by type
  Map<QualityIssueType, int> get issuesByType {
    final Map<QualityIssueType, int> result = {};
    for (final issue in issues) {
      result[issue.type] = (result[issue.type] ?? 0) + 1;
    }
    return result;
  }

  /// Returns true if quality is acceptable for marine navigation
  bool get isQualityAcceptable =>
      overallQuality.index <= ChartQualityLevel.fair.index &&
      criticalIssues.isEmpty;

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toIso8601String(),
    'overallQuality': overallQuality.toString(),
    'totalChartsAnalyzed': totalChartsAnalyzed,
    'issues': issues.map((i) => i.toJson()).toList(),
    'regionReports': regionReports.map((k, v) => MapEntry(k, v.toJson())),
    'recommendations': recommendations,
  };
}

/// Quality report for a specific region
class RegionQualityReport {
  const RegionQualityReport({
    required this.regionName,
    required this.qualityLevel,
    required this.chartCount,
    required this.coveragePercentage,
    required this.lastUpdated,
    required this.issues,
  });

  /// Name of the region
  final String regionName;
  
  /// Quality level for this region
  final ChartQualityLevel qualityLevel;
  
  /// Number of charts in region
  final int chartCount;
  
  /// Percentage of region covered by charts
  final double coveragePercentage;
  
  /// When charts were last updated
  final DateTime lastUpdated;
  
  /// Issues specific to this region
  final List<QualityIssue> issues;

  /// Returns true if region has adequate coverage
  bool get hasAdequateCoverage => coveragePercentage >= 85.0;

  Map<String, dynamic> toJson() => {
    'regionName': regionName,
    'qualityLevel': qualityLevel.toString(),
    'chartCount': chartCount,
    'coveragePercentage': coveragePercentage,
    'lastUpdated': lastUpdated.toIso8601String(),
    'issues': issues.map((i) => i.toJson()).toList(),
  };
}

/// Quality alert for monitoring system
class QualityAlert {
  const QualityAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    required this.affectedCharts,
    required this.triggeredAt,
    required this.isResolved,
    this.resolvedAt,
    this.recommendedAction,
  });

  /// Unique alert ID
  final String id;
  
  /// Alert severity
  final AlertSeverity severity;
  
  /// Alert title
  final String title;
  
  /// Detailed description
  final String description;
  
  /// List of affected chart IDs
  final List<String> affectedCharts;
  
  /// When alert was triggered
  final DateTime triggeredAt;
  
  /// Whether alert has been resolved
  final bool isResolved;
  
  /// When alert was resolved
  final DateTime? resolvedAt;
  
  /// Recommended action
  final String? recommendedAction;

  /// Duration alert has been active
  Duration get activeDuration =>
      (resolvedAt ?? DateTime.now()).difference(triggeredAt);
}

/// Chart quality monitoring service for marine navigation safety
///
/// Provides continuous monitoring of chart data quality, coverage gaps,
/// and data integrity issues that could affect marine navigation safety.
class ChartQualityMonitor {
  ChartQualityMonitor({
    required AppLogger logger,
    required StorageService storageService,
    required CacheService cacheService,
    required StateRegionMappingService mappingService,
  }) : _logger = logger,
       _storageService = storageService,
       _cacheService = cacheService,
       _mappingService = mappingService;

  final AppLogger _logger;
  final StorageService _storageService;
  final CacheService _cacheService;
  final StateRegionMappingService _mappingService;

  // Monitoring state
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  final StreamController<QualityAlert> _alertsController =
      StreamController<QualityAlert>.broadcast();

  /// Stream of quality alerts
  Stream<QualityAlert> get qualityAlerts => _alertsController.stream;

  /// Whether monitoring is currently active
  bool get isMonitoring => _isMonitoring;

  /// Generates comprehensive quality report for all charts
  Future<QualityReport> generateQualityReport() async {
    _logger.info('Generating comprehensive chart quality report');
    
    final issues = <QualityIssue>[];
    final regionReports = <String, RegionQualityReport>{};
    final recommendations = <String>[];
    
    try {
      // Get all supported states for analysis
      final states = await _mappingService.getSupportedStates();
      int totalChartsAnalyzed = 0;
      
      for (final state in states) {
        _logger.debug('Analyzing charts for state: $state');
        
        final regionReport = await _analyzeRegionQuality(state);
        regionReports[state] = regionReport;
        totalChartsAnalyzed += regionReport.chartCount;
        issues.addAll(regionReport.issues);
      }
      
      // Generate overall recommendations
      recommendations.addAll(_generateRecommendations(issues));
      
      // Determine overall quality level
      final overallQuality = _calculateOverallQuality(issues, totalChartsAnalyzed);
      
      final report = QualityReport(
        generatedAt: DateTime.now(),
        overallQuality: overallQuality,
        totalChartsAnalyzed: totalChartsAnalyzed,
        issues: issues,
        regionReports: regionReports,
        recommendations: recommendations,
      );
      
      // Cache the report
      await _cacheQualityReport(report);
      
      _logger.info(
        'Quality report generated: $totalChartsAnalyzed charts analyzed, '
        '${issues.length} issues found, overall quality: ${overallQuality.name}'
      );
      
      return report;
    } catch (e) {
      _logger.error('Failed to generate quality report', exception: e);
      rethrow;
    }
  }

  /// Analyzes quality for a specific region
  Future<RegionQualityReport> _analyzeRegionQuality(String regionName) async {
    final issues = <QualityIssue>[];
    
    try {
      // Get charts for this region
      final chartCells = await _mappingService.getChartCellsForState(regionName);
      final bounds = await _mappingService.getStateBounds(regionName);
      
      if (bounds == null) {
        issues.add(QualityIssue(
          type: QualityIssueType.missingRequiredCharts,
          severity: AlertSeverity.error,
          description: 'No geographic bounds defined for region $regionName',
          chartId: 'N/A',
          detectedAt: DateTime.now(),
          affectedRegion: regionName,
          recommendedAction: 'Define geographic boundaries for region',
        ));
        
        return RegionQualityReport(
          regionName: regionName,
          qualityLevel: ChartQualityLevel.critical,
          chartCount: 0,
          coveragePercentage: 0.0,
          lastUpdated: DateTime.now(),
          issues: issues,
        );
      }
      
      final charts = await _storageService.getChartsInBounds(bounds);
      final regionCharts = charts.where((c) => chartCells.contains(c.id)).toList();
      
      // Analyze each chart
      for (final chart in regionCharts) {
        issues.addAll(await _analyzeChartQuality(chart, regionName));
      }
      
      // Check for coverage gaps
      final coveragePercentage = await _calculateCoveragePercentage(regionName, regionCharts);
      if (coveragePercentage < 50.0) {
        issues.add(QualityIssue(
          type: QualityIssueType.coverageGaps,
          severity: AlertSeverity.critical,
          description: 'Critical coverage gap: only ${coveragePercentage.toStringAsFixed(1)}% covered',
          chartId: 'COVERAGE',
          detectedAt: DateTime.now(),
          affectedRegion: regionName,
          recommendedAction: 'Add additional charts to improve coverage',
          metadata: {'coverage': coveragePercentage},
        ));
      } else if (coveragePercentage < 85.0) {
        issues.add(QualityIssue(
          type: QualityIssueType.coverageGaps,
          severity: AlertSeverity.warning,
          description: 'Coverage gap: only ${coveragePercentage.toStringAsFixed(1)}% covered',
          chartId: 'COVERAGE',
          detectedAt: DateTime.now(),
          affectedRegion: regionName,
          recommendedAction: 'Consider adding charts to improve coverage',
          metadata: {'coverage': coveragePercentage},
        ));
      }
      
      // Determine quality level for region
      final qualityLevel = _calculateRegionQuality(issues, regionCharts.length);
      
      return RegionQualityReport(
        regionName: regionName,
        qualityLevel: qualityLevel,
        chartCount: regionCharts.length,
        coveragePercentage: coveragePercentage,
        lastUpdated: DateTime.now(),
        issues: issues,
      );
    } catch (e) {
      _logger.error('Failed to analyze region $regionName', exception: e);
      
      issues.add(QualityIssue(
        type: QualityIssueType.corruption,
        severity: AlertSeverity.error,
        description: 'Failed to analyze region: ${e.toString()}',
        chartId: 'ANALYSIS_ERROR',
        detectedAt: DateTime.now(),
        affectedRegion: regionName,
        recommendedAction: 'Check data integrity and retry analysis',
      ));
      
      return RegionQualityReport(
        regionName: regionName,
        qualityLevel: ChartQualityLevel.critical,
        chartCount: 0,
        coveragePercentage: 0.0,
        lastUpdated: DateTime.now(),
        issues: issues,
      );
    }
  }

  /// Analyzes quality of individual chart
  Future<List<QualityIssue>> _analyzeChartQuality(Chart chart, String region) async {
    final issues = <QualityIssue>[];
    
    // Check metadata completeness
    if (chart.title.isEmpty) {
      issues.add(QualityIssue(
        type: QualityIssueType.missingMetadata,
        severity: AlertSeverity.warning,
        description: 'Chart ${chart.id} is missing title',
        chartId: chart.id,
        detectedAt: DateTime.now(),
        affectedRegion: region,
        recommendedAction: 'Update chart metadata with proper title',
      ));
    }
    
    if (chart.scale <= 0) {
      issues.add(QualityIssue(
        type: QualityIssueType.inconsistentScale,
        severity: AlertSeverity.error,
        description: 'Chart ${chart.id} has invalid scale: ${chart.scale}',
        chartId: chart.id,
        detectedAt: DateTime.now(),
        affectedRegion: region,
        recommendedAction: 'Correct chart scale information',
      ));
    }
    
    // Validate geographic bounds
    if (!_isValidBounds(chart.bounds)) {
      issues.add(QualityIssue(
        type: QualityIssueType.invalidBounds,
        severity: AlertSeverity.critical,
        description: 'Chart ${chart.id} has invalid geographic bounds',
        chartId: chart.id,
        detectedAt: DateTime.now(),
        affectedRegion: region,
        recommendedAction: 'Verify and correct chart geographic boundaries',
      ));
    }
    
    // Check for outdated charts
    final daysSinceUpdate = DateTime.now().difference(chart.lastUpdate).inDays;
    if (daysSinceUpdate > 180) { // 6 months
      issues.add(QualityIssue(
        type: QualityIssueType.outdatedChart,
        severity: AlertSeverity.warning,
        description: 'Chart ${chart.id} has not been updated in $daysSinceUpdate days',
        chartId: chart.id,
        detectedAt: DateTime.now(),
        affectedRegion: region,
        recommendedAction: 'Check for chart updates from NOAA',
        metadata: {'daysSinceUpdate': daysSinceUpdate},
      ));
    }
    
    return issues;
  }

  /// Calculates coverage percentage for a region
  Future<double> _calculateCoveragePercentage(String regionName, List<Chart> charts) async {
    // Simplified coverage calculation
    // In a real implementation, this would use spatial analysis
    if (charts.isEmpty) return 0.0;
    
    // Base coverage on number of charts and typical coverage area
    // This is a heuristic - real implementation would use geographic analysis
    final expectedChartsForRegion = _getExpectedChartCount(regionName);
    final coverageRatio = charts.length / expectedChartsForRegion;
    
    return (coverageRatio * 100).clamp(0.0, 100.0);
  }

  /// Gets expected chart count for a region
  int _getExpectedChartCount(String regionName) {
    // Heuristic based on region size and coastline complexity
    const expectedCounts = {
      'Alaska': 25,
      'California': 20,
      'Florida': 15,
      'Texas': 12,
      'Washington': 10,
      'Maine': 8,
      'Hawaii': 8,
      'North Carolina': 8,
      'South Carolina': 6,
      'Georgia': 6,
      'Louisiana': 8,
      'Alabama': 4,
      'Mississippi': 4,
      'Oregon': 8,
      'New York': 10,
      'Massachusetts': 8,
      'Connecticut': 4,
      'Rhode Island': 3,
      'New Hampshire': 3,
      'New Jersey': 6,
      'Delaware': 3,
      'Maryland': 6,
      'Virginia': 8,
      'Pennsylvania': 4,
      'Ohio': 5,
      'Michigan': 10,
      'Indiana': 3,
      'Illinois': 4,
      'Wisconsin': 6,
      'Minnesota': 8,
    };
    
    return expectedCounts[regionName] ?? 5; // Default expectation
  }

  /// Validates geographic bounds
  bool _isValidBounds(GeographicBounds bounds) {
    return bounds.north > bounds.south &&
           bounds.east != bounds.west && // Allow west > east for international date line
           bounds.north <= 90 &&
           bounds.south >= -90 &&
           bounds.east <= 180 &&
           bounds.west >= -180;
  }

  /// Calculates overall quality level
  ChartQualityLevel _calculateOverallQuality(List<QualityIssue> issues, int totalCharts) {
    if (totalCharts == 0) return ChartQualityLevel.critical;
    
    final criticalCount = issues.where((i) => i.severity == AlertSeverity.critical).length;
    final errorCount = issues.where((i) => i.severity == AlertSeverity.error).length;
    final warningCount = issues.where((i) => i.severity == AlertSeverity.warning).length;
    
    // Calculate issue density
    final criticalDensity = criticalCount / totalCharts;
    final errorDensity = errorCount / totalCharts;
    final warningDensity = warningCount / totalCharts;
    
    if (criticalDensity > 0.1) return ChartQualityLevel.critical; // >10% critical issues
    if (errorDensity > 0.2) return ChartQualityLevel.poor; // >20% error issues
    if (warningDensity > 0.3) return ChartQualityLevel.fair; // >30% warning issues
    if (warningDensity > 0.1) return ChartQualityLevel.good; // >10% warning issues
    
    return ChartQualityLevel.excellent;
  }

  /// Calculates quality level for a region
  ChartQualityLevel _calculateRegionQuality(List<QualityIssue> issues, int chartCount) {
    if (chartCount == 0) return ChartQualityLevel.critical;
    
    final criticalIssues = issues.where((i) => i.severity == AlertSeverity.critical).length;
    final errorIssues = issues.where((i) => i.severity == AlertSeverity.error).length;
    
    if (criticalIssues > 0) return ChartQualityLevel.critical;
    if (errorIssues > chartCount * 0.2) return ChartQualityLevel.poor;
    if (issues.length > chartCount * 0.5) return ChartQualityLevel.fair;
    if (issues.length > chartCount * 0.2) return ChartQualityLevel.good;
    
    return ChartQualityLevel.excellent;
  }

  /// Generates quality improvement recommendations
  List<String> _generateRecommendations(List<QualityIssue> issues) {
    final recommendations = <String>[];
    final issueTypes = <QualityIssueType, int>{};
    
    // Count issues by type
    for (final issue in issues) {
      issueTypes[issue.type] = (issueTypes[issue.type] ?? 0) + 1;
    }
    
    // Generate type-specific recommendations
    if (issueTypes[QualityIssueType.coverageGaps] != null) {
      recommendations.add(
        'Address ${issueTypes[QualityIssueType.coverageGaps]} coverage gaps by acquiring additional charts'
      );
    }
    
    if (issueTypes[QualityIssueType.outdatedChart] != null) {
      recommendations.add(
        'Update ${issueTypes[QualityIssueType.outdatedChart]} outdated charts from NOAA sources'
      );
    }
    
    if (issueTypes[QualityIssueType.missingMetadata] != null) {
      recommendations.add(
        'Complete metadata for ${issueTypes[QualityIssueType.missingMetadata]} charts'
      );
    }
    
    if (issueTypes[QualityIssueType.invalidBounds] != null) {
      recommendations.add(
        'Correct geographic boundaries for ${issueTypes[QualityIssueType.invalidBounds]} charts'
      );
    }
    
    if (issueTypes[QualityIssueType.duplicateCharts] != null) {
      recommendations.add(
        'Remove or consolidate ${issueTypes[QualityIssueType.duplicateCharts]} duplicate charts'
      );
    }
    
    // Add general recommendations
    if (issues.length > 10) {
      recommendations.add('Consider implementing automated quality monitoring');
    }
    
    return recommendations;
  }

  /// Caches quality report for performance
  Future<void> _cacheQualityReport(QualityReport report) async {
    try {
      const cacheKey = 'latest_quality_report';
      final jsonData = jsonEncode(report.toJson());
      final encodedBytes = Uint8List.fromList(utf8.encode(jsonData));
      
      await _cacheService.store(
        cacheKey,
        encodedBytes,
        maxAge: const Duration(hours: 6), // Cache for 6 hours
      );
    } catch (e) {
      _logger.warning('Failed to cache quality report: $e');
      // Non-fatal error, continue without caching
    }
  }

  /// Gets cached quality report if available
  Future<QualityReport?> getCachedQualityReport() async {
    try {
      const cacheKey = 'latest_quality_report';
      final cached = await _cacheService.get(cacheKey);
      
      if (cached != null) {
        final jsonData = utf8.decode(cached);
        final data = jsonDecode(jsonData) as Map<String, dynamic>;
        
        // Reconstruct report from cached data
        return QualityReport(
          generatedAt: DateTime.parse(data['generatedAt']),
          overallQuality: ChartQualityLevel.values.firstWhere(
            (e) => e.toString() == data['overallQuality'],
          ),
          totalChartsAnalyzed: data['totalChartsAnalyzed'],
          issues: (data['issues'] as List)
              .map((i) => QualityIssue.fromJson(i))
              .toList(),
          regionReports: (data['regionReports'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, _regionReportFromJson(v))),
          recommendations: List<String>.from(data['recommendations']),
        );
      }
    } catch (e) {
      _logger.warning('Failed to read cached quality report: $e');
    }
    
    return null;
  }

  /// Reconstructs region report from JSON
  RegionQualityReport _regionReportFromJson(dynamic json) {
    final data = json as Map<String, dynamic>;
    return RegionQualityReport(
      regionName: data['regionName'],
      qualityLevel: ChartQualityLevel.values.firstWhere(
        (e) => e.toString() == data['qualityLevel'],
      ),
      chartCount: data['chartCount'],
      coveragePercentage: data['coveragePercentage'],
      lastUpdated: DateTime.parse(data['lastUpdated']),
      issues: (data['issues'] as List)
          .map((i) => QualityIssue.fromJson(i))
          .toList(),
    );
  }

  /// Starts continuous quality monitoring
  Future<void> startMonitoring({Duration interval = const Duration(hours: 6)}) async {
    if (_isMonitoring) return;
    
    _logger.info('Starting chart quality monitoring with ${interval.inHours}h interval');
    _isMonitoring = true;
    
    // Run initial quality check
    await _runQualityCheck();
    
    // Schedule periodic checks
    _monitoringTimer = Timer.periodic(interval, (_) async {
      await _runQualityCheck();
    });
  }

  /// Stops quality monitoring
  Future<void> stopMonitoring() async {
    _logger.info('Stopping chart quality monitoring');
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Runs a quality check and emits alerts for issues
  Future<void> _runQualityCheck() async {
    try {
      _logger.debug('Running periodic quality check');
      
      final report = await generateQualityReport();
      
      // Generate alerts for critical issues
      for (final issue in report.criticalIssues) {
        final alert = QualityAlert(
          id: 'alert_${issue.chartId}_${issue.type.name}_${DateTime.now().millisecondsSinceEpoch}',
          severity: issue.severity,
          title: 'Critical Chart Quality Issue',
          description: issue.description,
          affectedCharts: [issue.chartId],
          triggeredAt: DateTime.now(),
          isResolved: false,
          recommendedAction: issue.recommendedAction,
        );
        
        _alertsController.add(alert);
      }
      
      _logger.info(
        'Quality check completed: ${report.issues.length} issues found, '
        '${report.criticalIssues.length} critical'
      );
    } catch (e) {
      _logger.error('Quality check failed', exception: e);
      
      // Emit system alert for monitoring failure
      final alert = QualityAlert(
        id: 'system_alert_${DateTime.now().millisecondsSinceEpoch}',
        severity: AlertSeverity.error,
        title: 'Quality Monitoring System Error',
        description: 'Failed to run quality check: ${e.toString()}',
        affectedCharts: [],
        triggeredAt: DateTime.now(),
        isResolved: false,
        recommendedAction: 'Check system logs and restart monitoring if needed',
      );
      
      _alertsController.add(alert);
    }
  }

  /// Disposes of resources
  void dispose() {
    stopMonitoring();
    _alertsController.close();
  }
}