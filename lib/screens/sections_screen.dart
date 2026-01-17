import 'package:flutter/material.dart';

import '../data/brhc_database.dart';
import '../models/brhc_models.dart';
import '../utils/font_scale.dart';
import '../utils/title_formatter.dart';
import '../widgets/fade_route.dart';
import 'about_screen.dart';
import 'chapters_screen.dart';
import 'introduction_screen.dart';
import 'launch_screen.dart';

class SectionsScreen extends StatefulWidget {
  const SectionsScreen({super.key});

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends State<SectionsScreen> {
  int _currentSectionIndex = 0;
  List<Section>? _sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _fontScale(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Home',
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              FadePageRoute<void>(page: const LaunchScreen()),
              (route) => false,
            );
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
              style: _scaleStyle(theme.textTheme.titleSmall, scale)?.copyWith(
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
          _sections = sections;
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
                  setState(() {
                    _currentSectionIndex = i;
                  });
                  Navigator.of(context).push(
                    FadePageRoute<void>(
                      page: ChaptersScreen(
                        sectionTitle: sections[i].rawTitle,
                        sectionIndex: i,
                      ),
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

  void _navigateToSection(int sectionIndex) {
    if (_sections == null || sectionIndex < 0 || sectionIndex >= _sections!.length) return;
    final section = _sections![sectionIndex];
    Navigator.of(context).push(
      FadePageRoute<void>(
        page: ChaptersScreen(
          sectionTitle: section.rawTitle,
          sectionIndex: sectionIndex,
        ),
      ),
    );
  }

  String _displaySectionTitle(Section section, int fallbackIndex) {
    final parsed = TitleFormatter.parseSectionTitle(section.rawTitle);
    // Always number: <number>. <title> (no duplication)
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
    final scale = _fontScale(context);

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
          style: _scaleStyle(theme.textTheme.titleMedium, scale)?.copyWith(
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            color: const Color(0xFF1F1B17),
          ),
        ),
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
