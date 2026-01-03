import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import '../widgets/fade_route.dart';
import 'questions_screen.dart';

class ChaptersScreen extends StatelessWidget {
  final String sectionTitle;

  const ChaptersScreen({super.key, required this.sectionTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chapters'),
      ),
      body: FutureBuilder<List<ChapterEntry>>(
        future: BrhcDatabase.instance.fetchChapters(sectionTitle),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final chapters = snapshot.data ?? [];
          final displaySectionTitle =
              TitleFormatter.parseSectionTitle(sectionTitle).title;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            );
          });

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: listItems.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displaySectionTitle,
                        textAlign: TextAlign.left,
                        softWrap: true,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chapters',
                        textAlign: TextAlign.left,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
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
    );
  }

}
