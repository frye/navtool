/// Integration test for Elliott Bay button functionality
/// Tests that Elliott Bay button loads real chart data, not sample data
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/app/app.dart';
import 'package:navtool/features/home/home_screen.dart';
import 'package:navtool/features/charts/chart_screen.dart';

void main() {
  group('Elliott Bay Button Integration Tests', () {
    testWidgets('Elliott Bay button loads real chart data', (tester) async {
      // Arrange: Start the app
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );
      
      // Wait for initial render
      await tester.pumpAndSettle();
      
      // Verify we're on the home screen
      expect(find.byType(HomeScreen), findsOneWidget);
      
      // Act: Find and tap the Elliott Bay Harbor Chart button
      final elliottBayButton = find.widgetWithText(ElevatedButton, 'Elliott Bay Harbor Chart');
      expect(elliottBayButton, findsOneWidget, reason: 'Elliott Bay button should be visible on home screen');
      
      await tester.tap(elliottBayButton);
      await tester.pumpAndSettle();
      
      // Assert: Should navigate to chart screen
      expect(find.byType(ChartScreen), findsOneWidget, reason: 'Should navigate to ChartScreen');
      
      // Verify chart title contains Elliott Bay
      expect(find.textContaining('Elliott Bay'), findsAtLeastNWidgets(1), 
        reason: 'Chart screen should show Elliott Bay in title or content');
      
      // Wait for chart features to load
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Verify no fallback error messages are shown
      expect(find.textContaining('S-57 feature loading may be incomplete'), findsNothing,
        reason: 'Should not show S-57 loading incomplete message for real chart data');
      expect(find.textContaining('Showing chart boundary only'), findsNothing,
        reason: 'Should not fall back to boundary-only display');
      
      // Verify loading succeeded (no persistent loading indicator)
      expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'Loading should complete without persistent loading indicator');
      
      // Check for success indicators in status bar or snackbars
      // The test passes if we reach chart screen without fallback errors
      print('Elliott Bay Button Test: Successfully navigated to chart screen');
    }, tags: ['integration', 'elliott-bay']);

    testWidgets('Elliott Bay button shows loading feedback', (tester) async {
      // Arrange: Start the app
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Act: Tap Elliott Bay button
      final elliottBayButton = find.widgetWithText(ElevatedButton, 'Elliott Bay Harbor Chart');
      expect(elliottBayButton, findsOneWidget);
      
      await tester.tap(elliottBayButton);
      
      // Assert: Should show loading feedback
      await tester.pump(); // Trigger immediate UI update
      
      // Look for loading snackbar or loading indicator
      final hasLoadingText = find.textContaining('Loading').evaluate().isNotEmpty;
      final hasLoadingIndicator = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      
      expect(
        hasLoadingText || hasLoadingIndicator,
        isTrue,
        reason: 'Should show loading feedback to user (either text or indicator)'
      );
      
      await tester.pumpAndSettle();
      
      print('Elliott Bay Button Test: Loading feedback displayed correctly');
    }, tags: ['integration', 'elliott-bay', 'ux']);

    testWidgets('Elliott Bay button handles errors gracefully', (tester) async {
      // This test verifies error handling if chart loading fails
      
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );
      
      await tester.pumpAndSettle();
      
      // Act: Tap Elliott Bay button
      final elliottBayButton = find.widgetWithText(ElevatedButton, 'Elliott Bay Harbor Chart');
      expect(elliottBayButton, findsOneWidget);
      
      await tester.tap(elliottBayButton);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      
      // Assert: If error occurs, should handle gracefully
      // Either succeed in loading or show appropriate error message
      final hasError = find.textContaining('Error').evaluate().isNotEmpty ||
                      find.textContaining('Failed').evaluate().isNotEmpty;
      
      final hasChartScreen = find.byType(ChartScreen).evaluate().isNotEmpty;
      
      expect(hasError || hasChartScreen, isTrue,
        reason: 'Should either load chart successfully or show appropriate error message');
      
      if (hasError) {
        print('Elliott Bay Button Test: Error handling verified');
      } else {
        print('Elliott Bay Button Test: Chart loading successful');
      }
    }, tags: ['integration', 'elliott-bay', 'error-handling']);
  });
}