import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/title_formatter.dart';
import '../widgets/fade_route.dart';
import 'about_screen.dart';
import 'chapters_screen.dart';
import 'introduction_screen.dart';
import 'launch_screen.dart';

class SectionsScreen extends StatelessWidget {
  const SectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Home',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              // Sections can be the root; replace with entry screen to avoid empty stack.
              navigator.pushReplacement(
                FadePageRoute<void>(page: const LaunchScreen()),
              );
            }
          },
        ),
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
          if (sections.isEmpty) {
            return const Center(
              child: Text(
                'No sections found.\n(Database not loaded)',
                textAlign: TextAlign.center,
              ),
            );
          }
          final listItems = <Widget>[
            _SectionButton(
              title: 'Introduction',
              onTap: () {
                Navigator.of(context).push(
                  FadePageRoute<void>(page: const IntroductionScreen()),
                );
              },
            ),
            for (var i = 0; i < sections.length; i++)
              _SectionButton(
                title: _displaySectionTitle(sections[i], i + 1),
                onTap: () {
                  Navigator.of(context).push(
                    FadePageRoute<void>(
                      page: ChaptersScreen(sectionTitle: sections[i].rawTitle),
                    ),
                  );
                },
              ),
          ];

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: listItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) => listItems[index],
          );
        },
      ),
    );
  }

  String _displaySectionTitle(Section section, int fallbackIndex) {
    final parsed = TitleFormatter.parseSectionTitle(section.rawTitle);
    final number = parsed.number ?? fallbackIndex.toString();
    final title = parsed.title.isEmpty ? section.title : parsed.title;
    return '$number. $title';
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.6)),
          borderRadius: BorderRadius.circular(6),
          color: theme.colorScheme.surface,
        ),
        child: Text(
          title,
          textAlign: TextAlign.left,
          softWrap: true,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
