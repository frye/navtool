import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';

void main() {
  group('ENC Parse Performance Smoke', () {
    final fixtures = [
      'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip',
      'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip',
    ];

    test('parses both ENC fixtures within reasonable time (non-strict)', () async {
      final totalWatch = Stopwatch()..start();
      int totalFeatures = 0;

      for (final p in fixtures) {
        if (!File(p).existsSync()) {
          print('[SMOKE] Missing fixture: $p (skipping)');
          continue;
        }
        final sw = Stopwatch()..start();
        final parsed = await S57Parser.loadFromZip(p);
        sw.stop();
        totalFeatures += parsed.features.length;
        print('[SMOKE] Parsed ${parsed.features.length} features from $p in ${sw.elapsedMilliseconds} ms');
      }

      totalWatch.stop();
      print('[SMOKE] Total features: $totalFeatures in ${totalWatch.elapsedMilliseconds} ms');

      // Soft expectation: complete within 30s in CI for both (do not fail if slower; just log)
      expect(totalFeatures > 0, isTrue, reason: 'Should parse at least one chart with real features');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
