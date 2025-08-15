import 'dart:io';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:path/path.dart' as path;
import '../logging/app_logger.dart';

/// Service for managing file system operations for NavTool
/// Provides secure access to chart storage, route files, and cache management
class FileSystemService {
  final AppLogger _logger;
  
  // Directory paths (cached after first access)
  Directory? _applicationDocumentsDirectory;
  Directory? _applicationSupportDirectory;
  Directory? _temporaryDirectory;
  Directory? _chartsDirectory;
  Directory? _routesDirectory;
  Directory? _cacheDirectory;

  FileSystemService({required AppLogger logger}) : _logger = logger;

  /// Initialize the file system service and create required directories
  Future<void> initialize() async {
    try {
      _logger.info('Initializing FileSystemService...');
      
      // Create all required directories
      await getChartsDirectory();
      await getRoutesDirectory();
      await getCacheDirectory();
      
      _logger.info('FileSystemService initialized successfully');
    } catch (error) {
      _logger.error('Failed to initialize FileSystemService', exception: error);
      rethrow;
    }
  }

  /// Get the application documents directory
  Future<Directory> getApplicationDocumentsDirectory() async {
    return _applicationDocumentsDirectory ??= await pp.getApplicationDocumentsDirectory();
  }

  /// Get the application support directory
  Future<Directory> getApplicationSupportDirectory() async {
    return _applicationSupportDirectory ??= await pp.getApplicationSupportDirectory();
  }

  /// Get the temporary directory
  Future<Directory> getTemporaryDirectory() async {
    return _temporaryDirectory ??= await pp.getTemporaryDirectory();
  }

  /// Get the charts directory (creates if doesn't exist)
  Future<Directory> getChartsDirectory() async {
    if (_chartsDirectory != null) return _chartsDirectory!;
    
    final documentsDir = await getApplicationDocumentsDirectory();
    _chartsDirectory = Directory(path.join(documentsDir.path, 'NavTool', 'charts'));
    await ensureDirectoryExists(_chartsDirectory!);
    return _chartsDirectory!;
  }

  /// Get the routes directory (creates if doesn't exist)
  Future<Directory> getRoutesDirectory() async {
    if (_routesDirectory != null) return _routesDirectory!;
    
    final documentsDir = await getApplicationDocumentsDirectory();
    _routesDirectory = Directory(path.join(documentsDir.path, 'NavTool', 'routes'));
    await ensureDirectoryExists(_routesDirectory!);
    return _routesDirectory!;
  }

