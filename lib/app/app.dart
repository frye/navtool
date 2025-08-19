import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../widgets/window_chrome/custom_window_chrome.dart';
import '../widgets/window_chrome/status_bar.dart';
import 'routes.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavTool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.home,
      routes: AppRoutes.routes,
      builder: (context, child) {
        // Apply custom window chrome only on Windows and Linux
        if (Platform.isWindows || Platform.isLinux) {
          return CustomWindowChrome(
            child: Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                const StatusBar(),
              ],
            ),
          );
        }
        // On other platforms (macOS), use default window chrome
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
