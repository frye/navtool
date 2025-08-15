import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
