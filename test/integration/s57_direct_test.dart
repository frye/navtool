import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';

void main() {
  group('S57 Direct File Test', () {
    testWidgets('should parse S57 file directly from extracted content', (tester) async {
      // Extract the ZIP file to temp directory
      final tempDir = Directory('/tmp/enc_test_direct');
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      
      // Extract the ZIP file using system unzip command
      final zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
      final result = await Process.run('unzip', ['-q', zipPath, '-d', tempDir.path]);
      
      if (result.exitCode != 0) {
        print('Failed to extract ZIP file: ${result.stderr}');
        return;
      }
      
      // Find the .000 file
      final chartFile = File('${tempDir.path}/ENC_ROOT/US5WA50M/US5WA50M.000');
      
      if (!chartFile.existsSync()) {
        print('Chart file not found after extraction');
        return;
      }
      
      print('Reading S57 chart file: ${chartFile.path}');
      final s57Data = await chartFile.readAsBytes();
      print('S57 file size: ${s57Data.length} bytes');
      
      print('Parsing S57 data...');
      final stopwatch = Stopwatch()..start();
      
      try {
        final parsedData = S57Parser.parse(s57Data);
        stopwatch.stop();
        
        print('S57 parsing completed in ${stopwatch.elapsedMilliseconds}ms');
        print('Features found: ${parsedData.features.length}');
        print('Bounds: ${parsedData.bounds.toMap()}');
        
        // Count feature types
        final frequencyMap = <String, int>{};
        for (final feature in parsedData.features) {
          final acronym = feature.featureType.acronym;
          frequencyMap[acronym] = (frequencyMap[acronym] ?? 0) + 1;
        }
        
        print('Feature frequency:');
        frequencyMap.forEach((type, count) {
          print('  $type: $count');
        });
        
        // Basic validations
        expect(parsedData.features, isNotEmpty);
        expect(parsedData.bounds.isValid, isTrue);
        expect(frequencyMap, isNotEmpty);
        
        // Check for expected marine features
        final depareCount = frequencyMap['DEPARE'] ?? 0;
        final coalneCount = frequencyMap['COALNE'] ?? 0;
        
        print('DEPARE (depth areas): $depareCount');
        print('COALNE (coastlines): $coalneCount');
        
        expect(depareCount, greaterThan(0), reason: 'Should have depth areas');
        expect(coalneCount, greaterThan(0), reason: 'Should have coastlines');
        
      } catch (e, stackTrace) {
        stopwatch.stop();
        print('Error parsing S57 after ${stopwatch.elapsedMilliseconds}ms: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      } finally {
        // Clean up
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}