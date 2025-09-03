// Flutter entrypoint wrapper to run the NOAA chart download logic within a Flutter context.
// This allows using providers and any Flutter framework types safely.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'download_noaa_chart_logic.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final chartId = args.isNotEmpty ? args[0] : 'US5WA11M';
  await runDownload(chartId);
}
