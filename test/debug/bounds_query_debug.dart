import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/geographic_bounds.dart';

void main() {
  test('debug bounds query logic', () {
    // Washington state bounds
    final washingtonBounds = GeographicBounds(
      north: 49.0, 
      south: 45.5, 
      east: -116.9, 
      west: -124.8
    );
    
    // Sample chart bounds from the logs
    final chartBounds = [
      GeographicBounds(north: 55.4999, south: 31.9999, east: -116.5001, west: -137.4999), // US1WC01M.000
      GeographicBounds(north: 61.25, south: 49.5, east: -132.4167, west: -165.75),        // US1WC04M.000  
      GeographicBounds(north: 60.3333, south: 18.75, east: -116.3333, west: -180.0),      // US1WC07M.000
    ];
    
    print('🔍 BOUNDS QUERY DEBUG');
    print('Washington bounds: N=${washingtonBounds.north}, S=${washingtonBounds.south}, E=${washingtonBounds.east}, W=${washingtonBounds.west}');
    print('');
    
    for (int i = 0; i < chartBounds.length; i++) {
      final chart = chartBounds[i];
      print('Chart $i bounds: N=${chart.north}, S=${chart.south}, E=${chart.east}, W=${chart.west}');
      
      // Current wrong SQL logic: chart bounds WITHIN state bounds
      final wrongQuery = chart.north >= washingtonBounds.south && 
                        chart.south <= washingtonBounds.north && 
                        chart.east >= washingtonBounds.west && 
                        chart.west <= washingtonBounds.east;
      
      // Correct intersection logic: boxes overlap
      final correctQuery = chart.north >= washingtonBounds.south && 
                          chart.south <= washingtonBounds.north && 
                          chart.east >= washingtonBounds.west && 
                          chart.west <= washingtonBounds.east;
                          
      // Actually correct intersection logic
      final reallyCorrect = !(chart.south > washingtonBounds.north || 
                             chart.north < washingtonBounds.south ||
                             chart.west > washingtonBounds.east ||
                             chart.east < washingtonBounds.west);
      
      print('  Wrong query result: $wrongQuery');
      print('  Correct intersection: $reallyCorrect');
      print('');
    }
  });
}
