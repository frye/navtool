import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Network connectivity status
enum NetworkStatus {
  /// Fully connected with good quality
  connected,
  
  /// No network connection
  disconnected,
  
  /// Connected but with limited functionality or poor quality
  limited,
  
  /// Connection status cannot be determined
  unknown,
}

/// Connection quality levels for marine environments
enum ConnectionQuality {
  /// Excellent connection - suitable for all operations
  excellent,
  
  /// Good connection - suitable for most operations
  good,
  
  /// Fair connection - may affect large downloads
  fair,
  
  /// Poor connection - only small requests recommended
  poor,
  
  /// Very poor connection - avoid non-critical operations
  veryPoor,
  
  /// No connection available
  offline,
}

/// Types of network connections
enum ConnectionType {
  /// High-speed wired connection
  ethernet,
  
  /// WiFi connection
  wifi,
  
  /// Cellular/mobile data
  cellular,
  
  /// Satellite internet (common in marine environments)
  satellite,
  
  /// Unknown or multiple connection types
  unknown,
}

/// Connection stability assessment
enum ConnectionStability {
  /// Very stable connection with minimal fluctuations
  veryStable,
  
  /// Stable connection with occasional minor issues
  stable,
  
  /// Moderately stable with noticeable fluctuations
  moderate,
  
  /// Unstable connection with frequent issues
  unstable,
  
  /// Very unstable connection, frequent disconnections
  veryUnstable,
}

/// Weather impact severity on network connections
enum WeatherImpactSeverity {
  /// No weather impact detected
  none,
  
  /// Minor impact, slight degradation possible
  minor,
  
  /// Moderate impact, noticeable performance issues
  moderate,
  
  /// Severe impact, significant service disruption
  severe,
  
  /// Extreme impact, service likely unavailable
  extreme,
}

/// Marine network conditions assessment
class MarineNetworkConditions {
  const MarineNetworkConditions({
    required this.connectionQuality,
    required this.isSuitableForChartDownload,
    required this.isSuitableForApiRequests,
    required this.recommendedTimeoutMultiplier,
    required this.estimatedSpeed,
    required this.latency,
  });

  /// Overall connection quality
  final ConnectionQuality connectionQuality;
  
  /// Whether connection is suitable for downloading charts
  final bool isSuitableForChartDownload;
  
  /// Whether connection is suitable for API requests
  final bool isSuitableForApiRequests;
  
  /// Recommended multiplier for standard timeouts
  final double recommendedTimeoutMultiplier;
  
  /// Estimated connection speed in Mbps
  final double estimatedSpeed;
  
  /// Current latency
  final Duration latency;
}

/// Marine-optimized timeout recommendations
class MarineTimeoutRecommendations {
  const MarineTimeoutRecommendations({
    required this.connectionTimeout,
    required this.readTimeout,
    required this.writeTimeout,
  });

  /// Timeout for establishing connections
  final Duration connectionTimeout;
  
  /// Timeout for reading data
  final Duration readTimeout;
  
  /// Timeout for writing data
  final Duration writeTimeout;
}

/// Weather impact assessment on network connectivity
class WeatherImpactAssessment {
  const WeatherImpactAssessment({
    required this.severity,
    required this.affectedServices,
    required this.recommendedActions,
  });

  /// Severity of weather impact
  final WeatherImpactSeverity severity;
  
  /// List of services likely to be affected
  final List<String> affectedServices;
  
  /// Recommended actions to take
  final List<String> recommendedActions;
}

/// Offline fallback strategy
class OfflineFallbackStrategy {
  const OfflineFallbackStrategy({
    required this.name,
    required this.description,
    required this.priority,
    required this.isAvailable,
  });

  /// Strategy name
  final String name;
  
  /// Description of the strategy
  final String description;
  
  /// Priority level (higher = more preferred)
  final int priority;
  
  /// Whether this strategy is currently available
  final bool isAvailable;
}

/// Graceful degradation plan
class DegradationPlan {
  const DegradationPlan({
    required this.disabledFeatures,
    required this.reducedFunctionality,
    required this.prioritizedOperations,
  });

  /// Features to disable completely
  final List<String> disabledFeatures;
  
