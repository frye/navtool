import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/about/about_dialog.dart';

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true),
              onSelected: () {
                // TODO: Implement new functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New file functionality not implemented yet')),
                );
              },
            ),
            PlatformMenuItem(
              label: 'Open',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
              onSelected: () {
                // TODO: Implement open functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Open file functionality not implemented yet')),
                );
              },
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Exit',
                  shortcut: SingleActivator(LogicalKeyboardKey.f4, alt: true),
                  onSelected: SystemNavigator.pop,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'About NavTool',
              onSelected: () {
                showDialog(
                  context: context,
                  builder: (context) => const AboutAppDialog(),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
