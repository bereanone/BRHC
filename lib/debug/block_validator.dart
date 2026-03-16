import 'package:flutter/foundation.dart';

import '../models/brhc_models.dart';
import 'debug_flags.dart';

class BlockValidator {
  // Logs only; never mutates block data.
  static void validateBlock(DocBlock block) {
    if (!DebugFlags.validator &&
        !DebugFlags.headingTrace &&
        !DebugFlags.poetryTrace) {
      return;
    }
    final text = block.rawText.isNotEmpty ? block.rawText : block.normalizedText;
    if ((DebugFlags.validator || DebugFlags.headingTrace) &&
        block.blockType == 'heading' &&
        !text.contains('<strong>')) {
      debugPrint('[VALIDATOR] heading missing <strong> (id=${block.blockId})');
    }
    if ((DebugFlags.validator || DebugFlags.poetryTrace) &&
        block.blockType == 'poetry' &&
        text.trim().isEmpty) {
      debugPrint('[VALIDATOR] poetry stanza break (id=${block.blockId})');
    }
  }

  // Warn if intro content is attached to a question context.
  static void validateIntroQuestionId(int blockId, int? questionId) {
    if (!DebugFlags.validator) {
      return;
    }
    if (questionId != null) {
      debugPrint(
        '[VALIDATOR] intro has questionId=$questionId (id=$blockId)',
      );
    }
  }

  // Logs question blocks that have no following answers in the render list.
  static void validateQuestion(int questionId, bool hasAnswers) {
    if (!DebugFlags.validator) {
      return;
    }
    if (!hasAnswers) {
      debugPrint('[VALIDATOR] question has no answers (id=$questionId)');
    }
  }

  // Diagnostics when render selection skips expected answers.
  static void logAnswerSkip(int questionId) {
    if (!DebugFlags.renderTrace) {
      return;
    }
    debugPrint('[RENDER] question rendered with no answers (id=$questionId)');
  }
}
