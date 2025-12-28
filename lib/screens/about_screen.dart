import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: ListView(
          children: [
            Text(
              'Biblical Heritage: Bible Readings for the Home (1914 Edition)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bible Readings for the Home was originally authored and published in 1914. '
              'Biblical Heritage makes no claim of authorship. Our sole role is the digital '
              'presentation of this historic work in app form, preserving its original '
              'structure and wording in order to continue its legacy for modern readers.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Credit: original authors and compilers of the 1914 publication. Biblical '
              'Heritage serves as the digital publisher and curator of this app edition.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
