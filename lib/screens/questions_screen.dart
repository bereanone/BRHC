import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';

class QuestionsScreen extends StatefulWidget {
  final String sectionTitle;
  final String chapterTitle;
  final String displayTitle;
  final int? initialBlockId;

  const QuestionsScreen({
    super.key,
    required this.sectionTitle,
    required this.chapterTitle,
    required this.displayTitle,
    this.initialBlockId,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _blockKeys = {};

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
      db.fetchPreviousChapter(
        sectionTitle: widget.sectionTitle,
        chapterTitle: widget.chapterTitle,
      ),
      db.fetchNextChapter(
        sectionTitle: widget.sectionTitle,
        chapterTitle: widget.chapterTitle,
      ),
    ]);

    return _ChapterScreenData(
      blocks: results[0] as List<DocBlock>,
      questions: results[1] as List<QuestionNavItem>,
      previous: results[2] as ChapterEntry?,
      next: results[3] as ChapterEntry?,
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayTitle)),
      body: FutureBuilder<_ChapterScreenData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          final blocks = data?.blocks ?? [];
          final questions = data?.questions ?? [];
          final previousChapter = data?.previous;
          final nextChapter = data?.next;
          final questionMap = {
            for (final q in questions) q.blockId: q,
          };

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = widget.initialBlockId;
            if (target != null) {
              _scrollToBlock(target);
            }
          });

          return Column(
            children: [
              _ChapterNavRow(
                title: widget.displayTitle,
                onPrevious: previousChapter == null
                    ? null
                    : () => _navigateToChapter(previousChapter),
                onNext: nextChapter == null ? null : () => _navigateToChapter(nextChapter),
              ),
              if (questions.isNotEmpty)
                _QuestionNavBar(
                  questions: questions,
                  onJump: _scrollToBlock,
                ),
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    if (notification.direction == ScrollDirection.idle) {
                      _updateActiveBlockFromScroll();
                    }
                    return false;
                  },
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    itemCount: blocks.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final block = blocks[index];
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
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _navigateToChapter(ChapterEntry chapter) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuestionsScreen(
          sectionTitle: chapter.sectionTitle,
          chapterTitle: chapter.chapterTitle,
          displayTitle: chapter.chapterTitle,
          initialBlockId: chapter.firstBlockId,
        ),
      ),
    );
  }

  void _scrollToBlock(int blockId) {
    final key = _blockKeys[blockId];
    if (key == null) {
      return;
    }
    final context = key.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
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
      if (offset >= 0) {
        break;
      }
    }
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
  final ChapterEntry? previous;
  final ChapterEntry? next;

  const _ChapterScreenData({
    required this.blocks,
    required this.questions,
    required this.previous,
    required this.next,
  });
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
      case 'question':
        return _QuestionBlock(block: block, question: question);
      case 'note':
        return _NoteBlock(block: block);
      case 'poetry':
        return _PoetryBlock(block: block);
      case 'table':
        return _TableBlock(block: block);
      case 'reading':
        return _ReadingBlock(block: block);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number == null ? block.normalizedText : '$number. ${block.normalizedText}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          block.normalizedText,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        _BlockImages(block.imageBlobs),
      ],
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final DocBlock block;

  const _NoteBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text(
            block.normalizedText,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
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
    final text = block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.5,
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
          Text(
            block.normalizedText,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
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
                            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
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

class _BlockImages extends StatelessWidget {
  final List<Uint8List> images;

  const _BlockImages(this.images);

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: images
            .map(
              (blob) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.memory(blob, fit: BoxFit.contain),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _QuestionNavBar extends StatelessWidget {
  final List<QuestionNavItem> questions;
  final ValueChanged<int> onJump;

  const _QuestionNavBar({
    required this.questions,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = questions[index];
          return TextButton(
            onPressed: () => onJump(item.blockId),
            style: TextButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.4),
                ),
              ),
            ),
            child: Text(
              '${item.questionNumber}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          );
        },
      ),
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
