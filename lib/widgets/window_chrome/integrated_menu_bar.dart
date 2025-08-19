import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/about/about_dialog.dart';
import '../../app/app.dart';

/// Integrated menu bar that displays application menus directly in the title bar
/// following VS Code's pattern. Provides keyboard shortcuts and accessibility.
class IntegratedMenuBar extends StatelessWidget {
  const IntegratedMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    final menus = [
      MenuDefinition('File', 'F', _getActionsForMenu('File')),
      MenuDefinition('Edit', 'E', _getActionsForMenu('Edit')),
      MenuDefinition('View', 'V', _getActionsForMenu('View')),
      MenuDefinition('Tools', 'T', _getActionsForMenu('Tools')),
      MenuDefinition('Help', 'H', _getActionsForMenu('Help')),
    ];
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: menus.map((menu) => _MenuButton(
        menu: menu,
        isOpen: false, // Not used with PopupMenuButton
        onToggle: (_, __) {}, // Not used with PopupMenuButton
        onClose: () {}, // Not used with PopupMenuButton
      )).toList(),
    );
  }

  static List<MenuAction> _getActionsForMenu(String title) {
    switch (title) {
      case 'File':
        return [
          MenuAction('New Chart', Icons.add, 'Ctrl+N', (context) {
            print('New Chart selected - navigating to chart');
            try {
              MyApp.navigatorKey.currentState?.pushNamed('/chart');
            } catch (e) {
              print('Failed to navigate: $e');
              // Fallback to showing a snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New Chart - Navigation functionality needs fixing')),
              );
            }
          }),
          MenuAction('Open', Icons.folder_open, 'Ctrl+O', (context) {
            print('Open selected - navigating to chart');
            try {
              MyApp.navigatorKey.currentState?.pushNamed('/chart');
            } catch (e) {
              print('Failed to navigate: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open - Navigation functionality needs fixing')),
              );
            }
          }),
          MenuAction('Import', Icons.file_upload, '', (context) {
            print('Import selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Import functionality coming soon!')),
            );
          }),
          MenuAction('Export', Icons.file_download, '', (context) {
            print('Export selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Recent Files', Icons.history, '', (context) {
            print('Recent Files selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recent files functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Exit', Icons.exit_to_app, 'Alt+F4', (context) {
            windowManager.close();
          }),
        ];
      case 'Edit':
        return [
          MenuAction('Undo', Icons.undo, 'Ctrl+Z', (context) {
            print('Undo selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Undo functionality coming soon!')),
            );
          }),
          MenuAction('Redo', Icons.redo, 'Ctrl+Y', (context) {
            print('Redo selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Redo functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Cut', Icons.cut, 'Ctrl+X', (context) {
            print('Cut selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cut functionality coming soon!')),
            );
          }),
          MenuAction('Copy', Icons.copy, 'Ctrl+C', (context) {
            print('Copy selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copy functionality coming soon!')),
            );
          }),
          MenuAction('Paste', Icons.paste, 'Ctrl+V', (context) {
            print('Paste selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Paste functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Preferences', Icons.settings, 'Ctrl+,', (context) {
            print('Preferences selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preferences functionality coming soon!')),
            );
          }),
        ];
      case 'View':
        return [
          MenuAction('Zoom In', Icons.zoom_in, 'Ctrl++', (context) {
            print('Zoom In selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Zoom functionality coming soon!')),
            );
          }),
          MenuAction('Zoom Out', Icons.zoom_out, 'Ctrl+-', (context) {
            print('Zoom Out selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Zoom functionality coming soon!')),
            );
          }),
          MenuAction('Reset Zoom', Icons.zoom_out_map, 'Ctrl+0', (context) {
            print('Reset Zoom selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Reset zoom functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Full Screen', Icons.fullscreen, 'F11', (context) async {
            if (await windowManager.isFullScreen()) {
              windowManager.setFullScreen(false);
            } else {
              windowManager.setFullScreen(true);
            }
          }),
        ];
      case 'Tools':
        return [
          MenuAction('Chart Library', Icons.map, '', (context) {
            print('Chart Library selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Chart library functionality coming soon!')),
            );
          }),
          MenuAction('GPS Settings', Icons.gps_fixed, '', (context) {
            print('GPS Settings selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('GPS settings functionality coming soon!')),
            );
          }),
          MenuAction('Navigation Tools', Icons.navigation, '', (context) {
            print('Navigation Tools selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Navigation tools functionality coming soon!')),
            );
          }),
        ];
      case 'Help':
        return [
          MenuAction('Documentation', Icons.help, 'F1', (context) {
            print('Documentation selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Documentation functionality coming soon!')),
            );
          }),
          MenuAction('About NavTool', Icons.info, '', (context) {
            print('About NavTool selected - showing dialog');
            // Use the global navigator key to access the root navigator
            try {
              final navigatorState = MyApp.navigatorKey.currentState;
              if (navigatorState != null) {
                showDialog(
                  context: navigatorState.context,
                  builder: (context) => const AboutAppDialog(),
                );
              } else {
                // Fallback to showing a snackbar
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('About NavTool - Dialog functionality needs fixing')),
                );
              }
            } catch (e) {
              print('Failed to show dialog: $e');
              // Fallback to showing a snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About NavTool - Dialog functionality needs fixing')),
              );
            }
          }),
          MenuAction('Check for Updates', Icons.system_update, '', (context) {
            print('Check for Updates selected');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Update check functionality coming soon!')),
            );
          }),
        ];
      default:
        return [];
    }
  }
}

class _MenuButton extends StatefulWidget {
  final MenuDefinition menu;
  final bool isOpen;
  final Function(String, GlobalKey) onToggle;
  final VoidCallback onClose;

  const _MenuButton({
    required this.menu,
    required this.isOpen,
    required this.onToggle,
    required this.onClose,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _isHovered = false;
  final GlobalKey _menuKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        key: _menuKey,
        onTap: () {
          print('Menu button clicked: ${widget.menu.title}');
          // For now, let's handle the actions directly instead of using dropdowns
          _showMenuActions(context);
        },
        onPanStart: (_) {
          // Consume pan events to prevent window dragging
          print('Pan start consumed by menu button: ${widget.menu.title}');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(3.0),
          ),
          child: Text(
            widget.menu.title,
            style: TextStyle(
              fontSize: 13.0,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  void _showMenuActions(BuildContext context) {
    if (widget.menu.title == 'Help') {
      // Show About dialog directly
      final aboutAction = widget.menu.actions.firstWhere(
        (action) => action.title == 'About NavTool',
        orElse: () => widget.menu.actions.first,
      );
      aboutAction.onPressed(context);
    } else if (widget.menu.title == 'File') {
      // Navigate to chart directly
      final newChartAction = widget.menu.actions.firstWhere(
        (action) => action.title == 'New Chart',
        orElse: () => widget.menu.actions.first,
      );
      newChartAction.onPressed(context);
    } else {
      // For other menus, show a simple snackbar for now
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.menu.title} menu functionality coming soon!')),
      );
    }
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
  final Function(BuildContext) onPressed;
  final bool isSeparator;

  MenuAction(this.title, this.icon, this.shortcut, this.onPressed)
      : isSeparator = false;

  MenuAction.separator()
      : title = '',
        icon = null,
        shortcut = '',
        onPressed = ((context) {}),
        isSeparator = true;
}