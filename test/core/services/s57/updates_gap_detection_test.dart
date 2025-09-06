/// Test for S-57 Gap Detection in Update Sequence
/// 
/// Tests gap detection when update .002 is missing

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_update_processor.dart';
import 'package:navtool/core/error/app_error.dart';

void main() {
  group('S57 Update Gap Detection', () {
    late S57UpdateProcessor processor;

    setUp(() {
      processor = S57UpdateProcessor();
    });

    test('should detect gap in update sequence', () async {
      // Create temporary test files that simulate a gap
      final tempDir = Directory.systemTemp.createTempSync('s57_gap_test');
      
      try {
        // Create update files with a gap (missing .002)
        final update001 = File('${tempDir.path}/TEST.001');
        final update003 = File('${tempDir.path}/TEST.003'); // Missing .002
        
        // Write minimal content to files
        await update001.writeAsBytes([0x20, 0x20, 0x20]); // Dummy content
        await update003.writeAsBytes([0x20, 0x20, 0x20]); // Dummy content
        
        final updateFiles = [update001, update003];
        
        // Expect an error due to the gap
        expect(
          () async => await processor.applySequentialUpdates('TEST', updateFiles),
          throwsA(isA<AppError>().having(
            (e) => e.message,
            'message',
            contains('Gap in update sequence'),
          )),
        );
        
      } finally {
        // Clean up
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should detect gap between .001 and .003', () async {
      final tempDir = Directory.systemTemp.createTempSync('s57_gap_test2');
      
      try {
        final update001 = File('${tempDir.path}/SAMPLE.001');
        final update003 = File('${tempDir.path}/SAMPLE.003');
        
        await update001.writeAsBytes([0x20]);
        await update003.writeAsBytes([0x20]);
        
        final updateFiles = [update001, update003];
        
        expect(
          () async => await processor.applySequentialUpdates('SAMPLE', updateFiles),
          throwsA(isA<AppError>().having(
            (e) => e.message,
            'message',
            allOf([
              contains('Gap in update sequence'),
              contains('expected .002'),
              contains('found .003'),
            ]),
          )),
        );
        
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should accept sequential updates without gaps', () async {
      final tempDir = Directory.systemTemp.createTempSync('s57_sequential_test');
      
      try {
        final update001 = File('${tempDir.path}/SAMPLE.001');
        final update002 = File('${tempDir.path}/SAMPLE.002');
        final update003 = File('${tempDir.path}/SAMPLE.003');
        
        await update001.writeAsBytes([0x20]);
        await update002.writeAsBytes([0x20]);
        await update003.writeAsBytes([0x20]);
        
        final updateFiles = [update001, update002, update003];
        
        // This should not throw an error during sequence validation
        // (it may fail later during parsing, but that's expected with dummy data)
        try {
          await processor.applySequentialUpdates('SAMPLE', updateFiles);
        } catch (e) {
          // We expect parsing errors with dummy data, but not gap detection errors
          expect(e.toString(), isNot(contains('Gap in update sequence')));
        }
        
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should handle empty update list', () async {
      final summary = await processor.applySequentialUpdates('TEST', []);
      
      expect(summary.applied, isEmpty);
      expect(summary.inserted, equals(0));
      expect(summary.modified, equals(0));
      expect(summary.deleted, equals(0));
    });

    test('should sort update files by sequence number', () async {
      final tempDir = Directory.systemTemp.createTempSync('s57_sort_test');
      
      try {
        // Create files in non-sequential order
        final update003 = File('${tempDir.path}/SAMPLE.003');
        final update001 = File('${tempDir.path}/SAMPLE.001');
        final update002 = File('${tempDir.path}/SAMPLE.002');
        
        await update003.writeAsBytes([0x20]);
        await update001.writeAsBytes([0x20]);
        await update002.writeAsBytes([0x20]);
        
        // Pass files in random order
        final updateFiles = [update003, update001, update002];
        
        try {
          await processor.applySequentialUpdates('SAMPLE', updateFiles);
        } catch (e) {
          // We expect parsing errors, but not sequence errors if sorting works
          expect(e.toString(), isNot(contains('Gap in update sequence')));
        }
        
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}