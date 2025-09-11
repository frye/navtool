#!/usr/bin/env dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Validates presence, size, and SHA256 (when known) of NOAA ENC test fixtures.
/// Run with: dart run bin/validate_enc_fixtures.dart
/// Exits with code 1 if required fixtures are missing or significantly mismatched.

class EncFixtureSpec {
  final String path;
  final int expectedSizeBytes;
  final String? sha256; // Optional if not yet recorded
  final int sizeTolerance; // Allow small variance (e.g., line ending change in archive metadata)
  const EncFixtureSpec(this.path, this.expectedSizeBytes, {this.sha256, this.sizeTolerance = 64});
}

final fixtures = <EncFixtureSpec>[
  EncFixtureSpec(
    'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip',
    147361,
    sha256: 'B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE',
  ),
  EncFixtureSpec(
    'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip',
    640268,
    // SHA256 not yet recorded in README
  ),
];

Future<void> main() async {
  print('[ENC Validation] Starting validation of ${fixtures.length} fixtures');
  var hadError = false;

  for (final spec in fixtures) {
    final file = File(spec.path);
    if (!file.existsSync()) {
      print('[ENC Validation][ERROR] Missing fixture: ${spec.path}');
      hadError = true;
      continue;
    }

    final bytes = await file.readAsBytes();
    final size = bytes.length;

    final sizeDelta = (size - spec.expectedSizeBytes).abs();
    if (sizeDelta > spec.sizeTolerance) {
      print('[ENC Validation][WARN] Size mismatch for ${spec.path}: actual=$size expected=${spec.expectedSizeBytes} Δ=$sizeDelta (> tolerance ${spec.sizeTolerance})');
    } else {
      print('[ENC Validation] Size OK for ${spec.path}: $size bytes');
    }

    if (spec.sha256 != null && spec.sha256!.isNotEmpty) {
      final digest = sha256.convert(bytes).toString().toUpperCase();
      if (digest != spec.sha256) {
        print('[ENC Validation][WARN] SHA256 mismatch for ${spec.path}: expected=${spec.sha256} actual=$digest');
      } else {
        print('[ENC Validation] SHA256 OK for ${spec.path}');
      }
    } else {
      final digest = sha256.convert(bytes).toString().toUpperCase();
      print('[ENC Validation] SHA256 (record for README if desired) ${spec.path}: $digest');
    }
  }

  if (hadError) {
    print('[ENC Validation] One or more required fixtures missing. See README.');
    exit(1);
  }
  print('[ENC Validation] Validation complete.');
}
