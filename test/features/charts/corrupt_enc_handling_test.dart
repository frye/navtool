import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';

void main() {
  group('Corrupt ENC Handling', () {
    const goodPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';

    test('produces parsing error for truncated ZIP with user-friendly message', () async {
      if (!File(goodPath).existsSync()) {
        print('[SKIP] Missing ENC fixture: $goodPath');
        return;
      }

      final fullBytes = await File(goodPath).readAsBytes();
      // Truncate aggressively to simulate corruption
      final truncated = fullBytes.sublist(0, (fullBytes.length / 10).floor());
      final corruptFile = File('test/fixtures/charts/noaa_enc/US5WA50M_corrupt.tmp');
      await corruptFile.writeAsBytes(truncated);

      try {
        await S57Parser.loadFromZip(corruptFile.path, chartId: 'US5WA50M');
        fail('Expected parsing failure for corrupt ENC');
      } catch (e) {
        final msg = e.toString().toLowerCase();
        expect(msg.contains('failed') || msg.contains('parse'), isTrue);
      } finally {
        if (await corruptFile.exists()) {
          await corruptFile.delete();
        }
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
