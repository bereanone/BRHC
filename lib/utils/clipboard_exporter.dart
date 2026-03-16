enum ClipboardScope {
  chapter,
  currentQuestion,
}

class ClipboardExport {
  final String text;

  const ClipboardExport({required this.text});
}

ClipboardExport buildClipboardExport({
  required String chapterTitle,
  required String sectionTitle,
  required List<Map<String, Object?>> blocks,
  required ClipboardScope scope,
  int? questionId,
}) {
  final blocksOut = <String>[];
  if (sectionTitle.isNotEmpty) {
    blocksOut.add(sectionTitle);
  }
  if (chapterTitle.isNotEmpty) {
    blocksOut.add(chapterTitle);
  }

  final filteredBlocks = _filterBlocks(blocks, scope, questionId);
  final questionMap = _questionMapFromBlocks(blocks);
  var lastQuestionId = -1;

  for (final block in filteredBlocks) {
    final qid = block['question_id'] as int?;
    if (qid != null &&
        qid != lastQuestionId &&
        (scope == ClipboardScope.chapter || qid == questionId)) {
      final q = questionMap[qid];
      if (q != null) {
        final number = q.$1;
        final qtext = q.$2;
        blocksOut.add('$number. $qtext');
      }
      lastQuestionId = qid;
    }

    final blockType = (block['block_type'] as String?) ?? '';
    final rawContent = (block['content'] as String?) ?? '';
    final imageRef = block['image_ref'] as String?;

    if (blockType == 'image') {
      final label = imageRef == null || imageRef.isEmpty
          ? '[Image]'
          : '[Image: $imageRef]';
      blocksOut.add(label);
      continue;
    }

    if (blockType == 'responsive') {
      final lines = _responsiveLines(rawContent);
      final textLines = lines
          .map((line) => _inlineHtmlToPlainText(_stripColorMarkers(line)))
          .where((line) => line.isNotEmpty)
          .toList();
      if (textLines.isNotEmpty) {
        final formatted = <String>[];
        for (var i = 0; i < textLines.length; i++) {
          formatted.add(i.isOdd ? '**${textLines[i]}**' : textLines[i]);
        }
        blocksOut.add(formatted.join('\n'));
      }
      continue;
    }

    final dotSplit = _parseDotLeaderRow(rawContent);
    if (dotSplit != null) {
      blocksOut.add('${dotSplit.left} .... ${dotSplit.right}');
      continue;
    }

    final htmlContent = _stripColorMarkers(rawContent).trim();
    final plainContent = _inlineHtmlToPlainText(htmlContent).trim();
    if (plainContent.isEmpty) {
      continue;
    }

    if (blockType == 'note') {
      blocksOut.add('NOTE: $plainContent');
    } else {
      blocksOut.add(plainContent);
    }
  }

  return ClipboardExport(text: blocksOut.join('\n\n').trim());
}

List<Map<String, Object?>> _filterBlocks(
  List<Map<String, Object?>> blocks,
  ClipboardScope scope,
  int? questionId,
) {
  switch (scope) {
    case ClipboardScope.chapter:
      return blocks;
    case ClipboardScope.currentQuestion:
      if (questionId == null) return const [];
      return blocks.where((b) => b['question_id'] == questionId).toList();
  }
}

Map<int, (String, String)> _questionMapFromBlocks(
  List<Map<String, Object?>> blocks,
) {
  final map = <int, (String, String)>{};
  for (final block in blocks) {
    final qid = block['question_id'] as int?;
    if (qid == null || map.containsKey(qid)) continue;
    final qnum = block['question_number'];
    final qtext = block['question_text'];
    if (qnum != null && qtext != null) {
      map[qid] = (qnum.toString(), qtext.toString());
    }
  }
  return map;
}

List<String> _responsiveLines(String rawContent) {
  final lines = rawContent
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isNotEmpty &&
      (lines.first.toUpperCase().contains('RESPONSIVE READING') ||
          lines.first.startsWith('[R]'))) {
    lines.removeAt(0);
  }
  return lines;
}

_DotLeaderSplit? _parseDotLeaderRow(String content) {
  if (content.contains('[L]') && content.contains('[R]')) {
    final leftMatches = RegExp(r'\[L\](.*?)\[/L\]', dotAll: true)
        .allMatches(content)
        .map((m) => m.group(1) ?? '')
        .join();
    final rightMatches = RegExp(r'\[R\](.*?)\[/R\]', dotAll: true)
        .allMatches(content)
        .map((m) => m.group(1) ?? '')
        .join();
    final left = _inlineHtmlToPlainText(
      leftMatches.replaceAll(RegExp(r'\.+\s*$'), ''),
    ).trim();
    final right = _inlineHtmlToPlainText(rightMatches).trim();
    if (left.isNotEmpty && right.isNotEmpty) {
      return _DotLeaderSplit(left, right);
    }
  }
  return null;
}

class _DotLeaderSplit {
  final String left;
  final String right;

  const _DotLeaderSplit(this.left, this.right);
}

String _stripColorMarkers(String input) {
  return input.replaceAll(RegExp(r'\[(?:/?[LR])\]'), '');
}

String _inlineHtmlToPlainText(String input) {
  if (input.isEmpty) return '';
  var s = input;
  s = s
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  return _stripColorMarkers(s);
}
