import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../logging/app_logger.dart';
import '../error/app_error.dart';
import 'cache_service.dart';
import 'file_system_service.dart';
import 'compression_service.dart';

/// Implementation of CacheService for marine navigation data caching
/// Provides both memory and disk caching with compression and expiration
class CacheServiceImpl implements CacheService {
  final AppLogger _logger;
  final FileSystemService _fileSystemService;
  final CompressionService _compressionService;

  // Memory cache for frequently accessed data
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimestamps = {};
  int _memoryCacheLimit = 100; // Default limit

  // Cache metadata for expiration tracking
  final Map<String, DateTime> _cacheExpirations = {};

  CacheServiceImpl({
    required AppLogger logger,
    required FileSystemService fileSystemService,
    required CompressionService compressionService,
  }) : _logger = logger,
       _fileSystemService = fileSystemService,
       _compressionService = compressionService;

  @override
  Future<void> store(String key, Uint8List data, {Duration? maxAge}) async {
    try {
      validateKey(key);

      if (data.isEmpty) {
        throw AppError.validation('Cache data cannot be empty');
      }

      _logger.debug('Storing cache data: $key (${data.length} bytes)');

      // Compress data before storing
      final compressionResult = await _compressionService.compressCacheData(
        data,
        cacheKey: key,
      );

      // Get cache directory
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final cacheFile = File(path.join(cacheDir.path, '$key.cache'));
      final metadataFile = File(path.join(cacheDir.path, '$key.meta'));

      // Write compressed data
      await cacheFile.writeAsBytes(compressionResult.compressedData);

      // Write metadata including expiration
      final metadata = {
        'originalSize': compressionResult.originalSize,
        'compressedSize': compressionResult.compressedSize,
        'compressionRatio': compressionResult.compressionRatio,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': maxAge != null
            ? DateTime.now().add(maxAge).millisecondsSinceEpoch
            : null,
      };
      await metadataFile.writeAsString(jsonEncode(metadata));

      // Update expiration tracking
      if (maxAge != null) {
        _cacheExpirations[key] = DateTime.now().add(maxAge);
      }

      _logger.debug(
        'Cache data stored: $key (compressed from ${compressionResult.originalSize} to ${compressionResult.compressedSize} bytes)',
      );
    } catch (e) {
      _logger.error('Failed to store cache data: $key', exception: e);
      if (e is AppError) rethrow;
      throw AppError.storage('Cache storage failed', originalError: e);
    }
  }

  @override
  Future<Uint8List?> get(String key) async {
    try {
      validateKey(key);

      // Check memory cache first
      final memoryData = getFromMemory(key);
      if (memoryData != null) {
        _logger.debug('Cache hit from memory: $key');
        return memoryData;
      }

      // Check if expired
      if (await isExpired(key)) {
        _logger.debug('Cache entry expired: $key');
        await remove(key);
        return null;
      }

      // Read from disk cache
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final cacheFile = File(path.join(cacheDir.path, '$key.cache'));

      if (!await cacheFile.exists()) {
        _logger.debug('Cache miss: $key');
        return null;
      }

      // Read and decompress data
      final compressedData = await cacheFile.readAsBytes();
      final data = await _compressionService.decompressCacheData(
        compressedData,
        cacheKey: key,
      );

      // Store in memory cache for faster access next time
      storeInMemory(key, data);

      _logger.debug('Cache hit from disk: $key (${data.length} bytes)');
      return data;
    } catch (e) {
      _logger.error('Failed to get cache data: $key', exception: e);
      return null;
    }
  }

