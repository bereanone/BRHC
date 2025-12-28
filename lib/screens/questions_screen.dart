import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';

class QuestionsScreen extends StatefulWidget {
  final String chapterTitle;
  final String displayTitle;
  final int chapterId;

  const QuestionsScreen({
    super.key,
    required this.chapterTitle,
    required this.displayTitle,
    required this.chapterId,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final Set<int> _expandedQuestions = {};
  final Map<int, bool> _markOverrides = {};
  final ScrollController _scrollController = ScrollController();

  late final Future<_QuestionsScreenData> _dataFuture = _loadData();

  Future<_QuestionsScreenData> _loadData() async {
    final db = BrhcDatabase.instance;
    final results = await Future.wait([
      db.fetchQuestions(
        chapterId: widget.chapterId,
      ),
      db.fetchPreviousChapter(widget.chapterId),
      db.fetchNextChapter(widget.chapterId),
    ]);

    return _QuestionsScreenData(
      questions: results[0] as List<QuestionItem>,
      previous: results[1] as Chapter?,
      next: results[2] as Chapter?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayTitle)),
      body: FutureBuilder<_QuestionsScreenData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          final questions = data?.questions ?? [];
          final previousChapter = data?.previous;
          final nextChapter = data?.next;
          return Column(
            children: [
              _ChapterNavRow(
                title: widget.displayTitle,
                onPrevious: previousChapter == null
                    ? null
                    : () => _navigateToChapter(previousChapter),
                onNext:
                    nextChapter == null ? null : () => _navigateToChapter(nextChapter),
              ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: questions.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final item = questions[index];
                    final isExpanded = _expandedQuestions.contains(item.questionId);
                    final isMarked =
                        _markOverrides[item.questionId] ?? item.checked;
                    return _QuestionBlock(
                      item: item,
                      isExpanded: isExpanded,
                      isMarked: isMarked,
                      onToggle:
                          item.isScripture && (item.verseText?.isNotEmpty ?? false)
                              ? () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedQuestions.remove(item.questionId);
                                    } else {
                                      _expandedQuestions.add(item.questionId);
                                    }
                                  });
                                }
                              : null,
                      onMark: () => _handleMarkTap(
                        questionId: item.questionId,
                        isMarked: isMarked,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _navigateToChapter(Chapter chapter) {
    final displayTitle = chapter.title;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuestionsScreen(
          chapterTitle: chapter.title,
          displayTitle: displayTitle,
          chapterId: chapter.chapterId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleMarkTap({
    required int questionId,
    required bool isMarked,
  }) {
    if (questionId <= 0) {
      debugPrint('Audit mark skipped: invalid question_id.');
      return;
    }
    setState(() {
      _markOverrides[questionId] = !isMarked;
    });
    BrhcDatabase.instance.setAuditMark(
      questionId: questionId,
      checked: !isMarked,
    );
  }
}

class _QuestionsScreenData {
  final List<QuestionItem> questions;
  final Chapter? previous;
  final Chapter? next;

  const _QuestionsScreenData({
    required this.questions,
    required this.previous,
    required this.next,
  });
}

class _QuestionBlock extends StatelessWidget {
  final QuestionItem item;
  final bool isExpanded;
  final bool isMarked;
  final VoidCallback? onToggle;
  final VoidCallback onMark;

  const _QuestionBlock({
    required this.item,
    required this.isExpanded,
    required this.isMarked,
    required this.onToggle,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answerText = Text(
      item.answer,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.question,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            IconButton(
              onPressed: onMark,
              icon: Icon(isMarked ? Icons.check_circle : Icons.check_circle_outline),
              iconSize: 20,
              color: theme.colorScheme.primary.withOpacity(0.8),
              tooltip: 'Mark for audit',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (onToggle != null)
          GestureDetector(onTap: onToggle, child: answerText)
        else
          answerText,
        if (item.isScripture && isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              item.verseText ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
        if (item.imageBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Image.memory(
              item.imageBytes!,
              fit: BoxFit.contain,
            ),
          ),
      ],
    );
  }
}

class _ChapterNavRow extends StatelessWidget {
  final String title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _ChapterNavRow({
    required this.title,
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
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surface,
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
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
