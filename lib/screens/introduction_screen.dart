import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/font_scale.dart';

class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    return FutureBuilder<List<DocBlock>>(
      future: _fetchIntroductionFallback(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final blocks = snapshot.data ?? [];
        if (blocks.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No introduction content found.')),
          );
        }
        return _buildScaffoldFromBlocks(context, theme, blocks, scale);
      },
    );
  }

  Future<List<DocBlock>> _fetchIntroductionFallback() async {
    final db = await BrhcDatabase.instance.database;
    final qRows = await db.rawQuery(
      'SELECT id FROM questions WHERE section_number = 0 AND chapter_number = 0 AND question_number = 0 LIMIT 1',
    );
    if (qRows.isEmpty) {
      return [];
    }
    final qId = qRows.first['id'] as int;
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM answer_blocks
      WHERE question_id = ?
      ORDER BY block_order ASC
      '''
      , [qId],
    );
    return rows.map((row) {
      return DocBlock(
        blockId: row['id'] as int? ?? 0,
        blockType: row['block_type'] as String? ?? 'text',
        rawText: row['content'] as String? ?? '',
        normalizedText: row['content'] as String? ?? '',
        tableJson: row['table_json'] as String?,
        imageBlobs: const [],
      );
    }).toList();
  }

  Widget _buildScaffoldFromBlocks(
    BuildContext context,
    ThemeData theme,
    List<DocBlock> blocks,
    double scale,
  ) {
    final titleBlock = blocks.first;
    final titleText = _stripMarkers(_stripMarkup(titleBlock.rawText)).trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleText.isEmpty ? 'Introduction' : titleText,
          style: _scaleStyle(theme.textTheme.titleMedium, scale)?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildIntroBody(
        theme,
        blocks.skip(1).toList(),
        titleText,
        scale,
      ),
    );
  }

  Widget _buildIntroBody(
    ThemeData theme,
    List<DocBlock> blocks,
    String titleText,
    double scale,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks.map((block) {
          final rawText = block.rawText;
          final normalizedText = block.normalizedText;
          final plainText = _stripMarkers(_stripMarkup(rawText)).trim();

          // --- INTRODUCTION RENDERING (NO QUESTION LOGIC) ---

          if (block.blockType == 'heading') {
            return Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 10),
              child: Text(
                plainText,
                textAlign: TextAlign.left,
                style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E2A25),
                ),
              ),
            );
          }

          if (block.blockType == 'poetry') {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                plainText,
                textAlign: TextAlign.center,
                style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            );
          }

          // Normal intro paragraphs
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              plainText,
              style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
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

  String _stripMarkers(String text) {
    return text.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '');
  }

  String _stripMarkup(String text) {
    return text.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('\n', ' ');
  }
}

double _fontScale(BuildContext context) {
  return FontScaleScope.maybeOf(context)?.scale ?? 1.0;
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}
