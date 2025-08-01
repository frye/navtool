import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/about/about_screen.dart';

class AppRoutes {
  static const String home = '/';
  static const String about = '/about';

  static Map<String, WidgetBuilder> routes = {
    home: (context) => const HomeScreen(),
    about: (context) => const AboutScreen(),
  };
}
