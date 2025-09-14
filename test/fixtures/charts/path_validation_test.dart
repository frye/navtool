import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'test_chart_data.dart';

/// Test to validate fixture path consistency and availability
void main() {
  group('Fixture Path Validation', () {
    test('should have correct S57 fixture structure', () {
      // Verify the new S57 structure exists
      final encRoot = Directory('test/fixtures/charts/s57_data/ENC_ROOT');
      expect(encRoot.existsSync(), isTrue, 
        reason: 'ENC_ROOT directory should exist');
        
      final us5wa50mDir = Directory('test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M');
      final us3wa01mDir = Directory('test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M');
      
      if (us5wa50mDir.existsSync()) {
        final us5wa50mFile = File('test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000');
        expect(us5wa50mFile.existsSync(), isTrue,
          reason: 'US5WA50M.000 base chart file should exist');
      }
      
      if (us3wa01mDir.existsSync()) {
        final us3wa01mFile = File('test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000');
        expect(us3wa01mFile.existsSync(), isTrue,
          reason: 'US3WA01M.000 base chart file should exist');
      }
    });
    
    test('TestChartData should return S57 paths', () {
      // Test the updated TestChartData class
      expect(TestChartData.elliottBayHarborChart, 
        contains('s57_data/ENC_ROOT'));
      expect(TestChartData.pugetSoundCoastalChart, 
        contains('s57_data/ENC_ROOT'));
        
      expect(TestChartData.elliottBayHarborChart, 
        endsWith('US5WA50M.000'));
      expect(TestChartData.pugetSoundCoastalChart, 
        endsWith('US3WA01M.000'));
    });
    
    test('should support both chart formats', () {
      // Verify legacy ZIP paths are still available
      expect(TestChartData.elliottBayHarborChartZip, 
        contains('noaa_enc'));
      expect(TestChartData.pugetSoundCoastalChartZip, 
        contains('noaa_enc'));
        
      // Verify helper methods
      expect(TestChartData.getChartBasePath('US5WA50M'), 
        endsWith('US5WA50M/US5WA50M.000'));
      expect(TestChartData.getChartDirectory('US5WA50M'), 
        endsWith('US5WA50M'));
    });
    
    test('chart files should exist in either format', () {
      final charts = ['US5WA50M', 'US3WA01M'];
      
      for (final chartId in charts) {
        final s57Path = TestChartData.getChartBasePath(chartId);
        final zipPath = chartId == 'US5WA50M' 
            ? TestChartData.elliottBayHarborChartZip
            : TestChartData.pugetSoundCoastalChartZip;
            
        final s57Exists = File(s57Path).existsSync();
        final zipExists = File(zipPath).existsSync();
        
        expect(s57Exists || zipExists, isTrue,
          reason: 'Chart $chartId should exist in either S57 or ZIP format');
          
        if (s57Exists) {
          print('✓ $chartId available in S57 format: $s57Path');
        } else if (zipExists) {
          print('✓ $chartId available in ZIP format: $zipPath');
        }
      }
    });
  });
}