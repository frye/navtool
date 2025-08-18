/// NOAA-specific exception classes for robust API error handling
/// 
/// This file defines a comprehensive hierarchy of exceptions for handling
/// various error scenarios that can occur when communicating with NOAA APIs.
/// All exceptions include error codes, retry flags, and metadata for debugging.

/// Base exception class for all NOAA API-related errors
class NoaaApiException implements Exception {
  const NoaaApiException(
    this.message, {
    this.errorCode,
    this.isRetryable = true,
    this.metadata,
  });

  /// Human-readable error message
  final String message;
  
  /// Optional error code for programmatic handling
  final String? errorCode;
  
  /// Whether this error can be retried
  final bool isRetryable;
  
  /// Additional metadata for debugging and context
  final Map<String, dynamic>? metadata;

  @override
  String toString() {
    if (errorCode != null) {
      return 'NoaaApiException: $message ($errorCode)';
    }
    return 'NoaaApiException: $message';
  }
}

/// Exception thrown when a requested chart is not available from NOAA
class ChartNotAvailableException extends NoaaApiException {
  ChartNotAvailableException(this.chartCellName)
    : super(
        'Chart $chartCellName is not available from NOAA',
        errorCode: 'CHART_NOT_AVAILABLE',
        isRetryable: false,
        metadata: {'chartCellName': chartCellName},
      );

  /// The chart cell name that was not found
  final String chartCellName;
}/// Exception thrown when there are network connectivity issues
class NetworkConnectivityException extends NoaaApiException {
  const NetworkConnectivityException([
    String message = 'No internet connection available',
  ]) : super(
        message,
        errorCode: 'NETWORK_CONNECTIVITY',
        isRetryable: true,
      );
}

/// Exception thrown when API rate limits are exceeded
class RateLimitExceededException extends NoaaApiException {
  RateLimitExceededException({
    String message = 'Rate limit exceeded for NOAA API requests',
    this.retryAfter,
  }) : super(
        message,
        errorCode: 'RATE_LIMIT_EXCEEDED',
        isRetryable: true,
        metadata: retryAfter != null
          ? {'retryAfterSeconds': retryAfter!.inSeconds}
          : null,
      );

  /// Duration to wait before retrying
  final Duration? retryAfter;
}/// Exception thrown when chart download operations fail
class ChartDownloadException extends NoaaApiException {
  ChartDownloadException(
    this.chartCellName,
    String message, {
    bool isRetryable = true,
    this.bytesDownloaded,
    this.totalBytes,
  }) : super(
        message,
        errorCode: 'CHART_DOWNLOAD_FAILED',
        isRetryable: isRetryable,
        metadata: _buildMetadata(chartCellName, bytesDownloaded, totalBytes),
      );

  /// The chart cell name being downloaded
  final String chartCellName;

  /// Number of bytes successfully downloaded (if known)
  final int? bytesDownloaded;

  /// Total number of bytes to download (if known)
  final int? totalBytes;

  static Map<String, dynamic> _buildMetadata(
    String chartCellName,
    int? bytesDownloaded,
    int? totalBytes,
  ) {
    final metadata = <String, dynamic>{'chartCellName': chartCellName};

    if (bytesDownloaded != null) {
      metadata['bytesDownloaded'] = bytesDownloaded;
    }

    if (totalBytes != null) {
      metadata['totalBytes'] = totalBytes;
    }

    if (bytesDownloaded != null && totalBytes != null && totalBytes > 0) {
      metadata['progressPercent'] = (bytesDownloaded / totalBytes) * 100.0;
    }

    return metadata;
  }
}

/// Exception thrown when NOAA services are temporarily unavailable
class NoaaServiceUnavailableException extends NoaaApiException {
  NoaaServiceUnavailableException([
    String message = 'NOAA service is temporarily unavailable',
    this.httpStatusCode,
  ]) : super(
        message,
        errorCode: 'SERVICE_UNAVAILABLE',
        isRetryable: true,
        metadata: httpStatusCode != null
          ? {'httpStatusCode': httpStatusCode}
          : null,
      );

  /// HTTP status code if available
  final int? httpStatusCode;
}