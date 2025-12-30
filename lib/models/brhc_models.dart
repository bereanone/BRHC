import 'dart:typed_data';

class Section {
  final String title;
  final String rawTitle;

  const Section({
    required this.title,
    required this.rawTitle,
  });
}

class ChapterEntry {
  final String sectionTitle;
  final String chapterTitle;
  final String rawSectionTitle;
  final String rawChapterTitle;
  final int firstBlockId;

  const ChapterEntry({
    required this.sectionTitle,
    required this.chapterTitle,
    required this.rawSectionTitle,
    required this.rawChapterTitle,
    required this.firstBlockId,
  });
}

class DocBlock {
  final int blockId;
  final String blockType;
  final String rawText;
  final String normalizedText;
  final String? tableJson;
  final List<Uint8List> imageBlobs;

  const DocBlock({
    required this.blockId,
    required this.blockType,
    required this.rawText,
    required this.normalizedText,
    required this.tableJson,
    required this.imageBlobs,
  });
}

class QuestionNavItem {
  final int blockId;
  final int questionNumber;
  final String questionText;

  const QuestionNavItem({
    required this.blockId,
    required this.questionNumber,
    required this.questionText,
  });
}
