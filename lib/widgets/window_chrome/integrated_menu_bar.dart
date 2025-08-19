import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Menu action types for the integrated menu system
enum MenuAction {
  // File menu
  newChart,
  openChart,
  importChart,
  exportChart,
  recentFiles,
  exit,

  // Edit menu
  undo,
  redo,
  cut,
  copy,
  paste,
  preferences,

  // View menu
  zoomIn,
  zoomOut,
  resetZoom,
  fullScreen,
  togglePanels,

  // Tools menu
  chartLibrary,
  gpsSettings,
  navigationTools,

  // Help menu
  documentation,
  about,
  checkUpdates,
}

/// Integrated menu bar widget that embeds menus directly in the title bar
class IntegratedMenuBar extends StatelessWidget {
  const IntegratedMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuButton(context, 'File', _fileMenuItems()),
        _buildMenuButton(context, 'Edit', _editMenuItems()),
        _buildMenuButton(context, 'View', _viewMenuItems()),
        _buildMenuButton(context, 'Tools', _toolsMenuItems()),
        _buildMenuButton(context, 'Help', _helpMenuItems()),
      ],
    );
  }

  Widget _buildMenuButton(BuildContext context, String title, List<PopupMenuEntry<MenuAction>> items) {
    return PopupMenuButton<MenuAction>(
      onSelected: (action) => _handleMenuAction(context, action),
      itemBuilder: (context) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14.0,
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<MenuAction>> _fileMenuItems() {
    return [
      const PopupMenuItem(
        value: MenuAction.newChart,
        child: ListTile(
          leading: Icon(Icons.add_chart),
          title: Text('New Chart'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.openChart,
        child: ListTile(
          leading: Icon(Icons.folder_open),
          title: Text('Open Chart'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.importChart,
        child: ListTile(
          leading: Icon(Icons.upload_file),
          title: Text('Import Chart'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.exportChart,
        child: ListTile(
          leading: Icon(Icons.download),
          title: Text('Export Chart'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.recentFiles,
        child: ListTile(
          leading: Icon(Icons.history),
          title: Text('Recent Files'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.exit,
        child: ListTile(
          leading: Icon(Icons.exit_to_app),
          title: Text('Exit'),
          dense: true,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<MenuAction>> _editMenuItems() {
    return [
      const PopupMenuItem(
        value: MenuAction.undo,
        child: ListTile(
          leading: Icon(Icons.undo),
          title: Text('Undo'),
          trailing: Text('Ctrl+Z'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.redo,
        child: ListTile(
          leading: Icon(Icons.redo),
          title: Text('Redo'),
          trailing: Text('Ctrl+Y'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.cut,
        child: ListTile(
          leading: Icon(Icons.cut),
          title: Text('Cut'),
          trailing: Text('Ctrl+X'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.copy,
        child: ListTile(
          leading: Icon(Icons.copy),
          title: Text('Copy'),
          trailing: Text('Ctrl+C'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.paste,
        child: ListTile(
          leading: Icon(Icons.paste),
          title: Text('Paste'),
          trailing: Text('Ctrl+V'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.preferences,
        child: ListTile(
          leading: Icon(Icons.settings),
          title: Text('Preferences'),
          trailing: Text('Ctrl+,'),
          dense: true,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<MenuAction>> _viewMenuItems() {
    return [
      const PopupMenuItem(
        value: MenuAction.zoomIn,
        child: ListTile(
          leading: Icon(Icons.zoom_in),
          title: Text('Zoom In'),
          trailing: Text('Ctrl++'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.zoomOut,
        child: ListTile(
          leading: Icon(Icons.zoom_out),
          title: Text('Zoom Out'),
          trailing: Text('Ctrl+-'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.resetZoom,
        child: ListTile(
          leading: Icon(Icons.zoom_out_map),
          title: Text('Reset Zoom'),
          trailing: Text('Ctrl+0'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.fullScreen,
        child: ListTile(
          leading: Icon(Icons.fullscreen),
          title: Text('Full Screen'),
          trailing: Text('F11'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.togglePanels,
        child: ListTile(
          leading: Icon(Icons.view_sidebar),
          title: Text('Toggle Panels'),
          dense: true,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<MenuAction>> _toolsMenuItems() {
    return [
      const PopupMenuItem(
        value: MenuAction.chartLibrary,
        child: ListTile(
          leading: Icon(Icons.library_books),
          title: Text('Chart Library'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.gpsSettings,
        child: ListTile(
          leading: Icon(Icons.gps_fixed),
          title: Text('GPS Settings'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.navigationTools,
        child: ListTile(
          leading: Icon(Icons.navigation),
          title: Text('Navigation Tools'),
          dense: true,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<MenuAction>> _helpMenuItems() {
    return [
      const PopupMenuItem(
        value: MenuAction.documentation,
        child: ListTile(
          leading: Icon(Icons.help),
          title: Text('Documentation'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: MenuAction.checkUpdates,
        child: ListTile(
          leading: Icon(Icons.update),
          title: Text('Check for Updates'),
          dense: true,
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: MenuAction.about,
        child: ListTile(
          leading: Icon(Icons.info),
          title: Text('About NavTool'),
          dense: true,
        ),
      ),
    ];
  }

  void _handleMenuAction(BuildContext context, MenuAction action) {
    switch (action) {
      case MenuAction.newChart:
        _showNotImplemented(context, 'New Chart');
        break;
      case MenuAction.openChart:
        _showNotImplemented(context, 'Open Chart');
        break;
      case MenuAction.importChart:
        _showNotImplemented(context, 'Import Chart');
        break;
      case MenuAction.exportChart:
        _showNotImplemented(context, 'Export Chart');
        break;
      case MenuAction.recentFiles:
        _showNotImplemented(context, 'Recent Files');
        break;
      case MenuAction.exit:
        // Close the application
        SystemNavigator.pop();
        break;
      case MenuAction.undo:
        _showNotImplemented(context, 'Undo');
        break;
      case MenuAction.redo:
        _showNotImplemented(context, 'Redo');
        break;
      case MenuAction.cut:
        _showNotImplemented(context, 'Cut');
        break;
      case MenuAction.copy:
        _showNotImplemented(context, 'Copy');
        break;
      case MenuAction.paste:
        _showNotImplemented(context, 'Paste');
        break;
      case MenuAction.preferences:
        _showNotImplemented(context, 'Preferences');
        break;
      case MenuAction.zoomIn:
        _showNotImplemented(context, 'Zoom In');
        break;
      case MenuAction.zoomOut:
        _showNotImplemented(context, 'Zoom Out');
        break;
      case MenuAction.resetZoom:
        _showNotImplemented(context, 'Reset Zoom');
        break;
      case MenuAction.fullScreen:
        _showNotImplemented(context, 'Full Screen');
        break;
      case MenuAction.togglePanels:
        _showNotImplemented(context, 'Toggle Panels');
        break;
      case MenuAction.chartLibrary:
        _showNotImplemented(context, 'Chart Library');
        break;
      case MenuAction.gpsSettings:
        _showNotImplemented(context, 'GPS Settings');
        break;
      case MenuAction.navigationTools:
        _showNotImplemented(context, 'Navigation Tools');
        break;
      case MenuAction.documentation:
        _showNotImplemented(context, 'Documentation');
        break;
      case MenuAction.about:
        _showAboutDialog(context);
        break;
      case MenuAction.checkUpdates:
        _showNotImplemented(context, 'Check for Updates');
        break;
    }
  }

  void _showNotImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming soon'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'NavTool',
      applicationVersion: '0.0.1+1',
      applicationIcon: const Icon(
        Icons.anchor,
        size: 48.0,
        color: Colors.blue,
      ),
      children: [
        const Text('A marine navigation and routing application for desktop platforms.'),
        const SizedBox(height: 8.0),
        const Text('Built with Flutter for Windows, macOS, and Linux.'),
      ],
    );
  }
}
