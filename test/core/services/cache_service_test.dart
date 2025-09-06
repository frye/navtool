import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/core/services/cache_service.dart';
import 'package:navtool/core/services/cache_service_impl.dart';
import 'package:navtool/core/services/file_system_service.dart';
import 'package:navtool/core/services/compression_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:navtool/core/models/compression_result.dart';
import '../../helpers/verify_helpers.dart';

// Generate mocks for dependencies
@GenerateMocks([AppLogger, FileSystemService, CompressionService])
import 'cache_service_test.mocks.dart';

void main() {
  group('CacheService Tests', () {
    late CacheServiceImpl cacheService;
    late MockAppLogger mockLogger;
    late MockFileSystemService mockFileSystem;
    late MockCompressionService mockCompression;

    setUp(() {
      mockLogger = MockAppLogger();
      mockFileSystem = MockFileSystemService();
      mockCompression = MockCompressionService();

      cacheService = CacheServiceImpl(
        logger: mockLogger,
        fileSystemService: mockFileSystem,
        compressionService: mockCompression,
      );
    });

    group('Cache Storage Operations', () {
      test('should store cache data with key', () async {
        // Arrange
        const cacheKey = 'test_cache_key';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        const maxAge = Duration(hours: 24);

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);
        when(
          mockCompression.compressCacheData(
            any,
            cacheKey: anyNamed('cacheKey'),
          ),
        ).thenAnswer(
          (_) async => CompressionResult(
            originalSize: 5,
            compressedSize: 3,
            compressionRatio: 0.6,
            compressionTime: Duration(milliseconds: 10),
            compressedData: Uint8List.fromList([1, 2, 3]),
          ),
        );

        // Act
        await cacheService.store(cacheKey, data, maxAge: maxAge);

        // Assert
        verify(mockFileSystem.getCacheDirectory()).called(1);
        verify(
          mockCompression.compressCacheData(data, cacheKey: cacheKey),
        ).called(1);
        // Verify storing and stored debug logs occurred
        verifyDebugLogged(mockLogger, 'Storing cache data:');
        verifyDebugLogged(mockLogger, 'Cache data stored:');
      });

      test('should retrieve cached data by key', () async {
        // Arrange
        const cacheKey = 'test_cache_key';
        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Store in memory cache first
        cacheService.storeInMemory(cacheKey, testData);

        // Act
        final result = await cacheService.get(cacheKey);

        // Assert - Should get from memory cache
        expect(result, equals(testData));
      });

      test('should check if cache key exists', () async {
        // Arrange
        const cacheKey = 'test_cache_key';
        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Store in memory cache first
        cacheService.storeInMemory(cacheKey, testData);

        // Act
        final exists = await cacheService.exists(cacheKey);

        // Assert - Should exist in memory cache
        expect(exists, isTrue);
      });

      test('should remove cached data by key', () async {
        // Arrange
        const cacheKey = 'test_cache_key';

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);

        // Act
        await cacheService.remove(cacheKey);

        // Assert
        verify(mockFileSystem.getCacheDirectory()).called(1);
        verifyInfoLogged(mockLogger, 'Cache entry removed:');
      });
    });

    group('Cache Management Operations', () {
      test('should clear all cache data', () async {
        // Arrange
        when(mockFileSystem.clearCache()).thenAnswer((_) async => true);

        // Act
        final cleared = await cacheService.clear();

        // Assert
        expect(cleared, isTrue);
        verify(mockFileSystem.clearCache()).called(1);
        verifyInfoLogged(mockLogger, 'All cache data cleared');
      });

      test('should get total cache size', () async {
        // Arrange
        const expectedSize = 1024;
        when(
          mockFileSystem.getCacheSize(),
        ).thenAnswer((_) async => expectedSize);

        // Act
        final size = await cacheService.getSize();

        // Assert
        expect(size, equals(expectedSize));
        verify(mockFileSystem.getCacheSize()).called(1);
      });

      test('should clean up expired cache entries', () async {
        // Arrange
        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);

        // Act
        final cleanedCount = await cacheService.cleanupExpired();

        // Assert
        expect(cleanedCount, isA<int>());
        verify(mockFileSystem.getCacheDirectory()).called(1);
        verifyInfoLogged(mockLogger, 'Cleaned up');
      });

      test('should get cache statistics', () async {
        // Arrange
        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);
        when(mockFileSystem.getCacheSize()).thenAnswer((_) async => 2048);

        // Act
        final stats = await cacheService.getStatistics();

        // Assert
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats, containsPair('totalSize', 2048));
        expect(stats, containsPair('entryCount', 0)); // No files in test
        verify(mockFileSystem.getCacheSize()).called(1);
      });
    });

    group('Cache Expiration', () {
      test('should handle cache expiration correctly', () async {
        // Arrange
        const cacheKey = 'expired_key';

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);

        // Act
        final isExpired = await cacheService.isExpired(cacheKey);

        // Assert
        expect(isExpired, isTrue); // Non-existent cache is considered expired
        verify(mockFileSystem.getCacheDirectory()).called(1);
      });

      test('should set cache expiration time', () async {
        // Arrange
        const cacheKey = 'test_key';
        final expiration = DateTime.now().add(Duration(hours: 1));

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);

        // Act & Assert - Should handle non-existent cache entry gracefully
        expect(
          () async => await cacheService.setExpiration(cacheKey, expiration),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Error Handling', () {
      test('should handle storage errors gracefully', () async {
        // Arrange
        const cacheKey = 'error_key';
        final data = Uint8List.fromList([1, 2, 3]);

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenThrow(Exception('Storage error'));

        // Act & Assert
        expect(
          () async => await cacheService.store(cacheKey, data),
          throwsA(isA<AppError>()),
        );
        verifyErrorLogged(mockLogger, 'Failed');
      });

      test('should handle compression errors gracefully', () async {
        // Arrange
        const cacheKey = 'compression_error_key';
        final data = Uint8List.fromList([1, 2, 3]);

        when(
          mockFileSystem.getCacheDirectory(),
        ).thenAnswer((_) async => Directory.systemTemp);
        when(
          mockCompression.compressCacheData(
            any,
            cacheKey: anyNamed('cacheKey'),
          ),
        ).thenThrow(AppError.storage('Compression failed'));

        // Act & Assert
        expect(
          () async => await cacheService.store(cacheKey, data),
          throwsA(isA<AppError>()),
        );
      });
    });

    group('Cache Key Validation', () {
      test('should validate cache keys', () {
        // Arrange & Act & Assert
        expect(() => cacheService.validateKey('valid_key'), returnsNormally);
        expect(
          () => cacheService.validateKey(''),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => cacheService.validateKey('key/with/slashes'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => cacheService.validateKey('key with spaces'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Memory Cache Integration', () {
      test(
        'should integrate with memory cache for frequently accessed data',
        () async {
          // Arrange
          const cacheKey = 'memory_cache_key';
          final data = Uint8List.fromList([1, 2, 3, 4, 5]);

          // Act - Store in memory cache
          cacheService.storeInMemory(cacheKey, data);

          // Assert - Should retrieve from memory
          final result = cacheService.getFromMemory(cacheKey);
          expect(result, equals(data));
        },
      );

      test('should evict old entries from memory cache when limit reached', () {
        // Arrange
        const maxEntries = 3;
        cacheService.setMemoryCacheLimit(maxEntries);

        // Act - Add more entries than limit
        for (int i = 0; i < maxEntries + 2; i++) {
          cacheService.storeInMemory('key_$i', Uint8List.fromList([i]));
        }

        // Assert - Should only have maxEntries
        expect(cacheService.getMemoryCacheSize(), equals(maxEntries));
      });
    });
  });
}
