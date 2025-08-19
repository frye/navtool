import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/widgets/macos_native_menu_bar.dart';

void main() {
  group('MacosNativeMenuBar Widget Tests', () {
    testWidgets('should create PlatformMenuBar with menus', (WidgetTester tester) async {
      // Arrange
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: MacosNativeMenuBar(
            child: Scaffold(
              body: Container(),
            ),
          ),
        ),
      );
      
      // Assert
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      
      final menuBar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      expect(menuBar.menus.length, greaterThanOrEqualTo(2));
      
      // Check that we have File and Help menu labels
      final menuLabels = menuBar.menus.map((menu) => menu.label).toList();
      expect(menuLabels.contains('File'), isTrue);
      expect(menuLabels.contains('Help'), isTrue);
      
      // Cleanup
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('should render child widget correctly', (WidgetTester tester) async {
      // Arrange
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const testKey = Key('test_child');
      
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: MacosNativeMenuBar(
            child: Container(
              key: testKey,
              child: const Text('Test Child'),
            ),
          ),
        ),
      );
      
      // Assert
      expect(find.byKey(testKey), findsOneWidget);
      expect(find.text('Test Child'), findsOneWidget);
      
      // Cleanup
      debugDefaultTargetPlatformOverride = null;
    });
  });
}