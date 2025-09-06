// Entry-point to run NOAA chart download within a Flutter app context.
// Run with: flutter run -d windows -t bin/download_chart.dart --dart-define=CHART_ID=US5WA11M
// Or pass chart id as first argument when using `dart run` (Flutter context required).
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/tools/download_noaa_chart_logic.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final chartId =
      const String.fromEnvironment(
        'CHART_ID',
        defaultValue: '',
      ).trim().isNotEmpty
      ? const String.fromEnvironment('CHART_ID')
      : (args.isNotEmpty ? args.first : 'US5WA11M');
  stdout.writeln('Downloading chart: $chartId');
  await runDownload(chartId);
  // Exit explicitly because Flutter run keeps process alive.
  exit(0);
}
