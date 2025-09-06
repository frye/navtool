import 'dart:typed_data';

/// Service interface for caching operations
/// Provides unified access to both memory and disk caching with compression
abstract class CacheService {
  /// Store data in cache with optional expiration
  Future<void> store(String key, Uint8List data, {Duration? maxAge});

  /// Retrieve data from cache
  /// Returns null if key doesn't exist or has expired
  Future<Uint8List?> get(String key);

  /// Check if a cache key exists and is not expired
  Future<bool> exists(String key);

  /// Remove data from cache
  Future<void> remove(String key);

  /// Clear all cached data
  Future<bool> clear();

  /// Get total cache size in bytes
  Future<int> getSize();

  /// Clean up expired cache entries
  /// Returns the number of entries cleaned up
  Future<int> cleanupExpired();

  /// Get cache statistics
  Future<Map<String, dynamic>> getStatistics();

  /// Check if a cache entry has expired
  Future<bool> isExpired(String key);

  /// Set expiration time for a cache entry
  Future<void> setExpiration(String key, DateTime expiration);

  /// Validate cache key format
  void validateKey(String key);

  // Memory cache operations for frequently accessed data

  /// Store data in memory cache (fast access)
  void storeInMemory(String key, Uint8List data);

  /// Get data from memory cache
  Uint8List? getFromMemory(String key);

  /// Remove from memory cache
  void removeFromMemory(String key);

  /// Clear memory cache
  void clearMemoryCache();

  /// Get memory cache size (number of entries)
  int getMemoryCacheSize();

  /// Set memory cache limit
  void setMemoryCacheLimit(int maxEntries);
}
