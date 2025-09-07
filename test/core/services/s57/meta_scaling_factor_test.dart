/// Meta test to ensure no hard-coded scaling factors remain in S-57 code
/// 
/// This test validates that coordinate scaling uses dynamic COMF/SOMF values
/// from metadata rather than hard-coded constants like 1e7 or 10000000.
/// 
/// Exceptions are allowed for:
/// - Test fixtures and test data
/// - Default fallback values with clear documentation
/// - Documentation examples

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Meta: Scaling Factor Validation', () {
    test('should not contain hard-coded scaling factors outside test fixtures', () async {
      final s57LibDir = Directory('lib/core/services/s57');
      expect(s57LibDir.existsSync(), isTrue, reason: 'S-57 library directory should exist');

      final violations = <String>[];
      
      // Patterns to detect hard-coded scaling factors
      final scalingPatterns = [
        RegExp(r'(?<!//.*)\b1e7\b(?!.*//.*test|fixture|example)'), // 1e7 not in comments about tests
        RegExp(r'(?<!//.*)\b10000000\.0?\b(?!.*//.*default|fallback|Default)'), // 10000000 not documented as default
        RegExp(r'(?<!//.*)\b1\.0e7\b(?!.*//.*test|fixture|example)'), // 1.0e7 variations
      ];

      // Check all Dart files in S-57 directory
      await for (final file in s57LibDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();
          final lines = content.split('\n');
          
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            
            // Skip lines that are clearly test data or documented defaults
            if (line.contains('Test') || 
                line.contains('test') ||
                line.contains('fixture') ||
                line.contains('Default COMF') ||
                line.contains('default to')) {
              continue;
            }
            
            for (final pattern in scalingPatterns) {
              if (pattern.hasMatch(line)) {
                violations.add('${file.path}:${i + 1}: $line');
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('Found hard-coded scaling factors:');
        for (final violation in violations) {
          print('  $violation');
        }
        print('\nAll coordinate scaling should use COMF/SOMF from metadata.');
        print('If defaults are needed, document them clearly as fallbacks.');
      }

      expect(violations, isEmpty, 
        reason: 'Hard-coded scaling factors found. Use COMF/SOMF from metadata instead.');
    });

    test('should validate COMF/SOMF usage pattern in parser', () async {
      final parserFile = File('lib/core/services/s57/s57_parser.dart');
      expect(parserFile.existsSync(), isTrue, reason: 'S-57 parser should exist');

      final content = await parserFile.readAsString();
      
      // Verify COMF/SOMF are referenced from metadata
      expect(content, contains('comf'), reason: 'Parser should reference COMF');
      expect(content, contains('metadata'), reason: 'Parser should use metadata for scaling');
      
      // Check for proper fallback pattern
      expect(content, contains('??'), reason: 'Should have null-coalescing defaults');
      
      print('✓ COMF/SOMF metadata usage pattern validated');
    });
  });
}