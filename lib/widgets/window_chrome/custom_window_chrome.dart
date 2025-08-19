import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'integrated_menu_bar.dart';

/// Custom window chrome widget that provides VS Code-like title bar
/// with integrated menus and window controls for Windows and Linux platforms
class CustomWindowChrome extends StatelessWidget {
  final Widget child;

  const CustomWindowChrome({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Custom title bar
        WindowTitleBarBox(
          child: Container(
            height: 40.0,
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
              children: [
                _buildAppIcon(),
                _buildAppTitle(context),
                const IntegratedMenuBar(),
                Expanded(child: MoveWindow()),
                _buildWindowControls(),
              ],
            ),
          ),
        ),
        // Main app content
        Expanded(child: child),
      ],
    );
  }

  Widget _buildAppIcon() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        width: 24.0,
        height: 24.0,
        child: Image.asset(
          'assets/icon.png',
          width: 24.0,
          height: 24.0,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to Material icon if asset loading fails
            return const Icon(
              Icons.anchor,
              size: 24.0,
              color: Colors.blue,
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        'NavTool',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildWindowControls() {
    return Row(
      children: [
        MinimizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.grey[600],
            iconMouseOver: Colors.grey[800],
            mouseOver: Colors.grey[200],
          ),
        ),
        MaximizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.grey[600],
            iconMouseOver: Colors.grey[800],
            mouseOver: Colors.grey[200],
          ),
        ),
        CloseWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.grey[600],
            iconMouseOver: Colors.white,
            mouseOver: Colors.red,
          ),
        ),
      ],
    );
  }
}
