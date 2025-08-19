import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/about/about_dialog.dart';

/// Integrated menu bar that displays application menus directly in the title bar
/// following VS Code's pattern. Provides keyboard shortcuts and accessibility.
class IntegratedMenuBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Prevent overflow
      children: _getMenus(context).map((menu) => _MenuButton(menu: menu)).toList(),
    );
  }

  static List<MenuDefinition> _getMenus(BuildContext context) => [
    MenuDefinition('File', 'F', [
      MenuAction('New Chart', Icons.add, 'Ctrl+N', () {
        Navigator.pushNamed(context, '/chart');
      }),
      MenuAction('Open', Icons.folder_open, 'Ctrl+O', () {
        Navigator.pushNamed(context, '/chart');
      }),
      MenuAction('Import', Icons.file_upload, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import functionality coming soon!')),
        );
      }),
      MenuAction('Export', Icons.file_download, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export functionality coming soon!')),
        );
      }),
      MenuAction.separator(),
      MenuAction('Recent Files', Icons.history, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recent files functionality coming soon!')),
        );
      }),
      MenuAction.separator(),
      MenuAction('Exit', Icons.exit_to_app, 'Alt+F4', () {
        windowManager.close();
      }),
    ]),
    MenuDefinition('Edit', 'E', [
      MenuAction('Undo', Icons.undo, 'Ctrl+Z', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Undo functionality coming soon!')),
        );
      }),
      MenuAction('Redo', Icons.redo, 'Ctrl+Y', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Redo functionality coming soon!')),
        );
      }),
      MenuAction.separator(),
      MenuAction('Cut', Icons.cut, 'Ctrl+X', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cut functionality coming soon!')),
        );
      }),
      MenuAction('Copy', Icons.copy, 'Ctrl+C', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copy functionality coming soon!')),
        );
      }),
      MenuAction('Paste', Icons.paste, 'Ctrl+V', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paste functionality coming soon!')),
        );
      }),
      MenuAction.separator(),
      MenuAction('Preferences', Icons.settings, 'Ctrl+,', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences functionality coming soon!')),
        );
      }),
    ]),
    MenuDefinition('View', 'V', [
      MenuAction('Zoom In', Icons.zoom_in, 'Ctrl++', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zoom functionality coming soon!')),
        );
      }),
      MenuAction('Zoom Out', Icons.zoom_out, 'Ctrl+-', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zoom functionality coming soon!')),
        );
      }),
      MenuAction('Reset Zoom', Icons.zoom_out_map, 'Ctrl+0', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset zoom functionality coming soon!')),
        );
      }),
      MenuAction.separator(),
      MenuAction('Full Screen', Icons.fullscreen, 'F11', () async {
        if (await windowManager.isFullScreen()) {
          windowManager.setFullScreen(false);
        } else {
          windowManager.setFullScreen(true);
        }
      }),
      MenuAction('Toggle Panels', Icons.view_sidebar, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Panel toggle functionality coming soon!')),
        );
      }),
    ]),
    MenuDefinition('Tools', 'T', [
      MenuAction('Chart Library', Icons.map, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chart library functionality coming soon!')),
        );
      }),
      MenuAction('GPS Settings', Icons.gps_fixed, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS settings functionality coming soon!')),
        );
      }),
      MenuAction('Navigation Tools', Icons.navigation, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigation tools functionality coming soon!')),
        );
      }),
    ]),
    MenuDefinition('Help', 'H', [
      MenuAction('Documentation', Icons.help, 'F1', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documentation functionality coming soon!')),
        );
      }),
      MenuAction('About NavTool', Icons.info, '', () {
        showDialog(
          context: context,
          builder: (context) => const AboutAppDialog(),
        );
      }),
      MenuAction('Check for Updates', Icons.system_update, '', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update check functionality coming soon!')),
        );
      }),
    ]),
  ];
}

class _MenuButton extends StatefulWidget {
  final MenuDefinition menu;

  const _MenuButton({required this.menu});

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuAction>(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // More compact
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(3.0), // Slightly smaller radius
          ),
          child: Text(
            widget.menu.title,
            style: TextStyle(
              fontSize: 13.0, // Reduced from 14.0
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
      onSelected: (action) => action.onPressed(),
      itemBuilder: (context) => widget.menu.actions
          .map((action) => _buildMenuItem(action))
          .cast<PopupMenuEntry<MenuAction>>()
          .toList(),
      offset: const Offset(0, 32), // Match the title bar height
    );
  }

  PopupMenuEntry<MenuAction> _buildMenuItem(MenuAction action) {
    if (action.isSeparator) {
      return const PopupMenuDivider();
    }

    return PopupMenuItem<MenuAction>(
      value: action,
      child: Row(
        children: [
          Icon(action.icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(action.title)),
          if (action.shortcut.isNotEmpty) ...[
            const SizedBox(width: 16),
            Text(
              action.shortcut,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Definition of a menu with title, mnemonic, and actions
class MenuDefinition {
  final String title;
  final String mnemonic;
  final List<MenuAction> actions;

  MenuDefinition(this.title, this.mnemonic, this.actions);
}

/// Definition of a menu action with icon, title, and callback
class MenuAction {
  final String title;
  final IconData? icon;
  final String shortcut;
  final VoidCallback onPressed;
  final bool isSeparator;

  MenuAction(this.title, this.icon, this.shortcut, this.onPressed)
      : isSeparator = false;

  MenuAction.separator()
      : title = '',
        icon = null,
        shortcut = '',
        onPressed = (() {}),
        isSeparator = true;
}