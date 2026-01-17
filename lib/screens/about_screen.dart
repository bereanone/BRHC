import 'package:flutter/material.dart';
import '../utils/font_scale.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontScaleScope.maybeOf(context)?.scale ?? 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: ListView(
          children: [
            Center(
              child: Image.asset(
                'assets/Images/brhc_1914_cover.jpg',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Biblical Heritage: Bible Readings for the Home (1914 Edition)',
              style: theme.textTheme.titleMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  )
                  .copyWith(
                    fontSize: theme.textTheme.titleMedium!.fontSize! * scale,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bible Readings for the Home was originally authored and published in 1914. '
              'Biblical Heritage makes no claim of authorship. Our sole role is the digital '
              'presentation of this historic work in app form, preserving its original '
              'structure and wording in order to continue its legacy for modern readers. '
              'Credit is due to the original authors and compilers of the 1914 publication, '
              'with Biblical Heritage serving as the digital publisher and curator of this app edition.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(height: 1.5)
                  .copyWith(
                    fontSize: theme.textTheme.bodyMedium!.fontSize! * scale,
                  ),
            ),
            const SizedBox(height: 20),
            Text(
              'The original 1914 title of this work was '
              '‘Bible Readings for the Home Circle.’ '
              'For app store and device display limitations, '
              'the title has been shortened to '
              '‘Bible Readings for the Home’ while preserving '
              'the complete original content without alteration.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(height: 1.5)
                  .copyWith(
                    fontSize: theme.textTheme.bodyMedium!.fontSize! * scale,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'This work was published in 1914 and is in the public domain.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(height: 1.5)
                  .copyWith(
                    fontSize: theme.textTheme.bodyMedium!.fontSize! * scale,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
