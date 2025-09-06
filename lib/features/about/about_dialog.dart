import 'package:flutter/material.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/version_text.dart';

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const AppIcon(size: 32),
          const SizedBox(width: 12),
          Text('About NavTool'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NavTool',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            'Marine Navigation and Routing Application',
            style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
          ),
          SizedBox(height: 8),
          VersionText(),
          SizedBox(height: 16),
          Text(
            'A comprehensive marine navigation solution designed for recreational and professional mariners.',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 12),
          Text(
            'Features:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            '• Electronic Chart Display (ECDIS)',
            style: TextStyle(fontSize: 12),
          ),
          Text(
            '• Route Planning and Optimization',
            style: TextStyle(fontSize: 12),
          ),
          Text('• Weather Routing (GRIB Data)', style: TextStyle(fontSize: 12)),
          Text(
            '• GPS Integration and Tracking',
            style: TextStyle(fontSize: 12),
          ),
          Text(
            '• Cross-platform Desktop Support',
            style: TextStyle(fontSize: 12),
          ),
          SizedBox(height: 12),
          Text(
            'Built with Flutter for optimal performance across desktop platforms.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
