import 'package:flutter/material.dart';

import '../utils/font_scale.dart';
import 'questions_header.dart';

class QuestionNavBar extends StatelessWidget {
  final int currentNumber;
  final VoidCallback? onPrevQuestion;
  final VoidCallback? onNextQuestion;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onClipboard;

  const QuestionNavBar({
    super.key,
    required this.currentNumber,
    required this.onPrevQuestion,
    required this.onNextQuestion,
    required this.onPrevChapter,
    required this.onNextChapter,
    this.onClipboard,
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
    final hasQuestions = currentNumber > 0;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: hasQuestions ? 4 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            key: const ValueKey('nav-prev-chapter'),
            onPressed: onPrevChapter,
            style: buttonStyle,
            child: const Text('<<'),
          ),
          if (hasQuestions) ...[
            const SizedBox(width: 6),
            TextButton(
              key: const ValueKey('nav-prev-question'),
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
              key: const ValueKey('nav-next-question'),
              onPressed: onNextQuestion,
              style: buttonStyle,
              child: const Text('>'),
            ),
          ],
          const SizedBox(width: 6),
          TextButton(
            key: const ValueKey('nav-next-chapter'),
            onPressed: onNextChapter,
            style: buttonStyle,
            child: const Text('>>'),
          ),
          if (onClipboard != null) ...[
            const SizedBox(width: 6),
            TextButton(
              key: const ValueKey('nav-clipboard'),
              onPressed: onClipboard,
              style: buttonStyle.copyWith(
                padding: MaterialStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                ),
              ),
              child: const Icon(Icons.content_copy, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class ChapterHeader extends StatelessWidget {
  final String sectionTitle;
  final String chapterTitle;
  final VoidCallback? onSectionTap;
  final VoidCallback? onChapterTap;

  const ChapterHeader({
    super.key,
    required this.sectionTitle,
    required this.chapterTitle,
    this.onSectionTap,
    this.onChapterTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            key: ValueKey('section-${sectionTitle}'),
            onTap: onSectionTap,
            child: Text(
              sectionTitle,
              softWrap: true,
              textAlign: TextAlign.center,
              style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            key: ValueKey('chapter-${chapterTitle}'),
            onTap: onChapterTap,
            child: Text(
              chapterTitle,
              softWrap: true,
              textAlign: TextAlign.center,
              style: _scaleStyle(theme.textTheme.titleMedium, scale)?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
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
