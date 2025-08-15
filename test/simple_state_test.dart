import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navtool/core/state/providers.dart';

void main() {
  group('Simple State Tests', () {
    test('provider container can be created', () {
      final container = ProviderContainer();
      expect(container, isNotNull);
      container.dispose();
    });

    test('app state provider can be read', () {
      final container = ProviderContainer();
      try {
        final state = container.read(appStateProvider);
        expect(state, isNotNull);
        expect(state.isInitialized, false);
      } finally {
        container.dispose();
      }
    });
  });
}
