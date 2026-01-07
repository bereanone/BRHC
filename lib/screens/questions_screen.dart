import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import 'chapters_screen.dart';
import 'sections_screen.dart';
import '../widgets/fade_route.dart';

class QuestionsScreen extends StatefulWidget {
  final String sectionTitle;
  final String chapterTitle;
  final String displayTitle;
  final String rawChapterTitle;
  final String displaySectionTitle;
  final int? initialBlockId;

  const QuestionsScreen({
    super.key,
    required this.sectionTitle,
    required this.chapterTitle,
    required this.displayTitle,
    required this.rawChapterTitle,
    required this.displaySectionTitle,
    this.initialBlockId,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _blockKeys = {};
  final Set<int> _questionBlockIds = {};
  int? _activeBlockId;
  bool _didAutoScroll = false;
  List<_QuestionAnchor> _allAnchors = const [];
  Map<int, _QuestionAnchor> _anchorByBlock = const {};
  List<_ChapterAnchor> _chapterAnchors = const [];
  List<_SectionAnchor> _sectionAnchors = const [];

  late final Future<_ChapterScreenData> _dataFuture = _loadData();

  Future<_ChapterScreenData> _loadData() async {
    final db = BrhcDatabase.instance;
    final results = await Future.wait([
      db.fetchChapterBlocks(
        sectionTitle: widget.sectionTitle,
        chapterTitle: widget.chapterTitle,
      ),
      db.fetchQuestionIndex(
        sectionTitle: widget.sectionTitle,
        chapterTitle: widget.chapterTitle,
      ),
      db.fetchAllQuestionAnchors(),
    ]);

    return _ChapterScreenData(
      blocks: results[0] as List<DocBlock>,
      questions: results[1] as List<QuestionNavItem>,
      anchors: results[2] as List<Map<String, Object?>>,
    );
  }

  @override
  void initState() {
    super.initState();
    _activeBlockId = widget.initialBlockId;
    _scrollController.addListener(_handleScroll);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_ChapterScreenData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            final blocks = data?.blocks ?? [];
            final questions = data?.questions ?? [];
            final anchors = data?.anchors ?? [];
            final questionMap = {
              for (final q in questions) q.blockId: q,
            };
            _questionBlockIds
              ..clear()
              ..addAll(questionMap.keys);
            _blockKeys.clear();
            _initializeAnchors(anchors);
            final headerTitle = _buildChapterHeader(widget.rawChapterTitle);
            final activeBlockId = _activeBlockId ??
                (questions.isNotEmpty ? questions.first.blockId : null);
            final activeAnchor =
                activeBlockId == null ? null : _anchorByBlock[activeBlockId];

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_didAutoScroll) {
                return;
              }
              final target = _initialQuestionBlockId();
              if (target != null) {
                _didAutoScroll = true;
                _scrollToBlock(target);
              }
            });

