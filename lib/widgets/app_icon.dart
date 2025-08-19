import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  const AppIcon({
    super.key,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Use the sailboat-themed app icon for all platforms
    return SvgPicture.asset(
      'assets/icons/app_icon.svg',
      width: size ?? 24.0,
      height: size ?? 24.0,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}
