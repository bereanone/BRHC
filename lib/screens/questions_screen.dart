import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import '../utils/font_scale.dart';
import 'chapters_screen.dart' as chapters;
import 'sections_screen.dart';
import '../widgets/fade_route.dart';
import '../debug/debug_flags.dart';
import '../debug/block_validator.dart';
import 'questions_header.dart';

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
  final Map<int, BuildContext> _questionContexts = {};
  List<_QuestionRow> _sortedQuestions = [];
  int _currentQuestionIndex = 0;
  bool _navIndexInitialized = false;
  bool _didAutoScroll = false;

  late final Future<_ChapterScreenData> _dataFuture = _loadData();

  Future<_ChapterScreenData> _loadData() async {
    final db = BrhcDatabase.instance;
    final rawQuestions = await _fetchQuestionRows();
    final questions =
        rawQuestions.where((q) => q.questionNumber > 0).toList();
    _assertQuestionsOrdered(questions, widget.rawChapterTitle);
    final answersByQuestion = <int, List<_AnswerBlock>>{
      for (final q in questions) q.id: [],
    };
    final introBlocks = <_AnswerBlock>[];
    final orphanBlocks = <_AnswerBlock>[];
    var chapterBlocks = <_AnswerBlock>[];

    final chapterNumber = _parseChapterNumber(widget.rawChapterTitle);
    if (chapterNumber != null) {
      chapterBlocks = await _fetchChapterAnswerBlocks(chapterNumber);
      final questionIds = questions.map((q) => q.id).toSet();
      int? currentQuestionId;
      for (final block in chapterBlocks) {
        if (block.blockType == 'intro') {
          introBlocks.add(block);
          continue;
        }
        if (questionIds.contains(block.questionId)) {
          currentQuestionId = block.questionId;
        }
        if (currentQuestionId == null) {
          orphanBlocks.add(block);
          continue;
        }
        answersByQuestion[currentQuestionId]!.add(block);
      }
    }
    final prevChapter = await db.fetchPreviousChapter(
      sectionTitle: widget.sectionTitle,
      chapterTitle: widget.chapterTitle,
    );
    final nextChapter = await db.fetchNextChapter(
      sectionTitle: widget.sectionTitle,
      chapterTitle: widget.chapterTitle,
    );
    return _ChapterScreenData(
      questions: questions,
      answersByQuestion: answersByQuestion,
      chapterBlocks: chapterBlocks,
      introBlocks: introBlocks,
      orphanBlocks: orphanBlocks,
      prevChapter: prevChapter,
      nextChapter: nextChapter,
    );
  }

  Future<List<_QuestionRow>> _fetchQuestionRows() async {
    final db = await BrhcDatabase.instance.database;
    final chapterNumber = _parseChapterNumber(widget.rawChapterTitle);
    if (chapterNumber == null) {
      return [];
    }
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM questions
      WHERE chapter_number = ?
        AND id > 0
      ORDER BY question_number ASC
      ''',
      [
        chapterNumber,
      ],
    );
    return rows
        .map<_QuestionRow>(
          (row) => _QuestionRow(
            id: row['id'] as int? ?? 0,
            questionNumber: row['question_number'] as int? ?? 0,
            questionText: row['question_text'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<_AnswerBlock>> _fetchAnswerBlocks(int questionId) async {
    if (questionId == 0) {
      return [];
    }
    final db = await BrhcDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM answer_blocks
      WHERE question_id = ?
      ORDER BY block_order ASC
      ''',
      [questionId],
    );
    return rows
        .map<_AnswerBlock>(
          (row) {
            final content = row['content'] as String? ?? '';
            final hasStrong = content.contains('<strong>');
            final hasEm = content.contains('<em>') || content.contains('<i>');
            debugPrint(
              '[DB_FETCH] id=${row['id']} type=${row['block_type']} '
              'hasStrong=$hasStrong hasEm=$hasEm content="$content"',
            );
            return _AnswerBlock(
              id: row['id'] as int? ?? 0,
              questionId: row['question_id'] as int? ?? 0,
              sequenceInQuestion: row['sequence_in_question'] as int? ?? 0,
              blockType: row['block_type'] as String? ?? 'answer',
              content: content,
              reference: row['reference'] as String?,
              imageRef: row['image_ref'],
            );
          },
        )
        .toList();
  }

  Future<List<_AnswerBlock>> _fetchChapterAnswerBlocks(int chapterNumber) async {
    final db = await BrhcDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT ab.*
      FROM answer_blocks ab
      JOIN questions q ON q.id = ab.question_id
      WHERE q.chapter_number = ?
      ORDER BY ab.id ASC
      ''',
      [chapterNumber],
    );
    return rows
        .map<_AnswerBlock>(
          (row) => _AnswerBlock(
            id: row['id'] as int? ?? 0,
            questionId: row['question_id'] as int? ?? 0,
            sequenceInQuestion: row['block_order'] as int? ?? 0,
            blockType: row['block_type'] as String? ?? 'answer',
            content: row['content'] as String? ?? '',
            reference: row['reference'] as String?,
            imageRef: row['image_ref'],
          ),
        )
        .toList();
  }

  DocBlock _answerBlockToDocBlock(_AnswerBlock answer) {
    final type = _mapAnswerBlockType(answer.blockType);
    if (type == 'image') {
      final ref = answer.imageRef?.toString().trim();
      final token = ref == null || ref.isEmpty ? '' : '[Pic: $ref]';
      return DocBlock(
        blockId: answer.id,
        blockType: 'image',
        rawText: token,
        normalizedText: token,
        tableJson: null,
        imageBlobs: const [],
      );
    }
    final content = _mergeAnswerContent(answer.content, answer.reference);
    return DocBlock(
      blockId: answer.id,
      blockType: type,
      rawText: content,
      normalizedText: _stripMarkersForDisplay(content),
      tableJson: null,
      imageBlobs: const [],
    );
  }

  String _mapAnswerBlockType(String raw) {
    switch (raw) {
      case 'intro':
        return 'intro';
      case 'poetry':
        return 'poetry';
      case 'note':
        return 'note';
      case 'heading':
        return 'heading';
      case 'scripture':
        return 'scripture';
      case 'responsive':
        return 'responsive';
      case 'image':
        return 'image';
      case 'answer':
        return 'answer';
      default:
        return 'text';
    }
  }

  String _mergeAnswerContent(String content, String? reference) {
    final trimmed = content.trim();
    final ref = reference?.trim() ?? '';
    if (ref.isEmpty) {
      return trimmed;
    }
    if (trimmed.isEmpty) {
      return ref;
    }
    if (trimmed.contains(ref)) {
      return trimmed;
    }
    return '$trimmed $ref';
  }

  @override
  void initState() {
    super.initState();
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
            final questions = data?.questions ?? [];
            final answersByQuestion = data?.answersByQuestion ?? {};
            final chapterBlocks = data?.chapterBlocks ?? [];
            final introBlocks = data?.introBlocks ?? [];
            final orphanBlocks = data?.orphanBlocks ?? [];
            final prevChapter = data?.prevChapter;
            final nextChapter = data?.nextChapter;
            _sortedQuestions = questions;

            if (!_navIndexInitialized) {
              _currentQuestionIndex = _sortedQuestions.isNotEmpty ? 0 : -1;
              _navIndexInitialized = true;
            }

            _questionContexts.clear();
            
            final hasQuestions = _sortedQuestions.isNotEmpty;
            final currentQuestionNumber = hasQuestions
                ? _sortedQuestions[_currentQuestionIndex].questionNumber
                : 0;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_didAutoScroll) return;
              if (_sortedQuestions.isNotEmpty) {
                _didAutoScroll = true;
                _scrollToQuestion(_sortedQuestions.first.id);
              }
            });

            return Column(
              children: [
                ChapterHeader(
                  sectionTitle: _displaySectionTitle(widget.sectionTitle),
                  chapterTitle: _buildChapterHeader(
                    widget.rawChapterTitle,
                  ),
                  onSectionTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SectionsScreen(),
                      ),
                    );
                  },
                  onChapterTap: () {
                    Navigator.of(context).push(
                      FadeRoute(
                        builder: (_) => ChaptersScreen(
                          sectionTitle: widget.sectionTitle,
                          displaySectionTitle: widget.displaySectionTitle,
                        ),
                      ),
                    );
                  },
                ),
                QuestionNavBar(
                  currentNumber: currentQuestionNumber,
                  onPrevQuestion:
                      (hasQuestions && _currentQuestionIndex > 0)
                          ? () => _jumpToQuestion(previous: true)
                          : null,
                  onNextQuestion:
                      (hasQuestions &&
                              _currentQuestionIndex <
                                  _sortedQuestions.length - 1)
                          ? () => _jumpToQuestion(previous: false)
                          : null,
                  onPrevChapter: prevChapter == null
                      ? null
                      : () => _jumpToChapter(previous: true),
                  onNextChapter: nextChapter == null
                      ? null
                      : () => _jumpToChapter(previous: false),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildQuestionWidgets(
                        answersByQuestion,
                        chapterBlocks,
                        introBlocks,
                        orphanBlocks,
                      ),
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

  void _scrollToQuestion(int questionId) {
    void attemptScroll(int remaining) {
      final context = _questionContexts[questionId];
      if (context == null) {
        if (remaining > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            attemptScroll(remaining - 1);
          });
        }
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }

    attemptScroll(6);
  }

  List<Widget> _buildQuestionWidgets(
    Map<int, List<_AnswerBlock>> answersByQuestion,
    List<_AnswerBlock> chapterBlocks,
    List<_AnswerBlock> introBlocks,
    List<_AnswerBlock> orphanBlocks,
  ) {
    final widgets = <Widget>[];
    final questionsById = {
      for (final q in _sortedQuestions) q.id: q,
    };
    final renderedQuestions = <int>{};
    final answerCounts = <int, int>{};
    final hasQuestions = questionsById.isNotEmpty;

    for (final block in chapterBlocks) {
      final docBlock = _answerBlockToDocBlock(block);
      BlockValidator.validateBlock(docBlock); // Diagnostics only.
      if (docBlock.blockType == 'intro') {
        BlockValidator.validateIntroQuestionId(block.id, block.questionId);
      }
      if (docBlock.blockType == 'answer') {
        final question = questionsById[block.questionId];
        if (question != null && renderedQuestions.add(question.id)) {
          widgets.add(
            KeyedSubtree(
              key: ValueKey('question-${question.id}'),
              child: Builder(
                builder: (context) {
                  _questionContexts[question.id] = context;
                  return _QuestionBlock(question: question);
                },
              ),
            ),
          );
        }
        if (question != null) {
          answerCounts[question.id] = (answerCounts[question.id] ?? 0) + 1;
        } else if (DebugFlags.renderTrace && hasQuestions) {
          widgets.add(
            _debugIntegrityWarning(
              context,
              '⚠ Orphaned answer (no active question)',
            ),
          );
        }
      }
      if (DebugFlags.poetryTrace && docBlock.blockType == 'poetry') {
        debugPrint(
          '[DEBUG] poetry block inside chapter flow (id=${block.questionId})',
        );
      }
      widgets.add(
        KeyedSubtree(
          key: ValueKey('block-${block.id}'),
          child: _AnswerBlockRenderer(
            block: docBlock,
          ),
        ),
      );
    }

    for (final question in _sortedQuestions) {
      if (question.id <= 0) {
        continue;
      }
      if (!renderedQuestions.contains(question.id)) {
        widgets.add(
          KeyedSubtree(
            key: ValueKey('question-${question.id}'),
            child: Builder(
              builder: (context) {
                _questionContexts[question.id] = context;
                return _QuestionBlock(question: question);
              },
            ),
          ),
        );
      }
      final hasAnswers = (answerCounts[question.id] ?? 0) > 0;
      BlockValidator.validateQuestion(question.id, hasAnswers);
      if (DebugFlags.renderTrace && !hasAnswers) {
        BlockValidator.logAnswerSkip(question.id);
        widgets.add(
          _debugIntegrityWarning(
            context,
            '⚠ No answers found for this question',
          ),
        );
      }
      if (renderedQuestions.contains(question.id)) {
        widgets.add(
          KeyedSubtree(
            key: ValueKey('divider-question-${question.id}'),
            child: const Divider(height: 24),
          ),
        );
      }
    }

    return widgets;
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

  void _assertQuestionsOrdered(
    List<_QuestionRow> questions,
    String rawChapterTitle,
  ) {
    var last = 0;
    for (final question in questions) {
      final current = question.questionNumber;
      if (current < last) {
        debugPrint(
          '[RENDER] Question order error in "$rawChapterTitle": '
          '$current after $last',
        );
        throw StateError('Question order error in $rawChapterTitle');
      }
      last = current;
    }
  }


  void _jumpToQuestion({required bool previous}) {
    if (_sortedQuestions.isEmpty) {
      return;
    }
    int newIndex = _currentQuestionIndex;
    if (previous) {
      if (newIndex > 0) newIndex--;
    } else {
      if (newIndex < _sortedQuestions.length - 1) newIndex++;
    }
    if (newIndex != _currentQuestionIndex) {
      setState(() {
        _currentQuestionIndex = newIndex;
      });
      _scrollToQuestion(_sortedQuestions[newIndex].id);
    }
  }

  int? _parseChapterNumber(String rawTitle) {
    final parsed = TitleFormatter.parseChapterTitle(rawTitle);
    final number = parsed.number;
    if (number == null || number.isEmpty) {
      return null;
    }
    return int.tryParse(number);
  }


  Future<void> _jumpToChapter({required bool previous}) async {
    final db = BrhcDatabase.instance;
    final target = previous
        ? await db.fetchPreviousChapter(
            sectionTitle: widget.sectionTitle,
            chapterTitle: widget.chapterTitle,
          )
        : await db.fetchNextChapter(
            sectionTitle: widget.sectionTitle,
            chapterTitle: widget.chapterTitle,
          );
    if (!mounted || target == null) {
      return;
    }
    _navigateToChapter(target, fromLeft: previous);
  }

  

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChapterScreenData {
  final List<_QuestionRow> questions;
  final Map<int, List<_AnswerBlock>> answersByQuestion;
  final List<_AnswerBlock> chapterBlocks;
  final List<_AnswerBlock> introBlocks;
  final List<_AnswerBlock> orphanBlocks;
  final ChapterEntry? prevChapter;
  final ChapterEntry? nextChapter;

  const _ChapterScreenData({
    required this.questions,
    required this.answersByQuestion,
    required this.chapterBlocks,
    required this.introBlocks,
    required this.orphanBlocks,
    required this.prevChapter,
    required this.nextChapter,
  });
}

class _QuestionRow {
  final int id;
  final int questionNumber;
  final String questionText;

  const _QuestionRow({
    required this.id,
    required this.questionNumber,
    required this.questionText,
  });
}

class _AnswerBlock {
  final int id;
  final int questionId;
  final int sequenceInQuestion;
  final String blockType;
  final String content;
  final String? reference;
  final Object? imageRef;
  final bool hasStrong;
  final bool hasEm;
  final bool hasI;
  final bool hasU;

  _AnswerBlock({
    required this.id,
    required this.questionId,
    required this.sequenceInQuestion,
    required this.blockType,
    required this.content,
    required this.reference,
    required this.imageRef,
  })  : hasStrong = _hasStrongInContent(content),
        hasEm = content.contains('<em>'),
        hasI = content.contains('<i>'),
        hasU = content.contains('<u>') {
    debugPrint(
      '[MODEL] id=$id type=$blockType hasStrong=$hasStrong hasEm=$hasEm '
      'hasI=$hasI hasU=$hasU content="$content"',
    );
  }
}

bool _hasStrongInContent(String content) {
  return content.contains('<strong>');
}

class _QuestionBlock extends StatelessWidget {
  final _QuestionRow question;

  const _QuestionBlock({
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    final displayText = question.questionText;
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final scaledBaseStyle = _scaleStyle(baseStyle, scale) ?? baseStyle;
    final hasHtml = _containsMarkup(displayText);

    final displayNumber = question.questionNumber;
    final questionStyle = scaledBaseStyle.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: const Color(0xFF0000FF),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hasHtml
            ? RichText(
                text: TextSpan(
                  style: questionStyle,
                  children: [
                    TextSpan(
                      text: '$displayNumber. ',
                      style: questionStyle,
                    ),
                    _renderInlineHtml(
                      displayText,
                      questionStyle,
                    ),
                  ],
                ),
              )
            : Text(
                '$displayNumber. $displayText',
                softWrap: true,
                style: questionStyle,
              ),
      ],
    );
  }
}

class _AnswerBlockRenderer extends StatelessWidget {
  final DocBlock block;

  const _AnswerBlockRenderer({required this.block});

  @override
  Widget build(BuildContext context) {
    final renderSource =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final hasStrong = renderSource.contains('<strong>');
    final hasEm =
        renderSource.contains('<em>') || renderSource.contains('<i>');
    final htmlAware = _containsMarkup(renderSource);
    debugPrint(
      '[RENDER_SELECT] blockType=${block.blockType} htmlAware=$htmlAware '
      'hasStrong=$hasStrong hasEm=$hasEm',
    );
    return renderBlockByType(block);
  }
}

Widget renderBlockByType(DocBlock block) {
  final renderSource =
      block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
  if (block.blockType == 'heading' && !renderSource.contains('<strong>')) {
    throw StateError('Heading missing <strong> (id=${block.blockId})');
  }
  switch (block.blockType) {
    case 'note':
      return _NoteBlock(block: block);
    case 'note_heading':
      return _NoteBlock(block: block, isHeading: true);
    case 'title_ref':
      return _TitleRefBlock(block: block);
    case 'intro':
      return _IntroBlock(block: block);
    case 'poetry':
      return _PoetryBlock(block: block);
    case 'table':
      return _TableBlock(block: block);
    case 'responsive':
    case 'reading':
      return _ReadingBlock(block: block);
    case 'image':
      final filename = _extractPicFilename(renderSource);
      if (filename == null) {
        return const SizedBox.shrink();
      }
      final imageId = int.tryParse(filename);
      if (imageId == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: _InlineImageById(
          key: ValueKey('image-block-${block.blockId}-id-$imageId'),
          imageId: imageId,
        ),
      );
    case 'scripture':
      return _TextBlock(block: block, isScripture: true);
    case 'heading':
      return _TextBlock(
        block: block,
        isHeading: true,
        textAlign: TextAlign.center,
        // Force HTML-aware rendering so <strong> applies in headings.
        forceHtml: true,
      );
    case 'answer':
    case 'text':
    default:
      return _TextBlock(block: block);
  }
}

class _TextBlock extends StatelessWidget {
  final DocBlock block;
  final bool isScripture;
  final bool isHeading;
  final TextAlign textAlign;
  final bool forceHtml;

  const _TextBlock({
    required this.block,
    this.isScripture = false,
    this.isHeading = false,
    this.textAlign = TextAlign.start,
    this.forceHtml = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    final renderSource =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final hasStrong = renderSource.contains('<strong>');
    final hasEm =
        renderSource.contains('<em>') || renderSource.contains('<i>');
    debugPrint(
      '[RENDER_INPUT] widget=_TextBlock id=${block.blockId} '
      'hasStrong=$hasStrong hasEm=$hasEm',
    );
    debugPrint(
      '[RENDER_WIDGET] using ${_containsMarkup(renderSource) ? 'RichText' : 'Text'} '
      'htmlAware=${_containsMarkup(renderSource)}',
    );
    final text = _stripMarkersForDisplay(renderSource);
    debugPrint(
      '[RENDER_INPUT] widget=_TextBlock id=${block.blockId} '
      'hasStrong=$hasStrong hasEm=$hasEm text="$text"',
    );
    var style = _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
      height: 1.5,
      color: const Color(0xFF1F1B17),
    );
    if (isScripture) {
      style = style?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    if (isHeading) {
      debugPrint('[RENDER_OVERRIDE] heading bold forced id=${block.blockId}');
      final baseSize = style?.fontSize ?? 14;
      style = style?.copyWith(
        fontWeight: _containsMarkup(renderSource)
            ? style?.fontWeight
            : FontWeight.w700,
        fontSize: baseSize * 1.15,
      );
    }
    debugPrint(
      '[RENDER_STYLE] widget=_TextBlock id=${block.blockId} '
      'fontWeight=${style?.fontWeight} fontStyle=${style?.fontStyle}',
    );
    final widgets = _buildInlineWidgets(
      context,
      text,
      style,
      textAlign: textAlign,
      forceHtml: forceHtml || isHeading,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widgets,
        _BlockImages(block.imageBlobs),
      ],
    );
    if (isHeading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: content,
      );
    }
    return content;
  }
}

class _IntroBlock extends StatelessWidget {
  final DocBlock block;

  const _IntroBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    return _TextBlock(
      block: block,
      textAlign: TextAlign.start,
      forceHtml: true,
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
    final scale = _fontScale(context);
    final renderSource =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final hasEm =
        renderSource.contains('<em>') || renderSource.contains('<i>');
    final hasLineMarker =
        RegExp(r'\[L\d+\]').hasMatch(renderSource);
    debugPrint(
      '[RESP_TRACE] id=${block.blockId} hasEm=$hasEm hasLineMarker=$hasLineMarker',
    );
    final text = _stripMarkersForDisplay(renderSource);
    final style = _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
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
    final scale = _fontScale(context);
    final renderSource =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(renderSource);
    final style = _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
      height: 1.5,
      color: const Color(0xFF1F1B17),
    );
    final widgets =
        _buildInlineWidgets(context, text, style, textAlign: TextAlign.center);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...widgets,
          _BlockImages(block.imageBlobs),
        ],
      ),
    );
  }
}

class _ReadingBlock extends StatelessWidget {
  final DocBlock block;

  const _ReadingBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    final renderSource =
        block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    final text = _stripMarkersForDisplay(renderSource);
    final style = _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
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
    final scale = _fontScale(context);
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
                            style: _scaleStyle(theme.textTheme.bodySmall, scale)
                                ?.copyWith(
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
    final scale = _fontScale(context);
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
    final style = _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
      height: 1.4,
    );
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
  final int offset;

  const _InlinePiece.text(this.text, this.offset) : filename = null;
  const _InlinePiece.image(this.filename, this.offset) : text = null;
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
    return [_InlinePiece.text(text, 0)];
  }
  final pieces = <_InlinePiece>[];
  var index = 0;
  for (final match in matches) {
    if (match.start > index) {
      pieces.add(
        _InlinePiece.text(text.substring(index, match.start), index),
      );
    }
    final filename = match.group(1)?.trim();
    if (filename != null && filename.isNotEmpty) {
      pieces.add(_InlinePiece.image(filename, match.start));
    }
    index = match.end;
  }
  if (index < text.length) {
    pieces.add(_InlinePiece.text(text.substring(index), index));
  }
  return pieces;
}

Widget _debugIntegrityWarning(BuildContext context, String text) {
  final style = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Colors.red,
        fontSize: 12,
      );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, style: style),
  );
}

List<Widget> _buildInlineWidgets(
  BuildContext context,
  String text,
  TextStyle? style, {
  TextAlign? textAlign,
  bool forceHtml = false,
}) {
  final pieces = _splitTextByPicTags(text);
  final widgets = <Widget>[];
  for (var index = 0; index < pieces.length; index++) {
    final piece = pieces[index];
    if (piece.text != null && piece.text!.isNotEmpty) {
      final segment = piece.text!;
      if (forceHtml || _containsMarkup(segment)) {
        widgets.add(
          RichText(
            text: _renderInlineHtml(segment, style),
            textAlign: textAlign ?? TextAlign.start,
          ),
        );
      } else {
        widgets.add(
          Text(
            segment,
            softWrap: true,
            textAlign: textAlign,
            style: style,
          ),
        );
      }
    } else if (piece.filename != null && piece.filename!.isNotEmpty) {
      widgets.add(
        _InlineImageByFilename(
          key: ValueKey('inline-img-${piece.filename}-${piece.offset}'),
          filename: piece.filename!,
        ),
      );
    }
  }
  if (widgets.isEmpty) {
    widgets.add(
      Text(
        text,
        softWrap: true,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
  return widgets;
}

class _InlineImageByFilename extends StatelessWidget {
  final String filename;

  const _InlineImageByFilename({super.key, required this.filename});

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
              final viewerKey = key is ValueKey
                  ? (key as ValueKey).value.toString()
                  : filename;
              return ClipRect(
                child: InteractiveViewer(
                  key: ValueKey('img-file-$viewerKey'),
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

class _InlineImageById extends StatelessWidget {
  final int imageId;

  const _InlineImageById({super.key, required this.imageId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _fetchImageBlobById(imageId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 12);
        }
        final blob = snapshot.data;
        if (blob == null) {
          if (_missingPicLog.add('id:$imageId')) {
            debugPrint('Missing image for [Pic] id: $imageId');
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
              final viewerKey =
                  key is ValueKey ? (key as ValueKey).value.toString() : '$imageId';
              return ClipRect(
                child: InteractiveViewer(
                  key: ValueKey('img-id-$viewerKey'),
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

  Future<Uint8List?> _fetchImageBlobById(int id) async {
    final db = await BrhcDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT image_blob FROM brhc_images WHERE image_id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    final blob = rows.first['image_blob'];
    return blob is Uint8List ? blob : null;
  }
}

bool _containsMarkup(String text) {
  return RegExp(r'<\s*/?\s*(strong|em|i|u|br)\s*/?\s*>', caseSensitive: false)
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
      .replaceAll(
        RegExp(
          r'<\s*/?\s*(?!strong|em|i|u|br)\w+[^>]*>',
          caseSensitive: false,
        ),
        '',
      );
  final spans = <TextSpan>[];
  var buffer = StringBuffer();
  var boldDepth = 0;
  var italicDepth = 0;
  var underlineDepth = 0;

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: baseStyle?.copyWith(
          fontWeight: boldDepth > 0 ? FontWeight.w700 : baseStyle?.fontWeight,
          fontStyle: italicDepth > 0 ? FontStyle.italic : baseStyle?.fontStyle,
          decoration:
              underlineDepth > 0 ? TextDecoration.underline : baseStyle?.decoration,
        ),
      ),
    );
    buffer.clear();
  }

  final tagRegex = RegExp(r'<\s*/?\s*(strong|em|i|u)\s*>', caseSensitive: false);
  var index = 0;
  for (final match in tagRegex.allMatches(normalized)) {
    buffer.write(normalized.substring(index, match.start));
    flush();
    final tag = match.group(1)?.toLowerCase() ?? '';
    final token = match.group(0) ?? '';
    final isClosing = RegExp(r'^<\s*/').hasMatch(token);
    if (tag == 'strong') {
      boldDepth = isClosing
          ? (boldDepth - 1).clamp(0, 1000).toInt()
          : boldDepth + 1;
    } else if (tag == 'em' || tag == 'i') {
      italicDepth = isClosing
          ? (italicDepth - 1).clamp(0, 1000).toInt()
          : italicDepth + 1;
    } else if (tag == 'u') {
      underlineDepth = isClosing
          ? (underlineDepth - 1).clamp(0, 1000).toInt()
          : underlineDepth + 1;
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
                .map(
                  (imageBytes) {
                    final imageKey = _imageBytesKey(imageBytes);
                    return Padding(
                      key: ValueKey('block-image-$imageKey'),
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
                                  imageBytes,
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
                                      key: ValueKey('block-image-iv-$imageKey'),
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
                  );
                },
                )
                .toList(),
          ),
        );
      },
    );
  }
}

String _imageBytesKey(Uint8List bytes) {
  var hash = 0;
  for (var i = 0; i < bytes.length; i += 64) {
    hash = (hash * 31 + bytes[i]) & 0x7fffffff;
  }
  return '${bytes.length}-$hash';
}

double _fontScale(BuildContext context) {
  return FontScaleScope.maybeOf(context)?.scale ?? 1.0;
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}

extension _ChapterLookup on BrhcDatabase {
  Future<List<ChapterEntry>> fetchChaptersForSection({
    required String sectionTitle,
  }) {
    return fetchChapters(sectionTitle);
  }
}

class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) {
            return builder(context);
          },
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
}

class ChaptersScreen extends StatelessWidget {
  final String sectionTitle;
  final String displaySectionTitle;

  const ChaptersScreen({
    super.key,
    required this.sectionTitle,
    required this.displaySectionTitle,
  });

  @override
  Widget build(BuildContext context) {
    return chapters.ChaptersScreen(sectionTitle: sectionTitle);
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
            key: const ValueKey('chapter-nav-prev'),
            onPressed: onPrevious,
            icon: const Icon(Icons.arrow_back_ios_new),
            iconSize: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          const Spacer(),
          IconButton(
            key: const ValueKey('chapter-nav-next'),
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
