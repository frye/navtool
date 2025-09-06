import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';

void main() {
  group('Direct Archive Test', () {
    testWidgets('should extract ZIP using archive package directly', (tester) async {
      final zipFile = File('test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip');
      
      if (!zipFile.existsSync()) {
        print('ZIP file not found, skipping test');
        return;
      }
      
      print('Reading ZIP file: ${zipFile.path}');
      final zipData = await zipFile.readAsBytes();
      print('ZIP data size: ${zipData.length} bytes');
      
      print('Starting ZIP decoding...');
      final stopwatch = Stopwatch()..start();
      
      try {
        final archive = ZipDecoder().decodeBytes(zipData);
        stopwatch.stop();
        
        print('ZIP decoded successfully in ${stopwatch.elapsedMilliseconds}ms');
        print('Archive contains ${archive.files.length} files:');
        
        for (final file in archive.files) {
          if (file.isFile) {
            print('  ${file.name} (${file.size} bytes)');
            
            if (file.name.endsWith('.000')) {
              print('    -> This is the main chart file');
            }
          }
        }
        
        // Test passed
        expect(archive.files.length, greaterThan(0));
        
      } catch (e, stackTrace) {
        stopwatch.stop();
        print('Error after ${stopwatch.elapsedMilliseconds}ms: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      }
    });
  });
}