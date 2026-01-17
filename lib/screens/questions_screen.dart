import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import 'chapters_screen.dart' as chapters;
import 'sections_screen.dart';
import '../widgets/fade_route.dart';
import 'questions_header.dart';
import 'package:brhc_app/widgets/lib/widgets/chapter_blocks_view.dart';

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
            final prevChapter = data?.prevChapter;
            final nextChapter = data?.nextChapter;
            _sortedQuestions = questions;
            final chapterId =
                _parseChapterNumber(widget.rawChapterTitle) ?? 0;

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
                  child: ChapterBlocksView(chapterId: chapterId),
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
