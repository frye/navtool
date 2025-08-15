import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/gps_service_impl.dart';
import 'package:navtool/core/services/gps_service_win32.dart';

void main() {
  group('Platform-specific GPS Service Tests', () {
    test('should use correct GPS service implementation based on platform', () {
      final container = ProviderContainer();
      
      try {
        final gpsService = container.read(gpsServiceProvider);
        
        // Verify that the correct implementation is used based on current platform
        if (defaultTargetPlatform == TargetPlatform.windows) {
          expect(gpsService, isA<GpsServiceWin32>());
        } else {
          // macOS, Linux, iOS, Android should use geolocator-based implementation
          expect(gpsService, isA<GpsServiceImpl>());
        }
        
        // Verify that service implements the GPS interface correctly
        expect(gpsService.getCurrentPosition, isA<Function>());
        expect(gpsService.requestLocationPermission, isA<Function>());
        expect(gpsService.checkLocationPermission, isA<Function>());
        expect(gpsService.isLocationEnabled, isA<Function>());
        
      } finally {
        container.dispose();
      }
    });

    test('should handle platform-specific GPS service creation without errors', () {
      final container = ProviderContainer();
      
      try {
        // This should not throw any exceptions
        expect(() => container.read(gpsServiceProvider), returnsNormally);
        
        final gpsService = container.read(gpsServiceProvider);
        expect(gpsService, isNotNull);
        
      } finally {
        container.dispose();
      }
    });
  });
}
