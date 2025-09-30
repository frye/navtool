/// TDD Test Suite for ChartLoadError Factory Methods (T008)
/// Tests MUST FAIL until T021 implementation is complete.
///
/// Requirements Coverage:
/// - FR-020: Specific error messages for different failure types
/// - FR-021: Actionable troubleshooting suggestions
/// - R10: Structured error taxonomy with user guidance
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/features/charts/chart_load_error.dart';

void main() {
  group('ChartLoadError Factory Methods Tests (T008 - MUST FAIL)', () {
    test('T008.1: Extraction error with context and suggestions', () {
      // ACT: Create extraction error
      final error = ChartLoadError.extraction(
        'Failed to extract US5WA50M.000 from ZIP',
        detail: 'Archive does not contain expected .000 file',
        context: {'zipPath': '/path/to/chart.zip', 'chartId': 'US5WA50M'},
      );

      // ASSERT: Error properties
      expect(error.type, equals(ChartLoadErrorType.extraction));
      expect(error.message, contains('US5WA50M'));
      expect(error.detail, contains('.000'));
      expect(error.isRetryable, isTrue,
          reason: 'Extraction errors should be retryable');
      
      // ASSERT: Context includes diagnostic info
      expect(error.context!['zipPath'], equals('/path/to/chart.zip'));
      expect(error.context!['chartId'], equals('US5WA50M'));

      // ASSERT: Suggestions provided
      expect(error.suggestions, isNotEmpty,
          reason: 'Extraction errors should provide troubleshooting guidance');
      expect(error.suggestions.any((s) => s.contains('ZIP') || s.contains('archive')),
          isTrue,
          reason: 'Should suggest ZIP-related troubleshooting');
    });

    test('T008.2: Integrity error with expected and actual hashes', () {
      // ACT: Create integrity error with hash mismatch context
      final error = ChartLoadError.integrity(
        'Chart integrity verification failed for US5WA50M',
        detail: 'SHA256 hash does not match expected value',
        context: {
          'chartId': 'US5WA50M',
          'expectedHash': 'abc123def456',
          'actualHash': 'xyz789ghi012',
        },
      );

      // ASSERT: Error properties
      expect(error.type, equals(ChartLoadErrorType.integrity));
      expect(error.isRetryable, isFalse,
          reason: 'Integrity errors are not retryable');
      
      // ASSERT: Context includes hash comparison
      expect(error.context!['expectedHash'], equals('abc123def456'));
      expect(error.context!['actualHash'], equals('xyz789ghi012'));

      // ASSERT: Suggestions for integrity failures
      expect(error.suggestions, isNotEmpty);
      expect(error.suggestions.any((s) => s.contains('SHA256') || s.contains('hash')),
          isTrue,
          reason: 'Should suggest hash-related troubleshooting');
    });

    test('T008.3: Parsing error with retry context', () {
      // ACT: Create parsing error with retry count
      final error = ChartLoadError.parsing(
        'Failed to parse S-57 data after 3 retries',
        detail: 'Malformed record at offset 0x1234',
        context: {
          'chartId': 'US5WA50M',
          'retryCount': 3,
          'offset': '0x1234',
        },
      );

      // ASSERT: Error properties
      expect(error.type, equals(ChartLoadErrorType.parsing));
      expect(error.isRetryable, isTrue);
      expect(error.context!['retryCount'], equals(3));
      
      // ASSERT: Suggestions include parsing guidance
      expect(error.suggestions.any((s) => s.contains('parsing') || s.contains('S-57')),
          isTrue);
    });

    test('T008.4: Network error with retryable flag', () {
      // ACT: Create network error
      final error = ChartLoadError.network(
        'Network connection failed',
        detail: 'Unable to reach NOAA API server',
        context: {'url': 'https://api.noaa.gov/charts'},
      );

      // ASSERT: Network errors are retryable
      expect(error.type, equals(ChartLoadErrorType.network));
      expect(error.isRetryable, isTrue,
          reason: 'Network errors should be retryable');
      
      // ASSERT: Suggestions include connectivity guidance
      expect(error.suggestions.any((s) => s.contains('network') || s.contains('connectivity')),
          isTrue);
    });

    test('T008.5: Data not found error (not retryable)', () {
      // ACT: Create data not found error
      final error = ChartLoadError.dataNotFound(
        'Chart US5WA50M not found in local storage',
        context: {'chartId': 'US5WA50M'},
      );

      // ASSERT: Data not found errors are not retryable
      expect(error.type, equals(ChartLoadErrorType.dataNotFound));
      expect(error.isRetryable, isFalse,
          reason: 'Missing data won\'t be fixed by retry');
      
      // ASSERT: Suggestions include download/fixture guidance
      expect(error.suggestions.any((s) => s.contains('download') || s.contains('fixture')),
          isTrue);
    });

    test('T008.6: Cancelled error with minimal context', () {
      // ACT: Create cancelled error
      final error = ChartLoadError.cancelled(
        message: 'User cancelled chart load operation',
        context: {'chartId': 'US5WA50M'},
      );

      // ASSERT: Cancelled errors have minimal guidance
      expect(error.type, equals(ChartLoadErrorType.cancelled));
      expect(error.isRetryable, isFalse);
      expect(error.suggestions, isNotEmpty,
          reason: 'Should provide basic guidance even for cancellation');
    });

    test('T008.7: Error with timestamp and original exception', () {
      // ARRANGE: Original exception
      final originalException = FormatException('Invalid S-57 format');
      final stackTrace = StackTrace.current;

      // ACT: Create error with exception details
      final error = ChartLoadError.parsing(
        'Parsing failed',
        error: originalException,
        stackTrace: stackTrace,
      );

      // ASSERT: Exception details preserved
      expect(error.originalError, equals(originalException));
      expect(error.stackTrace, isNotNull);
      expect(error.timestamp, isNotNull,
          reason: 'Should auto-generate timestamp');
      
      // Timestamp should be recent (within last second)
      final now = DateTime.now();
      final diff = now.difference(error.timestamp).inSeconds;
      expect(diff, lessThan(2),
          reason: 'Timestamp should be current');
    });
  });

  group('ChartLoadError Suggestions Tests (T008 Extended)', () {
    test('T008.8: Extraction error suggestions are actionable', () {
      // ACT: Get extraction error suggestions
      final error = ChartLoadError.extraction('Test extraction failure');
      final suggestions = error.suggestions;

      // ASSERT: Suggestions are specific and actionable
      expect(suggestions.length, greaterThanOrEqualTo(2),
          reason: 'Should provide multiple troubleshooting steps');
      
      // Check for specific keywords
      final allText = suggestions.join(' ').toLowerCase();
      expect(allText.contains('zip') || allText.contains('archive'), isTrue);
      expect(allText.contains('verify') || allText.contains('check'), isTrue);
    });

    test('T008.9: Integrity error suggestions mention hash verification', () {
      final error = ChartLoadError.integrity('Integrity check failed');
      final suggestions = error.suggestions;

      final allText = suggestions.join(' ').toLowerCase();
      expect(allText.contains('sha256') || allText.contains('hash'), isTrue);
      expect(allText.contains('download') || allText.contains('re-download'), isTrue);
    });

    test('T008.10: Parsing error suggestions include validation steps', () {
      final error = ChartLoadError.parsing('Parse failure');
      final suggestions = error.suggestions;

      final allText = suggestions.join(' ').toLowerCase();
      expect(allText.contains('parsing') || allText.contains('s-57'), isTrue);
      expect(allText.contains('console') || allText.contains('log'), isTrue);
    });
  });

  group('ChartLoadError JSON Serialization (T008 Extended)', () {
    test('T008.11: Error context serializes to JSON for logging', () {
      // ACT: Create error with rich context
      final error = ChartLoadError.extraction(
        'Extraction failed',
        context: {
          'chartId': 'US5WA50M',
          'zipSize': 147000,
          'expectedFile': 'US5WA50M.000',
        },
      );

      // ASSERT: Context can be serialized (for logging/debugging)
      expect(error.context, isNotNull);
      expect(error.context!['chartId'], equals('US5WA50M'));
      expect(error.context!['zipSize'], equals(147000));
      expect(error.context!['expectedFile'], equals('US5WA50M.000'));
    });
  });
}
