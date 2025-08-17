import 'package:flutter/material.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/version_text.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const AppIcon(size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'NavTool',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Marine Navigation and Routing Application',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  VersionText(
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Description',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'A comprehensive marine navigation solution designed for recreational and professional mariners. Built with Flutter for optimal cross-platform performance.',
            ),
            const SizedBox(height: 24),
            Text(
              'Key Features',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('• Electronic Chart Display and Information System (ECDIS)'),
            const Text('• Advanced Route Planning and Optimization'),
            const Text('• Weather Routing with GRIB Data Integration'),
            const Text('• Real-time GPS Position and Tracking'),
            const Text('• Cross-platform Desktop Support'),
            const Text('• Responsive UI for Various Screen Sizes'),
            const SizedBox(height: 24),
            Text(
              'Navigation Standards',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('• S-57 Electronic Navigational Charts'),
            const Text('• NMEA 0183/2000 GPS Integration'),
            const Text('• International Maritime Organization (IMO) Compliance'),
          ],
        ),
      ),
    );
  }
}
