/// Meta test to prevent blocking TODOs from remaining in S-57 code
/// 
/// This test fails if any line matches the pattern `// TODO(blocking)`
/// within the S-57 library code (lib/**/s57/**).
/// 
/// Blocking TODOs indicate unfinished critical functionality that
/// would prevent production use of the S-57 parser.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Meta: TODO Blocking Guard', () {
    test('should fail if blocking TODOs exist in S-57 code', () async {
      final s57LibDir = Directory('lib/core/services/s57');
      expect(s57LibDir.existsSync(), isTrue, reason: 'S-57 library directory should exist');

      final blockingTodos = <String>[];
      
      // Pattern to match blocking TODOs
      final blockingPattern = RegExp(r'//\s*TODO\s*\(\s*blocking\s*\)', caseSensitive: false);

      // Check all Dart files in S-57 directory
      await for (final file in s57LibDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();
          final lines = content.split('\n');
          
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            
            if (blockingPattern.hasMatch(line)) {
              blockingTodos.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }

      if (blockingTodos.isNotEmpty) {
        print('Found blocking TODOs that must be resolved:');
        for (final todo in blockingTodos) {
          print('  $todo');
        }
        print('\nAll blocking TODOs must be resolved before consolidation.');
        print('Convert to regular TODOs or implement the functionality.');
      }

      expect(blockingTodos, isEmpty, 
        reason: 'Blocking TODOs found in S-57 code. These must be resolved for production readiness.');
    });

    test('should allow non-blocking TODOs', () async {
      final s57LibDir = Directory('lib/core/services/s57');
      
      final regularTodos = <String>[];
      final regularPattern = RegExp(r'//\s*TODO(?!\s*\(\s*blocking\s*\))', caseSensitive: false);

      await for (final file in s57LibDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();
          final lines = content.split('\n');
          
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            
            if (regularPattern.hasMatch(line)) {
              regularTodos.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }

      if (regularTodos.isNotEmpty) {
        print('Found ${regularTodos.length} non-blocking TODOs (acceptable):');
        for (final todo in regularTodos.take(5)) {
          print('  $todo');
        }
        if (regularTodos.length > 5) {
          print('  ... and ${regularTodos.length - 5} more');
        }
      }

      // Non-blocking TODOs are acceptable
      print('✓ ${regularTodos.length} non-blocking TODOs found (acceptable for consolidation)');
    });
  });
}