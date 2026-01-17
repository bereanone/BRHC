import '../utils/font_scale.dart';
import 'package:flutter/material.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontScaleScope.maybeOf(context)?.scale ?? 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('How to Use'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        children: [
          Text(
            'Getting Started',
            style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap Enter to begin reading the book. You will be taken to the list of Sections, which organize the content by topic.',
            style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Finding Content',
            style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a Section, then select a Chapter within that Section. Scroll vertically to read the content. '
            'Questions appear in numbered order and are immediately followed by their answers.',
            style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Navigation Controls',
            style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'At the top of the reading screen, both the section title and chapter title are interactive. '
            'Tapping the section title opens the Section picker. '
            'Tapping the chapter title opens the Chapter list for the current Section.\n\n'
            'Below the titles are navigation buttons:\n'
            '<< moves to the previous Chapter.\n'
            '< moves to the previous Question.\n'
            '> moves to the next Question.\n'
            '>> moves to the next Chapter.\n\n'
            'If a Chapter has no questions, only Chapter navigation is active.',
            style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Reading Size',
            style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the gear icon on the entry screen to adjust the reading font size. This setting applies consistently across all reading, help, and information screens.',
            style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Return Home',
            style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the back arrow to move up one level at a time. From the Sections screen, the back arrow returns you to the entry screen.',
            style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}
