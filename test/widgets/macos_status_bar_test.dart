import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/widgets/macos_status_bar.dart';

void main() {
  group('MacosStatusBar Widget Tests', () {
    testWidgets('should display status text correctly', (WidgetTester tester) async {
      // Arrange
      const statusText = 'GPS: Connected - Charts: 3 loaded';
      
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MacosStatusBar(statusText: statusText),
          ),
        ),
      );
      
      // Assert
      expect(find.byType(MacosStatusBar), findsOneWidget);
      expect(find.text(statusText), findsOneWidget);
    });

    testWidgets('should have correct height and styling', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MacosStatusBar(statusText: 'Test status'),
          ),
        ),
      );
      
      // Assert
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(MacosStatusBar),
          matching: find.byType(Container),
        ),
      );
      
      expect(container.constraints?.minHeight, equals(24.0));
      expect(container.alignment, equals(Alignment.centerLeft));
    });

    testWidgets('should use appropriate macOS theming', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: MacosStatusBar(statusText: 'Test status'),
          ),
        ),
      );
      
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: MacosStatusBar(statusText: 'Test status'),
          ),
        ),
      );
      
      // Assert - should adapt to theme
      expect(find.byType(MacosStatusBar), findsOneWidget);
    });

    testWidgets('should handle empty status text', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MacosStatusBar(statusText: ''),
          ),
        ),
      );
      
      // Assert
      expect(find.byType(MacosStatusBar), findsOneWidget);
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('should handle long status text with ellipsis', (WidgetTester tester) async {
      // Arrange
      const longStatusText = 'This is a very long status text that should be truncated with ellipsis when the status bar width is limited';
      
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200, // Limited width
              child: const MacosStatusBar(statusText: longStatusText),
            ),
          ),
        ),
      );
      
      // Assert
      expect(find.byType(MacosStatusBar), findsOneWidget);
      
      final textWidget = tester.widget<Text>(
        find.descendant(
          of: find.byType(MacosStatusBar),
          matching: find.byType(Text),
        ),
      );
      
      expect(textWidget.overflow, equals(TextOverflow.ellipsis));
    });

    testWidgets('should position at bottom of layout', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Container(
                    key: const Key('main_content'),
                    color: Colors.blue,
                  ),
                ),
                const MacosStatusBar(statusText: 'Bottom status'),
              ],
            ),
          ),
        ),
      );
      
      // Assert
      final statusBarPosition = tester.getBottomLeft(find.byType(MacosStatusBar));
      final mainContentPosition = tester.getBottomLeft(find.byKey(const Key('main_content')));
      
      // Status bar should be below main content
      expect(statusBarPosition.dy, greaterThan(mainContentPosition.dy));
    });
  });
}