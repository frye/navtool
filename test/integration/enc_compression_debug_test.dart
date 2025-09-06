import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/compression_service_impl.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/app_error.dart';
import '../utils/enc_test_utilities.dart';

void main() {
  group('ENC Compression Debug Tests', () {
    testWidgets('should extract ZIP file contents', (tester) async {
      final fixtures = EncTestUtilities.discoverFixtures();
      
      if (!fixtures.hasPrimaryChart) {
        print('No fixtures available for ZIP extraction test');
        return;
      }
      
      print('Testing ZIP extraction for: ${fixtures.primaryChartPath}');
      
      final zipFile = File(fixtures.primaryChartPath!);
      final zipData = await zipFile.readAsBytes();
      
      print('ZIP file size: ${zipData.length} bytes');
      
      final compressionService = CompressionServiceImpl(logger: _TestLoggerAdapter());
      
      try {
        final extractedFiles = await compressionService.extractChartArchive(
          zipData,
          chartId: 'TEST',
        );
        
        print('Extracted ${extractedFiles.length} files:');
        for (final file in extractedFiles) {
          print('  ${file.fileName} (${file.size} bytes) - isChart: ${file.isChartFile}');
        }
        
        expect(extractedFiles, isNotEmpty);
        
        // Look for .000 file
        final chartFile = extractedFiles.where((f) => f.fileName.endsWith('.000')).firstOrNull;
        if (chartFile != null) {
          print('Found chart file: ${chartFile.fileName} (${chartFile.size} bytes)');
        } else {
          print('No .000 chart file found');
        }
        
      } catch (e, stackTrace) {
        print('Error during extraction: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      }
    });
  });
}

// Simple logger adapter for testing
class _TestLoggerAdapter implements AppLogger {
  @override
  void info(String message, {String? context, Object? exception}) {
    print('[INFO]${context != null ? ' [$context]' : ''} $message${exception != null ? ' | $exception' : ''}');
  }
  
  @override
  void debug(String message, {String? context, Object? exception}) {
    print('[DEBUG]${context != null ? ' [$context]' : ''} $message${exception != null ? ' | $exception' : ''}');
  }
  
  @override
  void warning(String message, {String? context, Object? exception}) {
    print('[WARN]${context != null ? ' [$context]' : ''} $message${exception != null ? ' | $exception' : ''}');
  }
  
  @override
  void error(String message, {String? context, Object? exception}) {
    print('[ERROR]${context != null ? ' [$context]' : ''} $message${exception != null ? ' | $exception' : ''}');
  }
  
  @override
  void logError(AppError error) {
    print('[ERROR] AppError: ${error.message}');
  }
}