import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';

class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Introduction'),
      ),
      body: FutureBuilder<List<DocBlock>>(
        future: BrhcDatabase.instance.fetchIntroductionBlocks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final blocks = snapshot.data ?? [];
          if (blocks.isEmpty) {
            debugPrint('Introduction blocks missing or empty.');
            return const Center(
              child: Text('No introduction content found.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: blocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final block = blocks[index];
              final text =
                  block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
              final isHeading = block.blockType == 'intro_heading';
              final baseStyle = (isHeading
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: isHeading ? FontWeight.w700 : FontWeight.w400,
                    height: 1.5,
                  );
              return RichText(
                text: _renderInlineHtml(text, baseStyle),
              );
            },
          );
        },
      ),
    );
  }

  TextSpan _renderInlineHtml(String text, TextStyle? baseStyle) {
    final normalized = text
        .replaceAll(RegExp(r'<\\s*br\\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\\s*/?p\\s*>', caseSensitive: false), '\n\n');
    final spans = <TextSpan>[];
    var buffer = StringBuffer();
    var bold = false;
    var italic = false;

    void flush() {
      if (buffer.isEmpty) {
        return;
      }
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: baseStyle?.copyWith(
            fontWeight: bold ? FontWeight.w700 : baseStyle?.fontWeight,
            fontStyle: italic ? FontStyle.italic : baseStyle?.fontStyle,
          ),
        ),
      );
      buffer.clear();
    }

    final tagRegex = RegExp(r'<\\/?(strong|b|em|i)>', caseSensitive: false);
    var index = 0;
    for (final match in tagRegex.allMatches(normalized)) {
      buffer.write(normalized.substring(index, match.start));
      flush();
      final tag = match.group(1)?.toLowerCase() ?? '';
      final isClosing = normalized.substring(match.start + 1).startsWith('/');
      if (tag == 'strong' || tag == 'b') {
        bold = !isClosing;
      } else if (tag == 'em' || tag == 'i') {
        italic = !isClosing;
      }
      index = match.end;
    }
    buffer.write(normalized.substring(index));
    flush();

    return TextSpan(children: spans, style: baseStyle);
  }
}
