import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:brhc_app/data/brhc_database.dart';
import 'package:brhc_app/utils/font_scale.dart';

class ChapterBlocksView extends StatefulWidget {
  final int chapterId;
  final Map<int, GlobalKey>? questionKeys;
  final ScrollController? scrollController;

  const ChapterBlocksView({
    super.key,
    required this.chapterId,
    this.questionKeys,
    this.scrollController,
  });

  @override
  State<ChapterBlocksView> createState() => _ChapterBlocksViewState();
}

class _ChapterBlocksViewState extends State<ChapterBlocksView> {
  late Future<List<Map<String, Object?>>> _blocksFuture;

  @override
  void initState() {
    super.initState();
    _blocksFuture = _fetchBlocks();
  }

  @override
  void didUpdateWidget(covariant ChapterBlocksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId) {
      _blocksFuture = _fetchBlocks();
    }
  }

  Future<List<Map<String, Object?>>> _fetchBlocks() async {
    final db = await BrhcDatabase.instance.database;
    // Always load blocks directly by chapter_id, including chapter_id = 0 (Introduction).
    // Do NOT infer/borrow introduction content from other chapters.
    return db.rawQuery(
      '''
      SELECT
        ab.block_order,
        ab.block_type,
        ab.content,
        ab.image_ref,
        ab.question_id,
        q.question_number,
        q.question_text
      FROM answer_blocks ab
      LEFT JOIN questions q ON q.id = ab.question_id
      WHERE ab.chapter_id = ?
      ORDER BY ab.block_order ASC
      ''',
      [widget.chapterId],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _blocksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final blocks = snapshot.data ?? const <Map<String, Object?>>[];
        if (blocks.isEmpty) {
          // Make the empty-state message accurate for both Introduction and normal chapters.
          return Center(
            child: Text(
              widget.chapterId == 0
                  ? 'Introduction blocks not found (chapter_id = 0).'
                  : 'No content found.',
              textAlign: TextAlign.center,
            ),
          );
        }

        // FIX: intro title handling
        final bool isIntro = widget.chapterId == 0;
        String? introTitle;
        final Set<int> skipIndexes = {};

        if (isIntro && blocks.isNotEmpty && blocks[0]['block_type'] == 'heading') {
          introTitle =
              _inlineHtmlToPlainText((blocks[0]['content'] as String?) ?? '');

          for (int i = 0; i < blocks.length; i++) {
            if (blocks[i]['block_type'] == 'heading' &&
                _inlineHtmlToPlainText((blocks[i]['content'] as String?) ?? '') ==
                    introTitle) {
              skipIndexes.add(i);
            } else {
              break;
            }
          }
        }

        final scale = FontScaleScope.maybeOf(context)?.scale ?? 1.0;
        final displayItems = <Map<String, Object?>>[];
        if (introTitle != null) {
          displayItems.add({
            "kind": "intro_title",
            "text": introTitle!,
          });
        }
        int? lastQuestionId;
        var insertedResponsiveLabel = false;
        String? previousBlockType;
        for (var i = 0; i < blocks.length; i++) {
          if (skipIndexes.contains(i)) {
            continue;
          }
          final block = blocks[i];
          final qid = block['question_id'] as int?;
          if (qid != null && qid != lastQuestionId) {
            displayItems.add({
              "kind": "question",
              "question_id": qid,
              "question_number": block['question_number'],
              "question_text": block['question_text'],
            });
            lastQuestionId = qid;
          }
          final blockType = (block['block_type'] as String?) ?? '';
          if (!insertedResponsiveLabel &&
              blockType == 'responsive' &&
              previousBlockType == 'heading') {
            displayItems.add({
              "kind": "responsive_label",
            });
            insertedResponsiveLabel = true;
          }
          displayItems.add({
            "kind": "block",
            "block": block,
          });
          previousBlockType = blockType;
        }

        Widget buildItem(Map<String, Object?> item) {
          final kind = item['kind'] as String? ?? '';
          if (kind == 'intro_title') {
            return Padding(
              padding: const EdgeInsets.only(top: 0, bottom: 12),
              child: Text(
                item['text'] as String? ?? '',
                textAlign: TextAlign.center,
                style: _scaleStyle(
                  Theme.of(context).textTheme.titleLarge,
                  scale,
                )?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
            );
          }
          if (kind == 'responsive_label') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '(A RESPONSIVE READING)',
                textAlign: TextAlign.center,
                style: _scaleStyle(
                  Theme.of(context).textTheme.bodySmall,
                  scale,
                )?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          if (kind == 'question') {
            final number = item['question_number']?.toString() ?? '';
            final text = item['question_text']?.toString() ?? '';
            final questionId = item['question_id'] as int?;
            final questionStyle = _scaleStyle(
              Theme.of(context).textTheme.bodyMedium,
              scale,
            )?.copyWith(
              color: const Color(0xFF0000FF),
              fontWeight: FontWeight.bold,
              height: 1.4,
            );
            final questionKey =
                questionId == null ? null : widget.questionKeys?[questionId];
            final questionWidget = Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: RichText(
                text: TextSpan(
                  style: questionStyle,
                  children: [
                    if (number.isNotEmpty) TextSpan(text: '$number. '),
                    TextSpan(text: text),
                  ],
                ),
              ),
            );
            if (questionKey == null) {
              return questionWidget;
            }
            return KeyedSubtree(
              key: questionKey,
              child: questionWidget,
            );
          }

          final block = item['block'] as Map<String, Object?>;
          final blockType = (block['block_type'] as String?) ?? '';
          final rawContent = (block['content'] as String?) ?? '';
          final content = _inlineHtmlToPlainText(rawContent);
          final imageRef = block['image_ref'] as String?;

          switch (blockType) {
            case 'heading':
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  content,
                  textAlign: TextAlign.start,
                  style: _scaleStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    scale,
                  )?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
              );

            case 'poetry':
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  // Poetry should preserve line breaks.
                  rawContent
                      .replaceAll('<br>', '\n')
                      .replaceAll('<br/>', '\n')
                      .replaceAll('<br />', '\n')
                      .split('\n')
                      .map(_inlineHtmlToPlainText)
                      .join('\n'),
                  textAlign: TextAlign.center,
                  style: _scaleStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    scale,
                  )?.copyWith(height: 1.5),
                ),
              );

            case 'note':
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.5),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withOpacity(0.6),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  content,
                  textAlign: TextAlign.start,
                  style: _scaleStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    scale,
                  )?.copyWith(
                    height: 1.5,
                  ),
                ),
              );

            case 'responsive':
              if (content.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              final lines = rawContent
                  .replaceAll('<br>', '\n')
                  .replaceAll('<br/>', '\n')
                  .replaceAll('<br />', '\n')
                  .split('\n')
                  .map(_inlineHtmlToPlainText)
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              if (lines.isNotEmpty &&
                  (lines.first.toUpperCase().contains('RESPONSIVE READING') ||
                      lines.first.startsWith('[R]'))) {
                lines.removeAt(0);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding:
                            EdgeInsets.only(left: i.isOdd ? 12.0 : 0.0),
                        child: Text(
                          lines[i],
                          textAlign: TextAlign.start,
                          style: _scaleStyle(
                            Theme.of(context).textTheme.bodyMedium,
                            scale,
                          )?.copyWith(
                            height: 1.6,
                            fontWeight:
                                i.isOdd ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                  ],
                ),
              );

            case 'image':
              if (imageRef == null || imageRef.trim().isEmpty) {
                return const _MissingImageBox();
              }
              return _ImageByFilename(filename: imageRef.trim());

            case 'intro':
            case 'answer':
            default:
              final dotSplit = _parseDotLeaderRow(rawContent);
              if (dotSplit != null) {
                final left = dotSplit.left;
                final right = dotSplit.right;
                final style = _scaleStyle(
                  Theme.of(context).textTheme.bodyMedium,
                  scale,
                )?.copyWith(height: 1.5);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: Text(left, style: style)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomPaint(
                            painter: _DotLeaderPainter(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.35),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            right,
                            style: style,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  content,
                  textAlign: TextAlign.start,
                  style: _scaleStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    scale,
                  )?.copyWith(
                    height: 1.5,
                  ),
                ),
              );
          }
        }

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          children: displayItems.map(buildItem).toList(),
        );
      },
    );
  }
}

