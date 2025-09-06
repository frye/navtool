import 'package:mockito/mockito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/logging/app_logger.dart';

/// Common helper wrappers to reduce brittle direct verify calls for AppLogger.
/// Use patterns (substring or RegExp) instead of full message literals.

void verifyInfoLogged(
  dynamic logger,
  Pattern pattern, {
  String? expectedContext,
  int times = 1,
}) {
  if (expectedContext != null) {
    verify(
      logger.info(argThat(_containsPattern(pattern)), context: expectedContext),
    ).called(times);
  } else {
    verify(
      logger.info(
        argThat(_containsPattern(pattern)),
        context: anyNamed('context'),
      ),
    ).called(times);
  }
}

void verifyWarningLogged(
  dynamic logger,
  Pattern pattern, {
  String? expectedContext,
  int times = 1,
}) {
  if (expectedContext != null) {
    verify(
      logger.warning(
        argThat(_containsPattern(pattern)),
        context: expectedContext,
        exception: anyNamed('exception'),
      ),
    ).called(times);
  } else {
    verify(
      logger.warning(
        argThat(_containsPattern(pattern)),
        context: anyNamed('context'),
        exception: anyNamed('exception'),
      ),
    ).called(times);
  }
}

void verifyErrorLogged(
  dynamic logger,
  Pattern pattern, {
  String? expectedContext,
  int times = 1,
}) {
  if (expectedContext != null) {
    verify(
      logger.error(
        argThat(_containsPattern(pattern)),
        context: expectedContext,
        exception: anyNamed('exception'),
      ),
    ).called(times);
  } else {
    verify(
      logger.error(
        argThat(_containsPattern(pattern)),
        context: anyNamed('context'),
        exception: anyNamed('exception'),
      ),
    ).called(times);
  }
}

/// Verify a debug log occurred. Debug logs are sometimes noisier; this helper keeps parity with
/// the info/warning/error helpers and allows incremental migration of direct verify calls.
void verifyDebugLogged(
  dynamic logger,
  Pattern pattern, {
  String? expectedContext,
  int times = 1,
}) {
  if (expectedContext != null) {
    verify(
      logger.debug(
        argThat(_containsPattern(pattern)),
        context: expectedContext,
        exception: anyNamed('exception'),
      ),
    ).called(times);
  } else {
    verify(
      logger.debug(
        argThat(_containsPattern(pattern)),
        context: anyNamed('context'),
        exception: anyNamed('exception'),
      ),
    ).called(times);
  }
}

/// Assert that no error logs were emitted. Useful for negative-path assertions where the
/// presence of an error log would indicate regression. This intentionally ignores context value.
void expectNoErrorLogs(dynamic logger) {
  verifyNever(
    logger.error(
      any,
      context: anyNamed('context'),
      exception: anyNamed('exception'),
    ),
  );
}

Matcher _containsPattern(Pattern p) {
  if (p is RegExp) {
    return predicate<String>(
      (msg) => p.hasMatch(msg),
      'message matching /${p.pattern}/',
    );
  }
  return contains(p.toString());
}