  /// Features with reduced functionality
  final List<String> reducedFunctionality;
  
  /// Operations to prioritize
  final List<String> prioritizedOperations;
}

/// Network monitoring event types
enum MonitoringEventType {
  /// Connection status changed
  statusChange,
  
  /// Quality assessment updated
  qualityUpdate,
  
  /// Connection interruption detected
  interruption,
  
  /// Connection restored
  restoration,
  
  /// Latency spike detected
  latencySpike,
  
  /// Speed degradation detected
  speedDegradation,
}

/// Network monitoring event
class NetworkMonitoringEvent {
  const NetworkMonitoringEvent({
    required this.type,
    required this.timestamp,
    required this.data,
  });

  /// Type of monitoring event
  final MonitoringEventType type;
  
  /// When the event occurred
  final DateTime timestamp;
  
  /// Additional event data
  final Map<String, dynamic> data;
}

/// Connection interruption information
class ConnectionInterruption {
  const ConnectionInterruption({
    required this.startTime,
    this.endTime,
    required this.duration,
    required this.cause,
  });

  /// When the interruption started
  final DateTime startTime;
  
  /// When the interruption ended (null if ongoing)
  final DateTime? endTime;
  
  /// Duration of the interruption
  final Duration duration;
  
  /// Suspected cause of the interruption
  final String cause;
}

/// Configuration for network resilience
class NetworkResilienceConfig {
  const NetworkResilienceConfig({
    this.connectionTimeoutThreshold = const Duration(seconds: 30),
    this.qualityAssessmentInterval = const Duration(minutes: 5),
    this.stabilityWindowSize = const Duration(minutes: 10),
    this.marineOptimizations = true,
  });

  /// Threshold for considering connection timeout
  final Duration connectionTimeoutThreshold;
  
  /// How often to assess connection quality
  final Duration qualityAssessmentInterval;
  
  /// Time window for assessing connection stability
  final Duration stabilityWindowSize;
  
  /// Enable marine-specific optimizations
  final bool marineOptimizations;
}

/// Network resilience utility for marine environments
/// 
/// Provides comprehensive network monitoring, quality assessment,
/// and marine-specific optimizations for reliable connectivity
/// in challenging maritime conditions.
class NetworkResilience {
  /// Creates a network resilience instance
  NetworkResilience({NetworkResilienceConfig? config})
      : config = config ?? const NetworkResilienceConfig() {
    _initializeMonitoring();
  }

  /// Configuration settings
  NetworkResilienceConfig config;

  /// Stream controller for network status changes
  final StreamController<NetworkStatus> _statusController = 
      StreamController<NetworkStatus>.broadcast();

  /// Stream controller for monitoring events
  final StreamController<NetworkMonitoringEvent> _eventsController = 
      StreamController<NetworkMonitoringEvent>.broadcast();

  /// Stream controller for connection interruptions
  final StreamController<ConnectionInterruption> _interruptionsController = 
      StreamController<ConnectionInterruption>.broadcast();

  /// Current monitoring state
  bool _isMonitoring = false;
  
  /// Monitoring timer
  Timer? _monitoringTimer;
  
  /// Last known network status
  NetworkStatus _lastStatus = NetworkStatus.unknown;
  
  /// Connection quality history for stability assessment
  final List<_QualityMeasurement> _qualityHistory = [];

  /// Stream of network status changes
  Stream<NetworkStatus> get networkStatusStream => _statusController.stream;

  /// Stream of monitoring events
  Stream<NetworkMonitoringEvent> get monitoringEvents => _eventsController.stream;

  /// Stream of connection interruptions
  Stream<ConnectionInterruption> get connectionInterruptions => 
      _interruptionsController.stream;

  /// Whether monitoring is currently active
  bool get isMonitoring => _isMonitoring;