            return Column(
              children: [
                _ChapterHeader(
                  sectionTitle: _displaySectionTitle(
                    (activeAnchor?.sectionTitle ?? widget.sectionTitle),
                  ),
                  chapterTitle: _buildChapterHeader(
                    (activeAnchor?.chapterTitle ?? widget.rawChapterTitle),
                  ),
                  onSectionTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SectionsScreen(),
                      ),
                    );
                  },
                ),
                if (activeAnchor != null)
                  _QuestionNavBar(
                    currentNumber: activeAnchor.questionNumber,
                    onPrevQuestion: () => _jumpToQuestion(previous: true),
                    onNextQuestion: () => _jumpToQuestion(previous: false),
                    onPrevChapter: () => _jumpToChapter(previous: true),
                    onNextChapter: () => _jumpToChapter(previous: false),
                  ),
                Expanded(
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction == ScrollDirection.idle) {
                        _updateActiveBlockFromScroll();
                      }
                      return false;
                    },
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      children: [
                        for (var i = 0; i < blocks.length; i++) ...[
                          _buildRenderItem(blocks[i], questionMap),
                          if (i != blocks.length - 1) const Divider(height: 24),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _navigateToChapter(ChapterEntry chapter, {required bool fromLeft}) {
    final beginOffset = fromLeft ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => QuestionsScreen(
          sectionTitle: chapter.rawSectionTitle,
          chapterTitle: chapter.rawChapterTitle,
          displayTitle: chapter.chapterTitle,
          rawChapterTitle: chapter.rawChapterTitle,
          displaySectionTitle: _displaySectionTitle(chapter.rawSectionTitle),
          initialBlockId: chapter.firstBlockId,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween<Offset>(begin: beginOffset, end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeInOut));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  void _scrollToBlock(int blockId) {
    void attemptScroll(int remaining) {
      final key = _blockKeys[blockId];
      final context = key?.currentContext;
      if (context == null) {
        if (remaining > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            attemptScroll(remaining - 1);
          });
        }
        return;
      }
      if (_activeBlockId != blockId) {
        setState(() {
          _activeBlockId = blockId;
        });
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }

    attemptScroll(6);
  }

  void _handleScroll() {
    // Keep for future scroll anchoring enhancements.
  }

  void _updateActiveBlockFromScroll() {
    for (final entry in _blockKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) {
        continue;
      }
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) {
        continue;
      }
      final offset = box.localToGlobal(Offset.zero).dy;
      if (offset >= 0 && _questionBlockIds.contains(entry.key)) {
        if (_activeBlockId != entry.key) {
          setState(() {
            _activeBlockId = entry.key;
          });
        }
        break;
      }
    }
  }

  Widget _buildRenderItem(
    DocBlock block,
    Map<int, QuestionNavItem> questionMap,
  ) {
    final key = _blockKeys.putIfAbsent(
      block.blockId,
      () => GlobalKey(),
    );
    final question = questionMap[block.blockId];
    return Container(
      key: key,
      child: _BlockRenderer(
        block: block,
        question: question,
      ),
    );
  }

  String _buildChapterHeader(String rawTitle) {
    final parsed = TitleFormatter.parseChapterTitle(rawTitle);
    if (parsed.number == null || parsed.number!.isEmpty) {
      return parsed.title.trim();
    }
    return 'Chapter ${parsed.number}. ${parsed.title}';
  }

  String _displaySectionTitle(String rawTitle) {
    final parsed = TitleFormatter.parseSectionTitle(rawTitle);
    if (parsed.number == null || parsed.number!.isEmpty) {
      return parsed.title;
    }
    return '${parsed.number}. ${parsed.title}';
  }

  void _initializeAnchors(List<Map<String, Object?>> rows) {
    if (_allAnchors.isNotEmpty || rows.isEmpty) {
      return;
    }
    final anchors = <_QuestionAnchor>[];
    for (final row in rows) {
      final blockId = row['block_id'] as int?;
      final questionNumber = row['question_number'] as int?;
      final sectionTitle = row['section_title'] as String?;
      final chapterTitle = row['chapter_title'] as String?;
      if (blockId == null ||
          questionNumber == null ||
          sectionTitle == null ||
          chapterTitle == null) {
        continue;
      }
      anchors.add(
        _QuestionAnchor(
          blockId: blockId,
          questionNumber: questionNumber,
          sectionTitle: sectionTitle,
          chapterTitle: chapterTitle,
        ),
      );
    }
    _allAnchors = anchors;
    _anchorByBlock = {for (final a in anchors) a.blockId: a};
    _chapterAnchors = _buildChapterAnchors(anchors);
    _sectionAnchors = _buildSectionAnchors(anchors);
  }

  int? _initialQuestionBlockId() {
    if (_allAnchors.isEmpty) {
      return null;
    }
    final match = _allAnchors.firstWhere(
      (a) => a.chapterTitle == widget.chapterTitle,
      orElse: () => _allAnchors.first,
    );
    return match.blockId;
  }

  void _jumpToQuestion({required bool previous}) {
    final index = _currentAnchorIndex();
    if (index == null) {
      return;
    }
    final nextIndex = previous ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= _allAnchors.length) {
      return;
    }
    _scrollToBlock(_allAnchors[nextIndex].blockId);
  }

  void _jumpToChapter({required bool previous}) {
    final current = _currentAnchorIndex();
    if (current == null || _chapterAnchors.isEmpty) {
      return;
    }
    final currentChapterIndex =
        _chapterAnchors.lastIndexWhere((c) => c.startIndex <= current);
    if (currentChapterIndex == -1) {
      return;
    }
    final targetIndex =
        previous ? currentChapterIndex - 1 : currentChapterIndex + 1;
    if (targetIndex < 0 || targetIndex >= _chapterAnchors.length) {
      return;
    }
    final anchor = _allAnchors[_chapterAnchors[targetIndex].startIndex];
    _navigateToAnchor(anchor, fromLeft: previous);
  }

  void _jumpToSection({required bool previous}) {
    final current = _currentAnchorIndex();
    if (current == null || _sectionAnchors.isEmpty) {
      return;
    }
    final currentSectionIndex =
        _sectionAnchors.lastIndexWhere((s) => s.startIndex <= current);
    if (currentSectionIndex == -1) {
      return;
    }
    final targetIndex =
        previous ? currentSectionIndex - 1 : currentSectionIndex + 1;
    if (targetIndex < 0 || targetIndex >= _sectionAnchors.length) {
      return;
    }
    final anchor = _allAnchors[_sectionAnchors[targetIndex].startIndex];
    _navigateToAnchor(anchor, fromLeft: previous);
  }

  int? _currentAnchorIndex() {
    if (_allAnchors.isEmpty) {
      return null;
    }
    final current = _activeBlockId ?? widget.initialBlockId;
    if (current == null) {
      return null;
    }
    final index = _allAnchors.lastIndexWhere((a) => a.blockId <= current);
    return index == -1 ? null : index;
  }

  List<_ChapterAnchor> _buildChapterAnchors(List<_QuestionAnchor> anchors) {
    final items = <_ChapterAnchor>[];
    String? current;
    for (var i = 0; i < anchors.length; i++) {
      if (anchors[i].chapterTitle != current) {
        current = anchors[i].chapterTitle;
        items.add(_ChapterAnchor(chapterTitle: current, startIndex: i));
      }
    }
    return items;
  }

  List<_SectionAnchor> _buildSectionAnchors(List<_QuestionAnchor> anchors) {
    final items = <_SectionAnchor>[];
    String? current;
    for (var i = 0; i < anchors.length; i++) {
      if (anchors[i].sectionTitle != current) {
        current = anchors[i].sectionTitle;
        items.add(_SectionAnchor(sectionTitle: current, startIndex: i));
      }
    }
    return items;
  }

  void _navigateToAnchor(_QuestionAnchor anchor, {required bool fromLeft}) {
    final entry = ChapterEntry(
      sectionTitle: TitleFormatter.parseSectionTitle(anchor.sectionTitle).title,
      chapterTitle: TitleFormatter.parseChapterTitle(anchor.chapterTitle).title,
      rawSectionTitle: anchor.sectionTitle,
      rawChapterTitle: anchor.chapterTitle,
      firstBlockId: anchor.blockId,
    );
    _navigateToChapter(entry, fromLeft: fromLeft);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChapterScreenData {
  final List<DocBlock> blocks;
  final List<QuestionNavItem> questions;
  final List<Map<String, Object?>> anchors;

  const _ChapterScreenData({
    required this.blocks,
    required this.questions,
    required this.anchors,
  });
}

class _QuestionAnchor {
  final int blockId;
  final int questionNumber;
  final String sectionTitle;
  final String chapterTitle;

  const _QuestionAnchor({
    required this.blockId,
    required this.questionNumber,
    required this.sectionTitle,
    required this.chapterTitle,
  });
}

class _ChapterAnchor {
  final String chapterTitle;
  final int startIndex;

  const _ChapterAnchor({required this.chapterTitle, required this.startIndex});
}

class _SectionAnchor {
  final String sectionTitle;
  final int startIndex;

  const _SectionAnchor({required this.sectionTitle, required this.startIndex});
}

class _BlockRenderer extends StatelessWidget {
  final DocBlock block;
  final QuestionNavItem? question;

  const _BlockRenderer({
    required this.block,
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    switch (block.blockType) {
      case 'section':
      case 'chapter':
        return block.imageBlobs.isEmpty
            ? const SizedBox.shrink()
            : _BlockImages(block.imageBlobs);
      case 'question':
        return _QuestionBlock(block: block, question: question);
      case 'note':
        return _NoteBlock(block: block);
      case 'note_heading':
        return _NoteBlock(block: block, isHeading: true);
      case 'title_ref':
        return _TitleRefBlock(block: block);
      case 'poetry':
        return _PoetryBlock(block: block);
      case 'table':
        return _TableBlock(block: block);
      case 'reading':
        return _ReadingBlock(block: block);
      case 'image':
        final filename = _extractPicFilename(
          block.rawText.isNotEmpty ? block.rawText : block.normalizedText,
        );
        if (filename == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: _InlineImageByFilename(filename: filename),
        );
      case 'text':
      default:
        return _TextBlock(block: block);
    }
  }
}

class _QuestionBlock extends StatelessWidget {
  final DocBlock block;
  final QuestionNavItem? question;

  const _QuestionBlock({required this.block, required this.question});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = question?.questionNumber;
    final rawText =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(
      !_containsMarkup(rawText) && _containsMarkup(block.normalizedText)
          ? block.normalizedText
          : rawText,
    );
    final baseStyle = theme.textTheme.bodyMedium;
    final width = MediaQuery.of(context).size.width;
    final fontSize = (baseStyle?.fontSize ?? 16) -
        (width < 340 ? 3 : width < 380 ? 2 : 0);
    final hasHtml = _containsMarkup(text);
    final questionStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: const Color(0xFF0000FF),
      fontSize: fontSize,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hasHtml
            ? RichText(
                text: TextSpan(
                  children: [
                    if (number != null)
                      TextSpan(text: '$number. ', style: questionStyle),
                    _renderInlineHtml(
                      text,
                      questionStyle,
                    ),
                  ],
                ),
              )
            : Text(
                number == null ? text : '$number. $text',
                softWrap: true,
                style: questionStyle,
              ),
        _BlockImages(block.imageBlobs),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  final DocBlock block;

  const _TextBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawText =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(
      !_containsMarkup(rawText) && _containsMarkup(block.normalizedText)
          ? block.normalizedText
          : rawText,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      color: const Color(0xFF1F1B17),
    );
    final widgets = _buildInlineWidgets(context, text, style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widgets,
        _BlockImages(block.imageBlobs),
      ],
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final DocBlock block;
  final bool isHeading;

  const _NoteBlock({required this.block, this.isHeading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawText =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(
      !_containsMarkup(rawText) && _containsMarkup(block.normalizedText)
          ? block.normalizedText
          : rawText,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      fontWeight: isHeading ? FontWeight.w700 : FontWeight.w400,
      color: const Color(0xFF1F1B17),
    );
    final widgets = _buildInlineWidgets(context, text, style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface.withOpacity(0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...widgets,
          _BlockImages(block.imageBlobs),
        ],
      ),
    );
  }
}

class _PoetryBlock extends StatelessWidget {
  final DocBlock block;

  const _PoetryBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawText =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(
      !_containsMarkup(rawText) && _containsMarkup(block.normalizedText)
          ? block.normalizedText
          : rawText,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      height: 1.5,
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) - 1,
      color: const Color(0xFF1F1B17),
    );
    final widgets = _buildInlineWidgets(context, text, style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widgets.map(
          (widget) => Align(
            alignment: Alignment.center,
            child: widget,
          ),
        ),
        _BlockImages(block.imageBlobs),
      ],
    );
  }
}

