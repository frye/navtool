import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app/app.dart';
import 'core/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager for Windows and Linux only
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Hide system title bar for custom chrome
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // Initialize FFI database factory for desktop (required before opening any databases)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Create provider container to initialize services
  final container = ProviderContainer();
  
  try {
    // Initialize background task service early
    final backgroundTaskService = container.read(backgroundTaskServiceProvider);
    await backgroundTaskService.initialize();
    
    // Run the app with the provider scope
    runApp(
      ProviderScope(
        child: const MyApp(),
      ),
    );
  } catch (error) {
    // Log initialization error and run app without background tasks
    debugPrint('Failed to initialize background tasks: $error');
    runApp(
      ProviderScope(
        child: const MyApp(),
      ),
    );
  }
}
