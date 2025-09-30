/// TDD Test Suite for ZipExtractor Multi-Pattern Extraction (T004)
/// Tests MUST FAIL until T017 implementation is complete.
///
/// Requirements Coverage:
/// - R03: Multi-pattern ZIP extraction (root, ENC_ROOT, nested)
/// - R04: Fallback extraction strategies with precedence
/// - R27: Robust error handling for malformed archives
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:navtool/core/utils/zip_extractor.dart';

void main() {
  group('ZipExtractor Multi-Pattern Extraction Tests (T004)', () {
    late Archive testArchive;
    late List<int> zipBytes;
    const chartId = 'US5WA50M';

    setUp(() {
      testArchive = Archive();
    });

    /// Helper: Add file to archive
    void addFile(Archive archive, String path, String content) {
      final file = ArchiveFile(path, content.length, content.codeUnits);
      archive.addFile(file);
    }

    /// Helper: Encode archive to ZIP bytes
    List<int> encodeZip(Archive archive) {
      return ZipEncoder().encode(archive)!;
    }

    test('T004.1: Extract from root layout (US5WA50M.000 at root)', () async {
      // ARRANGE: Create ZIP with .000 file at root
      addFile(testArchive, '$chartId.000', 'S57_ROOT_LAYOUT_DATA');
      addFile(testArchive, 'CATALOG.031', 'CATALOG_DATA');
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should find .000 file in root layout
      expect(result, isNotNull, reason: 'Should extract .000 from root layout');
      expect(String.fromCharCodes(result!), equals('S57_ROOT_LAYOUT_DATA'),
          reason: 'Should return correct root layout file content');
    });

    test('T004.2: Extract from ENC_ROOT layout (ENC_ROOT/US5WA50M/US5WA50M.000)', () async {
      // ARRANGE: Create ZIP with standard NOAA ENC_ROOT structure
      addFile(testArchive, 'ENC_ROOT/$chartId/$chartId.000', 'S57_ENC_ROOT_DATA');
      addFile(testArchive, 'ENC_ROOT/$chartId/$chartId.txt', 'README_DATA');
      addFile(testArchive, 'ENC_ROOT/CATALOG.031', 'CATALOG_DATA');
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should find .000 file in ENC_ROOT structure
      expect(result, isNotNull, reason: 'Should extract .000 from ENC_ROOT layout');
      expect(String.fromCharCodes(result!), equals('S57_ENC_ROOT_DATA'),
          reason: 'Should return correct ENC_ROOT layout file content');
    });

    test('T004.3: Extract from nested layout (CHARTS/ENC_ROOT/US5WA50M/US5WA50M.000)', () async {
      // ARRANGE: Create ZIP with nested folder structure
      addFile(testArchive, 'CHARTS/ENC_ROOT/$chartId/$chartId.000', 'S57_NESTED_DATA');
      addFile(testArchive, 'CHARTS/ENC_ROOT/$chartId/$chartId.txt', 'README_DATA');
      addFile(testArchive, 'CHARTS/ENC_ROOT/CATALOG.031', 'CATALOG_DATA');
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should find .000 file in nested layout
      expect(result, isNotNull, reason: 'Should extract .000 from nested layout');
      expect(String.fromCharCodes(result!), equals('S57_NESTED_DATA'),
          reason: 'Should return correct nested layout file content');
    });

    test('T004.4: Fallback precedence - ENC_ROOT preferred over root when both present', () async {
      // ARRANGE: Create ZIP with BOTH root and ENC_ROOT layouts
      addFile(testArchive, '$chartId.000', 'S57_ROOT_DATA');  // Less specific
      addFile(testArchive, 'ENC_ROOT/$chartId/$chartId.000', 'S57_ENC_ROOT_DATA');  // More specific
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should prefer ENC_ROOT over root (R04: precedence)
      expect(result, isNotNull, reason: 'Should extract when multiple layouts present');
      expect(String.fromCharCodes(result!), equals('S57_ENC_ROOT_DATA'),
          reason: 'Should prefer ENC_ROOT layout over root when both present');
    });

    test('T004.5: Fallback to nested when ENC_ROOT not found', () async {
      // ARRANGE: Create ZIP with only nested layout (no ENC_ROOT at top level)
      addFile(testArchive, 'NOAA_CHARTS/ENC_ROOT/$chartId/$chartId.000', 'S57_NESTED_FALLBACK');
      addFile(testArchive, 'NOAA_CHARTS/ENC_ROOT/CATALOG.031', 'CATALOG_DATA');
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should find .000 file in nested fallback
      expect(result, isNotNull, reason: 'Should fallback to nested layout when ENC_ROOT not at root');
      expect(String.fromCharCodes(result!), equals('S57_NESTED_FALLBACK'),
          reason: 'Should return correct nested fallback file content');
    });

    test('T004.6: Return null when no .000 file matches any pattern', () async {
      // ARRANGE: Create ZIP with NO .000 files, only other files
      addFile(testArchive, 'CATALOG.031', 'CATALOG_DATA');
      addFile(testArchive, 'README.txt', 'README_DATA');
      addFile(testArchive, 'ENC_ROOT/$chartId/$chartId.txt', 'TEXT_FILE');
      zipBytes = encodeZip(testArchive);

      // ACT: Extract S-57 data
      final result = await ZipExtractor.extractS57FromZip(zipBytes, chartId);

      // ASSERT: Should return null when no .000 file found (R27: error handling)
      expect(result, isNull, reason: 'Should return null when no .000 file matches any pattern');
    });
  });

  group('ZipExtractor Edge Cases (T004 Extended)', () {
    test('T004.7: Handle case-insensitive matching for chart ID', () async {
      // ARRANGE: Create ZIP with mixed case in path
      final archive = Archive();
      final file = ArchiveFile('ENC_ROOT/us5wa50m/US5WA50M.000', 18, 'S57_MIXEDCASE_DATA'.codeUnits);
      archive.addFile(file);
      final zipBytes = ZipEncoder().encode(archive)!;

      // ACT: Extract with uppercase chart ID
      final result = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');

      // ASSERT: Should handle case variations
      expect(result, isNotNull, reason: 'Should handle case-insensitive matching');
    });

    test('T004.8: Handle corrupt ZIP gracefully', () async {
      // ARRANGE: Create invalid ZIP bytes
      final corruptZip = List<int>.filled(100, 0xFF);

      // ACT & ASSERT: Should not throw, return null
      expect(
        () async => await ZipExtractor.extractS57FromZip(corruptZip, 'US5WA50M'),
        returnsNormally,
        reason: 'Should handle corrupt ZIP without throwing exception',
      );

      final result = await ZipExtractor.extractS57FromZip(corruptZip, 'US5WA50M');
      expect(result, isNull, reason: 'Should return null for corrupt ZIP');
    });
  });
}
