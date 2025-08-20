import 'package:flutter/material.dart';
import 'dart:io';
import 'routes.dart';
import '../widgets/window_chrome/custom_window_chrome.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global navigation key to access navigator from anywhere
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'NavTool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routes: AppRoutes.routes,
      initialRoute: AppRoutes.home,
      debugShowCheckedModeBanner: false,
    );
  }
}
