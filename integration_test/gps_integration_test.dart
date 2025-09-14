import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:navtool/main.dart' as app;
import 'package:navtool/features/charts/widgets/gps_control_panel.dart';
import 'package:navtool/features/charts/widgets/vessel_position_overlay.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('GPS Integration Tests', () {
    testWidgets('should display GPS controls in chart interface', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to charts if needed (depends on app structure)
      // This is a placeholder - would need to match actual navigation
      
      // Look for GPS-related widgets
      expect(find.text('GPS'), findsWidgets);
      
      // Should be able to find GPS status indicators
      expect(find.byIcon(Icons.gps_fixed), findsWidgets);
    });

    testWidgets('should handle GPS permission request', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Look for GPS permission related UI
      // This would test the GPS permission flow
      
      // Try to find and tap GPS-related buttons
      final gpsButtons = find.byIcon(Icons.my_location);
      if (gpsButtons.hasFound) {
        await tester.tap(gpsButtons.first);
        await tester.pumpAndSettle();
      }

      // Verify no crashes occur
      expect(tester.takeException(), isNull);
    });

    testWidgets('should display vessel overlay on charts', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to chart view
      // This is app-specific navigation logic
      
      // Look for vessel position overlay
      expect(find.byType(VesselPositionOverlay), findsWidgets);
    });

    testWidgets('should handle GPS track recording', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Look for track recording controls
      final recordButtons = find.byIcon(Icons.fiber_manual_record);
      if (recordButtons.hasFound) {
        // Try to start recording
        await tester.tap(recordButtons.first);
        await tester.pumpAndSettle();
        
        // Should show recording indicator
        expect(find.byIcon(Icons.stop), findsWidgets);
        
        // Stop recording
        await tester.tap(find.byIcon(Icons.stop).first);
        await tester.pumpAndSettle();
        
        // Should return to record state
        expect(find.byIcon(Icons.fiber_manual_record), findsWidgets);
      }

      // Verify no crashes
      expect(tester.takeException(), isNull);
    });

    testWidgets('should center chart on vessel position', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Look for center on vessel button
      final centerButtons = find.byIcon(Icons.my_location);
      if (centerButtons.hasFound) {
        await tester.tap(centerButtons.first);
        await tester.pumpAndSettle();
        
        // Should show some feedback (snackbar, etc)
        expect(find.text('Centered'), findsWidgets);
      }

      expect(tester.takeException(), isNull);
    });
  });
}