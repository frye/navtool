import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:navtool/core/services/download_service_impl.dart';
import 'package:navtool/core/services/http_client_service.dart';
import 'package:navtool/core/services/storage_service.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/error/error_handler.dart';
import 'package:navtool/core/state/download_state.dart';

// Simple mocks (manual lightweight) since we only need minimal behaviors
class MockHttpClientService extends Mock implements HttpClientService {}
class FakeStorageService extends Mock implements StorageService {
  Directory dir;
  FakeStorageService(this.dir);
  @override
  Future<Directory> getChartsDirectory() async => dir;
}
class MockAppLogger extends Mock implements AppLogger {}
class MockErrorHandler extends Mock implements ErrorHandler {}

void main() {
  group('DownloadService resume cleanup', () {
    late Directory tempDir;
    late MockHttpClientService http;
  late FakeStorageService storage;
    late MockAppLogger logger;
    late MockErrorHandler errors;

    DownloadServiceImpl _build() => DownloadServiceImpl(
      httpClient: http,
      storageService: storage,
      logger: logger,
      errorHandler: errors,
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resume_cleanup_test');
      http = MockHttpClientService();
  storage = FakeStorageService(tempDir);
  logger = MockAppLogger();
  errors = MockErrorHandler();
    });

    tearDown(() async {
      try { if (await tempDir.exists()) await tempDir.delete(recursive: true); } catch (_) {}
    });

    test('removes orphaned resume entry with no files', () async {
      final stateFile = File('${tempDir.path}/.download_state.json');
      final state = {
        'downloads': {},
        'resumeData': {
          'ORPHAN': {
            'chartId': 'ORPHAN',
            'originalUrl': 'https://example.com/orphan.zip',
            'downloadedBytes': 123,
            'lastAttempt': DateTime.now().toIso8601String(),
            'checksum': null,
            'supportsRange': null,
            'attempts': 2,
            'lastErrorCode': null,
          }
        },
        'queue': []
      };
      await stateFile.writeAsString(jsonEncode(state));
      final service = _build();
      await service.recoverDownloads(const []); // triggers load + sweep
      final resume = await service.getResumeData('ORPHAN');
      expect(resume, isNull, reason: 'Orphan entry should be removed');
      service.dispose();
    });

    test('normalizes mismatched partial size instead of removing', () async {
      final stateFile = File('${tempDir.path}/.download_state.json');
      final part = File('${tempDir.path}/MISMATCH.zip.part');
      await part.writeAsBytes(List<int>.filled(50, 7));
      final state = {
        'downloads': {},
        'resumeData': {
          'MISMATCH': {
            'chartId': 'MISMATCH',
            'originalUrl': 'https://example.com/mismatch.zip',
            'downloadedBytes': 10, // stale value
            'lastAttempt': DateTime.now().toIso8601String(),
            'checksum': null,
            'supportsRange': true,
            'attempts': 1,
            'lastErrorCode': null,
          }
        },
        'queue': []
      };
      await stateFile.writeAsString(jsonEncode(state));
      final service = _build();
      await service.recoverDownloads(const []);
      final resume = await service.getResumeData('MISMATCH');
      expect(resume, isNotNull);
      expect(resume!.downloadedBytes, 50, reason: 'Should adjust to actual .part size');
      service.dispose();
    });

    test('removes completed final file entry', () async {
      final stateFile = File('${tempDir.path}/.download_state.json');
      final finalFile = File('${tempDir.path}/COMPLETE.zip');
      await finalFile.writeAsBytes(List<int>.filled(40, 1));
      final state = {
        'downloads': {},
        'resumeData': {
          'COMPLETE': {
            'chartId': 'COMPLETE',
            'originalUrl': 'https://example.com/complete.zip',
            'downloadedBytes': 20, // less than final size => treat as complete
            'lastAttempt': DateTime.now().toIso8601String(),
            'checksum': null,
            'supportsRange': true,
            'attempts': 3,
            'lastErrorCode': null,
          }
        },
        'queue': []
      };
      await stateFile.writeAsString(jsonEncode(state));
      final service = _build();
      await service.recoverDownloads(const []);
      final resume = await service.getResumeData('COMPLETE');
      expect(resume, isNull, reason: 'Completed file should clear resume metadata');
      service.dispose();
    });

    test('removes zero-length corrupt partial entry', () async {
      final stateFile = File('${tempDir.path}/.download_state.json');
      final part = File('${tempDir.path}/ZERO.zip.part');
      await part.writeAsBytes(const []); // zero length partial
      final state = {
        'downloads': {},
        'resumeData': {
          'ZERO': {
            'chartId': 'ZERO',
            'originalUrl': 'https://example.com/zero.zip',
            'downloadedBytes': 100,
            'lastAttempt': DateTime.now().toIso8601String(),
            'checksum': null,
            'supportsRange': false,
            'attempts': 1,
            'lastErrorCode': null,
          }
        },
        'queue': []
      };
      await stateFile.writeAsString(jsonEncode(state));
      final service = _build();
      await service.recoverDownloads(const []);
      final resume = await service.getResumeData('ZERO');
      expect(resume, isNull, reason: 'Zero-length partial should be treated as corrupt and removed');
      expect(await part.exists(), isFalse, reason: 'Corrupt partial file should be deleted');
      service.dispose();
    });
  });
}
