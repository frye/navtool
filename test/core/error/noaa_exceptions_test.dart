import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/error/noaa_exceptions.dart';

void main() {
  group('NoaaApiException Tests', () {
    test('should create NoaaApiException with required parameters', () {
      // Arrange & Act
      const exception = NoaaApiException('Test error message');
      
      // Assert
      expect(exception.message, 'Test error message');
      expect(exception.errorCode, isNull);
      expect(exception.isRetryable, isTrue); // Default value
      expect(exception.metadata, isNull);
    });

    test('should create NoaaApiException with all parameters', () {
      // Arrange
      const metadata = {'requestId': '123', 'endpoint': '/catalog'};
      
      // Act
      const exception = NoaaApiException(
        'Detailed error message',
        errorCode: 'NOAA_001',
        isRetryable: false,
        metadata: metadata,
      );
      
      // Assert
      expect(exception.message, 'Detailed error message');
      expect(exception.errorCode, 'NOAA_001');
      expect(exception.isRetryable, isFalse);
      expect(exception.metadata, metadata);
    });

    test('should return formatted string representation', () {
      // Arrange
      const exception = NoaaApiException(
        'Network error',
        errorCode: 'NOAA_NET_001',
      );
      
      // Act
      final stringRep = exception.toString();
      
      // Assert
      expect(stringRep, 'NoaaApiException: Network error (NOAA_NET_001)');
    });

    test('should return simple string representation without error code', () {
      // Arrange
      const exception = NoaaApiException('Simple error');
      
      // Act
      final stringRep = exception.toString();
      
      // Assert
      expect(stringRep, 'NoaaApiException: Simple error');
    });
  });

  group('ChartNotAvailableException Tests', () {
    test('should create exception with chart cell name', () {
      // Arrange & Act
      final exception = ChartNotAvailableException('US5CA52M');
      
      // Assert
      expect(exception.message, 'Chart US5CA52M is not available from NOAA');
      expect(exception.errorCode, 'CHART_NOT_AVAILABLE');
      expect(exception.isRetryable, isFalse);
      expect(exception.chartCellName, 'US5CA52M');
    });

    test('should be instance of NoaaApiException', () {
      // Arrange & Act
      final exception = ChartNotAvailableException('US1AK90M');
      
      // Assert
      expect(exception, isA<NoaaApiException>());
    });

    test('should include chart cell name in metadata', () {
      // Arrange & Act
      final exception = ChartNotAvailableException('US4FL11M');
      
      // Assert
      expect(exception.metadata, isNotNull);
      expect(exception.metadata!['chartCellName'], 'US4FL11M');
    });
  });

  group('NetworkConnectivityException Tests', () {
    test('should create exception with default message', () {
      // Arrange & Act
      const exception = NetworkConnectivityException();
      
      // Assert
      expect(exception.message, 'No internet connection available');
      expect(exception.errorCode, 'NETWORK_CONNECTIVITY');
      expect(exception.isRetryable, isTrue);
    });

    test('should create exception with custom message', () {
      // Arrange & Act
      const exception = NetworkConnectivityException(
        'Satellite connection timeout',
      );
      
      // Assert
      expect(exception.message, 'Satellite connection timeout');
      expect(exception.errorCode, 'NETWORK_CONNECTIVITY');
      expect(exception.isRetryable, isTrue);
    });

    test('should be instance of NoaaApiException', () {
      // Arrange & Act
      const exception = NetworkConnectivityException();
      
      // Assert
      expect(exception, isA<NoaaApiException>());
    });
  });

  group('RateLimitExceededException Tests', () {
    test('should create exception with default message', () {
      // Arrange & Act
      final exception = RateLimitExceededException();
      
      // Assert
      expect(exception.message, 'Rate limit exceeded for NOAA API requests');
      expect(exception.errorCode, 'RATE_LIMIT_EXCEEDED');
      expect(exception.isRetryable, isTrue);
    });

    test('should create exception with retry after duration', () {
      // Arrange & Act
      final exception = RateLimitExceededException(
        retryAfter: Duration(seconds: 30),
      );
      
      // Assert
      expect(exception.retryAfter, const Duration(seconds: 30));
      expect(exception.metadata!['retryAfterSeconds'], 30);
    });

    test('should create exception with custom message and retry duration', () {
      // Arrange & Act
      final exception = RateLimitExceededException(
        message: 'Too many catalog requests',
        retryAfter: Duration(minutes: 1),
      );
      
      // Assert
      expect(exception.message, 'Too many catalog requests');
      expect(exception.retryAfter, const Duration(minutes: 1));
      expect(exception.metadata!['retryAfterSeconds'], 60);
    });
  });

  group('ChartDownloadException Tests', () {
    test('should create exception with chart cell name', () {
      // Arrange & Act
      final exception = ChartDownloadException(
        'US5CA52M',
        'Download failed due to server error',
      );
      
      // Assert
      expect(exception.message, 'Download failed due to server error');
      expect(exception.errorCode, 'CHART_DOWNLOAD_FAILED');
      expect(exception.isRetryable, isTrue);
      expect(exception.chartCellName, 'US5CA52M');
    });

    test('should create non-retryable exception', () {
      // Arrange & Act
      final exception = ChartDownloadException(
        'US1AK90M',
        'File corrupted and cannot be downloaded',
        isRetryable: false,
      );
      
      // Assert
      expect(exception.isRetryable, isFalse);
      expect(exception.chartCellName, 'US1AK90M');
    });

    test('should include download progress in metadata', () {
      // Arrange & Act
      final exception = ChartDownloadException(
        'US4FL11M',
        'Download interrupted',
        bytesDownloaded: 1024,
        totalBytes: 2048,
      );
      
      // Assert
      expect(exception.metadata!['chartCellName'], 'US4FL11M');
      expect(exception.metadata!['bytesDownloaded'], 1024);
      expect(exception.metadata!['totalBytes'], 2048);
      expect(exception.metadata!['progressPercent'], 50.0);
    });
  });

  group('NoaaServiceUnavailableException Tests', () {
    test('should create exception with default message', () {
      // Arrange & Act
      final exception = NoaaServiceUnavailableException();
      
      // Assert
      expect(exception.message, 'NOAA service is temporarily unavailable');
      expect(exception.errorCode, 'SERVICE_UNAVAILABLE');
      expect(exception.isRetryable, isTrue);
    });

    test('should create exception with maintenance message', () {
      // Arrange & Act
      final exception = NoaaServiceUnavailableException(
        'Service under maintenance until 14:00 UTC',
      );
      
      // Assert
      expect(exception.message, 'Service under maintenance until 14:00 UTC');
    });

    test('should include HTTP status code in metadata', () {
      // Arrange & Act
      final exception = NoaaServiceUnavailableException(
        'Service temporarily unavailable',
        503,
      );

      // Assert
      expect(exception.metadata!['httpStatusCode'], 503);
    });
  });
}
