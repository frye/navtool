import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Global test configuration for Flutter tests
/// This file is automatically loaded by the test runner
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Initialize SQLite FFI for desktop platforms (including Raspberry Pi)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Setup method channel mocks for plugins that require platform implementation
  setupMethodChannelMocks();
  
  await testMain();
}

/// Sets up method channel mocks for platform plugins
void setupMethodChannelMocks() {
  // NOTE: Avoid overriding Flutter foundation debug variables (like debugPrint) globally.
  // Earlier attempt to silence logs by reassigning debugPrint triggered the framework invariant
  // "The value of a foundation debug variable was changed by the test" across many widget tests.
  // If log noise reduction is desired, prefer injecting a NoOp/AppLogger override per test via
  // Riverpod's provider overrides instead of mutating global foundation state here.
  // Mock shared_preferences
  const MethodChannel('plugins.flutter.io/shared_preferences')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'getAll':
        return <String, Object>{}; // Return empty preferences
      case 'setBool':
      case 'setInt':
      case 'setDouble':
      case 'setString':
      case 'setStringList':
        return true; // Successfully set value
      case 'remove':
        return true; // Successfully removed value
      case 'clear':
        return true; // Successfully cleared all values
      default:
        return null;
    }
  });

  // Mock path_provider if needed
  const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'getApplicationDocumentsDirectory':
        return '/tmp/flutter_test/documents';
      case 'getApplicationSupportDirectory':
        return '/tmp/flutter_test/support';
      case 'getTemporaryDirectory':
        return '/tmp/flutter_test/temp';
      default:
        return null;
    }
  });

  // Mock device_info_plus if needed
  const MethodChannel('dev.fluttercommunity.plus/device_info')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'getDeviceInfo':
        return {
          'name': 'Test Device',
          'model': 'Test Model',
          'manufacturer': 'Test Manufacturer',
          'systemName': 'Test OS',
          'systemVersion': '1.0.0',
        };
      default:
        return null;
    }
  });

  // Mock package_info_plus if needed
  const MethodChannel('dev.fluttercommunity.plus/package_info')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'getAll':
        return {
          'appName': 'NavTool Test',
          'packageName': 'com.example.navtool.test',
          'version': '1.0.0',
          'buildNumber': '1',
        };
      default:
        return null;
    }
  });
}
