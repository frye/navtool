import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  const AppIcon({super.key, this.size, this.color});

  /// Get the appropriate icon asset path based on the current platform
  String _getIconAssetPath() {
    // Use platform-specific icons for better integration
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return 'assets/icons/app_icon_macos_sailboat.svg';
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return 'assets/icons/app_icon.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _getIconAssetPath(),
      width: size ?? 24.0,
      height: size ?? 24.0,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}
