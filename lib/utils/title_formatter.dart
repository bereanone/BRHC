class TitleFormatter {
  static final RegExp _tagPrefix = RegExp(r'^\s*\[[A-Za-z]+\]\s*');
  static final RegExp _sectionPrefix =
      RegExp(r'^Section\s+(\d+)\s*[-.:]?\s*', caseSensitive: false);
  static final RegExp _chapterPrefix =
      RegExp(r'^Chapter\s+(\d+)\s*[-.:]?\s*', caseSensitive: false);

  static String stripTagPrefix(String value) {
    return value.replaceFirst(_tagPrefix, '');
  }

  static SectionTitle parseSectionTitle(String raw) {
    final cleaned = stripTagPrefix(raw).trim();
    final match = _sectionPrefix.firstMatch(cleaned);
    if (match == null) {
      return SectionTitle(number: null, title: cleaned);
    }
    final number = match.group(1);
    final title = cleaned.substring(match.end).trim();
    return SectionTitle(number: number, title: title);
  }

  static ChapterTitle parseChapterTitle(String raw) {
    final cleaned = stripTagPrefix(raw).trim();
    final match = _chapterPrefix.firstMatch(cleaned);
    if (match == null) {
      return ChapterTitle(number: null, title: cleaned);
    }
    final number = match.group(1);
    final title = cleaned.substring(match.end).trim();
    return ChapterTitle(number: number, title: title);
  }
}

class SectionTitle {
  final String? number;
  final String title;

  const SectionTitle({required this.number, required this.title});
}

class ChapterTitle {
  final String? number;
  final String title;

  const ChapterTitle({required this.number, required this.title});
}
