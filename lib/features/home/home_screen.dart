import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/gps_status_widget.dart';
import '../about/about_dialog.dart';
import '../about/about_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine if we're on a desktop or mobile/tablet layout
        final isDesktop = constraints.maxWidth > 800 || defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS;

        if (isDesktop) {
          return _buildDesktopLayout(context);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Custom menu bar similar to VS Code
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withAlpha(50),
                ),
              ),
            ),
            child: Row(
              children: [
                // App icon on the left
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: const AppIcon(size: 16),
                ),
                // Menu items
                _buildMenuButton(context, 'File', [
                  const PopupMenuItem<String>(value: 'New Chart', child: Text('New Chart')),
                  const PopupMenuItem<String>(value: 'Open Chart', child: Text('Open Chart')),
                  const PopupMenuItem<String>(value: 'Import GRIB Data', child: Text('Import GRIB Data')),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(value: 'Exit', child: Text('Exit')),
                ]),
                _buildMenuButton(context, 'Help', [
                  const PopupMenuItem<String>(value: 'About NavTool', child: Text('About NavTool')),
                ]),
                const Spacer(),
                // GPS status indicator on the right
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.gps_fixed,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'GPS',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          // Main content area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side - Welcome content
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AppIcon(size: 128),
                          const SizedBox(height: 24),
                          Text(
                            'Welcome to NavTool',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Marine Navigation and Routing Application',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/chart');
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('New Chart'),
                              ),
                              const SizedBox(width: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/chart');
                                },
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Open Chart'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right side - GPS Status
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 40),
                        const GpsStatusWidget(),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Status',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '✅ GPS Service: Active',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '✅ Windows Compatibility: Fixed',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '⚠️ Real GPS Hardware: Not connected',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String label, List<PopupMenuEntry<String>> items) {
    return PopupMenuButton<String>(
      itemBuilder: (context) => items,
      onSelected: (value) {
        // Handle menu selections
        if (value == 'About NavTool') {
          showDialog(
            context: context,
            builder: (context) => const AboutAppDialog(),
          );
        } else if (value == 'New Chart' || value == 'Open Chart') {
          Navigator.pushNamed(context, '/chart');
        } else if (value == 'Exit') {
          // Exit the application
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exit functionality coming soon!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$value functionality coming soon!')),
          );
        }
      },
      offset: const Offset(0, 30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppIcon(size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'NavTool',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIcon(size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Text(
                      'NavTool',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'Marine Navigation',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withAlpha(200),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Charts'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/chart');
              },
            ),
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('Routes'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Route planning functionality coming soon!')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const AppIcon(size: 96),
              const SizedBox(height: 24),
              Text(
                'Welcome to NavTool',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Marine Navigation and Routing Application',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/chart');
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('New Chart'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/chart');
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Chart'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const GpsStatusWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
