import 'dart:typed_data';

class Section {
  final String title;

  const Section({required this.title});
}

class Chapter {
  final String title;
  final int chapterId;

  const Chapter({
    required this.title,
    required this.chapterId,
  });
}

class QuestionItem {
  final int questionId;
  final String question;
  final String answer;
  final String? answerType;
  final String? verseText;
  final Uint8List? imageBytes;
  final bool checked;

  const QuestionItem({
    required this.questionId,
    required this.question,
    required this.answer,
    required this.answerType,
    required this.verseText,
    required this.imageBytes,
    required this.checked,
  });

  bool get isScripture => answerType == 'scripture';
}
