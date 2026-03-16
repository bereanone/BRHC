import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/font_scale.dart';
import '../utils/title_formatter.dart';
import 'chapters_screen.dart' as chapters;
import 'sections_screen.dart';
import '../widgets/fade_route.dart';
import 'questions_header.dart';
import 'package:brhc_app/widgets/chapter_blocks_view.dart';
import '../utils/clipboard_exporter.dart';
import 'launch_screen.dart';

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
  final Map<int, GlobalKey> _questionContexts = {};
  List<_QuestionRow> _sortedQuestions = [];
  List<Map<String, Object?>> _chapterBlocks = const [];
  int _currentQuestionIndex = 0;
  bool _navIndexInitialized = false;
  bool _didAutoScroll = false;

  late final Future<_ChapterScreenData> _dataFuture = _loadData();

  Future<_ChapterScreenData> _loadData() async {
    final db = BrhcDatabase.instance;
    final questions = await _fetchQuestionRows();

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
      prevChapter: prevChapter,
      nextChapter: nextChapter,
    );
  }

  Future<List<_QuestionRow>> _fetchQuestionRows() async {
    final db = await BrhcDatabase.instance.database;
    final chapterId = _parseChapterNumber(widget.rawChapterTitle);
    if (chapterId == null) {
      return [];
    }
    final rows = await db.rawQuery(
      '''
      SELECT id, question_number, question_text
      FROM questions
      WHERE chapter_id = ?
      ORDER BY order_in_chapter ASC
      ''',
      [chapterId],
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

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        toolbarHeight: 16,
        titleSpacing: 0,
        centerTitle: false,
        primary: false,
        actions: const [],
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(top: 0),
            child: FutureBuilder<_ChapterScreenData>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data;
                final questions = data?.questions ?? [];
                final prevChapter = data?.prevChapter;
                final nextChapter = data?.nextChapter;
                _sortedQuestions = questions;
                final chapterId =
                    _parseChapterNumber(widget.rawChapterTitle) ?? 0;

                if (!_navIndexInitialized) {
                  _currentQuestionIndex = _sortedQuestions.isNotEmpty ? 0 : -1;
                  _navIndexInitialized = true;
                }

                final hasQuestions = _sortedQuestions.isNotEmpty;
                final currentQuestionNumber = hasQuestions
                    ? _sortedQuestions[_currentQuestionIndex].questionNumber
                    : 0;
                if (hasQuestions) {
                  for (final question in _sortedQuestions) {
                    _questionContexts.putIfAbsent(
                      question.id,
                      () => GlobalKey(),
                    );
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_didAutoScroll) return;
                  if (_sortedQuestions.isNotEmpty) {
                    _didAutoScroll = true;
                    _scrollToQuestion(_sortedQuestions.first.id);
                  }
                });

                if (!hasQuestions) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const ValueKey('nav-navigate'),
                            onPressed: _showNavigateSheet,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              textStyle: _scaleStyle(
                                Theme.of(context).textTheme.labelLarge,
                                _fontScale(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Navigate'),
                          ),
                        ),
                      ),
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
                        currentNumber: 0,
                        onPrevQuestion: null,
                        onNextQuestion: null,
                        onPrevChapter: prevChapter == null
                            ? null
                            : () => _jumpToChapter(previous: true),
                        onNextChapter: nextChapter == null
                            ? null
                            : () => _jumpToChapter(previous: false),
                        onClipboard: _showClipboardSheet,
                      ),
                      Expanded(
                        child: ChapterBlocksView(
                          chapterId: chapterId,
                          scrollController: _scrollController,
                          onBlocksLoaded: (blocks) {
                            _chapterBlocks = blocks;
                          },
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          key: const ValueKey('nav-navigate'),
                          onPressed: _showNavigateSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            textStyle: _scaleStyle(
                              Theme.of(context).textTheme.labelLarge,
                              _fontScale(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Navigate'),
                        ),
                      ),
                    ),
                    ChapterHeader(
                      sectionTitle: _displaySectionTitle(widget.sectionTitle),
                      chapterTitle: _buildChapterHeader(widget.rawChapterTitle),
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
                      onClipboard: _showClipboardSheet,
                    ),
                    Expanded(
                      child: ChapterBlocksView(
                        chapterId: chapterId,
                        questionKeys: _questionContexts,
                        scrollController: _scrollController,
                        onBlocksLoaded: (blocks) {
                          _chapterBlocks = blocks;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Clipboard floating button removed as per refactor instructions.
        ],
      ),
    );
  }

  void _navigateToChapter(ChapterEntry chapter, {required bool fromLeft}) {
    final beginOffset = fromLeft
        ? const Offset(-1.0, 0.0)
        : const Offset(1.0, 0.0);
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
          final tween = Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeInOut));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  void _scrollToQuestion(int questionId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _questionContexts[questionId];
      final context = key?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    });
  }

  void _showClipboardSheet() {
    final hasQuestions = _sortedQuestions.isNotEmpty;
    final currentQuestionId = hasQuestions
        ? _sortedQuestions[_currentQuestionIndex].id
        : null;
    final questionBlocks = currentQuestionId == null
        ? const <Map<String, Object?>>[]
        : _chapterBlocks
              .where((b) => b['question_id'] == currentQuestionId)
              .toList();
    final chapterTitle = _buildChapterHeader(widget.rawChapterTitle);

    ClipboardScope scope = ClipboardScope.chapter;
    final hasQuestionBlocks = questionBlocks.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Copy'),
                    RadioListTile<ClipboardScope>(
                      value: ClipboardScope.chapter,
                      groupValue: scope,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => scope = value);
                      },
                      title: const Text('Copy entire chapter'),
                    ),
                    RadioListTile<ClipboardScope>(
                      value: ClipboardScope.currentQuestion,
                      groupValue: scope,
                      onChanged: hasQuestions
                          ? (value) {
                              if (value == null) return;
                              setState(() => scope = value);
                            }
                          : null,
                      title: const Text('Copy current question + answer'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            final export = buildClipboardExport(
                              chapterTitle: chapterTitle,
                              sectionTitle: _displaySectionTitle(
                                widget.sectionTitle,
                              ),
                              blocks: _chapterBlocks,
                              scope: scope,
                              questionId: currentQuestionId,
                            );
                            await Clipboard.setData(
                              ClipboardData(text: export.text),
                            );
                            if (mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Copied')),
                              );
                            }
                          },
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showNavigateSheet() {
    final navContext = context;
    showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        final scale = _fontScale(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.of(sheetContext).pop();
                        Future.microtask(() {
                          if (!mounted) return;
                          Navigator.of(navContext).pushAndRemoveUntil(
                            FadePageRoute<void>(page: const LaunchScreen()),
                            (route) => false,
                          );
                        });
                      },
                      child: Text(
                        'Home',
                        style: _scaleStyle(theme.textTheme.labelLarge, scale),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.of(sheetContext).pop();
                        Future.microtask(() {
                          if (!mounted) return;
                          Navigator.of(navContext).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SectionsScreen(),
                            ),
                          );
                        });
                      },
                      child: Text(
                        'Sections',
                        style: _scaleStyle(theme.textTheme.labelLarge, scale),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.of(sheetContext).pop();
                        Future.microtask(() {
                          if (!mounted) return;
                          Navigator.of(navContext).push(
                            FadeRoute(
                              builder: (_) => ChaptersScreen(
                                sectionTitle: widget.sectionTitle,
                                displaySectionTitle: widget.displaySectionTitle,
                              ),
                            ),
                          );
                        });
                      },
                      child: Text(
                        'Chapters',
                        style: _scaleStyle(theme.textTheme.labelLarge, scale),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: theme.dividerColor),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Shortcuts:',
                      style: _scaleStyle(
                        theme.textTheme.titleSmall,
                        scale,
                      )?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ShortcutLine(
                    label: '<<',
                    text: 'Previous chapter (within the current section)',
                  ),
                  _ShortcutLine(
                    label: '<',
                    text: 'Previous question in this chapter',
                  ),
                  _ShortcutLine(label: 'X', text: 'Current question number'),
                  _ShortcutLine(
                    label: '>',
                    text: 'Next question in this chapter',
                  ),
                  _ShortcutLine(
                    label: '>>',
                    text: 'Next chapter (within the current section)',
                  ),
                  _ShortcutLine(
                    label: 'Copy',
                    text: 'Copies the current question and its answer',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Font size can be adjusted from the Home screen using the gear icon in the bottom-right corner.',
                    style: _scaleStyle(theme.textTheme.bodySmall, scale)
                        ?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
  final ChapterEntry? prevChapter;
  final ChapterEntry? nextChapter;

  const _ChapterScreenData({
    required this.questions,
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

class _ShortcutLine extends StatelessWidget {
  final String label;
  final String text;

  const _ShortcutLine({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: _scaleStyle(
                theme.textTheme.bodyMedium,
                scale,
              )?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: _scaleStyle(theme.textTheme.bodyMedium, scale),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterNavRow extends StatelessWidget {
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _ChapterNavRow({required this.onPrevious, required this.onNext});

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

double _fontScale(BuildContext context) {
  return FontScaleScope.maybeOf(context)?.scale ?? 1.0;
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}
