import 'package:flutter/material.dart';
import 'dart:io';
import 'routes.dart';
import '../widgets/window_chrome/custom_window_chrome.dart';

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
      home: _AppContent(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _AppContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Apply custom window chrome on Windows and Linux only
    // macOS will use native menu bars (issue #110)
    if (Platform.isWindows || Platform.isLinux) {
      return CustomWindowChrome(
        child: Navigator(
          onGenerateRoute: (settings) {
            final routeName = settings.name ?? '/';
            final routeBuilder = AppRoutes.routes[routeName];
            if (routeBuilder != null) {
              return MaterialPageRoute(
                builder: routeBuilder,
                settings: settings,
              );
            }
            // Default to home if route not found
            return MaterialPageRoute(
              builder: AppRoutes.routes['/']!,
              settings: RouteSettings(name: '/'),
            );
          },
        ),
      );
    } else {
      // For macOS and other platforms, use normal navigation
      return Navigator(
        onGenerateRoute: (settings) {
          final routeName = settings.name ?? '/';
          final routeBuilder = AppRoutes.routes[routeName];
          if (routeBuilder != null) {
            return MaterialPageRoute(
              builder: routeBuilder,
              settings: settings,
            );
          }
          // Default to home if route not found
          return MaterialPageRoute(
            builder: AppRoutes.routes['/']!,
            settings: RouteSettings(name: '/'),
          );
        },
      );
    }
  }
}
