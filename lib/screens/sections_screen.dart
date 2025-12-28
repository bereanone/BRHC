import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../widgets/fade_route.dart';
import 'about_screen.dart';
import 'chapters_screen.dart';

class SectionsScreen extends StatelessWidget {
  const SectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sections'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                FadePageRoute<void>(page: const AboutScreen()),
              );
            },
            child: Text(
              'About',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Section>>(
        future: BrhcDatabase.instance.fetchSections(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sections = snapshot.data ?? [];
          return LayoutBuilder(
            builder: (context, constraints) {
              const tileHeight = 52.0;
              const spacing = 8.0;
              final contentHeight = sections.isEmpty
                  ? 0.0
                  : (sections.length * tileHeight) +
                      ((sections.length - 1) * spacing) +
                      24;
              final listItems = List.generate(sections.length, (index) {
                final section = sections[index];
                return SizedBox(
                  height: tileHeight,
                  child: _SectionButton(
                    title: section.title,
                    onTap: () {
                      Navigator.of(context).push(
                        FadePageRoute<void>(
                          page: ChaptersScreen(sectionTitle: section.title),
                        ),
                      );
                    },
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
                itemCount: sections.length,
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

class _SectionButton extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SectionButton({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.6)),
          borderRadius: BorderRadius.circular(6),
          color: theme.colorScheme.surface,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
