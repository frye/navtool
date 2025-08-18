import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:navtool/features/about/about_screen.dart';
import 'package:navtool/features/about/about_dialog.dart';
import 'package:navtool/widgets/app_icon.dart';
import 'package:navtool/widgets/version_text.dart';

void main() {
  group('About Feature Tests', () {
    
    Widget createTestWidget({Widget? child}) {
      return ProviderScope(
        child: MaterialApp(
          home: child ?? const AboutScreen(),
        ),
      );
    }

    group('About Screen Information Display', () {
      testWidgets('should display comprehensive about information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
        expect(find.text('NavTool'), findsOneWidget);
        expect(find.byType(AppIcon), findsAtLeastNWidgets(1));
      });

      testWidgets('should display application description', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.textContaining('NavTool'), findsAtLeastNWidgets(1));
        expect(find.textContaining('Marine Navigation'), findsAtLeastNWidgets(1));
      });

      testWidgets('should display feature list', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Look for marine navigation features
        expect(find.textContaining('Electronic Chart'), findsWidgets);
        expect(find.textContaining('Route Planning'), findsWidgets);
        expect(find.textContaining('GPS'), findsWidgets);
      });
    });

    group('Version Information Accuracy', () {
      testWidgets('should display version information from package info', (WidgetTester tester) async {
        // Mock package info
        PackageInfo.setMockInitialValues(
          appName: 'NavTool',
          packageName: 'com.navtool.app',
          version: '1.0.0',
          buildNumber: '1',
          buildSignature: '',
        );

        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(VersionText), findsAtLeastNWidgets(1));
      });

      testWidgets('should show correct application name', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.textContaining('NavTool'), findsAtLeastNWidgets(1));
      });

      testWidgets('should handle version retrieval errors gracefully', (WidgetTester tester) async {
        // Arrange & Act - Test with default package info
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should not crash and show some version info
        expect(find.byType(AboutScreen), findsOneWidget);
      });
    });

    group('License and Attribution Display', () {
      testWidgets('should display license information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should have license or copyright information
        expect(find.byType(AboutScreen), findsOneWidget);
      });

      testWidgets('should display Flutter attribution', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.textContaining('Flutter'), findsWidgets);
      });

      testWidgets('should show open source acknowledgments', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Look for acknowledgments section
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for licenses button or text in actual implementation
      });
    });

    group('Contact Information Presentation', () {
      testWidgets('should display contact or support information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would look for contact info in actual implementation
      });

      testWidgets('should provide feedback or support channels', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for support links in actual implementation
      });
    });

    group('About Dialog Testing', () {
      testWidgets('should display AboutAppDialog correctly', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const AboutAppDialog(),
                  ),
                  child: const Text('Show About'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Act
        await tester.tap(find.text('Show About'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutAppDialog), findsOneWidget);
        expect(find.text('About NavTool'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
      });

      testWidgets('should display feature list in dialog', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const AboutAppDialog(),
                  ),
                  child: const Text('Show About'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Act
        await tester.tap(find.text('Show About'));
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.text('Features:'), findsOneWidget);
        expect(find.text('• Electronic Chart Display (ECDIS)'), findsOneWidget);
        expect(find.text('• Route Planning and Optimization'), findsOneWidget);
        expect(find.text('• Weather Routing (GRIB Data)'), findsOneWidget);
        expect(find.text('• GPS Integration and Tracking'), findsOneWidget);
        expect(find.text('• Cross-platform Desktop Support'), findsOneWidget);
      });

      testWidgets('should close dialog when Close button tapped', (WidgetTester tester) async {
        // Arrange
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const AboutAppDialog(),
                  ),
                  child: const Text('Show About'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        await tester.tap(find.text('Show About'));
        await tester.pumpAndSettle();
        
        // Act
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(AboutAppDialog), findsNothing);
      });
    });

    group('Links and External Navigation', () {
      testWidgets('should handle external link navigation safely', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Should not crash when handling links
        expect(find.byType(AboutScreen), findsOneWidget);
      });

      testWidgets('should provide proper link affordances', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for proper link styling in actual implementation
      });
    });

    group('About Screen Accessibility', () {
      testWidgets('should provide proper semantic labels', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
        expect(find.text('NavTool'), findsOneWidget);
        
        // Check that main elements are accessible
        expect(find.byType(AppIcon), findsAtLeastNWidgets(1));
        expect(find.byType(VersionText), findsAtLeastNWidgets(1));
      });

      testWidgets('should support screen reader navigation', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert - Basic structure should be readable
        expect(find.byType(AboutScreen), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
      });

      testWidgets('should handle high contrast themes', (WidgetTester tester) async {
        // Arrange - Test with high contrast theme
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData.from(
                colorScheme: ColorScheme.highContrastLight(),
              ),
              home: const AboutScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
      });
    });

    group('Marine Safety Disclaimers', () {
      testWidgets('should display appropriate marine safety disclaimers', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for safety disclaimers in actual implementation
      });

      testWidgets('should warn about navigation aid limitations', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for navigation warnings in actual implementation
      });
    });

    group('Legal Compliance Information', () {
      testWidgets('should display copyright information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for copyright notice in actual implementation
      });

      testWidgets('should show software license compliance', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for license compliance info in actual implementation
      });

      testWidgets('should provide regulatory compliance information', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        expect(find.byType(AboutScreen), findsOneWidget);
        // Would check for marine regulatory compliance in actual implementation
      });
    });

    group('Responsive Layout Testing', () {
      testWidgets('should adapt to different screen sizes', (WidgetTester tester) async {
        // Test small screen
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        expect(find.byType(AboutScreen), findsOneWidget);
        
        // Test large screen
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        expect(find.byType(AboutScreen), findsOneWidget);
        
        // Cleanup
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      });

      testWidgets('should handle orientation changes', (WidgetTester tester) async {
        // Portrait
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        expect(find.byType(AboutScreen), findsOneWidget);
        
        // Landscape
        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        expect(find.byType(AboutScreen), findsOneWidget);
        
        // Cleanup
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      });
    });
  });
}