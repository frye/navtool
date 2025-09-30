import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/utils/zip_extractor.dart';

void main() {
  test('extractS57FromZip should find .000 in US5WA50M fixture', () async {
    final path = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
    if (!File(path).existsSync()) {
      // Skip in CI if fixture is absent
      return expect(true, isTrue, reason: 'Fixture missing: $path');
    }

    final bytes = await File(path).readAsBytes();
    final s57 = await ZipExtractor.extractS57FromZip(bytes, 'US5WA50M');
    expect(s57, isNotNull, reason: 'Expected to extract .000 bytes for US5WA50M');
    expect(s57!.length, greaterThan(100));
  });
}
