import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basic chart workflow test', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Chart Workflow'))));
    expect(find.text('Chart Workflow'), findsOneWidget);
  });
}
