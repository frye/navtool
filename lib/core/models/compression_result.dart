import 'dart:typed_data';

/// Represents the result of a compression operation
class CompressionResult {
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  final Duration compressionTime;
  final Uint8List compressedData;

  const CompressionResult({
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
    required this.compressionTime,
    required this.compressedData,
  });

  /// Calculate space saved in bytes
  int get spaceSaved => originalSize - compressedSize;

  /// Calculate compression percentage (0-100)
  double get compressionPercentage => (1.0 - compressionRatio) * 100.0;

  /// Check if compression was effective (saved at least 10% space)
  bool get isEffective => compressionRatio <= 0.9;

  @override
  String toString() {
    return 'CompressionResult(original: ${originalSize}B, compressed: ${compressedSize}B, '
           'ratio: ${(compressionRatio * 100).toStringAsFixed(1)}%, '
           'time: ${compressionTime.inMilliseconds}ms)';
  }
}

/// Compression levels for different use cases
enum CompressionLevel {
  /// Fast compression for real-time operations
  fast,
  
  /// Balanced compression for general use
  balanced,
  
  /// Maximum compression for storage optimization
  maximum;

  /// Get compression level value for archive library
  int get level {
    switch (this) {
      case CompressionLevel.fast:
        return 1;
      case CompressionLevel.balanced:
        return 6;
      case CompressionLevel.maximum:
        return 9;
    }
  }

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case CompressionLevel.fast:
        return 'Fast';
      case CompressionLevel.balanced:
        return 'Balanced';
      case CompressionLevel.maximum:
        return 'Maximum';
    }
  }
}

/// Represents a file extracted from an archive
class ExtractedFile {
  final String fileName;
  final Uint8List data;
  final DateTime? lastModified;
  final bool isChartFile;

  const ExtractedFile({
    required this.fileName,
    required this.data,
    this.lastModified,
    required this.isChartFile,
  });

  /// Check if this is an S-57 chart file
  bool get isS57ChartFile {
    final extension = fileName.toLowerCase().split('.').last;
    return extension.length == 3 && 
           (extension.startsWith('00') || extension.startsWith('01') || extension.startsWith('02'));
  }

  /// Get file size in bytes
  int get size => data.length;

  @override
  String toString() {
    return 'ExtractedFile(name: $fileName, size: ${size}B, isChart: $isChartFile)';
  }
}

/// Advanced compression settings
class CompressionSettings {
  final CompressionLevel level;
  final bool enableDictionary;
  final int chunkSize;
  final int memoryLevel;
  final bool enableChecksum;

  CompressionSettings({
    required this.level,
    this.enableDictionary = false,
    this.chunkSize = 16384,
    this.memoryLevel = 8,
    this.enableChecksum = true,
  }) {
    // Validate settings in constructor
    if (chunkSize <= 0) {
      throw ArgumentError('Chunk size must be positive');
    }
    if (memoryLevel < 1 || memoryLevel > 9) {
      throw ArgumentError('Memory level must be between 1 and 9');
    }
  }

  /// Validate compression settings (optional call for explicit validation)
  void validate() {
    // Validation is already done in constructor
  }

  @override
  String toString() {
    return 'CompressionSettings(level: ${level.displayName}, '
           'dictionary: $enableDictionary, chunk: ${chunkSize}B, '
           'memory: $memoryLevel, checksum: $enableChecksum)';
  }
}
