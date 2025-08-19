import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/about/about_dialog.dart';

/// Native macOS menu bar implementation using PlatformMenuBar
/// Provides File and Help menus integrated with the macOS menu system
class MacosNativeMenuBar extends StatelessWidget {
  final Widget child;
  final VoidCallback? onNewChart;
  final VoidCallback? onOpenChart;
  final VoidCallback? onAboutSelected;

  const MacosNativeMenuBar({
    super.key,
    required this.child,
    this.onNewChart,
    this.onOpenChart,
    this.onAboutSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Chart',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
              onSelected: () {
                if (onNewChart != null) {
                  onNewChart!();
                } else {
                  Navigator.pushNamed(context, '/chart');
                }
              },
            ),
            PlatformMenuItem(
              label: 'Open Chart',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: () {
                if (onOpenChart != null) {
                  onOpenChart!();
                } else {
                  Navigator.pushNamed(context, '/chart');
                }
              },
            ),
            PlatformMenuItem(
              label: 'Import GRIB Data',
              onSelected: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Import GRIB Data functionality coming soon!')),
                );
              },
            ),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'About NavTool',
              onSelected: () {
                if (onAboutSelected != null) {
                  onAboutSelected!();
                } else {
                  showDialog(
                    context: context,
                    builder: (context) => const AboutAppDialog(),
                  );
                }
              },
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}