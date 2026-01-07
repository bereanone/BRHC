import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import '../widgets/fade_route.dart';
import 'questions_screen.dart';
import 'sections_screen.dart';

class ChaptersScreen extends StatelessWidget {
  final String sectionTitle;
  final int? sectionIndex;

  const ChaptersScreen({super.key, required this.sectionTitle, this.sectionIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<ChapterEntry>>(
          future: BrhcDatabase.instance.fetchChapters(sectionTitle),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final chapters = snapshot.data ?? [];
            // Always display: <number>. <title> (no duplication)
            final parsedSection = TitleFormatter.parseSectionTitle(sectionTitle);
            final displaySectionTitle =
                parsedSection.number != null && parsedSection.number!.isNotEmpty
                    ? '${parsedSection.number}. ${parsedSection.title}'
                    : parsedSection.title;
          final sectionAnchorBlockId =
              chapters.isNotEmpty ? chapters.first.firstBlockId : null;
          final listItems = List.generate(chapters.length, (index) {
              final chapter = chapters[index];
              final parsed = TitleFormatter.parseChapterTitle(chapter.rawChapterTitle);
              final number = parsed.number ?? '${index + 1}';
              final title = parsed.title;
              final displayTitle = '$number. $title';
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    FadePageRoute<void>(
                      page: QuestionsScreen(
                        sectionTitle: chapter.rawSectionTitle,
                        chapterTitle: chapter.rawChapterTitle,
                        displayTitle: displayTitle,
                        rawChapterTitle: chapter.rawChapterTitle,
                        displaySectionTitle: displaySectionTitle,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.6),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: theme.colorScheme.surface,
                  ),
                  child: Text(
                    displayTitle,
                    textAlign: TextAlign.left,
                    softWrap: true,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            });

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: listItems.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new),
                              tooltip: 'Previous section',
                              onPressed: sectionAnchorBlockId == null
                                  ? null
                                  : () async {
                                      final prevSection =
                                          await BrhcDatabase.instance
                                              .fetchPreviousSectionWithContentByBlock(
                                        blockId: sectionAnchorBlockId,
                                      );
                                      if (prevSection == null || !context.mounted) {
                                        return;
                                      }
                                      Navigator.of(context).pushReplacement(
                                        FadePageRoute<void>(
                                          page: ChaptersScreen(
                                            sectionTitle:
                                                prevSection.rawSectionTitle,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    FadePageRoute<void>(
                                      page: const SectionsScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  displaySectionTitle,
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios),
                              tooltip: 'Next section',
                              onPressed: sectionAnchorBlockId == null
                                  ? null
                                  : () async {
                                      final nextSection =
                                          await BrhcDatabase.instance
                                              .fetchNextSectionWithContentByBlock(
                                        blockId: sectionAnchorBlockId,
                                      );
                                      if (nextSection == null || !context.mounted) {
                                        return;
                                      }
                                      Navigator.of(context).pushReplacement(
                                        FadePageRoute<void>(
                                          page: ChaptersScreen(
                                            sectionTitle:
                                                nextSection.rawSectionTitle,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Chapters',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return listItems[index - 1];
              },
            );
          },
        ),
      ),
    );
  }

}
