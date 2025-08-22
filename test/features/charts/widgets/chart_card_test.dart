import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/features/charts/widgets/chart_card.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

void main() {
  group('ChartCard Tests', () {
    Chart createTestChart({
      String? id,
      String? title,
      int? scale,
      ChartType? type,
      String? state,
      bool? isDownloaded,
      int? fileSize,
    }) {
      return Chart(
        id: id ?? 'US5CA52M',
        title: title ?? 'San Francisco Bay',
        scale: scale ?? 25000,
        bounds: GeographicBounds(
          north: 37.9,
          south: 37.7,
          east: -122.3,
          west: -122.5,
        ),
        lastUpdate: DateTime(2024, 1, 15),
        state: state ?? 'California',
        type: type ?? ChartType.harbor,
        description: 'Detailed harbor chart of San Francisco Bay',
        isDownloaded: isDownloaded ?? false,
        fileSize: fileSize, // Don't provide default value
      );
    }

    Widget createTestWidget({
      required Chart chart,
      bool? isSelected,
      ValueChanged<bool?>? onSelectionChanged,
      VoidCallback? onTap,
      VoidCallback? onInfoTap,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChartCard(
              chart: chart,
              isSelected: isSelected ?? false,
              onSelectionChanged: onSelectionChanged,
              onTap: onTap,
              onInfoTap: onInfoTap,
            ),
          ),
        ),
      );
    }

    group('Chart Card Display', () {
      testWidgets('should display chart basic information', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('US5CA52M'), findsOneWidget);
        expect(find.text('Scale: 1:25,000'), findsOneWidget);
        expect(find.text('Harbor'), findsOneWidget);
      });

      testWidgets('should display chart file size', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart(fileSize: 15728640); // 15MB

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('15.0 MB'), findsOneWidget);
      });

      testWidgets('should display chart bounds', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.textContaining('37.7° - 37.9°N'), findsOneWidget);
        expect(find.textContaining('122.3° - 122.5°W'), findsOneWidget);
      });

      testWidgets('should display download status icon when downloaded', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart(isDownloaded: true);

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byIcon(Icons.download_done), findsOneWidget);
        expect(find.text('Downloaded'), findsOneWidget);
      });

      testWidgets('should display cloud icon when not downloaded', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart(isDownloaded: false);

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byIcon(Icons.cloud_download), findsOneWidget);
        expect(find.text('Available'), findsOneWidget);
      });

      testWidgets('should display chart type badge with correct color', (WidgetTester tester) async {
        // Arrange & Act - Harbor chart
        await tester.pumpWidget(createTestWidget(chart: createTestChart(type: ChartType.harbor)));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Harbor'), findsOneWidget);
        final harborChip = tester.widget<Chip>(find.byType(Chip));
        expect(harborChip.backgroundColor, Colors.blue.shade100);

        // Arrange & Act - Coastal chart
        await tester.pumpWidget(createTestWidget(chart: createTestChart(type: ChartType.coastal)));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Coastal'), findsOneWidget);
        final coastalChip = tester.widget<Chip>(find.byType(Chip));
        expect(coastalChip.backgroundColor, Colors.green.shade100);
      });
    });

    group('Interaction Handling', () {
      testWidgets('should call onTap when card is tapped', (WidgetTester tester) async {
        // Arrange
        bool tapCalled = false;
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          onTap: () => tapCalled = true,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Card));
        await tester.pump();

        // Assert
        expect(tapCalled, isTrue);
      });

      testWidgets('should call onInfoTap when info button is tapped', (WidgetTester tester) async {
        // Arrange
        bool infoTapCalled = false;
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          onInfoTap: () => infoTapCalled = true,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.info_outline));
        await tester.pump();

        // Assert
        expect(infoTapCalled, isTrue);
      });

      testWidgets('should call onSelectionChanged when checkbox is tapped', (WidgetTester tester) async {
        // Arrange
        bool? selectionValue;
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          isSelected: false,
          onSelectionChanged: (value) => selectionValue = value,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        // Assert
        expect(selectionValue, isTrue);
      });

      testWidgets('should show checkbox when onSelectionChanged is provided', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          onSelectionChanged: (value) {},
        ));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(Checkbox), findsOneWidget);
      });

      testWidgets('should hide checkbox when onSelectionChanged is null', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(Checkbox), findsNothing);
      });
    });

    group('Visual States', () {
      testWidgets('should show selected state with different background', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          isSelected: true,
          onSelectionChanged: (value) {},
        ));
        await tester.pumpAndSettle();

        // Assert
        final card = tester.widget<Card>(find.byType(Card));
        expect(card.color, isNotNull);
        expect(find.byType(Checkbox), findsOneWidget);
        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, isTrue);
      });

      testWidgets('should show unselected state with default background', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          isSelected: false,
          onSelectionChanged: (value) {},
        ));
        await tester.pumpAndSettle();

        // Assert
        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, isFalse);
      });

      testWidgets('should show loading state for charts without file size', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart(fileSize: null);

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Size unknown'), findsOneWidget);
      });
    });

    group('Chart Type Styling', () {
      testWidgets('should display different colors for different chart types', (WidgetTester tester) async {
        final testCases = [
          (ChartType.harbor, Colors.blue.shade100),
          (ChartType.approach, Colors.orange.shade100),
          (ChartType.coastal, Colors.green.shade100),
          (ChartType.general, Colors.purple.shade100),
          (ChartType.overview, Colors.grey.shade100),
        ];

        for (final (type, expectedColor) in testCases) {
          // Arrange
          final chart = createTestChart(type: type);

          // Act
          await tester.pumpWidget(createTestWidget(chart: chart));
          await tester.pumpAndSettle();

          // Assert
          final chip = tester.widget<Chip>(find.byType(Chip));
          expect(chip.backgroundColor, expectedColor, reason: 'Color for $type should be $expectedColor');
          expect(find.text(type.displayName), findsOneWidget);
        }
      });
    });

    group('Accessibility', () {
      testWidgets('should have proper semantic labels', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          onSelectionChanged: (value) {},
        ));
        await tester.pumpAndSettle();

        // Assert
        expect(find.bySemanticsLabel('San Francisco Bay chart card'), findsOneWidget);
        expect(find.bySemanticsLabel('Select chart San Francisco Bay'), findsOneWidget);
        expect(find.bySemanticsLabel('Chart information for San Francisco Bay'), findsOneWidget);
      });

      testWidgets('should be keyboard accessible', (WidgetTester tester) async {
        // Arrange
        bool tapCalled = false;
        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(
          chart: chart,
          onTap: () => tapCalled = true,
        ));
        await tester.pumpAndSettle();

        // Focus and activate with keyboard
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        // Assert
        expect(tapCalled, isTrue);
      });
    });

    group('Layout Responsiveness', () {
      testWidgets('should adapt to small screen sizes', (WidgetTester tester) async {
        // Arrange
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.byType(Card), findsOneWidget);
      });

      testWidgets('should adapt to large screen sizes', (WidgetTester tester) async {
        // Arrange
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final chart = createTestChart();

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.byType(Card), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should handle missing chart data gracefully', (WidgetTester tester) async {
        // Arrange
        final chart = Chart(
          id: '',
          title: '',
          scale: 1, // Minimum valid scale
          bounds: GeographicBounds(north: 0, south: 0, east: 0, west: 0),
          lastUpdate: DateTime.now(),
          state: '',
          type: ChartType.harbor,
        );

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ChartCard), findsOneWidget);
        // Should not crash even with empty data
      });

      testWidgets('should handle very long chart titles', (WidgetTester tester) async {
        // Arrange
        final chart = createTestChart(
          title: 'This is a very long chart title that should be truncated or wrapped properly in the UI',
        );

        // Act
        await tester.pumpWidget(createTestWidget(chart: chart));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ChartCard), findsOneWidget);
        // Should handle long text without overflow
      });
    });
  });
}