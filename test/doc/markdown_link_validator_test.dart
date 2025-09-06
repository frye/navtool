import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Test that validates all markdown links resolve to existing files
/// 
/// This test scans all markdown files in the project and ensures that
/// internal links ([text](path)) point to files that actually exist.
void main() {
  group('Markdown Link Validation', () {
    late List<File> markdownFiles;
    late String projectRoot;

    setUpAll(() {
      projectRoot = Directory.current.path;
      markdownFiles = _findMarkdownFiles(projectRoot);
      print('Found ${markdownFiles.length} markdown files to validate');
    });

    test('all internal markdown links resolve to existing files', () {
      final brokenLinks = <String>[];
      
      for (final file in markdownFiles) {
        final relativePath = path.relative(file.path, from: projectRoot);
        print('Checking links in: $relativePath');
        
        final content = file.readAsStringSync();
        final links = _extractMarkdownLinks(content);
        
        for (final link in links) {
          if (_isInternalLink(link)) {
            final targetPath = _resolveLinkedPath(file, link);
            
            if (!File(targetPath).existsSync() && !Directory(targetPath).existsSync()) {
              brokenLinks.add('$relativePath -> $link (resolved to: $targetPath)');
            }
          }
        }
      }
      
      if (brokenLinks.isNotEmpty) {
        print('❌ Found ${brokenLinks.length} broken links:');
        for (final link in brokenLinks) {
          print('   $link');
        }
        fail('Found ${brokenLinks.length} broken internal links');
      } else {
        print('✅ All internal markdown links are valid');
      }
    });

    test('S-57 documentation cross-references are valid', () {
      // Test specific cross-references mentioned in the S-57 docs
      final s57Files = markdownFiles.where((f) => 
        f.path.contains('s57') || f.path.contains('S57')).toList();
      
      final expectedCrossRefs = {
        'docs/s57_format_overview.md': [
          '../S57_IMPLEMENTATION_ANALYSIS.md',
          's57_troubleshooting.md'
        ],
        'docs/s57_troubleshooting.md': [
          's57_format_overview.md',
          '../S57_IMPLEMENTATION_ANALYSIS.md',
          'benchmarks/s57_benchmarks.md'
        ],
        'README.md': [
          'docs/s57_format_overview.md',
          'docs/s57_troubleshooting.md',
          'S57_IMPLEMENTATION_ANALYSIS.md',
          'docs/benchmarks/s57_benchmarks.md'
        ],
      };
      
      final missingRefs = <String>[];
      
      for (final entry in expectedCrossRefs.entries) {
        final filePath = path.join(projectRoot, entry.key);
        final file = File(filePath);
        
        if (!file.existsSync()) {
          missingRefs.add('Missing file: ${entry.key}');
          continue;
        }
        
        final content = file.readAsStringSync();
        
        for (final expectedRef in entry.value) {
          if (!content.contains(expectedRef)) {
            missingRefs.add('${entry.key} missing reference to: $expectedRef');
          }
        }
      }
      
      if (missingRefs.isNotEmpty) {
        print('❌ Missing expected cross-references:');
        for (final ref in missingRefs) {
          print('   $ref');
        }
        fail('Missing ${missingRefs.length} expected cross-references');
      } else {
        print('✅ All expected S-57 cross-references found');
      }
    });

    test('documentation files mentioned in issue exist', () {
      final requiredFiles = [
        'docs/s57_format_overview.md',
        'docs/s57_troubleshooting.md',
        'S57_IMPLEMENTATION_ANALYSIS.md',
        'README.md',
      ];
      
      final missingFiles = <String>[];
      
      for (final requiredFile in requiredFiles) {
        final filePath = path.join(projectRoot, requiredFile);
        if (!File(filePath).existsSync()) {
          missingFiles.add(requiredFile);
        }
      }
      
      if (missingFiles.isNotEmpty) {
        fail('Missing required documentation files: $missingFiles');
      } else {
        print('✅ All required documentation files exist');
      }
    });
  });
}

/// Find all markdown files in the project directory
List<File> _findMarkdownFiles(String projectRoot) {
  final markdownFiles = <File>[];
  
  void findMarkdownInDirectory(Directory dir) {
    try {
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          markdownFiles.add(entity);
        } else if (entity is Directory && !_shouldSkipDirectory(entity)) {
          findMarkdownInDirectory(entity);
        }
      }
    } catch (e) {
      // Skip directories we can't read
    }
  }
  
  findMarkdownInDirectory(Directory(projectRoot));
  return markdownFiles;
}

/// Check if directory should be skipped during search
bool _shouldSkipDirectory(Directory dir) {
  final name = path.basename(dir.path);
  return name.startsWith('.') || 
         name == 'node_modules' || 
         name == 'build' ||
         name == '.dart_tool';
}

/// Extract markdown links from file content
List<String> _extractMarkdownLinks(String content) {
  final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  final matches = linkPattern.allMatches(content);
  return matches.map((m) => m.group(2)!).toList();
}

/// Check if link is internal (not HTTP/HTTPS)
bool _isInternalLink(String link) {
  return !link.startsWith('http://') && 
         !link.startsWith('https://') &&
         !link.startsWith('mailto:') &&
         !link.startsWith('#'); // Fragment links
}

/// Resolve relative link path to absolute file path
String _resolveLinkedPath(File sourceFile, String link) {
  final sourceDir = path.dirname(sourceFile.path);
  
  // Handle fragment links (e.g., "file.md#section")
  final linkPath = link.split('#')[0];
  
  if (path.isAbsolute(linkPath)) {
    return linkPath;
  } else {
    return path.normalize(path.join(sourceDir, linkPath));
  }
}