class _ReadingBlock extends StatelessWidget {
  final DocBlock block;

  const _ReadingBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawText =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(
      !_containsMarkup(rawText) && _containsMarkup(block.normalizedText)
          ? block.normalizedText
          : rawText,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      color: const Color(0xFF1F1B17),
    );
    final widgets = _buildInlineWidgets(context, text, style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...widgets,
          _BlockImages(block.imageBlobs),
        ],
      ),
    );
  }
}

class _TableBlock extends StatelessWidget {
  final DocBlock block;

  const _TableBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _parseTable(block.tableJson);
    if (rows.isEmpty) {
      return _TextBlock(block: block);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          border: TableBorder.all(
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows
              .map(
                (row) => TableRow(
                  children: row
                      .map(
                        (cell) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            cell,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                              color: const Color(0xFF1F1B17),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
        _BlockImages(block.imageBlobs),
      ],
    );
  }

  List<List<String>> _parseTable(String? tableJson) {
    if (tableJson == null || tableJson.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(tableJson);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .map<List<String>>((row) {
            if (row is! List) {
              return [];
            }
            return row
                .map<String>((cell) {
                  if (cell is List) {
                    return cell.join('\n').trim();
                  }
                  return cell?.toString() ?? '';
                })
                .toList();
          })
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class _TitleRefBlock extends StatelessWidget {
  final DocBlock block;

  const _TitleRefBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String left = '';
    String right = '';
    if (block.tableJson != null && block.tableJson!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(block.tableJson!);
        if (decoded is Map) {
          left = decoded['left']?.toString() ?? '';
          right = decoded['right']?.toString() ?? '';
        }
      } catch (_) {}
    }
    if (left.isEmpty && right.isEmpty) {
      final text = block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
      final parts = text.split('\n');
      if (parts.isNotEmpty) {
        left = parts.first;
        right = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
      }
    }
    left = _stripMarkersForDisplay(left);
    right = _stripMarkersForDisplay(right);
    final leftHasHtml = _containsMarkup(left);
    final rightHasHtml = _containsMarkup(right);
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: leftHasHtml
                    ? RichText(text: _renderInlineHtml(left, style))
                    : Text(left, style: style),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomPaint(
                  painter: _DotLeaderPainter(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                  child: const SizedBox(height: 16),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: rightHasHtml
                    ? RichText(text: _renderInlineHtml(right, style))
                    : Text(
                        right,
                        style: style,
                        textAlign: TextAlign.right,
                      ),
              ),
            ],
          );
        },
      ),
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
    final y = size.height / 2;
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

class _InlinePiece {
  final String? text;
  final String? filename;

  const _InlinePiece.text(this.text) : filename = null;
  const _InlinePiece.image(this.filename) : text = null;
}

final RegExp _picTagRegex =
    RegExp(r'\[Pic:\s*([^\]]+?)\s*\]', caseSensitive: false);
final Set<String> _missingPicLog = {};

String? _extractPicFilename(String text) {
  final match = _picTagRegex.firstMatch(text);
  return match?.group(1)?.trim();
}

List<_InlinePiece> _splitTextByPicTags(String text) {
  final matches = _picTagRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return [_InlinePiece.text(text)];
  }
  final pieces = <_InlinePiece>[];
  var index = 0;
  for (final match in matches) {
    if (match.start > index) {
      pieces.add(_InlinePiece.text(text.substring(index, match.start)));
    }
    final filename = match.group(1)?.trim();
    if (filename != null && filename.isNotEmpty) {
      pieces.add(_InlinePiece.image(filename));
    }
    index = match.end;
  }
  if (index < text.length) {
    pieces.add(_InlinePiece.text(text.substring(index)));
  }
  return pieces;
}

List<Widget> _buildInlineWidgets(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final pieces = _splitTextByPicTags(text);
  final widgets = <Widget>[];
  for (final piece in pieces) {
    if (piece.text != null && piece.text!.isNotEmpty) {
      final segment = piece.text!;
      if (_containsMarkup(segment)) {
        widgets.add(RichText(text: _renderInlineHtml(segment, style)));
      } else {
        widgets.add(Text(segment, softWrap: true, style: style));
      }
    } else if (piece.filename != null && piece.filename!.isNotEmpty) {
      widgets.add(_InlineImageByFilename(filename: piece.filename!));
    }
  }
  if (widgets.isEmpty) {
    widgets.add(Text(text, softWrap: true, style: style));
  }
  return widgets;
}

class _InlineImageByFilename extends StatelessWidget {
  final String filename;

