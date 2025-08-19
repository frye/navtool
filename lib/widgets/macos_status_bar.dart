import 'package:flutter/material.dart';

/// A simple status bar widget for macOS applications
/// Displays status text at the bottom of the window
class MacosStatusBar extends StatelessWidget {
  final String statusText;

  const MacosStatusBar({
    super.key,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(50),
          ),
        ),
      ),
      child: Text(
        statusText,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}