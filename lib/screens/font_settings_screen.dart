import 'package:flutter/material.dart';

import '../utils/font_scale.dart';

class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  static const _options = <_FontOption>[
    _FontOption('Small', 1.0),
    _FontOption('Medium', 1.2),
    _FontOption('Large', 1.4),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = FontScaleScope.of(context);
    final theme = Theme.of(context);
    TextStyle? scaleStyle(TextStyle? style, double scale) {
      final fontSize = style?.fontSize;
      if (fontSize == null) return style;
      return style!.copyWith(fontSize: fontSize * scale);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentScale = controller.scale;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Font Settings'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              Text(
                'Choose a text size',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in _options)
                RadioListTile<double>(
                  value: option.scale,
                  groupValue: currentScale,
                  title: Text(option.label),
                  onChanged: (value) {
                    if (value == null) return;
                    controller.setScale(value);
                  },
                ),
              const Divider(height: 28),
              Text(
                'Preview',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Behold, I make all things new.',
                style: scaleStyle(
                  theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                  currentScale,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '— Revelation 21:5 (KJV)',
                style: scaleStyle(
                  theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                  currentScale,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FontOption {
  final String label;
  final double scale;

  const _FontOption(this.label, this.scale);
}
