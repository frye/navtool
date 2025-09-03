import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/about/about_dialog.dart';
import '../../app/app.dart';
import '../../core/logging/app_logger.dart';

/// Integrated menu bar that displays application menus directly in the title bar
/// following VS Code's pattern. Provides keyboard shortcuts and accessibility.
class IntegratedMenuBar extends StatefulWidget {
  const IntegratedMenuBar({super.key});

  @override
  State<IntegratedMenuBar> createState() => _IntegratedMenuBarState();
}

class _IntegratedMenuBarState extends State<IntegratedMenuBar> {
  String? _openMenuTitle;

  void _toggleMenu(String menuTitle, GlobalKey menuKey) {
    setState(() {
      if (_openMenuTitle == menuTitle) {
        _openMenuTitle = null;
      } else {
        _openMenuTitle = menuTitle;
      }
    });
  }

  void _closeMenu() {
    setState(() {
      _openMenuTitle = null;
    });
  }

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
        isOpen: _openMenuTitle == menu.title,
        onToggle: _toggleMenu,
        onClose: _closeMenu,
      )).toList(),
    );
  }

  static List<MenuAction> _getActionsForMenu(String title) {
    switch (title) {
      case 'File':
        return [
          MenuAction('New Chart', Icons.add, 'Ctrl+N', (context) {
            logger.info('New Chart selected - navigating to chart', context: 'Menu.File');
            try {
              MyApp.navigatorKey.currentState?.pushNamed('/chart');
            } catch (e) {
              logger.error('Failed to navigate', context: 'Menu.File', exception: e);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New Chart - Navigation functionality needs fixing')),
              );
            }
          }),
          MenuAction('Open', Icons.folder_open, 'Ctrl+O', (context) {
            logger.info('Open selected - navigating to chart', context: 'Menu.File');
            try {
              MyApp.navigatorKey.currentState?.pushNamed('/chart');
            } catch (e) {
              logger.error('Failed to navigate', context: 'Menu.File', exception: e);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open - Navigation functionality needs fixing')),
              );
            }
          }),
          MenuAction('Import', Icons.file_upload, '', (context) {
            logger.info('Import selected', context: 'Menu.File');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Import functionality coming soon!')),
            );
          }),
          MenuAction('Export', Icons.file_download, '', (context) {
            logger.info('Export selected', context: 'Menu.File');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Recent Files', Icons.history, '', (context) {
            logger.info('Recent Files selected', context: 'Menu.File');
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
            logger.info('Undo selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Undo functionality coming soon!')),
            );
          }),
          MenuAction('Redo', Icons.redo, 'Ctrl+Y', (context) {
            logger.info('Redo selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Redo functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Cut', Icons.cut, 'Ctrl+X', (context) {
            logger.info('Cut selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cut functionality coming soon!')),
            );
          }),
          MenuAction('Copy', Icons.copy, 'Ctrl+C', (context) {
            logger.info('Copy selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copy functionality coming soon!')),
            );
          }),
          MenuAction('Paste', Icons.paste, 'Ctrl+V', (context) {
            logger.info('Paste selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Paste functionality coming soon!')),
            );
          }),
          MenuAction.separator(),
          MenuAction('Preferences', Icons.settings, 'Ctrl+,', (context) {
            logger.info('Preferences selected', context: 'Menu.Edit');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preferences functionality coming soon!')),
            );
          }),
        ];
      case 'View':
        return [
          MenuAction('Zoom In', Icons.zoom_in, 'Ctrl++', (context) {
            logger.info('Zoom In selected', context: 'Menu.View');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Zoom functionality coming soon!')),
            );
          }),
          MenuAction('Zoom Out', Icons.zoom_out, 'Ctrl+-', (context) {
            logger.info('Zoom Out selected', context: 'Menu.View');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Zoom functionality coming soon!')),
            );
          }),
          MenuAction('Reset Zoom', Icons.zoom_out_map, 'Ctrl+0', (context) {
            logger.info('Reset Zoom selected', context: 'Menu.View');
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
            logger.info('Chart Library selected', context: 'Menu.Tools');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Chart library functionality coming soon!')),
            );
          }),
          MenuAction('GPS Settings', Icons.gps_fixed, '', (context) {
            logger.info('GPS Settings selected', context: 'Menu.Tools');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('GPS settings functionality coming soon!')),
            );
          }),
          MenuAction('Navigation Tools', Icons.navigation, '', (context) {
            logger.info('Navigation Tools selected', context: 'Menu.Tools');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Navigation tools functionality coming soon!')),
            );
          }),
        ];
      case 'Help':
        return [
          MenuAction('Documentation', Icons.help, 'F1', (context) {
            logger.info('Documentation selected', context: 'Menu.Help');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Documentation functionality coming soon!')),
            );
          }),
          MenuAction('About NavTool', Icons.info, '', (context) {
            logger.info('About NavTool selected - showing dialog', context: 'Menu.Help');
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
              logger.error('Failed to show dialog', context: 'Menu.Help', exception: e);
              // Fallback to showing a snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About NavTool - Dialog functionality needs fixing')),
              );
            }
          }),
          MenuAction('Check for Updates', Icons.system_update, '', (context) {
            logger.info('Check for Updates selected', context: 'Menu.Help');
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
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    // Show/hide overlay based on isOpen state
    if (widget.isOpen && _overlayEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDropdown());
    } else if (!widget.isOpen && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _removeOverlay());
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        key: _menuKey,
        onTap: () {
          logger.debug('Menu button clicked: ${widget.menu.title}', context: 'Menu.UI');
          widget.onToggle(widget.menu.title, _menuKey);
        },
        onPanStart: (_) {
          // Consume pan events to prevent window dragging
          logger.debug('Pan start consumed by menu button: ${widget.menu.title}', context: 'Menu.UI');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
      color: (_isHovered || widget.isOpen)
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.transparent,
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

  void _showDropdown() {
    if (_overlayEntry != null) return;

    final RenderBox? renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: offset.dx,
        top: offset.dy + renderBox.size.height,
        child: GestureDetector(
          onTap: () {
            widget.onClose();
          },
          child: Container(
            width: MediaQuery.of(overlayContext).size.width,
            height: MediaQuery.of(overlayContext).size.height,
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {}, // Prevent closing when clicking the menu
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.menu.actions.map((action) {
                          if (action.isSeparator) {
                            return const Divider(height: 1, thickness: 1);
                          }
                          return _buildMenuItem(action);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Use the widget's own context to find the overlay
    final overlay = Overlay.of(context);
    overlay.insert(_overlayEntry!);
  }

  Widget _buildMenuItem(MenuAction action) {
    return InkWell(
      onTap: () {
        logger.debug('Menu action selected: ${action.title}', context: 'Menu.Action');
        widget.onClose();
        // Execute the action using the global navigator context
        final navigatorState = MyApp.navigatorKey.currentState;
        if (navigatorState != null) {
          action.onPressed(navigatorState.context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
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