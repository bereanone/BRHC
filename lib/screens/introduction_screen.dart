import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';

class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<DocBlock>>(
      future: BrhcDatabase.instance.fetchIntroductionBlocks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final blocks = snapshot.data ?? [];
        if (blocks.isEmpty) {
          debugPrint('Introduction blocks missing or empty.');
          return const Scaffold(
            body: Center(child: Text('No introduction content found.')),
          );
        }
        final titleBlock = blocks.first;
        final titleText = _stripMarkers(_stripMarkup(titleBlock.rawText)).trim();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              titleText.isEmpty ? 'Introduction' : titleText,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
          ),
          body: _buildIntroBody(theme, blocks.skip(1).toList(), titleText),
        );
      },
    );
  }

  Widget _buildIntroBody(
    ThemeData theme,
    List<DocBlock> blocks,
    String titleText,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks.map((block) {
          final rawText = block.rawText;
          final normalizedText = block.normalizedText;
          final plainText = _stripMarkers(_stripMarkup(rawText)).trim();
          if (plainText.isEmpty || plainText == titleText) {
            return const SizedBox.shrink();
          }

          if (block.blockType == 'intro_paragraph' && _isAllBoldWrapper(normalizedText)) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _stripMarkers(_stripMarkup(normalizedText)).trim(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          if (block.blockType == 'intro_heading') {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                plainText,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              plainText,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: const Color(0xFF2E2A25),
              ),
              textAlign: TextAlign.left,
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isAllBoldWrapper(String text) {
    final trimmed = text.trim();
    if (!trimmed.toLowerCase().startsWith('<strong>') ||
        !trimmed.toLowerCase().endsWith('</strong>')) {
      return false;
    }
    final inner = trimmed
        .replaceFirst(RegExp(r'^<\s*strong\s*>', caseSensitive: false), '')
        .replaceFirst(RegExp(r'<\s*/\s*strong\s*>$', caseSensitive: false), '')
        .trim();
    return inner.isNotEmpty;
  }

  String _stripMarkers(String text) {
    return text.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '');
  }

  String _stripMarkup(String text) {
    return text.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('\n', ' ');
  }
}