  @override
  Future<bool> exists(String key) async {
    try {
      validateKey(key);

      // Check memory cache
      if (_memoryCache.containsKey(key)) {
        return true;
      }

      // Check disk cache
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final cacheFile = File(path.join(cacheDir.path, '$key.cache'));

      if (!await cacheFile.exists()) {
        return false;
      }

      // Check if expired
      if (await isExpired(key)) {
        await remove(key);
        return false;
      }

      return true;
    } catch (e) {
      _logger.error('Failed to check cache existence: $key', exception: e);
      return false;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      validateKey(key);

      // Remove from memory cache
      removeFromMemory(key);

      // Remove from disk cache
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final cacheFile = File(path.join(cacheDir.path, '$key.cache'));
      final metadataFile = File(path.join(cacheDir.path, '$key.meta'));

      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }

      // Remove expiration tracking
      _cacheExpirations.remove(key);

      _logger.info('Cache entry removed: $key');
    } catch (e) {
      _logger.error('Failed to remove cache entry: $key', exception: e);
    }
  }

  @override
  Future<bool> clear() async {
    try {
      // Clear memory cache
      clearMemoryCache();

      // Clear disk cache
      final cleared = await _fileSystemService.clearCache();

      // Clear expiration tracking
      _cacheExpirations.clear();

      _logger.info('All cache data cleared');
      return cleared;
    } catch (e) {
      _logger.error('Failed to clear cache', exception: e);
      return false;
    }
  }

  @override
  Future<int> getSize() async {
    try {
      return await _fileSystemService.getCacheSize();
    } catch (e) {
      _logger.error('Failed to get cache size', exception: e);
      return 0;
    }
  }

  @override
  Future<int> cleanupExpired() async {
    try {
      final cacheDir = await _fileSystemService.getCacheDirectory();
      int cleanedCount = 0;

      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.endsWith('.cache')) {
          final fileName = path.basenameWithoutExtension(entity.path);
          final key = fileName;

          if (await isExpired(key)) {
            await remove(key);
            cleanedCount++;
          }
        }
      }

      _logger.info('Cleaned up $cleanedCount expired cache entries');
      return cleanedCount;
    } catch (e) {
      _logger.error('Failed to cleanup expired cache entries', exception: e);
      return 0;
    }
  }

  @override
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final totalSize = await getSize();
      int entryCount = 0;
      int expiredCount = 0;

      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.endsWith('.cache')) {
          entryCount++;
          final fileName = path.basenameWithoutExtension(entity.path);
          final key = fileName;

          if (await isExpired(key)) {
            expiredCount++;
          }
        }
      }

      return {
        'totalSize': totalSize,
        'entryCount': entryCount,
        'expiredCount': expiredCount,
        'memoryCacheSize': _memoryCache.length,
        'memoryCacheLimit': _memoryCacheLimit,
      };
    } catch (e) {
      _logger.error('Failed to get cache statistics', exception: e);
      return {
        'totalSize': await getSize(),
        'entryCount': 0,
        'expiredCount': 0,
        'memoryCacheSize': _memoryCache.length,
        'memoryCacheLimit': _memoryCacheLimit,
      };
    }
  }

  @override
  Future<bool> isExpired(String key) async {
    try {
      // Check in-memory expiration tracking first
      if (_cacheExpirations.containsKey(key)) {
        return DateTime.now().isAfter(_cacheExpirations[key]!);
      }

      // Check metadata file
      final cacheDir = await _fileSystemService.getCacheDirectory();
      final metadataFile = File(path.join(cacheDir.path, '$key.meta'));

      if (!await metadataFile.exists()) {
        return true; // No metadata means expired/invalid
      }

      final metadataJson = await metadataFile.readAsString();
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;

      final expiresAt = metadata['expiresAt'] as int?;
      if (expiresAt == null) {
        return false; // No expiration set
      }

      final expiration = DateTime.fromMillisecondsSinceEpoch(expiresAt);
      final isExpired = DateTime.now().isAfter(expiration);

      // Update in-memory tracking
      _cacheExpirations[key] = expiration;

      return isExpired;
    } catch (e) {
      _logger.error('Failed to check cache expiration: $key', exception: e);
      return true; // Assume expired on error
    }
  }

  @override
  Future<void> setExpiration(String key, DateTime expiration) async {
    try {
      validateKey(key);

      final cacheDir = await _fileSystemService.getCacheDirectory();
      final metadataFile = File(path.join(cacheDir.path, '$key.meta'));

      if (!await metadataFile.exists()) {
        throw AppError.validation('Cache entry does not exist: $key');
      }

      // Update metadata file
      final metadataJson = await metadataFile.readAsString();
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
      metadata['expiresAt'] = expiration.millisecondsSinceEpoch;
      await metadataFile.writeAsString(jsonEncode(metadata));

      // Update in-memory tracking
      _cacheExpirations[key] = expiration;

      _logger.debug('Updated cache expiration: $key -> $expiration');
    } catch (e) {
      _logger.error('Failed to set cache expiration: $key', exception: e);
      if (e is AppError) rethrow;
      throw AppError.storage(
        'Failed to set cache expiration',
        originalError: e,
      );
    }
  }

  @override
  void validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError('Cache key cannot be empty');
    }
    if (key.contains('/') || key.contains('\\')) {
      throw ArgumentError('Cache key cannot contain path separators');
    }
    if (key.contains(' ')) {
      throw ArgumentError('Cache key cannot contain spaces');
    }
    if (key.length > 250) {
      throw ArgumentError('Cache key too long (max 250 characters)');
    }
  }

  @override
  void storeInMemory(String key, Uint8List data) {
    validateKey(key);

    // Implement LRU eviction if limit exceeded
    if (_memoryCache.length >= _memoryCacheLimit &&
        !_memoryCache.containsKey(key)) {
      _evictOldestFromMemory();
    }

    _memoryCache[key] = data;
    _memoryCacheTimestamps[key] = DateTime.now();

    _logger.debug('Stored in memory cache: $key (${data.length} bytes)');
  }

  @override
  Uint8List? getFromMemory(String key) {
    final data = _memoryCache[key];
    if (data != null) {
      // Update timestamp for LRU
      _memoryCacheTimestamps[key] = DateTime.now();
    }
    return data;
  }

  @override
  void removeFromMemory(String key) {
    _memoryCache.remove(key);
    _memoryCacheTimestamps.remove(key);
  }

  @override
  void clearMemoryCache() {
    _memoryCache.clear();
    _memoryCacheTimestamps.clear();
    _logger.debug('Memory cache cleared');
  }

  @override
  int getMemoryCacheSize() {
    return _memoryCache.length;
  }

  @override
  void setMemoryCacheLimit(int maxEntries) {
    if (maxEntries <= 0) {
      throw ArgumentError('Memory cache limit must be positive');
    }

    _memoryCacheLimit = maxEntries;

    // Evict entries if current size exceeds new limit
    while (_memoryCache.length > _memoryCacheLimit) {
      _evictOldestFromMemory();
    }

    _logger.debug('Memory cache limit set to: $maxEntries');
  }

  /// Evict the oldest entry from memory cache (LRU)
  void _evictOldestFromMemory() {
    if (_memoryCacheTimestamps.isEmpty) return;

    // Find the oldest entry
    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _memoryCacheTimestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestKey = entry.key;
        oldestTime = entry.value;
      }
    }

    if (oldestKey != null) {
      removeFromMemory(oldestKey);
      _logger.debug('Evicted from memory cache: $oldestKey');
    }
  }
}
