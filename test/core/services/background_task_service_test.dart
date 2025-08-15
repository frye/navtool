import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:workmanager/workmanager.dart';
import 'package:navtool/core/services/background_task_service.dart';
import 'package:navtool/core/services/download_service.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/gps_position.dart';

// Generate mocks
@GenerateMocks([
  Workmanager,
  DownloadService,
  GpsService,
  AppLogger,
])
import 'background_task_service_test.mocks.dart';

void main() {
  group('BackgroundTaskService', () {
    late BackgroundTaskService backgroundTaskService;
    late MockWorkmanager mockWorkmanager;
    late MockDownloadService mockDownloadService;
    late MockGpsService mockGpsService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockWorkmanager = MockWorkmanager();
      mockDownloadService = MockDownloadService();
      mockGpsService = MockGpsService();
      mockLogger = MockAppLogger();
      
      backgroundTaskService = BackgroundTaskServiceImpl(
        workmanager: mockWorkmanager,
        downloadService: mockDownloadService,
        gpsService: mockGpsService,
        logger: mockLogger,
      );
      
      // Clear any previous interactions
      clearInteractions(mockWorkmanager);
      clearInteractions(mockLogger);
    });

    group('initialization', () {
      test('should initialize workmanager on startup', () async {
        // Arrange
        when(mockWorkmanager.initialize(
          any,
          isInDebugMode: anyNamed('isInDebugMode'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.initialize();

        // Assert
        verify(mockWorkmanager.initialize(
          any,
          isInDebugMode: false,
        )).called(1);
      });

      test('should enable debug mode when in debug', () async {
        // Arrange
        when(mockWorkmanager.initialize(
          any,
          isInDebugMode: anyNamed('isInDebugMode'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.initialize(isDebugMode: true);

        // Assert
        verify(mockWorkmanager.initialize(
          any,
          isInDebugMode: true,
        )).called(1);
      });
    });

    group('chart download tasks', () {
      test('should register periodic chart download task', () async {
        // Arrange
        when(mockWorkmanager.registerPeriodicTask(
          any, 
          any,
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.registerChartDownloadTask();

        // Assert
        verify(mockWorkmanager.registerPeriodicTask(
          'chartDownloadTask', 
          'chartDownload',
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).called(1);
        verify(mockLogger.info('Chart download task registered')).called(1);
      });

      test('should register one-time chart download task', () async {
        // Arrange
        const chartId = 'test-chart-123';
        when(mockWorkmanager.registerOneOffTask(any, any, inputData: anyNamed('inputData')))
            .thenAnswer((_) async {});

        // Act
        await backgroundTaskService.scheduleChartDownload(chartId);

        // Assert
        verify(mockWorkmanager.registerOneOffTask(
          'downloadChart_$chartId',
          'downloadSingleChart',
          inputData: {'chartId': chartId},
        )).called(1);
      });

      test('should cancel chart download task', () async {
        // Arrange
        const chartId = 'test-chart-123';
        when(mockWorkmanager.cancelByUniqueName(any)).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.cancelChartDownload(chartId);

        // Assert
        verify(mockWorkmanager.cancelByUniqueName('downloadChart_$chartId')).called(1);
      });
    });

    group('GPS tracking tasks', () {
      test('should register periodic GPS tracking task', () async {
        // Arrange
        when(mockWorkmanager.registerPeriodicTask(
          any, 
          any,
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.registerGpsTrackingTask();

        // Assert
        verify(mockWorkmanager.registerPeriodicTask(
          'gpsTrackingTask', 
          'gpsTracking',
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).called(1);
        verify(mockLogger.info('GPS tracking task registered')).called(1);
      });

      test('should register route recording task', () async {
        // Arrange
        const routeId = 'route-456';
        when(mockWorkmanager.registerPeriodicTask(
          any, 
          any,
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.startRouteRecording(routeId);

        // Assert
        verify(mockWorkmanager.registerPeriodicTask(
          'routeRecording_$routeId', 
          'recordRoute',
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).called(1);
      });

      test('should stop route recording task', () async {
        // Arrange
        const routeId = 'route-456';
        when(mockWorkmanager.cancelByUniqueName(any)).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.stopRouteRecording(routeId);

        // Assert
        verify(mockWorkmanager.cancelByUniqueName('routeRecording_$routeId')).called(1);
      });
    });

    group('weather update tasks', () {
      test('should register periodic weather update task', () async {
        // Arrange
        when(mockWorkmanager.registerPeriodicTask(
          any, 
          any,
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.registerWeatherUpdateTask();

        // Assert
        verify(mockWorkmanager.registerPeriodicTask(
          'weatherUpdateTask', 
          'weatherUpdate',
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).called(1);
        verify(mockLogger.info('Weather update task registered')).called(1);
      });
    });

    group('task management', () {
      test('should cancel all background tasks', () async {
        // Arrange
        when(mockWorkmanager.cancelAll()).thenAnswer((_) async {});

        // Act
        await backgroundTaskService.cancelAllTasks();

        // Assert
        verify(mockWorkmanager.cancelAll()).called(1);
      });

      test('should get active task count', () async {
        // This is a placeholder for when workmanager supports task status queries
        // Currently workmanager doesn't provide this functionality
        expect(backgroundTaskService.getActiveTaskCount(), equals(0));
      });
    });

    group('error handling', () {
      test('should handle workmanager initialization failure', () async {
        // Arrange
        when(mockWorkmanager.initialize(
          any,
          isInDebugMode: anyNamed('isInDebugMode'),
        )).thenThrow(Exception('Workmanager initialization failed'));

        // Act & Assert
        await expectLater(
          backgroundTaskService.initialize(),
          throwsA(isA<BackgroundTaskException>()),
        );
      });

      test('should log errors when task registration fails', () async {
        // Arrange
        when(mockWorkmanager.registerPeriodicTask(
          any, 
          any,
          frequency: anyNamed('frequency'),
          tag: anyNamed('tag'),
          existingWorkPolicy: anyNamed('existingWorkPolicy'),
          initialDelay: anyNamed('initialDelay'),
          constraints: anyNamed('constraints'),
          backoffPolicy: anyNamed('backoffPolicy'),
          backoffPolicyDelay: anyNamed('backoffPolicyDelay'),
          outOfQuotaPolicy: anyNamed('outOfQuotaPolicy'),
          inputData: anyNamed('inputData'),
        )).thenThrow(Exception('Task registration failed'));

        // Act & Assert
        await expectLater(
          backgroundTaskService.registerChartDownloadTask(),
          throwsA(isA<BackgroundTaskException>()),
        );
        
        verify(mockLogger.error(any)).called(1);
      });
    });
  });
}

// Mock callback dispatcher for testing
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}