  /// Checks if device is currently online
  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Gets current network status
  Future<NetworkStatus> getNetworkStatus() async {
    final isConnected = await isOnline();
    if (!isConnected) {
      return NetworkStatus.disconnected;
    }

    final quality = await assessConnectionQuality();
    switch (quality) {
      case ConnectionQuality.excellent:
      case ConnectionQuality.good:
      case ConnectionQuality.fair:
        return NetworkStatus.connected;
      case ConnectionQuality.poor:
      case ConnectionQuality.veryPoor:
        return NetworkStatus.limited;
      case ConnectionQuality.offline:
        return NetworkStatus.disconnected;
    }
  }

  /// Checks network status and emits changes
  Future<void> checkNetworkStatus() async {
    final currentStatus = await getNetworkStatus();
    if (currentStatus != _lastStatus) {
      _lastStatus = currentStatus;
      _statusController.add(currentStatus);
      
      _emitEvent(NetworkMonitoringEvent(
        type: MonitoringEventType.statusChange,
        timestamp: DateTime.now(),
        data: {'previousStatus': _lastStatus, 'currentStatus': currentStatus},
      ));
    }
  }

  /// Waits for network connection with optional timeout
  Future<void> waitForConnection({
    Duration? timeout,
    bool requireOnline = true,
  }) async {
    final completer = Completer<void>();
    late StreamSubscription subscription;
    Timer? timer;

    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          subscription.cancel();
          if (requireOnline) {
            completer.completeError(TimeoutException('Connection timeout', timeout));
          } else {
            completer.complete();
          }
        }
      });
    }

    // Check current status first
    if (await isOnline()) {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
      return completer.future;
    }

    subscription = networkStatusStream.listen((status) {
      if (status == NetworkStatus.connected || 
          status == NetworkStatus.limited) {
        timer?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  /// Assesses current connection quality
  Future<ConnectionQuality> assessConnectionQuality() async {
    if (!await isOnline()) {
      return ConnectionQuality.offline;
    }

    final latency = await measureLatency();
    final speed = await measureConnectionSpeed();

    // Marine-optimized quality assessment
    if (speed >= 10.0 && latency.inMilliseconds <= 100) {
      return ConnectionQuality.excellent;
    } else if (speed >= 5.0 && latency.inMilliseconds <= 300) {
      return ConnectionQuality.good;
    } else if (speed >= 2.0 && latency.inMilliseconds <= 800) {
      return ConnectionQuality.fair;
    } else if (speed >= 0.5 && latency.inMilliseconds <= 2000) {
      return ConnectionQuality.poor;
    } else {
      return ConnectionQuality.veryPoor;
    }
  }

  /// Measures connection speed in Mbps
  Future<double> measureConnectionSpeed() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Simple speed test using HTTP request
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://www.google.com'));
      final response = await request.close();
      
      final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      stopwatch.stop();
      
      client.close();
      
      // Estimate speed (this is a rough approximation)
      final totalBytes = bytes.length;
      final totalSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      final bytesPerSecond = totalBytes / totalSeconds;
      final mbps = (bytesPerSecond * 8) / (1024 * 1024); // Convert to Mbps
      
      return math.max(0.1, mbps); // Minimum 0.1 Mbps
    } catch (_) {
      return 0.1; // Default low speed on error
    }
  }

  /// Measures connection latency
  Future<Duration> measureLatency({String? testHost}) async {
    final host = testHost ?? 'google.com';
    final stopwatch = Stopwatch()..start();
    
    try {
      await InternetAddress.lookup(host);
      stopwatch.stop();
      return Duration(milliseconds: stopwatch.elapsedMilliseconds);
    } catch (_) {
      stopwatch.stop();
      return const Duration(milliseconds: 5000); // High latency for failed lookup
    }
  }

  /// Detects connection type
  Future<ConnectionType> getConnectionType() async {
    // Simplified detection - in a real implementation this would
    // use platform-specific APIs to detect actual connection type
    if (await isOnline()) {
      final latency = await measureLatency();
      
      // Heuristic-based detection
      if (latency.inMilliseconds > 600) {
        return ConnectionType.satellite; // High latency suggests satellite
      } else if (latency.inMilliseconds > 200) {
        return ConnectionType.cellular;
      } else {
        return ConnectionType.wifi; // Assume WiFi for low latency
      }
    }
    
    return ConnectionType.unknown;
  }

  /// Assesses connection stability
  Future<ConnectionStability> assessConnectionStability() async {
    if (_qualityHistory.length < 3) {
      return ConnectionStability.moderate; // Not enough data
    }

    final recentMeasurements = _qualityHistory
        .where((m) => DateTime.now().difference(m.timestamp) < config.stabilityWindowSize)
        .toList();

    if (recentMeasurements.length < 3) {
      return ConnectionStability.moderate;
    }

    final qualities = recentMeasurements.map((m) => m.quality.index).toList();
    final variance = _calculateVariance(qualities);

    if (variance <= 0.5) {
      return ConnectionStability.veryStable;
    } else if (variance <= 1.0) {
      return ConnectionStability.stable;
    } else if (variance <= 2.0) {
      return ConnectionStability.moderate;
    } else if (variance <= 4.0) {
      return ConnectionStability.unstable;
    } else {
      return ConnectionStability.veryUnstable;
    }
  }

  /// Detects if using satellite internet
  Future<bool> isSatelliteConnection() async {
    final connectionType = await getConnectionType();
    return connectionType == ConnectionType.satellite;
  }

  /// Assesses marine network conditions
  Future<MarineNetworkConditions> assessMarineNetworkConditions() async {
    final quality = await assessConnectionQuality();
    final speed = await measureConnectionSpeed();
    final latency = await measureLatency();

    // Marine-specific assessments
    final isSuitableForChartDownload = quality.index <= ConnectionQuality.fair.index && 
                                      speed >= 1.0;
    final isSuitableForApiRequests = quality != ConnectionQuality.offline;

    // Calculate timeout multiplier based on conditions
    double timeoutMultiplier = 1.0;
    if (await isSatelliteConnection()) {
      timeoutMultiplier = 3.0; // Satellite connections need longer timeouts
    } else if (quality == ConnectionQuality.poor) {
      timeoutMultiplier = 2.0;
    } else if (quality == ConnectionQuality.veryPoor) {
      timeoutMultiplier = 4.0;
    }

    return MarineNetworkConditions(
      connectionQuality: quality,
      isSuitableForChartDownload: isSuitableForChartDownload,
      isSuitableForApiRequests: isSuitableForApiRequests,
      recommendedTimeoutMultiplier: timeoutMultiplier,
      estimatedSpeed: speed,
      latency: latency,
    );
  }

  /// Gets marine-specific timeout recommendations
  Future<MarineTimeoutRecommendations> getMarineTimeoutRecommendations() async {
    final conditions = await assessMarineNetworkConditions();
    final multiplier = conditions.recommendedTimeoutMultiplier;

    return MarineTimeoutRecommendations(
      connectionTimeout: Duration(seconds: (30 * multiplier).round()),
      readTimeout: Duration(minutes: (10 * multiplier).round()),
      writeTimeout: Duration(minutes: (5 * multiplier).round()),
    );
  }

  /// Assesses weather impact on connection
  Future<WeatherImpactAssessment> assessWeatherImpactOnConnection() async {
    // Simplified weather impact assessment
    // In a real implementation, this would integrate with weather APIs
    final quality = await assessConnectionQuality();
    final stability = await assessConnectionStability();

    WeatherImpactSeverity severity;
    List<String> affectedServices;
    List<String> recommendedActions;

    if (quality == ConnectionQuality.offline || 
        stability == ConnectionStability.veryUnstable) {
      severity = WeatherImpactSeverity.severe;
      affectedServices = ['Chart Downloads', 'API Requests', 'Real-time Updates'];
      recommendedActions = [
        'Wait for weather conditions to improve',
        'Use offline charts if available',
        'Delay non-critical operations'
      ];
    } else if (quality == ConnectionQuality.veryPoor || 
               stability == ConnectionStability.unstable) {
      severity = WeatherImpactSeverity.moderate;
      affectedServices = ['Chart Downloads', 'Large File Transfers'];
      recommendedActions = [
        'Prioritize critical operations',
        'Use smaller download chunks',
        'Implement longer timeouts'
      ];
    } else {
      severity = WeatherImpactSeverity.minor;
      affectedServices = [];
      recommendedActions = ['Continue normal operations'];
    }

    return WeatherImpactAssessment(
      severity: severity,
      affectedServices: affectedServices,
      recommendedActions: recommendedActions,
    );
  }

  /// Checks if offline mode is supported
  bool supportsOfflineMode() {
    return true; // Marine apps should always support offline mode
  }

  /// Gets available offline fallback strategies
  Future<List<OfflineFallbackStrategy>> getOfflineFallbackStrategies() async {
    return [
      const OfflineFallbackStrategy(
        name: 'Cached Charts',
        description: 'Use previously downloaded chart data',
        priority: 10,
        isAvailable: true,
      ),
      const OfflineFallbackStrategy(
        name: 'Basic Navigation',
        description: 'Continue with essential navigation features only',
        priority: 8,
        isAvailable: true,
      ),
      const OfflineFallbackStrategy(
        name: 'Local Database',
        description: 'Use locally stored navigation data',
        priority: 6,
        isAvailable: true,
      ),
    ];
  }

  /// Creates a degradation plan for poor connection quality
  Future<DegradationPlan> createDegradationPlan(ConnectionQuality quality) async {
    switch (quality) {
      case ConnectionQuality.poor:
        return const DegradationPlan(
          disabledFeatures: ['Auto-sync', 'Real-time weather'],
          reducedFunctionality: ['Chart updates', 'Route sharing'],
          prioritizedOperations: ['Navigation', 'Safety alerts'],
        );
      
      case ConnectionQuality.veryPoor:
        return const DegradationPlan(
          disabledFeatures: ['Auto-sync', 'Real-time weather', 'Chart downloads'],
          reducedFunctionality: ['Chart updates', 'Route sharing', 'Online services'],
          prioritizedOperations: ['Navigation', 'Safety alerts', 'Emergency communications'],
        );
      
      case ConnectionQuality.offline:
        return const DegradationPlan(
          disabledFeatures: ['All online features'],
          reducedFunctionality: [],
          prioritizedOperations: ['Offline navigation', 'Emergency procedures'],
        );
      
      default:
        return const DegradationPlan(
          disabledFeatures: [],
          reducedFunctionality: [],
          prioritizedOperations: ['Normal operations'],
        );
    }
  }

  /// Starts network monitoring
  Future<void> startMonitoring({Duration? interval}) async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    final monitoringInterval = interval ?? const Duration(seconds: 30);

    _monitoringTimer = Timer.periodic(monitoringInterval, (_) async {
      await checkNetworkStatus();
      
      // Record quality measurement for stability assessment
      final quality = await assessConnectionQuality();
      _qualityHistory.add(_QualityMeasurement(
        quality: quality,
        timestamp: DateTime.now(),
      ));

      // Keep only recent measurements
      _qualityHistory.removeWhere(
        (m) => DateTime.now().difference(m.timestamp) > config.stabilityWindowSize,
      );

      _emitEvent(NetworkMonitoringEvent(
        type: MonitoringEventType.qualityUpdate,
        timestamp: DateTime.now(),
        data: {'quality': quality.toString()},
      ));
    });
  }

  /// Stops network monitoring
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Updates configuration at runtime
  Future<void> updateConfiguration(NetworkResilienceConfig newConfig) async {
    config = newConfig;
    
    // Restart monitoring with new configuration if currently monitoring
    if (_isMonitoring) {
      stopMonitoring();
      await startMonitoring();
    }
  }

  /// Disposes resources
  void dispose() {
    stopMonitoring();
    _statusController.close();
    _eventsController.close();
    _interruptionsController.close();
  }

  /// Initializes monitoring components
  void _initializeMonitoring() {
    // Set up initial state
    checkNetworkStatus();
  }

  /// Emits a monitoring event
  void _emitEvent(NetworkMonitoringEvent event) {
    _eventsController.add(event);
  }

  /// Calculates variance for stability assessment
  double _calculateVariance(List<int> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((x) => (x - mean) * (x - mean));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }
}

/// Internal class for tracking quality measurements
class _QualityMeasurement {
  const _QualityMeasurement({
    required this.quality,
    required this.timestamp,
  });

  final ConnectionQuality quality;
  final DateTime timestamp;
}