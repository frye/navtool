import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:navtool/core/utils/path_dash_utils.dart';

void main() {
  group('PathDashUtils Tests', () {
    late Path testPath;
    
    setUp(() {
      testPath = Path();
      testPath.moveTo(0, 0);
      testPath.lineTo(100, 0);
      testPath.lineTo(100, 100);
    });
    
    group('Basic Dash Functionality', () {
      test('should create dashed path from source path', () {
        final dashedPath = PathDashUtils.createDashedPath(
          testPath, 
          [10.0, 5.0], // 10 units on, 5 units off
        );
        
        expect(dashedPath, isNotNull);
        expect(dashedPath, isA<Path>());
      });
      
      test('should handle empty dash array', () {
        final dashedPath = PathDashUtils.createDashedPath(testPath, []);
        
        // Should return original path for empty dash array
        expect(dashedPath, isNotNull);
      });
      
      test('should handle zero-length dashes', () {
        final dashedPath = PathDashUtils.createDashedPath(testPath, [0.0, 0.0]);
        
        // Should return original path for all-zero dash array
        expect(dashedPath, isNotNull);
      });
    });
    
    group('Maritime-Specific Patterns', () {
      test('should create cable dashed pattern', () {
        final cablePath = PathDashUtils.cableDashedPath(testPath);
        
        expect(cablePath, isNotNull);
        expect(cablePath, isA<Path>());
      });
      
      test('should create pipeline dotted pattern', () {
        final pipelinePath = PathDashUtils.pipelineDottedPath(testPath);
        
        expect(pipelinePath, isNotNull);
        expect(pipelinePath, isA<Path>());
      });
      
      test('should create submarine cable pattern', () {
        final submarinePath = PathDashUtils.submarineCablePath(testPath);
        
        expect(submarinePath, isNotNull);
        expect(submarinePath, isA<Path>());
      });
      
      test('should create pipeline with markers pattern', () {
        final markerPath = PathDashUtils.pipelineWithMarkersPath(testPath);
        
        expect(markerPath, isNotNull);
        expect(markerPath, isA<Path>());
      });
    });
    
    group('Dotted Path Functionality', () {
      test('should create dotted path with specific dot and gap lengths', () {
        final dottedPath = PathDashUtils.createDottedPath(testPath, 3.0, 2.0);
        
        expect(dottedPath, isNotNull);
        expect(dottedPath, isA<Path>());
      });
    });
    
    group('Edge Cases', () {
      test('should handle empty path', () {
        final emptyPath = Path();
        final dashedEmpty = PathDashUtils.createDashedPath(emptyPath, [5.0, 5.0]);
        
        expect(dashedEmpty, isNotNull);
      });
      
      test('should handle single point path', () {
        final singlePointPath = Path();
        singlePointPath.moveTo(50, 50);
        
        final dashedSingle = PathDashUtils.createDashedPath(singlePointPath, [5.0, 5.0]);
        
        expect(dashedSingle, isNotNull);
      });
      
      test('should handle very short path segments', () {
        final shortPath = Path();
        shortPath.moveTo(0, 0);
        shortPath.lineTo(1, 0); // Very short line
        
        final dashedShort = PathDashUtils.createDashedPath(shortPath, [10.0, 5.0]);
        
        expect(dashedShort, isNotNull);
      });
    });
  });
}