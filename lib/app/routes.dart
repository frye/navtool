import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/about/about_screen.dart';
import '../features/charts/chart_screen.dart';
import '../features/charts/chart_browser_screen.dart';

class AppRoutes {
  static const String home = '/';
  static const String about = '/about';
  static const String chart = '/chart';
  static const String chartBrowser = '/chart-browser';

  static Map<String, WidgetBuilder> routes = {
    home: (context) => const HomeScreen(),
    about: (context) => const AboutScreen(),
    chart: (context) => const ChartScreen(),
    chartBrowser: (context) => const ChartBrowserScreen(),
  };
}
