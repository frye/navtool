import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:navtool/core/logging/app_logger.dart';

import 'integrated_menu_bar.dart';
import 'status_bar.dart';

/// Custom window chrome that provides a VS Code-like title bar integration
/// for Windows and Linux platforms. On macOS, this widget will return the
/// child directly since macOS uses native menu bars.
class CustomWindowChrome extends StatefulWidget {
  final Widget child;

  const CustomWindowChrome({super.key, required this.child});

  @override
  State<CustomWindowChrome> createState() => _CustomWindowChromeState();
}

class _CustomWindowChromeState extends State<CustomWindowChrome> {
  @override
  Widget build(BuildContext context) {
    // Only apply custom chrome on Windows and Linux
    if (!Platform.isWindows && !Platform.isLinux) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          // Custom title bar with integrated menu
          const _CustomTitleBar(),
          // Main content area
          Expanded(child: widget.child),
          // Status bar at bottom
          const StatusBar(),
        ],
      ),
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  static const double titleBarHeight = 32.0; // Reduced from 40.0

  const _CustomTitleBar();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        // Use logger instead of print to respect avoid_print lint
        logger.debug(
          'Starting drag from title bar background',
          context: 'WindowChrome',
        );
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: titleBarHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1.0,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App icon and title (draggable)
            Row(
              children: [
                _buildAppIcon(),
                const SizedBox(width: 4),
                _buildAppTitle(context),
                const SizedBox(width: 8),
              ],
            ),
            // Menu bar - will have its own gesture detection
            const IntegratedMenuBar(),
            // Expanded draggable area
            Expanded(child: Container()),
            _buildWindowControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 6.0,
        vertical: 4.0,
      ), // Reduced padding
      child: Image.asset(
        'assets/icons/app_icon.png',
        width: 20.0, // Reduced from 24.0
        height: 20.0, // Reduced from 24.0
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildAppTitle(BuildContext context) {
    return Text(
      'NavTool',
      style: TextStyle(
        fontSize: 13.0, // Reduced from 14.0
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildWindowControls(BuildContext context) {
    return Row(
      children: [
        _WindowControlButton(
          icon: Icons.minimize,
          onPressed: () => windowManager.minimize(),
          tooltip: 'Minimize',
        ),
        _WindowControlButton(
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          tooltip: 'Maximize/Restore',
        ),
        _WindowControlButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          isClose: true,
          tooltip: 'Close',
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final String tooltip;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
    required this.tooltip,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isHovered
        ? (widget.isClose ? Colors.red : Colors.grey.withValues(alpha: 0.2))
        : Colors.transparent;

    final iconColor = _isHovered && widget.isClose
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32, // Match the title bar height
          decoration: BoxDecoration(color: backgroundColor),
          child: Icon(
            widget.icon,
            size: 14, // Reduced from 16
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
