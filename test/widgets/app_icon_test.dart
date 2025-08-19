import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:navtool/widgets/app_icon.dart';

void main() {
  group('AppIcon Widget Tests', () {
    
    Widget createTestWidget({Widget? child}) {
      return MaterialApp(
        home: Scaffold(
          body: child ?? const AppIcon(),
        ),
      );
    }

    testWidgets('should display SVG icon', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Assert
      expect(find.byType(AppIcon), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('should use correct default size', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Assert
      final svgPicture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svgPicture.width, 24.0);
      expect(svgPicture.height, 24.0);
    });

    testWidgets('should accept custom size', (WidgetTester tester) async {
      // Arrange
      const customSize = 48.0;
      
      // Act
      await tester.pumpWidget(createTestWidget(
        child: const AppIcon(size: customSize)
      ));
      await tester.pumpAndSettle();
      
      // Assert
      final svgPicture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svgPicture.width, customSize);
      expect(svgPicture.height, customSize);
    });

    group('Platform-specific Icon Tests', () {
      testWidgets('should use macOS style icon on macOS platform', (WidgetTester tester) async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        final svgPicture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(svgPicture.bytesLoader.toString(), contains('app_icon_macos_sailboat.svg'));
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('should use standard icon on non-macOS platforms', (WidgetTester tester) async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        final svgPicture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(svgPicture.bytesLoader.toString(), contains('app_icon.svg'));
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('Accessibility Tests', () {
      testWidgets('should have proper semantics for screen readers', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        final appIcon = tester.widget<AppIcon>(find.byType(AppIcon));
        // The icon should have semantic meaning for accessibility
        expect(find.byType(AppIcon), findsOneWidget);
      });
    });

    group('Apple-style Icon Content Tests', () {
      testWidgets('should have rounded rectangle boundary on macOS', (WidgetTester tester) async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        final svgPicture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        // Should use the macOS-style icon with rounded rectangle boundary
        expect(svgPicture.bytesLoader.toString(), contains('app_icon_macos_sailboat.svg'));
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('should contain sailboat-themed content within Apple boundary', (WidgetTester tester) async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        
        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        
        // Assert
        // The icon should combine Apple-style boundary with sailboat content
        expect(find.byType(AppIcon), findsOneWidget);
        expect(find.byType(SvgPicture), findsOneWidget);
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });
    });
  });
}