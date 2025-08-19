import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/widgets/macos_native_menu_bar.dart';
import 'package:navtool/widgets/macos_status_bar.dart';

void main() {
  group('macOS Native UI Integration Tests', () {

    testWidgets('should display PlatformMenuBar on macOS', (WidgetTester tester) async {
      // Arrange
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      
      // Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MacosNativeMenuBar(
              child: Scaffold(
                body: Container(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Assert
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      
      // Cleanup
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('should display macOS status bar at bottom', (WidgetTester tester) async {
      // Arrange
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      
      // Act
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: Container()),
                  const MacosStatusBar(
                    statusText: 'Connected - GPS: Enabled',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Assert
      expect(find.byType(MacosStatusBar), findsOneWidget);
      expect(find.text('Connected - GPS: Enabled'), findsOneWidget);
      
      // Cleanup
      debugDefaultTargetPlatformOverride = null;
    });
  });
}