  /// Get the cache directory (creates if doesn't exist)
  Future<Directory> getCacheDirectory() async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    
    final documentsDir = await getApplicationDocumentsDirectory();
    _cacheDirectory = Directory(path.join(documentsDir.path, 'NavTool', 'cache'));
    await ensureDirectoryExists(_cacheDirectory!);
    return _cacheDirectory!;
  }

  /// Ensure a directory exists, create it if it doesn't
  Future<bool> ensureDirectoryExists(Directory directory) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        _logger.info('Created directory: ${directory.path}');
      }
      return true;
    } catch (error) {
      _logger.error('Failed to create directory: ${directory.path}', exception: error);
      return false;
    }
  }

  /// Write a chart file to the charts directory
  Future<File> writeChartFile(String fileName, List<int> bytes) async {
    try {
      if (!isValidChartFile(fileName)) {
        throw ArgumentError('Invalid chart file name: $fileName');
      }
      
      final chartsDir = await getChartsDirectory();
      final file = File(path.join(chartsDir.path, fileName));
      
      await file.writeAsBytes(bytes);
      _logger.info('Chart file written: ${file.path}');
      return file;
    } catch (error) {
      _logger.error('Failed to write chart file: $fileName', exception: error);
      rethrow;
    }
  }

  /// Read a chart file from the charts directory
  Future<List<int>> readChartFile(String fileName) async {
    try {
      if (!isValidChartFile(fileName)) {
        throw ArgumentError('Invalid chart file name: $fileName');
      }
      
      final chartsDir = await getChartsDirectory();
      final file = File(path.join(chartsDir.path, fileName));
      
      if (!await file.exists()) {
        throw FileSystemException('Chart file not found: $fileName');
      }
      
      final bytes = await file.readAsBytes();
      _logger.info('Chart file read: ${file.path}');
      return bytes;
    } catch (error) {
      _logger.error('Failed to read chart file: $fileName', exception: error);
      rethrow;
    }
  }

  /// Delete a chart file from the charts directory
  Future<bool> deleteChartFile(String fileName) async {
    try {
      if (!isValidChartFile(fileName)) {
        throw ArgumentError('Invalid chart file name: $fileName');
      }
      
      final chartsDir = await getChartsDirectory();
      final file = File(path.join(chartsDir.path, fileName));
      
      if (await file.exists()) {
        await file.delete();
        _logger.info('Chart file deleted: ${file.path}');
        return true;
      }
      
      return false;
    } catch (error) {
      _logger.error('Failed to delete chart file: $fileName', exception: error);
      return false;
    }
  }

  /// Check if a chart file exists
  Future<bool> chartFileExists(String fileName) async {
    try {
      if (!isValidChartFile(fileName)) {
        return false;
      }
      
      final chartsDir = await getChartsDirectory();
      final file = File(path.join(chartsDir.path, fileName));
      return await file.exists();
    } catch (error) {
      _logger.error('Failed to check chart file existence: $fileName', exception: error);
      return false;
    }
  }

  /// Get the size of a chart file in bytes
  Future<int?> getChartFileSize(String fileName) async {
    try {
      if (!isValidChartFile(fileName)) {
        return null;
      }
      
      final chartsDir = await getChartsDirectory();
      final file = File(path.join(chartsDir.path, fileName));
      
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.size;
      }
      
      return null;
    } catch (error) {
      _logger.error('Failed to get chart file size: $fileName', exception: error);
      return null;
    }
  }

  /// Export a route to a file
  Future<File> exportRoute(String routeName, String routeData) async {
    try {
      final routesDir = await getRoutesDirectory();
      final fileName = '$routeName.json';
      final file = File(path.join(routesDir.path, fileName));
      
      await file.writeAsString(routeData);
      _logger.info('Route exported: ${file.path}');
      return file;
    } catch (error) {
      _logger.error('Failed to export route: $routeName', exception: error);
      rethrow;
    }
  }

  /// Import a route from a file
  Future<String> importRoute(String filePath) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        throw FileSystemException('Route file not found: $filePath');
      }
      
      final routeData = await file.readAsString();
      _logger.info('Route imported: $filePath');
      return routeData;
    } catch (error) {
      _logger.error('Failed to import route: $filePath', exception: error);
      rethrow;
    }
  }

  /// List all route files in the routes directory
  Future<List<File>> listRouteFiles() async {
    try {
      final routesDir = await getRoutesDirectory();
      final files = <File>[];
      
      await for (final entity in routesDir.list()) {
        if (entity is File && isValidRouteFile(path.basename(entity.path))) {
          files.add(entity);
        }
      }
      
      _logger.info('Listed ${files.length} route files');
      return files;
    } catch (error) {
      _logger.error('Failed to list route files', exception: error);
      return [];
    }
  }

  /// Clear the cache directory
  Future<bool> clearCache() async {
    try {
      final cacheDir = await getCacheDirectory();
      
      await for (final entity in cacheDir.list()) {
        await entity.delete(recursive: true);
      }
      
      _logger.info('Cache cleared successfully');
      return true;
    } catch (error) {
      _logger.error('Failed to clear cache', exception: error);
      return false;
    }
  }

  /// Get the total size of the cache directory in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getCacheDirectory();
      int totalSize = 0;
      
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (error) {
      _logger.error('Failed to get cache size', exception: error);
      return 0;
    }
  }

  /// Validate if a file name is a valid chart file (S-57 format)
  bool isValidChartFile(String fileName) {
    if (fileName.isEmpty) return false;
    
    final extension = path.extension(fileName).toLowerCase();
    
    // S-57 files typically have numeric extensions: .000, .001, .002, etc.
    // Also support associated files like .A01, .A02, etc.
    if (extension.isEmpty) return false;
    
    final extensionWithoutDot = extension.substring(1);
    
    // Check for numeric extensions (000, 001, etc.)
    if (RegExp(r'^\d{3}$').hasMatch(extensionWithoutDot)) {
      return true;
    }
    
    // Check for alphanumeric extensions (A01, A02, etc.)
    if (RegExp(r'^[A-Z]\d{2}$').hasMatch(extensionWithoutDot)) {
      return true;
    }
    
    return false;
  }

  /// Validate if a file name is a valid route file
  bool isValidRouteFile(String fileName) {
    if (fileName.isEmpty) return false;
    
    final extension = path.extension(fileName).toLowerCase();
    return extension == '.json' || extension == '.gpx';
  }
}
