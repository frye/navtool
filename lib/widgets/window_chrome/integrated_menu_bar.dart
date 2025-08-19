import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/about/about_dialog.dart';

/// Integrated menu bar that displays application menus directly in the title bar
/// following VS Code's pattern. Provides keyboard shortcuts and accessibility.
class IntegratedMenuBar extends StatefulWidget {
  @override
  State<IntegratedMenuBar> createState() => _IntegratedMenuBarState();
}

class _IntegratedMenuBarState extends State<IntegratedMenuBar> {
  String? _openMenuTitle;

  void _closeAllMenus() {
    if (_openMenuTitle != null) {
      setState(() {
        _openMenuTitle = null;
      });
    }
  }

  void _toggleMenu(String menuTitle) {
    setState(() {
      _openMenuTitle = _openMenuTitle == menuTitle ? null : menuTitle;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _getMenus(context).map((menu) => _MenuButton(
        menu: menu,
        isOpen: _openMenuTitle == menu.title,
        onToggle: () {
          print('Menu toggle called for: ${menu.title}');
          _toggleMenu(menu.title);
        },
        onClose: _closeAllMenus,
      )).toList(),
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
  final bool isOpen;
  final VoidCallback onToggle;
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

  void _showDropdown() {
    if (_overlayEntry != null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + renderBox.size.height,
        child: GestureDetector(
          onTap: () {
            _removeOverlay();
            widget.onClose();
          },
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
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
                          return _buildMenuItem(context, action);
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

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    // Remove overlay when menu closes
    if (!widget.isOpen && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _removeOverlay();
      });
    } else if (widget.isOpen && _overlayEntry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDropdown();
      });
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          print('Menu button clicked: ${widget.menu.title}');
          widget.onToggle();
        },
        onPanStart: (_) {
          // Consume pan events to prevent window dragging
          print('Pan start consumed by menu button: ${widget.menu.title}');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: (_isHovered || widget.isOpen) ? Colors.grey.withOpacity(0.2) : Colors.transparent,
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

  Widget _buildMenuItem(BuildContext context, MenuAction action) {
    return InkWell(
      onTap: () {
        print('Menu action selected: ${action.title}');
        _removeOverlay();
        widget.onClose();
        action.onPressed();
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
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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