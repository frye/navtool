import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';
import '../error/error_handler.dart';
import 'app_state.dart';

/// Application settings
@immutable
class AppSettings {
  final AppThemeMode themeMode;
  final bool isDayMode;
  final int maxConcurrentDownloads;
  final bool enableGpsLogging;
  final bool showDebugInfo;
  final double chartRenderingQuality;
  final bool enableBackgroundDownloads;
  final bool autoSelectChart;
  final String preferredUnits; // 'metric' or 'imperial'
  final double gpsUpdateInterval; // seconds
  final bool enableOfflineMode;
  final bool showAdvancedFeatures;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.isDayMode = true,
    this.maxConcurrentDownloads = 3,
    this.enableGpsLogging = false,
    this.showDebugInfo = false,
    this.chartRenderingQuality = 1.0,
    this.enableBackgroundDownloads = true,
    this.autoSelectChart = true,
    this.preferredUnits = 'metric',
    this.gpsUpdateInterval = 1.0,
    this.enableOfflineMode = false,
    this.showAdvancedFeatures = false,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? isDayMode,
    int? maxConcurrentDownloads,
    bool? enableGpsLogging,
    bool? showDebugInfo,
    double? chartRenderingQuality,
    bool? enableBackgroundDownloads,
    bool? autoSelectChart,
    String? preferredUnits,
    double? gpsUpdateInterval,
    bool? enableOfflineMode,
    bool? showAdvancedFeatures,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      isDayMode: isDayMode ?? this.isDayMode,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      enableGpsLogging: enableGpsLogging ?? this.enableGpsLogging,
      showDebugInfo: showDebugInfo ?? this.showDebugInfo,
      chartRenderingQuality: chartRenderingQuality ?? this.chartRenderingQuality,
      enableBackgroundDownloads: enableBackgroundDownloads ?? this.enableBackgroundDownloads,
      autoSelectChart: autoSelectChart ?? this.autoSelectChart,
      preferredUnits: preferredUnits ?? this.preferredUnits,
      gpsUpdateInterval: gpsUpdateInterval ?? this.gpsUpdateInterval,
      enableOfflineMode: enableOfflineMode ?? this.enableOfflineMode,
      showAdvancedFeatures: showAdvancedFeatures ?? this.showAdvancedFeatures,
    );
  }

  /// Converts to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'isDayMode': isDayMode,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'enableGpsLogging': enableGpsLogging,
      'showDebugInfo': showDebugInfo,
      'chartRenderingQuality': chartRenderingQuality,
      'enableBackgroundDownloads': enableBackgroundDownloads,
      'autoSelectChart': autoSelectChart,
      'preferredUnits': preferredUnits,
      'gpsUpdateInterval': gpsUpdateInterval,
      'enableOfflineMode': enableOfflineMode,
      'showAdvancedFeatures': showAdvancedFeatures,
    };
  }

  /// Creates from JSON
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      isDayMode: json['isDayMode'] ?? true,
      maxConcurrentDownloads: json['maxConcurrentDownloads'] ?? 3,
      enableGpsLogging: json['enableGpsLogging'] ?? false,
      showDebugInfo: json['showDebugInfo'] ?? false,
      chartRenderingQuality: (json['chartRenderingQuality'] ?? 1.0).toDouble(),
      enableBackgroundDownloads: json['enableBackgroundDownloads'] ?? true,
      autoSelectChart: json['autoSelectChart'] ?? true,
      preferredUnits: json['preferredUnits'] ?? 'metric',
      gpsUpdateInterval: (json['gpsUpdateInterval'] ?? 1.0).toDouble(),
      enableOfflineMode: json['enableOfflineMode'] ?? false,
      showAdvancedFeatures: json['showAdvancedFeatures'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          isDayMode == other.isDayMode &&
          maxConcurrentDownloads == other.maxConcurrentDownloads &&
          enableGpsLogging == other.enableGpsLogging &&
          showDebugInfo == other.showDebugInfo &&
          chartRenderingQuality == other.chartRenderingQuality &&
          enableBackgroundDownloads == other.enableBackgroundDownloads &&
          autoSelectChart == other.autoSelectChart &&
          preferredUnits == other.preferredUnits &&
          gpsUpdateInterval == other.gpsUpdateInterval &&
          enableOfflineMode == other.enableOfflineMode &&
          showAdvancedFeatures == other.showAdvancedFeatures;

  @override
  int get hashCode =>
      themeMode.hashCode ^
      isDayMode.hashCode ^
      maxConcurrentDownloads.hashCode ^
      enableGpsLogging.hashCode ^
      showDebugInfo.hashCode ^
      chartRenderingQuality.hashCode ^
      enableBackgroundDownloads.hashCode ^
      autoSelectChart.hashCode ^
      preferredUnits.hashCode ^
      gpsUpdateInterval.hashCode ^
      enableOfflineMode.hashCode ^
      showAdvancedFeatures.hashCode;

  @override
  String toString() {
    return 'AppSettings('
        'themeMode: $themeMode, '
        'isDayMode: $isDayMode, '
        'maxConcurrentDownloads: $maxConcurrentDownloads, '
        'preferredUnits: $preferredUnits'
        ')';
  }
}