  const _InlineImageByFilename({required this.filename});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: BrhcDatabase.instance.fetchImageBlobByFilename(filename),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 12);
        }
        final blob = snapshot.data;
        if (blob == null) {
          if (_missingPicLog.add(filename)) {
            debugPrint('Missing image for [Pic]: $filename');
          }
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final image = Image.memory(
              blob,
              width: constraints.maxWidth,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return Text(
                  'Image decode failed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                );
              },
            );
            if (constraints.maxWidth < 600) {
              return ClipRect(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: image,
                ),
              );
            }
            return image;
          },
        );
      },
    );
  }
}

bool _containsMarkup(String text) {
  return RegExp(r'<\s*/?\s*(strong|em|b|i)\s*>', caseSensitive: false)
      .hasMatch(text);
}

String _stripMarkersForDisplay(String text) {
  return text.replaceFirst(
    RegExp(
      r'^\s*((?:<\s*(?:strong|em)\s*>\s*)?)\[(S|Ch|N|P|R|T|I)\]\s*',
      caseSensitive: false,
    ),
    r'$1',
  );
}

TextSpan _renderInlineHtml(String text, TextStyle? baseStyle) {
  final normalized = text
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*/?p\s*>', caseSensitive: false), '\n\n');
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

  final tagRegex = RegExp(r'<\/?(strong|b|em|i)>', caseSensitive: false);
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

class _BlockImages extends StatelessWidget {
  final List<Uint8List> images;

  const _BlockImages(this.images);

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: images
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Builder(
                              builder: (context) {
                                final image = Image.memory(
                                  entry.value,
                                  width: constraints.maxWidth,
                                  fit: BoxFit.fitWidth,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Text(
                                      'Image decode failed',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                    );
                                  },
                                );
                                if (constraints.maxWidth < 600) {
                                  return ClipRect(
                                    child: InteractiveViewer(
                                      minScale: 1.0,
                                      maxScale: 4.0,
                                      child: image,
                                    ),
                                  );
                                }
                                return image;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _QuestionNavBar extends StatelessWidget {
  final int currentNumber;
  final VoidCallback onPrevQuestion;
  final VoidCallback onNextQuestion;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;

  const _QuestionNavBar({
    required this.currentNumber,
    required this.onPrevQuestion,
    required this.onNextQuestion,
    required this.onPrevChapter,
    required this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = TextButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.35),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: onPrevChapter,
            style: buttonStyle,
            child: const Text('<<'),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onPrevQuestion,
            style: buttonStyle,
            child: const Text('<'),
          ),
          const SizedBox(width: 10),
          Text(
            '$currentNumber',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onNextQuestion,
            style: buttonStyle,
            child: const Text('>'),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onNextChapter,
            style: buttonStyle,
            child: const Text('>>'),
          ),
        ],
      ),
    );
  }
}

class _ChapterNavRow extends StatelessWidget {
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _ChapterNavRow({
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.arrow_back_ios_new),
            iconSize: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          const Spacer(),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_ios),
            iconSize: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  final String sectionTitle;
  final String chapterTitle;
  final VoidCallback? onSectionTap;

  const _ChapterHeader({
    required this.sectionTitle,
    required this.chapterTitle,
    this.onSectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final titleSize = (theme.textTheme.titleMedium?.fontSize ?? 18) -
        (width < 340 ? 2 : width < 380 ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onSectionTap,
            child: Text(
              sectionTitle,
              softWrap: true,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            chapterTitle,
            softWrap: true,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontSize: titleSize + 1,
            ),
          ),
        ],
      ),
    );
  }
}