class _ImageByFilename extends StatelessWidget {
  final String filename;

  const _ImageByFilename({required this.filename});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: BrhcDatabase.instance.fetchImageBlobByFilename(filename),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 12);
        }
        final blob = snapshot.data;
        if (blob == null) {
          return const _MissingImageBox();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Image.memory(blob, fit: BoxFit.fitWidth),
        );
      },
    );
  }
}

class _MissingImageBox extends StatelessWidget {
  const _MissingImageBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        color: Colors.grey.shade200,
      ),
      alignment: Alignment.center,
      child: const Text('Image missing'),
    );
  }
}

class _DotLeaderPainter extends CustomPainter {
  final Color color;

  const _DotLeaderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    const dotRadius = 1.0;
    const gap = 4.0;
    var x = 0.0;
    final y = size.height - dotRadius;
    while (x < size.width) {
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
      x += gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DotLeaderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DotLeaderSplit {
  final String left;
  final String right;

  const _DotLeaderSplit(this.left, this.right);
}

_DotLeaderSplit? _parseDotLeaderRow(String content) {
  if (content.contains('[L]') && content.contains('[R]')) {
    final leftMatches = RegExp(r'\[L\](.*?)\[/L\]', dotAll: true)
        .allMatches(content)
        .map((m) => m.group(1) ?? '')
        .join();
    final rightMatches = RegExp(r'\[R\](.*?)\[/R\]', dotAll: true)
        .allMatches(content)
        .map((m) => m.group(1) ?? '')
        .join();
    final left = _inlineHtmlToPlainText(
      leftMatches.replaceAll(RegExp(r'\.+\s*$'), ''),
    ).trim();
    final right = _inlineHtmlToPlainText(rightMatches).trim();
    if (left.isNotEmpty && right.isNotEmpty) {
      return _DotLeaderSplit(left, right);
    }
  }
  final plain = _inlineHtmlToPlainText(content).trim();
  if (plain.contains('\n')) return null;
  final match = RegExp(r'^(.+?)\.\s+([1-3]?\s*[A-Za-z].*\d.*)$')
      .firstMatch(plain);
  if (match == null) return null;
  final left = match.group(1)!.trim();
  final right = match.group(2)!.trim();
  if (left.isEmpty || right.isEmpty) {
    return null;
  }
  return _DotLeaderSplit(left, right);
}

/// Very small inline HTML-to-text helper for BRHC content.
///
/// - Strips tags like <strong>, <i>, <b>, etc.
/// - Converts common <br> variants to spaces (poetry path preserves separately).
/// - Decodes a few HTML entities.
String _inlineHtmlToPlainText(String input) {
  if (input.isEmpty) return '';

  var s = input;

  // Normalize line breaks in non-poetry text.
  s = s
      .replaceAll('<br>', ' ')
      .replaceAll('<br/>', ' ')
      .replaceAll('<br />', ' ');

  // Remove all remaining tags.
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // Decode a minimal set of entities and numeric entities.
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  // Decode numeric entities like &#34; and &#x2014;.
  s = s.replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (m) {
    final raw = m.group(1) ?? '';
    int? code;
    if (raw.startsWith('x') || raw.startsWith('X')) {
      code = int.tryParse(raw.substring(1), radix: 16);
    } else {
      code = int.tryParse(raw, radix: 10);
    }
    if (code == null) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });

  s = s.replaceAll('[I]', '');

  // Collapse whitespace.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  return utf8.decode(utf8.encode(s));
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}
