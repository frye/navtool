# HTTP Client Integration for NOAA API

This document describes the HTTP client implementation for NavTool's NOAA chart integration.

## Overview

The HTTP client infrastructure provides robust, marine-environment optimized network operations for downloading NOAA Electronic Navigational Charts (ENCs).

## Key Components

### HttpClientService

Core HTTP client service using Dio for enhanced networking capabilities:

```dart
final httpClient = HttpClientService(logger: logger);
httpClient.configureNoaaEndpoints();
httpClient.configureCertificatePinning();
```

**Features:**
- Marine environment optimized timeouts (30s connect, 10min receive)
- Automatic retry with exponential backoff
- Request/response logging
- Certificate pinning for secure downloads
- User-Agent headers for NOAA compatibility

### DownloadServiceImpl

Concrete implementation of the DownloadService interface:

```dart
final downloadService = DownloadServiceImpl(
  httpClient: httpClient,
  storageService: storageService,
  logger: logger,
  errorHandler: errorHandler,
);

// Download a chart
await downloadService.downloadChart('US5CA52M', 'https://charts.noaa.gov/...');

// Track progress
downloadService.getDownloadProgress('US5CA52M').listen((progress) {
  print('Download progress: ${progress.toStringAsFixed(1)}%');
});
```

**Features:**
- Progress tracking with broadcast streams
- Cancel/pause/resume capabilities
- Queue management
- Automatic file verification
- Cleanup on cancellation

### NetworkError

Comprehensive network error handling for marine environments:

```dart
try {
  await httpClient.get('/api/charts');
} catch (error) {
  final userMessage = NetworkError.getUserFriendlyMessage(error);
  final action = NetworkError.getRecommendedAction(error);
  final canRetry = NetworkError.isRetryable(error);
}
```

**Features:**
- User-friendly error messages
- Retry recommendations
- Connection type detection
- Marine-specific guidance

## Marine Environment Considerations

### Timeouts
- **Connection Timeout**: 30 seconds (accommodates satellite connections)
- **Receive Timeout**: 10 minutes (large chart file downloads)
- **Send Timeout**: 5 minutes (metadata uploads)

### Retry Logic
- **Max Retries**: 3 attempts with exponential backoff
- **Base Delay**: 2 seconds (doubled for each retry)
- **Retryable Conditions**: Network timeouts, server errors (5xx)

### Download Optimization
- **Chunk Size**: 1MB for resumable downloads
- **Concurrent Downloads**: Limited to 2 (conservative for bandwidth)
- **Progress Tracking**: Real-time updates for UI responsiveness

## Usage Examples

### Basic Chart Download

```dart
// Initialize services
final logger = ConsoleLogger();
final httpClient = HttpClientService(logger: logger);
final storageService = FileStorageService();
final downloadService = DownloadServiceImpl(
  httpClient: httpClient,
  storageService: storageService,
  logger: logger,
  errorHandler: ErrorHandler(logger: logger),
);

// Configure for NOAA
httpClient.configureNoaaEndpoints();

// Download chart
try {
  await downloadService.downloadChart(
    'US5CA52M', 
    'https://charts.noaa.gov/ENCs/US5CA52M.zip'
  );
  print('Chart downloaded successfully');
} catch (error) {
  print('Download failed: ${NetworkError.getUserFriendlyMessage(error)}');
}
```

### Progress Monitoring

```dart
// Monitor download progress
final progressStream = downloadService.getDownloadProgress('US5CA52M');
final subscription = progressStream.listen(
  (progress) => print('Progress: ${progress.toStringAsFixed(1)}%'),
  onError: (error) => print('Error: $error'),
  onDone: () => print('Download completed'),
);

// Cancel if needed
Timer(Duration(minutes: 5), () {
  downloadService.cancelDownload('US5CA52M');
  subscription.cancel();
});
```

## Error Handling

### Network Error Types

1. **Connection Errors**: No internet, DNS resolution failures
2. **Timeout Errors**: Connection, send, or receive timeouts
3. **HTTP Errors**: 4xx client errors, 5xx server errors
4. **Certificate Errors**: SSL/TLS verification failures
5. **Cancellation**: User or system initiated cancellation

### Recovery Strategies

- **No Connection**: Suggest checking internet connection
- **Timeout**: Automatic retry with exponential backoff
- **Server Error**: Suggest trying again later
- **Client Error**: Check chart availability and permissions
- **Certificate Error**: Report security issue to user

## Configuration

### Marine Network Configuration

```dart
class MarineNetworkConfig {
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(minutes: 10);
  static const Duration sendTimeout = Duration(minutes: 5);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const int maxConcurrentDownloads = 2;
  static const int downloadChunkSize = 1024 * 1024; // 1MB
}
```

### NOAA API Configuration

- **Base URL**: `https://charts.noaa.gov`
- **User Agent**: `NavTool/1.0.0 (Marine Navigation App)`
- **Accept Types**: `application/octet-stream, application/json, */*`
- **Follow Redirects**: Up to 5 redirects
- **Certificate Pinning**: Enabled for security

## Integration with Riverpod

The HTTP services are integrated with Riverpod for dependency injection:

```dart
// Access HTTP client
final httpClient = ref.read(httpClientServiceProvider);

// Access download service  
final downloadService = ref.read(downloadServiceProvider);

// Monitor download progress
final isDownloading = ref.watch(isDownloadingProvider);
```

## Security Considerations

- Certificate pinning prevents man-in-the-middle attacks
- HTTPS-only connections to NOAA services
- Validation of downloaded chart integrity
- Secure storage of downloaded charts
- No sensitive data in logs or error messages