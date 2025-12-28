import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
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
        title: Text(sectionTitle),
      ),
      body: FutureBuilder<List<Chapter>>(
        future: BrhcDatabase.instance.fetchChapters(sectionTitle),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final chapters = snapshot.data ?? [];
          return LayoutBuilder(
            builder: (context, constraints) {
              const tileHeight = 54.0;
              const spacing = 8.0;
              final contentHeight = chapters.isEmpty
                  ? 0.0
                  : (chapters.length * tileHeight) +
                      ((chapters.length - 1) * spacing) +
                      24;
              final listItems = List.generate(chapters.length, (index) {
                final chapter = chapters[index];
                final displayTitle = chapter.title;
                return SizedBox(
                  height: tileHeight,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        FadePageRoute<void>(
                        page: QuestionsScreen(
                          chapterTitle: chapter.title,
                          displayTitle: displayTitle,
                          chapterId: chapter.chapterId,
                        ),
                      ),
                    );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
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
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                );
              });

              if (contentHeight <= constraints.maxHeight) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < listItems.length; i++) ...[
                        listItems[i],
                        if (i != listItems.length - 1)
                          const SizedBox(height: spacing),
                      ],
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: chapters.length,
                separatorBuilder: (_, __) => const SizedBox(height: spacing),
                itemBuilder: (context, index) => listItems[index],
              );
            },
          );
        },
      ),
    );
  }
}
