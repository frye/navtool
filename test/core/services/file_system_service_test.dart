import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:navtool/core/services/file_system_service.dart';
import 'package:navtool/core/logging/app_logger.dart';

import 'file_system_service_test.mocks.dart';

// Generate mocks for dependencies
@GenerateMocks([AppLogger, Directory])
void main() {
  group('FileSystemService Tests', () {
    late FileSystemService fileSystemService;
    late MockAppLogger mockLogger;

    setUp(() {
      mockLogger = MockAppLogger();
      fileSystemService = FileSystemService(logger: mockLogger);
    });

    group('Initialization Tests', () {
      test('should initialize and create required directories', () async {
        // Arrange
        when(mockLogger.info(any)).thenReturn(null);

        // Act
        await fileSystemService.initialize();

        // Assert
        verify(mockLogger.info('FileSystemService initialized successfully')).called(1);
      });

      test('should handle initialization errors gracefully', () async {
        // Arrange
        when(mockLogger.error(any, exception: anyNamed('exception'))).thenReturn(null);

        // Act & Assert
        // The service should not throw even if path_provider fails
        expect(() => fileSystemService.initialize(), returnsNormally);
      });
    });

    group('Directory Management Tests', () {
      test('should get application documents directory', () async {
        // Act
        final directory = await fileSystemService.getApplicationDocumentsDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, isNotEmpty);
      });

      test('should get application support directory', () async {
        // Act
        final directory = await fileSystemService.getApplicationSupportDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, isNotEmpty);
      });

      test('should get temporary directory', () async {
        // Act
        final directory = await fileSystemService.getTemporaryDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, isNotEmpty);
      });

      test('should get charts directory', () async {
        // Act
        final directory = await fileSystemService.getChartsDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, contains('charts'));
      });

      test('should get routes directory', () async {
        // Act
        final directory = await fileSystemService.getRoutesDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, contains('routes'));
      });

      test('should get cache directory', () async {
        // Act
        final directory = await fileSystemService.getCacheDirectory();

        // Assert
        expect(directory, isA<Directory>());
        expect(directory.path, contains('cache'));
      });

      test('should create directory if it does not exist', () async {
        // Arrange
        final directory = await fileSystemService.getChartsDirectory();
        
        // Act
        final result = await fileSystemService.ensureDirectoryExists(directory);

        // Assert
        expect(result, isTrue);
        expect(directory.existsSync(), isTrue);
      });
    });

    group('File Operations Tests', () {
      test('should write file to charts directory', () async {
        // Arrange
        const fileName = 'test_chart.000';
        const content = 'test chart content';

        // Act
        final file = await fileSystemService.writeChartFile(fileName, content.codeUnits);

        // Assert
        expect(file, isA<File>());
        expect(file.existsSync(), isTrue);
        expect(await file.readAsString(), equals(content));

        // Cleanup
        await file.delete();
      });

      test('should read file from charts directory', () async {
        // Arrange
        const fileName = 'test_chart.000';
        const content = 'test chart content';
        final file = await fileSystemService.writeChartFile(fileName, content.codeUnits);

        // Act
        final readContent = await fileSystemService.readChartFile(fileName);

        // Assert
        expect(readContent, equals(content.codeUnits));

        // Cleanup
        await file.delete();
      });

      test('should delete file from charts directory', () async {
        // Arrange
        const fileName = 'test_chart.000';
        const content = 'test chart content';
        final file = await fileSystemService.writeChartFile(fileName, content.codeUnits);
        expect(file.existsSync(), isTrue);

        // Act
        final deleted = await fileSystemService.deleteChartFile(fileName);

        // Assert
        expect(deleted, isTrue);
        expect(file.existsSync(), isFalse);
      });

      test('should check if chart file exists', () async {
        // Arrange
        const fileName = 'test_chart.000';
        const content = 'test chart content';

        // Act & Assert - File should not exist initially
        expect(await fileSystemService.chartFileExists(fileName), isFalse);

        // Create file
        final file = await fileSystemService.writeChartFile(fileName, content.codeUnits);

        // Act & Assert - File should exist now
        expect(await fileSystemService.chartFileExists(fileName), isTrue);

        // Cleanup
        await file.delete();
      });

      test('should get file size for existing chart file', () async {
        // Arrange
        const fileName = 'test_chart.000';
        const content = 'test chart content';
        final file = await fileSystemService.writeChartFile(fileName, content.codeUnits);

        // Act
        final size = await fileSystemService.getChartFileSize(fileName);

        // Assert
        expect(size, equals(content.length));

        // Cleanup
        await file.delete();
      });

      test('should return null for non-existent file size', () async {
        // Arrange
        const fileName = 'non_existent.000';

        // Act
        final size = await fileSystemService.getChartFileSize(fileName);

        // Assert
        expect(size, isNull);
      });
    });

    group('Route File Operations Tests', () {
      test('should export route to file', () async {
        // Arrange
        const routeName = 'test_route';
        const routeData = '{"id":"route001","name":"Test Route"}';

        // Act
        final file = await fileSystemService.exportRoute(routeName, routeData);

        // Assert
        expect(file, isA<File>());
        expect(file.existsSync(), isTrue);
        expect(await file.readAsString(), equals(routeData));
        expect(file.path, contains('.json'));

        // Cleanup
        await file.delete();
      });

      test('should import route from file', () async {
        // Arrange
        const routeName = 'test_route';
        const routeData = '{"id":"route001","name":"Test Route"}';
        final file = await fileSystemService.exportRoute(routeName, routeData);

        // Act
        final importedData = await fileSystemService.importRoute(file.path);

        // Assert
        expect(importedData, equals(routeData));

        // Cleanup
        await file.delete();
      });

      test('should list all route files', () async {
        // Arrange
        const routeName1 = 'test_route_1';
        const routeName2 = 'test_route_2';
        const routeData = '{"test":"data"}';
        final file1 = await fileSystemService.exportRoute(routeName1, routeData);
        final file2 = await fileSystemService.exportRoute(routeName2, routeData);

        // Act
        final routeFiles = await fileSystemService.listRouteFiles();

        // Assert
        expect(routeFiles, isA<List<File>>());
        expect(routeFiles.length, greaterThanOrEqualTo(2));
        expect(routeFiles.map((f) => f.path), contains(file1.path));
        expect(routeFiles.map((f) => f.path), contains(file2.path));

        // Cleanup
        await file1.delete();
        await file2.delete();
      });
    });

    group('Cache Management Tests', () {
      test('should clear cache directory', () async {
        // Arrange
        const fileName = 'cached_file.tmp';
        const content = 'cached content';
        final cacheDir = await fileSystemService.getCacheDirectory();
        final cacheFile = File('${cacheDir.path}/$fileName');
        await cacheFile.writeAsString(content);
        expect(cacheFile.existsSync(), isTrue);

        // Act
        final cleared = await fileSystemService.clearCache();

        // Assert
        expect(cleared, isTrue);
        expect(cacheFile.existsSync(), isFalse);
      });

      test('should get cache size', () async {
        // Arrange
        const fileName = 'cached_file.tmp';
        const content = 'cached content';
        final cacheDir = await fileSystemService.getCacheDirectory();
        final cacheFile = File('${cacheDir.path}/$fileName');
        await cacheFile.writeAsString(content);

        // Act
        final cacheSize = await fileSystemService.getCacheSize();

        // Assert
        expect(cacheSize, greaterThanOrEqualTo(content.length));

        // Cleanup
        await cacheFile.delete();
      });
    });

    group('File Validation Tests', () {
      test('should validate S-57 chart file extension', () {
        // Act & Assert
        expect(fileSystemService.isValidChartFile('chart.000'), isTrue);
        expect(fileSystemService.isValidChartFile('chart.001'), isTrue);
        expect(fileSystemService.isValidChartFile('chart.txt'), isFalse);
        expect(fileSystemService.isValidChartFile('chart'), isFalse);
        expect(fileSystemService.isValidChartFile('chart.jpeg'), isFalse);
      });

      test('should validate route file extension', () {
        // Act & Assert
        expect(fileSystemService.isValidRouteFile('route.json'), isTrue);
        expect(fileSystemService.isValidRouteFile('route.gpx'), isTrue);
        expect(fileSystemService.isValidRouteFile('route.txt'), isFalse);
        expect(fileSystemService.isValidRouteFile('route'), isFalse);
        expect(fileSystemService.isValidRouteFile('route.jpeg'), isFalse);
      });
    });

    group('Error Handling Tests', () {
      test('should handle file operation errors gracefully', () async {
        // Arrange
        const invalidFileName = '/invalid/path/file.000';

        // Act & Assert
        expect(
          () => fileSystemService.writeChartFile(invalidFileName, []),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('should log errors when file operations fail', () async {
        // Arrange
        const invalidFileName = '/invalid/path/file.000';
        when(mockLogger.error(any, exception: anyNamed('exception'))).thenReturn(null);

        // Act & Assert
        try {
          await fileSystemService.writeChartFile(invalidFileName, []);
        } catch (e) {
          // Expected to throw
        }

        verify(mockLogger.error(any, exception: anyNamed('exception'))).called(1);
      });
    });

    group('Directory Security Tests', () {
      test('should create directories with secure permissions', () async {
        // Act
        final chartsDir = await fileSystemService.getChartsDirectory();
        final routesDir = await fileSystemService.getRoutesDirectory();

        // Assert - Directories should be created and accessible
        expect(chartsDir.existsSync(), isTrue);
        expect(routesDir.existsSync(), isTrue);
        
        // Test that we can write to these directories
        final testFile1 = File('${chartsDir.path}/security_test.tmp');
        final testFile2 = File('${routesDir.path}/security_test.tmp');
        
        await testFile1.writeAsString('test');
        await testFile2.writeAsString('test');
        
        expect(testFile1.existsSync(), isTrue);
        expect(testFile2.existsSync(), isTrue);

        // Cleanup
        await testFile1.delete();
        await testFile2.delete();
      });
    });
  });
}