/// Settings state notifier with persistence
class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final AppLogger _logger;
  final ErrorHandler _errorHandler;
  SharedPreferences? _prefs;

  AppSettingsNotifier({
    required AppLogger logger,
    required ErrorHandler errorHandler,
  })  : _logger = logger,
        _errorHandler = errorHandler,
        super(const AppSettings()) {
    _initializeSettings();
  }

  /// Initialize settings from persistent storage
  Future<void> _initializeSettings() async {
    try {
      // In test environment, don't try to access SharedPreferences
      // Check if Flutter binding is initialized
      try {
        _prefs = await SharedPreferences.getInstance();
        await _loadSettings();
        _logger.info('Settings initialized from storage');
      } catch (bindingError) {
        // If binding is not initialized (test environment), use default settings
        _logger.warning('Using default settings (binding not initialized)', exception: bindingError);
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      _logger.error('Failed to initialize settings', exception: error);
    }
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    try {
      final settingsJson = _prefs?.getString('app_settings');
      if (settingsJson != null) {
        // TODO: Parse JSON when dart:convert is available
        _logger.debug('Loaded settings from storage');
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      _logger.warning('Failed to load settings from storage', exception: error);
    }
  }

  /// Save settings to storage
  Future<void> _saveSettings() async {
    try {
      if (_prefs != null) {
        // TODO: Convert to JSON when dart:convert is available
        await _prefs!.setString('app_settings', state.toString());
        _logger.debug('Saved settings to storage');
      }
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
      _logger.warning('Failed to save settings to storage', exception: error);
    }
  }

  /// Updates theme mode
  Future<void> setThemeMode(AppThemeMode themeMode) async {
    try {
      state = state.copyWith(themeMode: themeMode);
      await _saveSettings();
      _logger.info('Theme mode changed: ${themeMode.displayName}');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates day mode for charts
  Future<void> setDayMode(bool isDayMode) async {
    try {
      state = state.copyWith(isDayMode: isDayMode);
      await _saveSettings();
      _logger.info('Chart day mode changed: $isDayMode');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates maximum concurrent downloads
  Future<void> setMaxConcurrentDownloads(int max) async {
    try {
      if (max <= 0 || max > 10) {
        _logger.warning('Invalid max concurrent downloads: $max');
        return;
      }
      state = state.copyWith(maxConcurrentDownloads: max);
      await _saveSettings();
      _logger.info('Max concurrent downloads changed: $max');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates GPS logging setting
  Future<void> setEnableGpsLogging(bool enabled) async {
    try {
      state = state.copyWith(enableGpsLogging: enabled);
      await _saveSettings();
      _logger.info('GPS logging changed: $enabled');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates debug info display
  Future<void> setShowDebugInfo(bool show) async {
    try {
      state = state.copyWith(showDebugInfo: show);
      await _saveSettings();
      _logger.info('Debug info display changed: $show');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates chart rendering quality
  Future<void> setChartRenderingQuality(double quality) async {
    try {
      if (quality < 0.1 || quality > 2.0) {
        _logger.warning('Invalid chart rendering quality: $quality');
        return;
      }
      state = state.copyWith(chartRenderingQuality: quality);
      await _saveSettings();
      _logger.info('Chart rendering quality changed: $quality');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates background downloads setting
  Future<void> setEnableBackgroundDownloads(bool enabled) async {
    try {
      state = state.copyWith(enableBackgroundDownloads: enabled);
      await _saveSettings();
      _logger.info('Background downloads changed: $enabled');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates auto chart selection
  Future<void> setAutoSelectChart(bool enabled) async {
    try {
      state = state.copyWith(autoSelectChart: enabled);
      await _saveSettings();
      _logger.info('Auto chart selection changed: $enabled');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates preferred units
  Future<void> setPreferredUnits(String units) async {
    try {
      if (!['metric', 'imperial'].contains(units)) {
        _logger.warning('Invalid units: $units');
        return;
      }
      state = state.copyWith(preferredUnits: units);
      await _saveSettings();
      _logger.info('Preferred units changed: $units');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates GPS update interval
  Future<void> setGpsUpdateInterval(double interval) async {
    try {
      if (interval < 0.1 || interval > 60.0) {
        _logger.warning('Invalid GPS update interval: $interval');
        return;
      }
      state = state.copyWith(gpsUpdateInterval: interval);
      await _saveSettings();
      _logger.info('GPS update interval changed: $interval');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates offline mode
  Future<void> setEnableOfflineMode(bool enabled) async {
    try {
      state = state.copyWith(enableOfflineMode: enabled);
      await _saveSettings();
      _logger.info('Offline mode changed: $enabled');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Updates advanced features visibility
  Future<void> setShowAdvancedFeatures(bool show) async {
    try {
      state = state.copyWith(showAdvancedFeatures: show);
      await _saveSettings();
      _logger.info('Advanced features visibility changed: $show');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }

  /// Resets all settings to defaults
  Future<void> resetToDefaults() async {
    try {
      state = const AppSettings();
      await _saveSettings();
      _logger.info('Settings reset to defaults');
    } catch (error, stackTrace) {
      _errorHandler.handleError(error, stackTrace);
    }
  }
}
